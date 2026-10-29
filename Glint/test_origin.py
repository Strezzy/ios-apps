# SPDX-License-Identifier: GPL-3.0-or-later
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('origin', Path(__file__).with_name('glint_origin.py'))
origin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(origin)


class OriginTests(unittest.TestCase):
    def test_post_links_are_canonical_and_tracking_is_removed(self):
        self.assertEqual(origin.post_url('http://instagram.com/artist/reels/ABC-_123/?igsh=secret#x'), 'https://www.instagram.com/reel/ABC-_123/')

    def test_profile_feed_and_non_instagram_urls_are_not_posts(self):
        for value in ['https://instagram.com/artist/', 'https://instagram.com/reels/',
                      'https://instagram.com/explore/', 'https://instagram.com/reels/audio/123/',
                      'https://instagram.com.evil.test/reel/ABC/', 'javascript://instagram.com/reel/ABC/',
                      'https://user:pass@instagram.com/reel/ABC/', 'https://instagram.com:999/reel/ABC/']:
            self.assertIsNone(origin.post_url(value), value)

    def test_channel_username_preferred_over_numeric_uploader_id(self):
        r = origin.record({'webpage_url': 'https://instagram.com/p/ABC/', 'channel': 'artist.name', 'uploader_id': '123456'})
        self.assertEqual(r['creatorURL'], 'https://www.instagram.com/artist.name/')

    def test_numeric_uploader_id_is_not_invented_as_a_profile(self):
        self.assertIsNone(origin.record({'webpage_url': 'https://instagram.com/p/ABC/', 'uploader_id': '123456'})['creatorURL'])

    def test_unicode_filename_normalization_keeps_same_sidecar(self):
        self.assertEqual(origin.sidecar('/tmp/café.mp4'), origin.sidecar('/tmp/cafe\u0301.mp4'))

    def test_numeric_channel_is_a_real_username(self):
        self.assertEqual(origin.record({'webpage_url': 'https://instagram.com/p/ABC/', 'channel': '123456'})['username'], '123456')

    def test_valid_profile_url_preferred_and_unrelated_url_rejected(self):
        info = {'webpage_url': 'https://instagram.com/p/ABC/', 'uploader_url': 'https://instagram.com/artist/', 'channel': 'other'}
        self.assertEqual(origin.record(info)['username'], 'artist')
        info.update(uploader_url='https://evil.test/artist/', channel=None)
        self.assertIsNone(origin.record(info)['creatorURL'])

    def test_per_item_post_wins_over_playlist_input(self):
        self.assertEqual(origin.record({'webpage_url': 'https://instagram.com/reel/CHILD/'}, 'https://instagram.com/artist/')['postURL'], 'https://www.instagram.com/reel/CHILD/')

    def test_only_allowlisted_metadata_is_saved(self):
        r = origin.record({'webpage_url': 'https://instagram.com/p/ABC/?igsh=private', 'title': 'a' * 400,
                           'cookies': 'SECRET', 'http_headers': {'Cookie': 'SECRET'}, 'url': 'https://cdn.test/?token=SECRET'})
        self.assertNotIn('SECRET', json.dumps(r)); self.assertNotIn('private', json.dumps(r))
        self.assertEqual(len(r['title']), 300)
        self.assertEqual(set(r), {'version', 'postURL', 'creatorURL', 'username', 'title'})

    def test_record_stays_next_to_actual_completed_file(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'a.mp4'; p.write_bytes(b'original')
            origin.save({'filepath': str(p), 'webpage_url': 'https://instagram.com/p/ABC/'}, d)
            self.assertEqual(json.loads(origin.sidecar(p).read_text())['postURL'], 'https://www.instagram.com/p/ABC/')
            self.assertEqual(p.read_bytes(), b'original')
            self.assertFalse(any(x.suffix == '.tmp' for x in Path(d).iterdir()))

    def test_files_outside_download_root_are_ignored(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'a.mp4'; p.write_bytes(b'original')
            inner = Path(d) / 'run'; inner.mkdir()
            origin.save({'filepath': str(p), 'webpage_url': 'https://instagram.com/p/ABC/'}, inner)
            self.assertFalse(origin.sidecar(p).exists())

    def test_hook_runs_after_final_move_and_restores_on_failure(self):
        class Downloader:
            def run_all_pps(self, key, info, **kwargs): return {**info, 'title': 'Final title'}
        original = Downloader.run_all_pps
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'merged.mp4'; p.write_bytes(b'final video')
            info = {'filepath': str(p), 'webpage_url': 'https://instagram.com/p/ABC/'}
            with patch.dict(sys.modules, {'yt_dlp': types.SimpleNamespace(YoutubeDL=Downloader)}):
                with self.assertRaises(RuntimeError):
                    with origin.capture_origins(d, None):
                        Downloader().run_all_pps('post_process', info)
                        self.assertFalse(origin.sidecar(p).exists())
                        Downloader().run_all_pps('after_move', info)
                        self.assertEqual(json.loads(origin.sidecar(p).read_text())['title'], 'Final title')
                        raise RuntimeError('cancelled')
            self.assertIs(Downloader.run_all_pps, original)


if __name__ == '__main__':
    unittest.main(verbosity=2)
