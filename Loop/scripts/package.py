from pathlib import Path
import hashlib
import json
import plistlib
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
build = root / 'Build'
app = build / 'Device/Build/Products/Release-iphoneos/Loop.app'
assert app.is_dir(), 'A native device build is required'
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.billy.loop'
assert 'iPhoneOS' in info['CFBundleSupportedPlatforms']
assert (app / 'PrivacyInfo.xcprivacy').is_file()
binary = app / info['CFBundleExecutable']
architecture = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).strip()
assert architecture == 'arm64', architecture
ipa = build / 'Loop.ipa'
with zipfile.ZipFile(ipa, 'w', zipfile.ZIP_DEFLATED) as archive:
    for item in sorted(app.rglob('*')):
        if item.is_file():
            archive.write(item, Path('Payload/Loop.app') / item.relative_to(app))
digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
report = {
    'product': 'Loop', 'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'], 'bundleIdentifier': info['CFBundleIdentifier'],
    'deploymentTarget': info['MinimumOSVersion'], 'sdk': info.get('DTSDKName'),
    'xcode': info.get('DTXcode'), 'configuration': 'Release',
    'distributionSigned': False, 'architecture': architecture,
    'implementation': 'Native SwiftUI, AVFoundation, Core Image, Vision; Metal portrait effects, bundled Core ML matting and aging; GIF, APNG, H.264 and HEVC',
    'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'ipaBytes': ipa.stat().st_size, 'sha256': digest,
    'physicalDeviceValidation': 'Not performed. Physical iPhone thermals, 4K long-export performance and sideload-host behavior require device testing.',
}
(build / 'BUILD-REPORT.json').write_text(json.dumps(report, indent=2) + '\n')
(build / 'SHA256SUMS.txt').write_text(digest + '  Loop.ipa\n')
print(json.dumps(report, indent=2))
