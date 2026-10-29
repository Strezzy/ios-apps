# SPDX-License-Identifier: GPL-3.0-or-later
"""Local media inspection and optional copies. No subprocesses or cloud services."""
import hashlib
import json
import os
import re
import shutil
import tempfile
from pathlib import Path


def classify_video(stream):
    """Require actual transfer/primaries/bit-depth evidence; 10-bit alone is not HDR."""
    pixel_format = str(stream.get('pix_fmt') or '').lower()
    depth = stream.get('bits_per_raw_sample') or stream.get('bits_per_sample')
    try:
        depth = int(depth)
    except (ValueError, TypeError):
        depth = None
    if depth is None or depth == 0:
        match = re.search(r'(?:p|gbrp)(10|12|16)(?:le|be)?$', pixel_format)
        depth = int(match.group(1)) if match else (10 if pixel_format in {'p010le', 'p010be'} else None)
    transfer = str(stream.get('color_transfer') or '')
    primaries = str(stream.get('color_primaries') or '')
    side_data = stream.get('side_data_list') or []
    dolby_vision = any('dovi' in str(x.get('side_data_type', '')).lower() or 'dolby vision' in str(x.get('side_data_type', '')).lower() for x in side_data)
    verified_hdr = bool(depth and depth >= 10 and primaries == 'bt2020' and transfer in {'arib-std-b67', 'smpte2084'})
    if verified_hdr:
        label = 'HLG' if transfer == 'arib-std-b67' else 'HDR10 / PQ'
        if dolby_vision:
            label += ' · Dolby Vision metadata detected'
    elif dolby_vision:
        label = 'Dolby Vision metadata detected; base HDR unverified'
    elif transfer in {'bt709', 'iec61966-2-1', 'smpte170m', 'gamma22', 'gamma28'}:
        label = 'SDR'
    else:
        label = 'HDR not verified'
    return {'verifiedHDR': verified_hdr, 'rangeLabel': label, 'bitDepth': depth, 'dolbyVision': dolby_vision,
            'transfer': transfer or 'Unknown', 'primaries': primaries or 'Unknown'}


def _video(metadata):
    return next((s for s in metadata.get('streams', []) if s.get('codec_type') == 'video' and not (s.get('disposition') or {}).get('attached_pic')), None)


def _bridge():
    from .ffmpeg_bridge import SwiftFFmpegBridge
    return SwiftFFmpegBridge()


def _file(path):
    source = Path(path).expanduser().resolve(strict=True)
    if not source.is_file():
        raise ValueError('Choose a downloaded video file, not a folder.')
    return source


def _fingerprint(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def glint_inspect_media(path):
    try:
        source = _file(path)
        metadata = _bridge().probe_metadata(str(source))
        video = _video(metadata)
        if not video:
            raise ValueError('No playable video stream was found in this file.')
        report = classify_video(video)
        report.update(success=True, codec=video.get('codec_name') or 'Unknown', width=video.get('width'),
                      height=video.get('height'), size=source.stat().st_size, error=None)
        return json.dumps(report)
    except Exception as error:
        return json.dumps({'success': False, 'error': str(error)})


def glint_make_photos_copy(path):
    """Create a different HEVC/AAC file; never replace, rename or delete the source."""
    temporary = None
    try:
        source = _file(path)
        bridge = _bridge()
        metadata = bridge.probe_metadata(str(source))
        video = _video(metadata)
        if not video:
            raise ValueError('No video stream found.')
        before = classify_video(video)
        if (before['dolbyVision'] or video.get('color_transfer') in {'arib-std-b67', 'smpte2084'}) and not before['verifiedHDR']:
            raise ValueError('The HDR base layer cannot be verified. Export the original instead; no SDR fallback was made.')
        available = shutil.disk_usage(source.parent).free
        if available < max(source.stat().st_size * 5, 512 * 1024 * 1024):
            raise ValueError('Not enough free space for a separate Photos copy. Free some storage and try again.')
        original_hash = _fingerprint(source)
        fd, temporary = tempfile.mkstemp(prefix='Glint-Photos-', suffix='.mp4', dir=source.parent)
        os.close(fd)
        args = ['-hide_banner', '-y', '-i', str(source), '-map', f'0:{video.get("index", 0)}', '-map', '0:a:0?',
                '-map_metadata', '0', '-c:v', 'hevc_videotoolbox', '-allow_sw', '0', '-tag:v', 'hvc1',
                '-c:a', 'aac', '-b:a', '256k', '-movflags', '+faststart']
        source_rate = int(video.get('bit_rate') or (metadata.get('format') or {}).get('bit_rate') or 16000000)
        args += ['-b:v', str(min(60000000, max(12000000, source_rate)))]
        if before['verifiedHDR']:
            args += ['-profile:v', 'main10', '-pix_fmt', 'p010le', '-color_primaries', 'bt2020',
                     '-color_trc', video['color_transfer'], '-colorspace', video.get('color_space') if video.get('color_space') in {'bt2020nc', 'bt2020c'} else 'bt2020nc']
        else:
            args += ['-profile:v', 'main', '-pix_fmt', 'yuv420p']
        result = bridge.run_ffmpeg([*args, temporary])
        if result.exit_code != 0:
            raise RuntimeError('The device could not create this HEVC copy. The original is untouched. ' + result.combined_output[-1200:])
        copied_video = _video(bridge.probe_metadata(temporary))
        if not copied_video or copied_video.get('codec_name') != 'hevc':
            raise RuntimeError('HEVC verification failed. The original is untouched.')
        after = classify_video(copied_video)
        if before['verifiedHDR'] and (not after['verifiedHDR'] or after['transfer'] != before['transfer']):
            raise RuntimeError('The exported copy did not retain verified HDR. It was discarded; the original is untouched.')
        if _fingerprint(source) != original_hash:
            raise RuntimeError('The source changed during export. The copy was discarded.')
        result = {'success': True, 'path': temporary, 'verifiedHDR': after['verifiedHDR'],
                  'rangeLabel': after['rangeLabel'], 'sourceUnchanged': True,
                  'note': 'Separate HEVC/AAC copy. Dolby Vision metadata is not preserved.' if before['dolbyVision'] else 'Separate HEVC/AAC copy; original unchanged.'}
        temporary = None
        return json.dumps(result)
    except Exception as error:
        return json.dumps({'success': False, 'error': str(error)})
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)
