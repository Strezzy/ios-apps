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
        depth = int(match.group(1)) if match else (10 if pixel_format in {'p010le', 'p010be'} else (8 if pixel_format in {'yuv420p', 'yuvj420p', 'nv12', 'yuv422p', 'yuv444p'} else None))
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


def _probe_video(bridge, source):
    """Resolve missing container tags from a bounded sample of decoded frames.

    Never infer HDR from the codec name, file name or bit depth alone, and never
    replace an explicit stream tag with a guessed value.
    """
    metadata = bridge.probe_metadata(str(source))
    video = _video(metadata)
    if not video:
        return metadata
    fields = ('pix_fmt', 'color_transfer', 'color_primaries', 'color_space', 'color_range')
    missing = [key for key in fields if video.get(key) in (None, '', 'unknown', 'unspecified')]
    if missing:
        try:
            decoded = bridge.probe_metadata(str(source), opts=[
                '-select_streams', str(video.get('index', 0)), '-read_intervals', '%+#8',
                '-show_frames', '-show_entries', 'frame=media_type,stream_index,' + ','.join(fields)])
            frames = [f for f in decoded.get('frames', []) if f.get('media_type') == 'video'
                      and f.get('stream_index', video.get('index', 0)) == video.get('index', 0)]
            for key in missing:
                values = {f[key] for f in frames if f.get(key) not in (None, '', 'unknown', 'unspecified')}
                if len(values) == 1:
                    video[key] = values.pop()
        except Exception:
            # Inspection still reports the known tags if decoding is unavailable.
            pass
    return metadata


def glint_inspect_media(path):
    try:
        source = _file(path)
        metadata = _probe_video(_bridge(), source)
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
    for key in ('color_transfer', 'color_primaries', 'color_space', 'color_range'):
        value = before_video.get(key)
        if value not in (None, '', 'unknown', 'unspecified') and after_video.get(key) != value:
            raise RuntimeError('The copy changed known color metadata; it was discarded.')
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
        metadata = _probe_video(bridge, source)
        video = _video(metadata)
        if not video:
            raise ValueError('No video stream found.')
        before = classify_video(video)
        codec = video.get('codec_name')
        # H.264 high-bit-depth/chroma profiles do not decode on ordinary iPhones.
        copy_video = not force_encode and (
            codec == 'h264' and video.get('pix_fmt') in {'yuv420p', 'yuvj420p', 'nv12'}
            or codec == 'hevc' and video.get('pix_fmt') in {'yuv420p', 'yuv420p10le', 'p010le', 'nv12'})
        if not copy_video and before['dolbyVision'] and video.get('color_transfer') not in {'arib-std-b67', 'smpte2084'}:
            raise ValueError('This Dolby Vision source has no verified HLG/PQ base layer. Save the original to Files; a separate playback preview is available in Library.')
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
            ten_bit = video.get('color_transfer') in {'arib-std-b67', 'smpte2084'} or (before['bitDepth'] or 0) >= 10
            args += ['-profile:v', 'main10' if ten_bit else 'main', '-pix_fmt', 'p010le' if ten_bit else 'yuv420p']
        for field, option in [('color_primaries', '-color_primaries'), ('color_transfer', '-color_trc'),
                              ('color_space', '-colorspace'), ('color_range', '-color_range')]:
            value = video.get(field)
            if value and value not in {'unknown', 'unspecified'}:
                args += [option, value]
        if audio:
            args += ['-c:a', 'copy'] if copy_audio else ['-c:a', 'aac', '-b:a', str(max(320000, 128000 * int(audio.get('channels') or 2)))]
        args += ['-movflags', '+faststart+write_colr', temporary]
        result = bridge.run_ffmpeg(args)
        if result.exit_code != 0:
            raise RuntimeError('Playable-copy preparation failed. Original retained. ' + result.combined_output[-800:])
        after = _verify_copy(metadata, _probe_video(bridge, temporary), codec if copy_video else 'hevc')
        if _fingerprint(source) != original_hash:
            raise RuntimeError('The source changed during export. The copy was discarded.')
        note = 'Video stream preserved without re-encoding.' if copy_video else 'High-quality HEVC copy at source resolution and frame timing.'
        if not before['verifiedHDR'] and video.get('color_transfer') in {'arib-std-b67', 'smpte2084'}:
            note += ' Known HDR tags retained in 10-bit HEVC; incomplete source metadata prevents full HDR verification.'
        if not copy_video:
            note += ' Re-encoding is not lossless; the original is unchanged.'
        if before['dolbyVision'] and not copy_video:
            note += ' HLG/PQ base HDR retained; Dolby Vision dynamic metadata is not preserved.'
        report = {'success': True, 'path': temporary, 'verifiedHDR': before['verifiedHDR'] and after['verifiedHDR'],
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


def _preview_lut(path, transfer, primaries):
    """Display-only BT.709 LUT: explicit PQ/HLG EOTF, gamut transform, tone map.

    The HLG display assumption is 1000 nits. This intentionally cannot be used
    for archival/Photos conversion; it compresses HDR highlights for a preview.
    """
    import math
    def linear(value):
        if transfer == 'smpte2084':
            p = value ** (1 / (2523 / 32))
            return (max(p - 3424 / 4096, 0) / max(2413 / 128 - 2392 / 128 * p, 1e-9)) ** (1 / (2610 / 16384)) * 10000 / 203
        scene = value * value / 3 if value <= 0.5 else (math.exp((value - 0.55991073) / 0.17883277) + 0.28466892) / 12
        return scene ** 1.2 * 1000 / 203
    def encode(value):
        value = min(1, max(0, value))
        return 4.5 * value if value < 0.018 else 1.099 * value ** 0.45 - 0.099
    with open(path, 'w') as handle:
        handle.write('TITLE "Glint SDR preview only"\nLUT_3D_SIZE 33\n')
        for blue in range(33):
            for green in range(33):
                for red in range(33):
                    r, g, b = (linear(v / 32) for v in (red, green, blue))
                    if primaries == 'bt2020':
                        r, g, b = (1.660491*r - 0.587641*g - 0.072850*b,
                                   -0.124550*r + 1.132900*g - 0.008350*b,
                                   -0.018151*r - 0.100579*g + 1.118730*b)
                    luminance = max(0, 0.2126*r + 0.7152*g + 0.0722*b)
                    white = 1000 / 203
                    gain = (1 + luminance / (white * white)) / (1 + luminance)
                    handle.write(' '.join(f'{encode(v * gain):.8f}' for v in (r, g, b)) + '\n')


def glint_make_preview(path):
    """Disposable H.264 preview for FFmpeg-decodable sources, including VP9/AV1.

    Independent from source-quality export. Never used as a Photos copy, never
    returned by the downloader, never overwrites the source. Bounded dimensions
    and frame rate keep playback accessible when source-size HEVC is unavailable.
    """
    temporary = None
    try:
        source = _file(path)
        bridge = _bridge()
        metadata = _probe_video(bridge, source)
        video = _video(metadata)
        if not video:
            raise ValueError('No video stream found.')
        duration = _duration(metadata, video)
        if shutil.disk_usage(tempfile.gettempdir()).free < max(128 * 1024 * 1024, duration * 14000000 / 8):
            raise ValueError('Free some storage to prepare a preview. The original can still be saved to Files.')
        original_hash = _fingerprint(source)
        transfer = video.get('color_transfer')
        hdr = transfer in {'arib-std-b67', 'smpte2084'}
        with tempfile.TemporaryDirectory(prefix='glint-preview-lut-') as workspace:
            # LUT paths are generated by us, not taken from untrusted media tags.
            lut = Path(workspace) / 'preview.cube'
            filters = ["scale=w='min(1080,iw)':h='min(1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2"]
            if hdr:
                _preview_lut(lut, transfer, video.get('color_primaries'))
                filters += ['format=gbrpf32le', f"lut3d=file='{lut}':interp=tetrahedral", 'scale=out_color_matrix=bt709']
            filters += ['format=yuv420p', 'sidedata=delete', 'setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709']
            fd, temporary = tempfile.mkstemp(prefix='Glint-Preview-', suffix='.mp4')
            os.close(fd)
            args = ['-hide_banner', '-y', '-i', str(source), '-map', f'0:{video.get("index", 0)}',
                    '-map', '0:a:0?', '-map_metadata', '-1', '-vf', ','.join(filters),
                    '-c:v', 'h264_videotoolbox', '-allow_sw', '1', '-prio_speed', '0',
                    '-profile:v', 'high', '-pix_fmt', 'yuv420p', '-b:v', '12000000',
                    '-r', str(min(30, _number(video.get('avg_frame_rate'), 30) or 30)),
                    '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
                    '-color_range', 'tv', '-c:a', 'aac', '-b:a', '320000', '-movflags', '+faststart', temporary]
            result = bridge.run_ffmpeg(args)
            if result.exit_code:
                raise RuntimeError('Preview preparation failed. Save the original to Files. ' + result.combined_output[-500:])
        output = bridge.probe_metadata(temporary)
        out_video = _video(output)
        if not out_video or out_video.get('codec_name') != 'h264' or out_video.get('pix_fmt') != 'yuv420p':
            raise RuntimeError('The preview failed codec validation.')
        if duration and abs(_duration(output, out_video) - duration) > max(.2, duration * .005):
            raise RuntimeError('The preview is incomplete; the original is unchanged.')
        if any(s.get('codec_type') == 'audio' for s in metadata.get('streams', [])) and not any(s.get('codec_type') == 'audio' and s.get('codec_name') == 'aac' for s in output.get('streams', [])):
            raise RuntimeError('The preview is missing audio.')
        if _fingerprint(source) != original_hash:
            raise RuntimeError('The source changed during preview generation.')
        note = 'Playback preview · H.264, up to 1080 pixels / 30 fps. '
        if hdr:
            note += 'HDR tone-mapped to SDR for preview only. '
        if not classify_video(video)['verifiedHDR'] and (hdr or classify_video(video)['dolbyVision'] or transfer in (None, '', 'unknown', 'unspecified')):
            note += 'Source color metadata is incomplete; preview colors may differ. '
        note += 'Save to Files exports the full-quality original.'
        report = {'success': True, 'path': temporary, 'sourceUnchanged': True, 'note': note, 'verifiedHDR': False}
        temporary = None
        return json.dumps(report)
    except (Exception, KeyboardInterrupt) as error:
        return json.dumps({'success': False, 'error': str(error) or 'Preview cancelled. Original retained.'})
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)
