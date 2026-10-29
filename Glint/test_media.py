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
        # macOS exposes /var through /private/var. Compare canonical paths, as the
        # production resolver does, so the fake bridge identifies its source.
        self.source = Path(self.temp.name).resolve() / 'source.webm'
        self.source.write_bytes(b'original-encoded-stream')
        self.original = self.source.read_bytes()
        self.output_hdr = True
        self.return_code = 0
        self.arguments = []
        self.input_video = stream(avg_frame_rate='30/1', duration='10', nb_frames='300')
        self.output_updates = {}
        self.audio = []
        owner = self
        class Bridge:
            def probe_metadata(self, path):
                source = Path(path).resolve() == owner.source
                output = dict(owner.input_video)
                if not source:
                    output.update(codec_name=owner.input_video['codec_name'] if 'copy' == owner.arguments[owner.arguments.index('-c:v') + 1] else 'hevc')
                    output.update(owner.output_updates)
                if not source and not owner.output_hdr:
                    output.update(color_transfer='bt709',color_primaries='bt709',pix_fmt='yuv420p')
                return {'streams':[output, *owner.audio], 'format':{'bit_rate':'5000000'}}
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
    def test_symlinked_source_keeps_correct_metadata(self):
        alias = self.source.with_name('linked.webm')
        alias.symlink_to(self.source)
        result = json.loads(media.glint_inspect_media(str(alias)))
        self.assertTrue(result['success'])
        self.assertEqual(result['codec'],'vp9')
        self.assertEqual(self.source.read_bytes(),self.original)

    def test_compatible_hevc_is_remuxed_without_video_loss(self):
        self.input_video['codec_name'] = 'hevc'
        result = json.loads(media.glint_make_photos_copy(str(self.source)))
        self.assertTrue(result['success'], result)
        self.assertTrue(result['videoCopied'])
        self.assertEqual(self.arguments[self.arguments.index('-c:v') + 1], 'copy')
        self.assertNotIn('-b:v', self.arguments)

    def test_compatible_h264_and_aac_are_copied(self):
        self.input_video.update(codec_name='h264', pix_fmt='yuv420p', color_transfer='bt709', color_primaries='bt709')
        self.audio = [{'index':1, 'codec_type':'audio', 'codec_name':'aac', 'profile':'LC'}]
        result = json.loads(media.glint_make_photos_copy(str(self.source)))
        self.assertTrue(result['success'], result)
        self.assertEqual(self.arguments[self.arguments.index('-c:a') + 1], 'copy')
        self.assertTrue(result['videoCopied'])

    def test_forced_retry_uses_hevc_at_original_resolution(self):
        self.input_video['codec_name'] = 'hevc'
        result = json.loads(media.glint_transcode_photos_copy(str(self.source)))
        self.assertTrue(result['success'], result)
        self.assertFalse(result['videoCopied'])
        self.assertIn('passthrough', self.arguments)
        self.assertNotIn('-vf', self.arguments)
        self.assertNotIn('-r', self.arguments)

    def test_high_bitrate_source_is_not_capped_at_60mbps(self):
        self.input_video['bit_rate'] = '90000000'
        result = json.loads(media.glint_make_photos_copy(str(self.source)))
        self.assertTrue(result['success'], result)
        self.assertGreaterEqual(int(self.arguments[self.arguments.index('-b:v') + 1]), 180000000)
        self.assertNotIn('-q:v', self.arguments)  # Not available in iOS VideoToolbox.

    def test_downscaled_copy_is_discarded(self):
        self.output_updates.update(width=720, height=1280)
        self.assertFalse(json.loads(media.glint_make_photos_copy(str(self.source)))['success'])
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_truncated_copy_is_discarded(self):
        self.output_updates['duration'] = '5'
        self.assertFalse(json.loads(media.glint_make_photos_copy(str(self.source)))['success'])

    def test_frame_rate_loss_is_rejected(self):
        self.output_updates['avg_frame_rate'] = '24/1'
        self.assertFalse(json.loads(media.glint_make_photos_copy(str(self.source)))['success'])

    def test_rotation_loss_is_rejected(self):
        self.input_video['side_data_list'] = [{'side_data_type':'Display Matrix', 'rotation':-90}]
        self.output_updates['side_data_list'] = []
        self.assertFalse(json.loads(media.glint_make_photos_copy(str(self.source)))['success'])

    def test_failed_remux_can_retry_encoding(self):
        self.input_video['codec_name'] = 'hevc'
        self.return_code = 1
        result = json.loads(media.glint_make_photos_copy(str(self.source)))
        self.assertTrue(result['retryWithEncode'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
