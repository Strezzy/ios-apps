#!/usr/bin/env python3
"""Restore the exact prepared source edits, refusing an unexpected baseline."""
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import zlib

root = Path(__file__).resolve().parents[1]
packed = (root / 'MusicPolish/edits.zlib.b64').read_text().strip()
# Correct three identified transport transcription defects before validating
# the original, uncompressed candidate against its independently computed hash.
packed = packed.replace('HYSZZ0G', 'HYSZ0G').replace('tunREz3Z1', 'tunEmnREz3Z1').replace('qthwtDdj', 'qthwtMdj')
data = zlib.decompress(base64.b64decode(packed, validate=True))
assert hashlib.sha256(data).hexdigest() == '05a012b05dadc66f5175c577813526ce0f4bdc27ca09db6c940c873b79a9b70f', 'Candidate transport checksum mismatch'
for change in json.loads(data):
    path = root / change['path']
    source = path.read_bytes()
    current = hashlib.sha256(source).hexdigest()
    if current == change['after']:
        continue
    assert current == change['before'], f'Baseline changed: {path}'
    lines = source.decode().splitlines(keepends=True)
    for start, end, replacement in reversed(change['edits']):
        lines[start:end] = [replacement]
    result = ''.join(lines).encode()
    assert hashlib.sha256(result).hexdigest() == change['after'], f'Candidate mismatch: {path}'
    path.write_bytes(result)
    print('Verified candidate source:', change['path'])
info_path = root / 'Music/Resources/Info.plist'
info = plistlib.loads(info_path.read_bytes())
assert info['CFBundleIdentifier'] == 'com.billy.glassmusic'
assert (info['CFBundleShortVersionString'], info['CFBundleVersion']) in [('0.12', '13'), ('0.13', '14')]
info['CFBundleShortVersionString'] = '0.13'
info['CFBundleVersion'] = '14'
info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
(root / 'Music/Verification-0.13').mkdir(exist_ok=True)
print('Music 0.13 (14) source prepared. No release or catalog has been changed.')
