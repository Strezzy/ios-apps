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
    artwork = ROOT / "Artwork.jpg"
    data = artwork.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    # Repair only the precisely identified three-byte transfer error in the
    # initial artwork upload. The final hash must match the original asset.
    if digest == "6fb6c49c63b355ff6f7503b291067301ca12b63df86ffe89a18b90927eb0516e":
        encoded = base64.b64encode(data)
        if encoded[144:148] != b"RUVF":
            raise RuntimeError("Unexpected artwork transfer error.")
        data = base64.b64decode(encoded[:144] + encoded[148:], validate=True)
        if hashlib.sha256(data).hexdigest() != ARTWORK_SHA256:
            raise RuntimeError("Artwork repair did not match the original source.")
        artwork.write_bytes(data)
    if hashlib.sha256(data).hexdigest() != ARTWORK_SHA256:
        raise RuntimeError("App artwork failed its source integrity check; do not publish this build.")
    assets = ROOT / "Assets.xcassets"
    icon = assets / "AppIcon.appiconset"
    brand = assets / "Brand.imageset"
    icon.mkdir(parents=True, exist_ok=True)
    brand.mkdir(parents=True, exist_ok=True)
    common = {"version": 1, "author": "xcode"}
    (assets / "Contents.json").write_text(json.dumps({"info": common}))
    subprocess.run(["sips", "-s", "format", "png", "-z", "1024", "1024", str(artwork), "--out", str(icon / "AppIcon.png")], check=True)
    (icon / "Contents.json").write_text(json.dumps({"images": [{"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "AppIcon.png"}], "info": common}))
    (brand / "Brand.jpg").write_bytes(data)
    (brand / "Contents.json").write_text(json.dumps({"images": [{"idiom": "universal", "filename": "Brand.jpg", "scale": "1x"}], "info": common}))
    manifest = {"NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": [],
                "NSPrivacyAccessedAPITypes": [
                    {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp", "NSPrivacyAccessedAPITypeReasons": ["C617.1"]},
                    {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryDiskSpace", "NSPrivacyAccessedAPITypeReasons": ["E174.1"]}]}
    (ROOT / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps(manifest))

if __name__ == "__main__":
    prepare()
