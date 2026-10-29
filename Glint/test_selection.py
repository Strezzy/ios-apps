# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the compiled Swift policy through real yt-dlp format selection, offline."""
import json
import os
from pathlib import Path
import shlex
import unittest

import yt_dlp

ARGUMENTS = json.loads(Path(os.environ['GLINT_QUALITY_ARGUMENTS']).read_text())


def video(name, width, height, hdr='HLG', **extra):
    return dict(format_id=name, url=f'https://example.invalid/{name}.mp4', ext='mp4',
                vcodec='vp09.02.51.10', acodec='none', width=width, height=height,
                fps=30, tbr=5000, dynamic_range=hdr, **extra)


AUDIO = dict(format_id='audio', url='https://example.invalid/audio.m4a', ext='m4a',
             vcodec='none', acodec='mp4a.40.2', abr=256)


def options(mode='video'):
    return yt_dlp.parse_options(['--ignore-config', *shlex.split(ARGUMENTS[mode])]).ydl_opts


def select(formats, mode='video'):
    opts = options(mode)
    opts.update(quiet=True, no_warnings=True, skip_download=True, check_formats=False)
    with yt_dlp.YoutubeDL(opts) as downloader:
        return downloader.process_ie_result(dict(id='fixture', title='Source HDR fixture', extractor='fixture',
                                                  formats=formats), download=False)


class SourceSelectionTests(unittest.TestCase):
    def selected_video(self, result):
        return next((s for s in result.get('requested_formats', []) if s['vcodec'] != 'none'), result)

    def test_largest_hdr_wins_over_higher_bitrate_small_hdr(self):
        small = video('small', 720, 1280)
        small['tbr'] = 20000
        result = select([small, video('largest', 2160, 3840), AUDIO])
        self.assertEqual(self.selected_video(result)['format_id'], 'largest')

    def test_larger_sdr_wins_over_lower_resolution_hdr(self):
        result = select([video('sdr', 2160, 3840, 'SDR'), video('hdr', 1080, 1920), AUDIO])
        self.assertEqual(self.selected_video(result)['format_id'], 'sdr')
        self.assertEqual(result['requested_formats'][1]['format_id'], 'audio')

    def test_sdr_only_downloads_successfully(self):
        self.assertEqual(self.selected_video(select([video('sdr', 1080, 1920, 'SDR'), AUDIO]))['format_id'], 'sdr')

    def test_unknown_range_does_not_block_download(self):
        self.assertEqual(self.selected_video(select([video('unknown', 1080, 1920, None), AUDIO]))['format_id'], 'unknown')

    def test_hdr_wins_at_equal_resolution(self):
        result = select([video('sdr', 1080, 1920, 'SDR'), video('hdr', 1080, 1920), AUDIO])
        self.assertEqual(self.selected_video(result)['format_id'], 'hdr')

    def test_progressive_hdr_fallback_has_audio(self):
        progressive = video('progressive', 1080, 1920)
        progressive['acodec'] = 'aac'
        self.assertEqual(select([progressive])['format_id'], 'progressive')

    def test_portrait_and_landscape_resolution(self):
        result = select([video('landscape', 1920, 1080), video('portrait', 1440, 2560), AUDIO])
        self.assertEqual(self.selected_video(result)['format_id'], 'portrait')

    def test_each_supported_hdr_label(self):
        for label in ['HLG', 'HDR10', 'HDR10+', 'HDR', 'PQ', 'DV', 'Dolby Vision']:
            with self.subTest(label=label):
                self.assertEqual(self.selected_video(select([video('hdr', 1080, 1920, label), AUDIO]))['format_id'], 'hdr')

    def test_mute_also_prioritizes_resolution(self):
        result = select([video('sdr', 2160, 3840, 'SDR'), video('hdr', 1080, 1920), AUDIO], 'mute')
        self.assertEqual(result['format_id'], 'sdr')
        self.assertEqual(result['acodec'], 'none')

    def test_source_video_is_not_converted_by_downloader(self):
        for mode in ARGUMENTS:
            opts = options(mode)
            self.assertFalse(opts['keepvideo'])
            self.assertFalse(opts.get('nocheckcertificate'))
            self.assertFalse(any(p['key'] in {'FFmpegVideoConvertor', 'FFmpegExtractAudio'} for p in opts['postprocessors']))


if __name__ == '__main__':
    unittest.main(verbosity=2)
