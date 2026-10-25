#!/usr/bin/env python3
"""Package only a native arm64 iPhone build, preserving original build identity."""
from pathlib import Path
import hashlib
import json
import plistlib
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "Build"
APP = BUILD / "Device/Build/Products/Release-iphoneos/Orbit.app"
assert APP.is_dir(), "A native device build is required"
info = plistlib.loads((APP / "Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "com.billy.orbit"
assert info["CFBundleDisplayName"] == "Orbit"
assert "iPhoneOS" in info["CFBundleSupportedPlatforms"]
assert (APP / "PrivacyInfo.xcprivacy").is_file()
assert (APP / "default.metallib").is_file(), "The spatial renderer must be packaged"
architecture = subprocess.check_output(
    ["lipo", "-archs", str(APP / info["CFBundleExecutable"])], text=True
).strip()
assert architecture == "arm64", architecture
ipa = BUILD / "Orbit.ipa"
with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED) as archive:
    for item in sorted(APP.rglob("*")):
        if item.is_file():
            archive.write(item, Path("Payload/Orbit.app") / item.relative_to(APP))
hasher = hashlib.sha256()
with ipa.open("rb") as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b""):
        hasher.update(chunk)
digest = hasher.hexdigest()
report = {
    "product": "Orbit",
    "version": info["CFBundleShortVersionString"],
    "build": info["CFBundleVersion"],
    "bundleIdentifier": info["CFBundleIdentifier"],
    "deploymentTarget": info["MinimumOSVersion"],
    "sdk": info.get("DTSDKName"),
    "xcode": info.get("DTXcode"),
    "configuration": "Release",
    "distributionSigned": False,
    "architecture": architecture,
    "implementation": "Native SwiftUI, AVFoundation stereo video output, Metal depth-aware rendering, Core Motion",
    "sourceCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
    "ipaBytes": ipa.stat().st_size,
    "sha256": digest,
    "physicalDeviceValidation": "Not performed. Real spatial-video quality, motion, thermals, and sideload-host behavior require testing on iPhone.",
}
(BUILD / "BUILD-REPORT.json").write_text(json.dumps(report, indent=2) + "\n")
(BUILD / "SHA256SUMS.txt").write_text(digest + "  Orbit.ipa\n")
print(json.dumps(report, indent=2))
