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


def _number(value, default=0):
    try:
        from fractions import Fraction
        return float(Fraction(str(value)))
    except (ValueError, TypeError, ZeroDivisionError):
        return default


def _rotation(video):
    for side in video.get('side_data_list') or []:
        if 'rotation' in side:
            return round(_number(side['rotation'])) % 360
    return round(_number((video.get('tags') or {}).get('rotate'))) % 360


def _duration(metadata, video):
    return _number(video.get('duration')) or _number((metadata.get('format') or {}).get('duration'))


def _verify_copy(before_metadata, after_metadata, copied_video_codec):
    before_video, after_video = _video(before_metadata), _video(after_metadata)
    if not after_video or after_video.get('codec_name') != copied_video_codec:
        raise RuntimeError('The playable copy failed codec verification.')
    for key in ('width', 'height'):
        if not before_video.get(key) or after_video.get(key) != before_video[key]:
            raise RuntimeError('The copy changed the source resolution; it was discarded.')
    if _rotation(before_video) != _rotation(after_video):
        raise RuntimeError('The copy changed the video orientation; it was discarded.')
    before, after = classify_video(before_video), classify_video(after_video)
    if before['verifiedHDR'] and (not after['verifiedHDR'] or after['transfer'] != before['transfer']):
        raise RuntimeError('The copy did not retain HDR. It was discarded; the original is untouched.')
    if before['bitDepth'] and (after['bitDepth'] or 0) < min(10, before['bitDepth']):
        raise RuntimeError('The copy lost video bit depth; it was discarded.')
    fps = _number(before_video.get('avg_frame_rate'))
    out_fps = _number(after_video.get('avg_frame_rate'))
    duration, out_duration = _duration(before_metadata, before_video), _duration(after_metadata, after_video)
    if duration and (not out_duration or abs(duration - out_duration) > max(0.15, 2 / (fps or 24))):
        raise RuntimeError('The copy changed the video duration; it was discarded.')
    if fps and out_fps and abs(fps - out_fps) > max(0.05, fps * 0.005):
        raise RuntimeError('The copy changed the frame rate; it was discarded.')
    frames, out_frames = _number(before_video.get('nb_frames')), _number(after_video.get('nb_frames'))
    if frames and out_frames and frames != out_frames:
        raise RuntimeError('The copy changed the frame count; it was discarded.')
    if any(s.get('codec_type') == 'audio' for s in before_metadata.get('streams', [])):
        audio = next((s for s in after_metadata.get('streams', []) if s.get('codec_type') == 'audio'), None)
        if not audio or audio.get('codec_name') not in {'aac', 'alac'}:
            raise RuntimeError('The copy did not retain playable audio; it was discarded.')
    return after


def _make_photos_copy(path, force_encode=False):
    """Remux when possible; otherwise encode a high-quality HEVC copy, never resize."""
    temporary = None
    copy_video = False
    try:
        source = _file(path)
        bridge = _bridge()
        metadata = bridge.probe_metadata(str(source))
        video = _video(metadata)
        if not video:
            raise ValueError('No video stream found.')
        before = classify_video(video)
        codec = video.get('codec_name')
        # H.264 high-bit-depth/chroma profiles do not decode on ordinary iPhones.
        copy_video = not force_encode and (
            codec == 'h264' and video.get('pix_fmt') in {'yuv420p', 'yuvj420p', 'nv12'}
            or codec == 'hevc' and video.get('pix_fmt') in {'yuv420p', 'yuv420p10le', 'p010le', 'nv12'})
        if not copy_video and (before['dolbyVision'] or video.get('color_transfer') in {'arib-std-b67', 'smpte2084'}) and not before['verifiedHDR']:
            raise ValueError('Downloaded original retained. This HDR format cannot be safely converted on this device.')
        audio = next((s for s in metadata.get('streams', []) if s.get('codec_type') == 'audio'), None)
        copy_audio = audio and not force_encode and audio.get('codec_name') in {'aac', 'alac'} and audio.get('profile') not in {'xHE-AAC', 'USAC'}
        fps = _number(video.get('avg_frame_rate'), 30) or 30
        source_rate = _number(video.get('bit_rate')) or _number((metadata.get('format') or {}).get('bit_rate'))
        # VideoToolbox -q:v is not supported on iOS. Use a generous source- and
        # pixel-rate-scaled bitrate, with quality prioritized over encoding speed.
        rate = round(max(24000000, source_rate * 2, _number(video.get('width')) * _number(video.get('height')) * fps * 0.4))
        if rate >= 2**31:
            raise ValueError('Source exceeds the supported encoder bitrate. Original retained without downscaling.')
        duration = _duration(metadata, video)
        estimate = source.stat().st_size * 2 if copy_video else max(source.stat().st_size * 5, rate * duration / 8 * 1.3)
        if shutil.disk_usage(source.parent).free < max(estimate, 512 * 1024 * 1024):
            raise ValueError('Not enough storage for a high-quality playable copy. Original retained; free space and retry.')
        original_hash = _fingerprint(source)
        fd, temporary = tempfile.mkstemp(prefix='Glint-Photos-', suffix='.mp4', dir=source.parent)
        os.close(fd)
        args = ['-hide_banner', '-y', '-noautorotate', '-i', str(source),
                '-map', f'0:{video.get("index", 0)}', '-map', '0:a:0?', '-map_metadata', '0']
        if copy_video:
            args += ['-c:v', 'copy', '-tag:v', 'hvc1' if codec == 'hevc' else 'avc1']
        else:
            args += ['-c:v', 'hevc_videotoolbox', '-allow_sw', '0', '-prio_speed', '0',
                     '-tag:v', 'hvc1', '-b:v', str(rate), '-fps_mode', 'passthrough']
            ten_bit = before['verifiedHDR'] or (before['bitDepth'] or 0) >= 10
            args += ['-profile:v', 'main10' if ten_bit else 'main', '-pix_fmt', 'p010le' if ten_bit else 'yuv420p']
            for field, option in [('color_primaries', '-color_primaries'), ('color_transfer', '-color_trc'),
                                  ('color_space', '-colorspace'), ('color_range', '-color_range')]:
                value = video.get(field)
                if value and value not in {'unknown', 'unspecified'}:
                    args += [option, value]
        if audio:
            args += ['-c:a', 'copy'] if copy_audio else ['-c:a', 'aac', '-b:a', str(max(320000, 128000 * int(audio.get('channels') or 2)))]
        args += ['-movflags', '+faststart', temporary]
        result = bridge.run_ffmpeg(args)
        if result.exit_code != 0:
            raise RuntimeError('Playable-copy preparation failed. Original retained. ' + result.combined_output[-800:])
        after = _verify_copy(metadata, bridge.probe_metadata(temporary), codec if copy_video else 'hevc')
        if _fingerprint(source) != original_hash:
            raise RuntimeError('The source changed during export. The copy was discarded.')
        note = 'Video stream preserved without re-encoding.' if copy_video else 'High-quality HEVC copy at source resolution and frame timing.'
        if before['dolbyVision'] and not copy_video:
            note += ' HLG/PQ base HDR retained; Dolby Vision dynamic metadata is not preserved.'
        report = {'success': True, 'path': temporary, 'verifiedHDR': after['verifiedHDR'],
                  'rangeLabel': after['rangeLabel'], 'sourceUnchanged': True, 'note': note,
                  'videoCopied': bool(copy_video)}
        temporary = None
        return json.dumps(report)
    except (Exception, KeyboardInterrupt) as error:
        return json.dumps({'success': False, 'error': str(error) or 'Conversion cancelled. Original retained.',
                           'retryWithEncode': bool(copy_video and not isinstance(error, KeyboardInterrupt))})
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def glint_make_photos_copy(path):
    return _make_photos_copy(path)


def glint_transcode_photos_copy(path):
    return _make_photos_copy(path, force_encode=True)
