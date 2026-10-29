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
    def probe_metadata(self, path):
        return json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', path]))

    def run_ffmpeg(self, args):
        result = subprocess.run(['ffmpeg', *args], capture_output=True, text=True)
        return types.SimpleNamespace(exit_code=result.returncode, combined_output=result.stderr)


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


if __name__ == '__main__':
    unittest.main(verbosity=2)
