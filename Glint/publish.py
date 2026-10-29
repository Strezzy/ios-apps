#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Publish only completed, tested archives; preserve every other catalog entry."""
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

REPO = os.environ.get('GITHUB_REPOSITORY', 'Strezzy/ios-apps')
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from scripts.update_catalog import inspect_ipa, readme_text
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
            'build-info.json', 'SHA256SUMS.txt', 'glint-tests.txt', 'engine-tests.txt', 'hdr-plugin-tests.txt',
            'selection-tests.txt', 'quality-arguments.json', 'catalog-tests.txt', 'paste-tests.txt', 'remux-tests.txt',
            'origin-tests.txt']
for filename in required:
    if not (DIST / filename).is_file() or (DIST / filename).stat().st_size == 0:
        raise RuntimeError(f'Missing build result: {filename}')
for line in (DIST / 'SHA256SUMS.txt').read_text().splitlines():
    expected, filename = line.split(None, 1)
    assert hashlib.sha256((DIST / filename.strip()).read_bytes()).hexdigest() == expected

# Validate catalog input before creating a publicly downloadable release.
ipa = DIST / 'Glint-LiveContainer.ipa'
ipa_info, ipa_permissions = inspect_ipa(ipa)
assert ipa_info['CFBundleIdentifier'] == BUILD['bundleIdentifier']
assert ipa_info['CFBundleVersion'] == BUILD['build']
metadata = json.loads((ROOT / 'app-registry.json').read_text())[BUILD['bundleIdentifier']]

notes = f'''# Glint 0.1.0 · Preview {BUILD['build']}

A warm Liquid Glass downloader with maximum-resolution selection, HDR support, a local library, queues, and protected local sign-in sessions.

Instagram is now a permanent tab in the native Liquid Glass bar. Library post and creator links open that same tab and browsing session. A floating Download button opens a compact link/paste composer and queues downloads into Library without changing the page or switching tabs. Navigation lives in a small menu; no oversized header, footer or Use login button. The current browser login is captured automatically for each download.

Save video offers only Save to Photos and Save to Files. Files opens the destination picker directly and exports the selected file unchanged, including VP9, without requiring playback or conversion. Photos prepares a compatible copy when possible. Source links remain available and can be copied without a share sheet.

VP9 and other FFmpeg-decodable formats can use a separate H.264 playback preview when Apple's native player cannot decode the source. Previews are clearly labeled, limited to 1080 pixels / 30 fps, tone-map explicit HLG/PQ to SDR, and live in a disposable cache. They never replace the source download or the full-quality Photos copy. Actual device decoder/encoder support still matters.

Full-quality conversion now checks a bounded sample of decoded frames for missing color and pixel-format metadata. Incomplete HDR metadata no longer triggers a blanket device-unsupported error: known tags are retained in 10-bit HEVC and unverified HDR stays labeled unverified. Copies that lose dimensions, timing, bit depth or known color tags are rejected, with the original retained.

The main action still chooses the highest exposed resolution, preferring HDR at that resolution. SDR and unknown-range videos remain downloadable. Paste handles URLs and shared text, and Instagram login remains optional for accessible public downloads.

Downloads are automatically checked for iPhone playback and Photos compatibility. When needed, Glint keeps an original in Files, tries MP4 with the existing video stream, then creates a high-quality HEVC/AAC copy. Library videos have a visible Save button for Photos or Files.

## Install
- **Glint.ipa** includes the Share Extension. Use your signing/sideloading installer.
- **Glint-LiveContainer.ipa** omits the extension for LiveContainer. Paste links inside Glint.
- Refresh the existing Strezzy’s Apps source after publication; no new source URL is required.

Unsigned archives require your installer to sign or prepare them. Minimum OS reported by the compiled app: **iOS {BUILD['minimumOS']}**.

## Quality
Source downloads do not resize or re-encode the service's stream. Compatibility conversion preserves dimensions, orientation, frame timing and verified HLG/PQ HDR, with a generous source- and resolution-based bitrate. Re-encoding is not lossless and does not preserve Dolby Vision dynamic metadata. The original is retained in Files → Glint → Originals before automatic preparation. If preparation cannot preserve these properties, Glint keeps the download and explains why a playable copy was unavailable. “Source” is the service's stream, not the creator's camera-original file.

## Verification and limitations
Native Xcode archive completed. Attached reports cover native URL/text paste payloads, provenance and cookie parsing, real yt-dlp selection fixtures, conversion safeguards, the engine and HDR plugin. Real host-FFmpeg fixtures cover lossless H.264 remux, VP9 HLG/PQ decoding, missing stream-tag recovery, HEVC source-size/color verification, H.264/AAC preview generation and failure cleanup. Host software encoders substitute for iPhone VideoToolbox in these tests. **Physical iPhone testing has not been performed for this release.** Live authenticated Instagram browsing, login/HDR retrieval, VideoToolbox conversion, Photos import, LiveContainer behavior, background continuation, and device thermals still need testing.

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
now = datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')
summary = metadata['localizedDescription']
version = {'version': BUILD['version'], 'buildVersion': BUILD['build'], 'buildNumber': BUILD['build'],
           'date': now, 'localizedDescription': summary, 'downloadURL': f'{BASE}/{ipa.name}',
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
    app.update({'name':'Glint', 'subtitle':metadata['subtitle'], 'developerName':'Strezzy',
                'localizedDescription':summary, 'category':'photo-video', 'tintColor':'#F05C29',
                'bundleIdentifier':BUILD['bundleIdentifier'], 'iconURL':f'https://raw.githubusercontent.com/{REPO}/main/assets/Glint.png',
                'versions':[version, *versions], 'version':BUILD['version'], 'versionDate':now,
                'versionDescription':summary, 'downloadURL':version['downloadURL'], 'size':version['size'],
                'appPermissions':ipa_permissions})
    if not matches:
        apps.append(app)
    return (json.dumps(catalog, ensure_ascii=False, indent=2) + '\n').encode()

put_file('apps.json', update_catalog, f"Publish Glint preview {BUILD['build']} in the existing app source")
def update_readme(old):
    # Include apps published while this archive was building; use the shared
    # renderer so future catalog rebuilds retain the Glint download listing.
    catalog = json.loads(base64.b64decode(api(f'repos/{REPO}/contents/apps.json?ref=main')['content']))
    template = base64.b64decode(api(f'repos/{REPO}/contents/scripts/README.template.md?ref=main')['content']).decode()
    return readme_text(catalog, template).encode()

put_file('README.md', update_readme, f"Link Glint preview {BUILD['build']} downloads")
print(f'Published https://github.com/{REPO}/releases/tag/{TAG}')
