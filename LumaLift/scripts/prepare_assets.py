#!/usr/bin/env python3
import json
import plistlib
from pathlib import Path
import shutil
import subprocess
ROOT = Path(__file__).resolve().parents[1]
def main():
    assets = ROOT / 'Resources/Assets.xcassets'
    for path in [assets, assets / 'AppIcon.appiconset', assets / 'BrandMark.imageset']:
        path.mkdir(parents=True, exist_ok=True)
    meta = {'info': {'version': 1, 'author': 'xcode'}}
    (assets / 'Contents.json').write_text(json.dumps(meta))
    icon = assets / 'AppIcon.appiconset/AppIcon.png'
    subprocess.run(['swift', str(ROOT / 'scripts/Icon.swift'), str(icon)], check=True)
    (assets / 'AppIcon.appiconset/Contents.json').write_text(json.dumps(dict(meta, images=[{'idiom':'universal', 'platform':'ios', 'size':'1024x1024', 'filename':'AppIcon.png'}])))
    shutil.copyfile(icon, assets / 'BrandMark.imageset/BrandMark.png')
    (assets / 'BrandMark.imageset/Contents.json').write_text(json.dumps(dict(meta, images=[{'idiom':'universal','filename':'BrandMark.png'}])))
    privacy = {'NSPrivacyTracking': False, 'NSPrivacyTrackingDomains': [], 'NSPrivacyCollectedDataTypes': [],
        'NSPrivacyAccessedAPITypes': [
            {'NSPrivacyAccessedAPIType': key, 'NSPrivacyAccessedAPITypeReasons': [reason]}
            for key, reason in [('NSPrivacyAccessedAPICategoryUserDefaults','CA92.1'),
                ('NSPrivacyAccessedAPICategoryFileTimestamp','C617.1'),
                ('NSPrivacyAccessedAPICategorySystemBootTime','35F9.1'),
                ('NSPrivacyAccessedAPICategoryDiskSpace','E174.1')]]}
    (ROOT / 'Resources/PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps(privacy))
if __name__ == '__main__': main()
