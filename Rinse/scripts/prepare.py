#!/usr/bin/env python3
"""Generate verified asset catalogs and the privacy manifest; no app-time downloads."""
import base64
import hashlib
import json
import plistlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARTWORK_SHA256 = "7111cd2c8c6a1f1e326d36e803a9348d608acead841b04c1108f1c95d0aa3fbc"

def prepare():
    artwork = ROOT / "Artwork.png"
    data = artwork.read_bytes()
    expected = "a1dde20ed7acb7e18803da9425ec67aa5fe7fe58"
    blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    if blob != expected:
        raise RuntimeError("Veil artwork failed its approved-source integrity check.")
    assets = ROOT / "Assets.xcassets"
    icon = assets / "AppIcon.appiconset"
    brand = assets / "Brand.imageset"
    icon.mkdir(parents=True, exist_ok=True)
    brand.mkdir(parents=True, exist_ok=True)
    common = {"version": 1, "author": "xcode"}
    (assets / "Contents.json").write_text(json.dumps({"info": common}))
    subprocess.run(["sips", "-s", "format", "png", "-z", "1024", "1024", str(artwork), "--out", str(icon / "AppIcon.png")], check=True)
    (icon / "Contents.json").write_text(json.dumps({"images": [{"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "AppIcon.png"}], "info": common}))
    (brand / "Brand.png").write_bytes(data)
    (brand / "Contents.json").write_text(json.dumps({"images": [{"idiom": "universal", "filename": "Brand.png", "scale": "1x"}], "info": common}))
    manifest = {"NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": [],
                "NSPrivacyAccessedAPITypes": [
                    {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp", "NSPrivacyAccessedAPITypeReasons": ["C617.1"]},
                    {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryDiskSpace", "NSPrivacyAccessedAPITypeReasons": ["E174.1"]}]}
    (ROOT / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps(manifest))

if __name__ == "__main__":
    prepare()
