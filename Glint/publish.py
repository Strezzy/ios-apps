#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Publish only completed, tested archives; preserve every other catalog entry."""
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

REPO = os.environ.get('GITHUB_REPOSITORY', 'Strezzy/ios-apps')
ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / 'Glint/dist'
BUILD = json.loads((DIST / 'build-info.json').read_text())
TAG = BUILD['tag']
BASE = f'https://github.com/{REPO}/releases/download/{TAG}'


def gh(*args, payload=None, check=True):
    return subprocess.run(['gh', *args], input=json.dumps(payload) if payload is not None else None,
                          text=True, capture_output=True, check=check)


def api(endpoint, payload=None):
    args = ['api', endpoint]
    if payload is not None:
        args += ['--method', 'PUT', '--input', '-']
    result = gh(*args, payload=payload)
    return json.loads(result.stdout) if result.stdout.strip() else {}


def put_file(path, transform, message):
    for attempt in range(4):
        read = gh('api', f'repos/{REPO}/contents/{path}?ref=main', check=False)
        if read.returncode:
            if '404' not in read.stderr:
                raise RuntimeError(read.stderr)
            old = b''
            sha = None
        else:
            current = json.loads(read.stdout)
            old = base64.b64decode(current['content'])
            sha = current['sha']
        new = transform(old)
        if new == old:
            return
        request = {'message': message, 'content': base64.b64encode(new).decode(), 'branch': 'main'}
        if sha:
            request['sha'] = sha
        result = gh('api', f'repos/{REPO}/contents/{path}', '--method', 'PUT', '--input', '-', payload=request, check=False)
        if result.returncode == 0:
            return
        if '409' not in result.stderr and '422' not in result.stderr:
            raise RuntimeError(result.stderr)
        time.sleep(attempt + 1)
    raise RuntimeError(f'Concurrent edits prevented updating {path}. The release itself is available.')


required = ['Glint.ipa', 'Glint-LiveContainer.ipa', 'Glint-Source.zip', 'Glint.png',
            'build-info.json', 'SHA256SUMS.txt', 'glint-tests.txt', 'engine-tests.txt', 'hdr-plugin-tests.txt']
for filename in required:
    if not (DIST / filename).is_file() or (DIST / filename).stat().st_size == 0:
        raise RuntimeError(f'Missing build result: {filename}')
for line in (DIST / 'SHA256SUMS.txt').read_text().splitlines():
    expected, filename = line.split(None, 1)
    assert hashlib.sha256((DIST / filename.strip()).read_bytes()).hexdigest() == expected

notes = f'''# Glint 0.1.0 · Preview {BUILD['build']}

A warm Liquid Glass downloader with source-first selection, Instagram HDR extraction, a quality picker, a local library, queues, and protected local sign-in sessions.

## Install
- **Glint.ipa** includes the Share Extension. Use your signing/sideloading installer.
- **Glint-LiveContainer.ipa** omits the extension for LiveContainer. Paste links inside Glint.
- Refresh the existing Strezzy’s Apps source after publication; no new source URL is required.

Unsigned archives require your installer to sign or prepare them. Minimum OS reported by the compiled app: **iOS {BUILD['minimumOS']}**.

## Quality
Default video downloads copy the delivered encoded streams. HDR availability depends on the media and authenticated session. Library's quality inspector checks the saved file's actual color metadata. A Photos-compatible HEVC copy is optional and separate from the untouched source. Conversion does not preserve Dolby Vision metadata. “Source” is the service's stream, not the creator's camera-original file.

## Verification and limitations
Native Xcode archive completed and the attached automated tests passed. **Physical iPhone testing has not been performed for this release.** Real Instagram login/HDR retrieval, Photos import, LiveContainer behavior, background continuation, and device thermals still need testing. The media tests use a mocked native bridge and are not hardware encoder tests.

Automated Instagram access can trigger account verification or restrictions. Stop if challenged. Save only media you own or have permission to download.

Source, licenses, dependency provenance and SHA-256 checksums are attached. Built from repository commit `{os.environ.get('GITHUB_SHA', 'local')}`.
'''
notes_path = DIST / 'RELEASE-NOTES.md'
notes_path.write_text(notes)
existing = gh('release', 'view', TAG, '--repo', REPO, '--json', 'tagName', check=False)
if existing.returncode != 0:
    result = gh('release', 'create', TAG, *[str(DIST / name) for name in required], str(notes_path),
                '--repo', REPO, '--target', os.environ['GITHUB_SHA'], '--title', f"Glint 0.1.0 · Preview {BUILD['build']}",
                '--notes-file', str(notes_path), '--prerelease', '--latest=false')
    print(result.stdout)
else:
    raise RuntimeError('This immutable release tag already exists. Start a fresh workflow attempt instead of overwriting assets.')

# Publish the icon and catalog only after the release asset URLs exist.
put_file('assets/Glint.png', lambda _: (DIST / 'Glint.png').read_bytes(), 'Add Glint app icon')
ipa = DIST / 'Glint.ipa'
now = datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')
summary = 'Preview: native Liquid Glass downloader; source-first streams, reported HDR formats, saved-file HDR inspection and separate Photos copies. Compiled and automated-tested; physical iPhone behavior remains unverified.'
version = {'version': BUILD['version'], 'buildVersion': BUILD['build'], 'buildNumber': BUILD['build'],
           'date': now, 'localizedDescription': summary, 'downloadURL': f'{BASE}/Glint.ipa',
           'size': ipa.stat().st_size, 'minOSVersion': BUILD['minimumOS'],
           'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest()}

def update_catalog(old):
    catalog = json.loads(old)
    apps = catalog.setdefault('apps', [])
    matches = [app for app in apps if app.get('bundleIdentifier') == BUILD['bundleIdentifier']]
    if len(matches) > 1:
        raise RuntimeError('Multiple Glint catalog entries require reconciliation.')
    app = matches[0] if matches else {}
    versions = [entry for entry in app.get('versions', []) if entry.get('buildVersion') != BUILD['build']]
    app.update({'name':'Glint', 'subtitle':'Source-first video downloader', 'developerName':'Strezzy',
                'localizedDescription':summary, 'category':'utilities', 'tintColor':'#F05C29',
                'bundleIdentifier':BUILD['bundleIdentifier'], 'iconURL':f'https://raw.githubusercontent.com/{REPO}/main/assets/Glint.png',
                'versions':[version, *versions], 'version':BUILD['version'], 'versionDate':now,
                'versionDescription':summary, 'downloadURL':version['downloadURL'], 'size':version['size'],
                'appPermissions':{'entitlements':[], 'privacy':{'NSPhotoLibraryAddUsageDescription':'Glint adds videos to Photos only when you choose Save to Photos.'}}})
    if not matches:
        apps.append(app)
    return (json.dumps(catalog, ensure_ascii=False, indent=2) + '\n').encode()

put_file('apps.json', update_catalog, f"Publish Glint preview {BUILD['build']} in the existing app source")
block = f'''<!-- glint:start -->
## Glint

Native Liquid Glass media downloader with source-stream preservation, Instagram HDR extraction, quality inspection and optional separate Photos copies.

[Download Glint.ipa]({BASE}/Glint.ipa) · [LiveContainer version]({BASE}/Glint-LiveContainer.ipa) · [Release notes](https://github.com/{REPO}/releases/tag/{TAG}) · [Source](Glint/README.md)

Preview {BUILD['build']}. Compiled and automated-tested; real-device HDR, login and installation remain unverified. Refresh your existing Strezzy’s Apps source for the new listing.
<!-- glint:end -->'''

def update_readme(old):
    text = old.decode()
    if '<!-- glint:start -->' in text:
        text = re.sub(r'<!-- glint:start -->.*?<!-- glint:end -->', lambda _: block, text, flags=re.S)
    else:
        text = text.rstrip() + '\n\n' + block + '\n'
    return text.encode()

put_file('README.md', update_readme, f"Link Glint preview {BUILD['build']} downloads")
print(f'Published https://github.com/{REPO}/releases/tag/{TAG}')
