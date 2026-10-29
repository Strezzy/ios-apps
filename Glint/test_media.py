# SPDX-License-Identifier: GPL-3.0-or-later
import importlib.util
from pathlib import Path
import json
import tempfile
import types
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('glint_media', Path(__file__).with_name('glint_media.py'))
media = importlib.util.module_from_spec(spec)
spec.loader.exec_module(media)


def stream(**updates):
    data = {'index':0,'codec_type':'video','codec_name':'vp9','pix_fmt':'yuv420p10le',
            'color_primaries':'bt2020','color_transfer':'arib-std-b67','color_space':'bt2020nc','width':1080,'height':1920}
    data.update(updates)
    return data


class ClassificationTests(unittest.TestCase):
    def test_hlg_verified(self):
        self.assertTrue(media.classify_video(stream())['verifiedHDR'])
    def test_pq_verified(self):
        self.assertEqual(media.classify_video(stream(color_transfer='smpte2084'))['rangeLabel'], 'HDR10 / PQ')
    def test_ten_bit_does_not_imply_hdr(self):
        result = media.classify_video(stream(color_transfer='bt709',color_primaries='bt709'))
        self.assertFalse(result['verifiedHDR'])
        self.assertEqual(result['rangeLabel'],'SDR')
    def test_missing_transfer_is_not_verified(self):
        self.assertFalse(media.classify_video(stream(color_transfer=None))['verifiedHDR'])
    def test_wrong_primaries_is_not_verified(self):
        self.assertFalse(media.classify_video(stream(color_primaries='bt709'))['verifiedHDR'])
    def test_eight_bit_is_not_verified(self):
        self.assertFalse(media.classify_video(stream(pix_fmt='yuv420p',bits_per_raw_sample='8'))['verifiedHDR'])
    def test_p010(self):
        self.assertEqual(media.classify_video(stream(pix_fmt='p010le'))['bitDepth'],10)
    def test_dolby_vision_requires_explicit_side_data(self):
        self.assertFalse(media.classify_video(stream(codec_name='av1'))['dolbyVision'])
        self.assertTrue(media.classify_video(stream(side_data_list=[{'side_data_type':'DOVI configuration record'}]))['dolbyVision'])
    def test_skip_attached_cover(self):
        metadata = {'streams':[stream(disposition={'attached_pic':1}),stream(index=1)]}
        self.assertEqual(media._video(metadata)['index'],1)


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name)/'source.webm'
        self.source.write_bytes(b'original-encoded-stream')
        self.original = self.source.read_bytes()
        self.output_hdr = True
        self.return_code = 0
        self.arguments = []
        owner = self
        class Bridge:
            def probe_metadata(self, path):
                source = Path(path) == owner.source
                output = stream(codec_name='vp9' if source else 'hevc')
                if not source and not owner.output_hdr:
                    output.update(color_transfer='bt709',color_primaries='bt709',pix_fmt='yuv420p')
                return {'streams':[output], 'format':{'bit_rate':'5000000'}}
            def run_ffmpeg(self, args):
                owner.arguments = args
                Path(args[-1]).write_bytes(b'new-compatible-encode')
                return types.SimpleNamespace(exit_code=owner.return_code,combined_output='encoder unavailable' if owner.return_code else '')
        self.patcher = patch.object(media,'_bridge',return_value=Bridge())
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
        space = patch.object(media.shutil,'disk_usage',return_value=types.SimpleNamespace(free=10**12))
        space.start()
        self.addCleanup(space.stop)
    def test_export_retains_original_and_separate_verified_copy(self):
        result = json.loads(media.glint_make_photos_copy(str(self.source)))
        self.assertTrue(result['success'],result)
        self.assertNotEqual(Path(result['path']),self.source)
        self.assertEqual(self.source.read_bytes(),self.original)
        self.assertTrue(result['verifiedHDR'])
        self.assertIn('hevc_videotoolbox',self.arguments)
        self.assertIn('p010le',self.arguments)
    def test_hdr_loss_discards_copy_not_source(self):
        self.output_hdr = False
        result = json.loads(media.glint_make_photos_copy(str(self.source)))
        self.assertFalse(result['success'])
        self.assertEqual(self.source.read_bytes(),self.original)
        self.assertEqual(list(Path(self.temp.name).glob('Glint-Photos-*.mp4')),[])
    def test_failed_encoder_cleans_up(self):
        self.return_code = 1
        self.assertFalse(json.loads(media.glint_make_photos_copy(str(self.source)))['success'])
        self.assertEqual(self.source.read_bytes(),self.original)
        self.assertEqual(list(Path(self.temp.name).glob('Glint-Photos-*.mp4')),[])
    def test_missing_input_returns_useful_error(self):
        result = json.loads(media.glint_make_photos_copy(str(self.source.with_name('missing.mp4'))))
        self.assertFalse(result['success'])
        self.assertTrue(result['error'])
    def test_inspector_reports_real_metadata(self):
        result = json.loads(media.glint_inspect_media(str(self.source)))
        self.assertTrue(result['success'])
        self.assertTrue(result['verifiedHDR'])
        self.assertEqual(result['codec'],'vp9')


if __name__ == '__main__':
    unittest.main(verbosity=2)
