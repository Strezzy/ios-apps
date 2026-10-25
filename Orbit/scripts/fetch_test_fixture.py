#!/usr/bin/env python3
"""Fetch one checksum-pinned Apple sample into the unit-test bundle only."""
from pathlib import Path
import hashlib
import shutil
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://docs-assets.developer.apple.com/published/31c34ca0bfce/ProcessingSpatialVideoWithACustomVideoCompositor.zip'
ARCHIVE_SHA256 = '5768aca8301f5ae8a347c02adc7a5ea9c36dcc364ab0b56ac815d85b6e5b1b1b'
MOVIE_SHA256 = '7c8763d13fad98ba3157c9ae761f265389e2d6c8960b27c356c84511fb816ecf'
DESTINATION = ROOT / 'Tests/Fixtures/Spatial.mov'


def digest(path):
    hasher = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            hasher.update(chunk)
    return hasher.hexdigest()


if DESTINATION.is_file() and digest(DESTINATION) == MOVIE_SHA256:
    print('Using the verified Apple spatial-video test fixture.')
else:
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as folder:
        archive_path = Path(folder) / 'AppleSpatialSample.zip'
        request = urllib.request.Request(URL, headers={'User-Agent': 'Orbit-Spatial-Playback-Tests'})
        with urllib.request.urlopen(request, timeout=45) as response, archive_path.open('wb') as output:
            shutil.copyfileobj(response, output, length=1024 * 1024)
        assert digest(archive_path) == ARCHIVE_SHA256, 'Apple sample archive checksum changed'
        with zipfile.ZipFile(archive_path) as archive:
            member = 'Media/spatial_lighthouse_flowers_waves_short.mov'
            with archive.open(member) as source, DESTINATION.open('wb') as output:
                shutil.copyfileobj(source, output, length=1024 * 1024)
        assert digest(DESTINATION) == MOVIE_SHA256, 'Spatial video checksum mismatch'
    print('Verified the original Apple spatial-video sample for the test target.')
