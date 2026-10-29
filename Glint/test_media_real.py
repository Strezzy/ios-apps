# SPDX-License-Identifier: GPL-3.0-or-later
"""Real FFmpeg remux checks. Hardware iPhone HEVC encoding needs device testing."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('media', Path(__file__).with_name('glint_media.py'))
media = importlib.util.module_from_spec(spec)
spec.loader.exec_module(media)


class LocalBridge:
    def probe_metadata(self, path, opts=None):
        return json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', *(opts or []), path]))

    def run_ffmpeg(self, args):
        result = subprocess.run(['ffmpeg', *args], capture_output=True, text=True)
        return types.SimpleNamespace(exit_code=result.returncode, combined_output=result.stderr)


class HostEncodingBridge(LocalBridge):
    """Exercise the real decode/filter/verification pipeline using host encoders.

    Does not claim to test iPhone VideoToolbox; native archive and device QA are
    separate checks. Video/audio pixel formats and color arguments stay intact.
    """
    def __init__(self, omit_stream_tags=False):
        self.omit_stream_tags = omit_stream_tags
    def probe_metadata(self, path, opts=None):
        result = super().probe_metadata(path, opts)
        if self.omit_stream_tags and not opts and Path(path).suffix == '.webm':
            for stream in result.get('streams', []):
                if stream.get('codec_type') == 'video':
                    stream.pop('pix_fmt', None)
                    stream.pop('color_primaries', None)
        return result
    def run_ffmpeg(self, args):
        args = list(args)
        for option in ['-allow_sw', '-prio_speed']:
            if option in args:
                index = args.index(option)
                del args[index:index + 2]
        args = [{'hevc_videotoolbox':'libx265', 'h264_videotoolbox':'libx264', 'p010le':'yuv420p10le'}.get(value, value) for value in args]
        if 'libx265' in args:
            args[-1:-1] = ['-x265-params', 'log-level=error:pools=1:frame-threads=1']
        return super().run_ffmpeg(args)


@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'Requires host FFmpeg and ffprobe')
class RealRemuxTests(unittest.TestCase):
    def test_h264_aac_remux_preserves_decoded_frames_and_source_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source.mkv'
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=96x64:rate=24',
                            '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '1',
                            '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', str(source)], check=True)
            original = source.read_bytes()
            with patch.object(media, '_bridge', return_value=LocalBridge()):
                result = json.loads(media.glint_make_photos_copy(str(source)))
            self.assertTrue(result['success'], result)
            self.assertTrue(result['videoCopied'])
            self.assertEqual(source.read_bytes(), original)
            def frames(path):
                data = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(path), '-map', '0:v:0', '-f', 'framemd5', '-'])
                return [line.rsplit(b',', 1)[-1].strip() for line in data.splitlines() if not line.startswith(b'#')]
            self.assertEqual(frames(source), frames(result['path']))
            output = LocalBridge().probe_metadata(result['path'])
            self.assertEqual(output['streams'][0]['width'], 96)
            self.assertEqual(output['streams'][1]['codec_name'], 'aac')

    def test_real_vp9_hdr_conversion_frame_probe_and_playable_preview(self):
        for transfer in ('arib-std-b67', 'smpte2084'):
            with self.subTest(transfer=transfer), tempfile.TemporaryDirectory() as directory:
                source = Path(directory) / 'source.webm'
                subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=96x64:rate=24',
                                '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '1',
                                '-c:v', 'libvpx-vp9', '-threads', '1', '-pix_fmt', 'yuv420p10le',
                                '-vf', f'setparams=range=limited:color_primaries=bt2020:color_trc={transfer}:colorspace=bt2020nc',
                                '-color_primaries', 'bt2020', '-color_trc', transfer, '-colorspace', 'bt2020nc',
                                '-color_range', 'tv', '-c:a', 'libopus', str(source)], check=True)
                original = source.read_bytes()
                bridge = HostEncodingBridge(omit_stream_tags=True)
                with patch.object(media, '_bridge', return_value=bridge):
                    inspected = json.loads(media.glint_inspect_media(str(source)))
                    self.assertTrue(inspected['verifiedHDR'], inspected)
                    converted = json.loads(media.glint_make_photos_copy(str(source)))
                    self.assertTrue(converted['success'], converted)
                    self.assertTrue(converted['verifiedHDR'])
                    converted_info = LocalBridge().probe_metadata(converted['path'])
                    self.assertEqual(media._video(converted_info)['width'], 96)
                    self.assertEqual(media._video(converted_info)['height'], 64)
                    self.assertEqual(media._video(converted_info)['color_transfer'], transfer)
                    preview = json.loads(media.glint_make_preview(str(source)))
                    self.assertTrue(preview['success'], preview)
                    try:
                        output = LocalBridge().probe_metadata(preview['path'])
                        self.assertEqual(media._video(output)['codec_name'], 'h264')
                        self.assertEqual(media._video(output)['color_transfer'], 'bt709')
                        self.assertEqual(output['streams'][1]['codec_name'], 'aac')
                        self.assertFalse(preview['verifiedHDR'])
                        self.assertIn('preview only', preview['note'])
                        subprocess.run(['ffmpeg', '-v', 'error', '-i', preview['path'], '-f', 'null', '-'], check=True)
                    finally:
                        Path(preview['path']).unlink(missing_ok=True)
                self.assertEqual(source.read_bytes(), original)

    def test_failed_preview_removes_partial_file_and_preserves_source(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source.mp4'
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=96x64:rate=24',
                            '-t', '0.2', '-c:v', 'libx264', str(source)], check=True)
            original = source.read_bytes()
            class FailedBridge(LocalBridge):
                def run_ffmpeg(self, args):
                    self.output = Path(args[-1])
                    self.output.write_bytes(b'partial')
                    return types.SimpleNamespace(exit_code=1, combined_output='Encoder unavailable')
            bridge = FailedBridge()
            with patch.object(media, '_bridge', return_value=bridge):
                result = json.loads(media.glint_make_preview(str(source)))
            self.assertFalse(result['success'])
            self.assertFalse(bridge.output.exists())
            self.assertEqual(source.read_bytes(), original)


if __name__ == '__main__':
    unittest.main(verbosity=2)
