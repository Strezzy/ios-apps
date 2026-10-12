#!/usr/bin/env python3
"""Generate asset catalogs and the privacy manifest; no app-time downloads."""
import json
import plistlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def prepare():
    assets = ROOT / "Assets.xcassets"
    icon = assets / "AppIcon.appiconset"
    brand = assets / "Brand.imageset"
    icon.mkdir(parents=True, exist_ok=True)
    brand.mkdir(parents=True, exist_ok=True)
    common = {"version": 1, "author": "xcode"}
    (assets / "Contents.json").write_text(json.dumps({"info": common}))
    subprocess.run(["sips", "-s", "format", "png", "-z", "1024", "1024", str(ROOT / "Artwork.jpg"), "--out", str(icon / "AppIcon.png")], check=True)
    (icon / "Contents.json").write_text(json.dumps({"images": [{"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "AppIcon.png"}], "info": common}))
    (brand / "Brand.jpg").write_bytes((ROOT / "Artwork.jpg").read_bytes())
    (brand / "Contents.json").write_text(json.dumps({"images": [{"idiom": "universal", "filename": "Brand.jpg", "scale": "1x"}], "info": common}))
    manifest = {"NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": [],
                "NSPrivacyAccessedAPITypes": [
                    {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp", "NSPrivacyAccessedAPITypeReasons": ["C617.1"]},
                    {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryDiskSpace", "NSPrivacyAccessedAPITypeReasons": ["E174.1"]}]}
    (ROOT / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps(manifest))

if __name__ == "__main__":
    prepare()
