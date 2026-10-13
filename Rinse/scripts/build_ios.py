#!/usr/bin/env python3
"""Build with Apple's SDK, run native media tests, launch, then package a device IPA."""
from __future__ import annotations
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path
from prepare import prepare

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "Build"
LOGS = BUILD / "Logs"
TESTS = ["testJPEGRemovesMetadataAndAppliesOrientation", "testPNGHasUniqueFingerprintsWithoutPixelChanges",
         "testHEICRoundTrip", "testPNGWithoutFingerprintPadding", "testCorruptInputIsRejected",
         "testExtensionPixelLimitIsEnforced", "testCancellationIsNotASuccess", "testCRC32KnownVector",
         "testVideoMetadataAndAllFrames", "testEarlyAudioEOFKeepsAllVideoFrames",
         "testColorModelIsTechnicalButCameraModelIsSensitive"]

def run(args, log=None, capture=False):
    args = list(map(str, args))
    print("+", " ".join(args), flush=True)
    if log:
        with (LOGS / (log + ".log")).open("w") as output:
            proc = subprocess.Popen(args, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in proc.stdout:
                output.write(line)
                if not line.startswith(("    /", "    builtin-", "    cd ", "    export ")):
                    print(line, end="", flush=True)
            if proc.wait():
                raise RuntimeError(f"{log} failed; see Build/Logs/{log}.log")
        return
    value = subprocess.run(args, cwd=ROOT, check=True, text=True, capture_output=capture)
    return value.stdout if capture else None

def main():
    if sys.platform != "darwin":
        raise SystemExit("Use the GitHub Actions Rinse workflow or macOS with Xcode 26+.")
    LOGS.mkdir(parents=True, exist_ok=True)
    report = {"status": "in progress", "physical_iphone_testing": "Not performed",
              "source_revision": os.environ.get("GITHUB_SHA"), "required_tests": TESTS,
              "source_hashes": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in ROOT.rglob("*.swift")}}
    try:
        report["xcode"] = run(["xcodebuild", "-version"], capture=True).strip()
        report["sdk"] = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], capture=True).strip()
        if int(report["sdk"].split(".")[0]) < 26:
            raise RuntimeError("The Liquid Glass interface requires iOS SDK 26 or newer.")
        shipping = list((ROOT / "Core").glob("*.swift")) + list((ROOT / "App").glob("*.swift")) + list((ROOT / "Share").glob("*.swift"))
        forbidden = re.compile(r"URLSession|URLRequest|import\s+(Network|WebKit|CFNetwork)|https?://")
        if any(forbidden.search(p.read_text()) for p in shipping):
            raise RuntimeError("App source network audit failed.")
        report["static_network_audit"] = "passed; no listed network APIs or web URLs in shipping Swift code"
        prepare()
        report["artwork_sha256"] = hashlib.sha256((ROOT / "Artwork.jpg").read_bytes()).hexdigest()
        run(["xcodegen", "generate", "--spec", "project.yml"], log="project")
        report["xcodegen"] = run(["xcodegen", "--version"], capture=True).strip()
        number = os.environ.get("RINSE_BUILD_NUMBER", "1")
        common = ["xcodebuild", "-project", "Rinse.xcodeproj", "-scheme", "Rinse", "-derivedDataPath", BUILD / "DerivedData",
                  "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "DEVELOPMENT_TEAM=", f"CURRENT_PROJECT_VERSION={number}"]
        devices = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "--json"], capture=True))
        choices = []
        for runtime, values in devices["devices"].items():
            match = re.search(r"iOS-(\d+)(?:-(\d+))?", runtime)
            if match and int(match.group(1)) >= 26:
                for device in values:
                    if device.get("isAvailable") and device["name"].startswith("iPhone"):
                        choices.append(((int(match.group(1)), int(match.group(2) or 0), device["name"] == "iPhone 17 Pro", device["name"]), device))
        if not choices:
            raise RuntimeError("No iOS 26+ iPhone simulator is installed.")
        device = max(choices, key=lambda pair: pair[0])[1]
        udid = device["udid"]
        report["simulator"] = device["name"]
        sim = common + ["-configuration", "Debug", "-destination", "id=" + udid]
        run(sim + ["build-for-testing"], log="simulator-build")
        if device["state"] != "Booted": run(["xcrun", "simctl", "boot", udid])
        run(["xcrun", "simctl", "bootstatus", udid, "-b"], log="simulator-boot")
        results = BUILD / "TestResults.xcresult"
        if results.exists(): shutil.rmtree(results)
        run(sim + ["-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
                   "-default-test-execution-time-allowance", "120", "-maximum-test-execution-time-allowance", "180",
                   "-resultBundlePath", results, "test-without-building"], log="native-tests")
        transcript = (LOGS / "native-tests.log").read_text()
        passed = [name for name in TESTS if re.search(r"Test Case '[^\n]*\b" + re.escape(name) + r"\b[^\n]*' passed", transcript)]
        if passed != TESTS: raise RuntimeError("Every required native test must pass; missing: " + str(set(TESTS) - set(passed)))
        report["native_tests"] = {"status": "passed", "count": len(passed), "tests": passed}
        simulator_app = BUILD / "DerivedData/Build/Products/Debug-iphonesimulator/Rinse.app"
        run(["xcrun", "simctl", "install", udid, simulator_app])
        run(["xcrun", "simctl", "launch", udid, "com.billy.rinse"], log="simulator-launch")
        time.sleep(3)
        run(["xcrun", "simctl", "io", udid, "screenshot", BUILD / "Simulator-Launch.png"])
        report["simulator_launch"] = "passed; see Simulator-Launch.png"
        run(common + ["-configuration", "Release", "-destination", "generic/platform=iOS", "build"], log="iphone-build")
        app = BUILD / "DerivedData/Build/Products/Release-iphoneos/Rinse.app"
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if info["CFBundleIdentifier"] != "com.billy.rinse" or "iPhoneOS" not in info["CFBundleSupportedPlatforms"]:
            raise RuntimeError("The packaged binary is not the intended physical iPhone app.")
        if (app / "Rinse").read_bytes()[:4] != b"\xcf\xfa\xed\xfe": raise RuntimeError("Missing device Mach-O executable.")
        if not (app / "PrivacyInfo.xcprivacy").exists(): raise RuntimeError("Privacy manifest missing.")
        extension = app / "PlugIns/RinseShare.appex"
        if not (extension / "RinseShare").is_file(): raise RuntimeError("Share extension missing.")
        ipa = BUILD / "Rinse.ipa"
        with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(app.rglob("*")):
                if path.is_file(): archive.write(path, "Payload/Rinse.app/" + path.relative_to(app).as_posix())
        with zipfile.ZipFile(ipa) as archive:
            if archive.testzip() is not None: raise RuntimeError("IPA archive validation failed.")
        report.update(status="passed", version=info["CFBundleShortVersionString"], build=info["CFBundleVersion"],
                      ipa_sha256=hashlib.sha256(ipa.read_bytes()).hexdigest(), ipa_bytes=ipa.stat().st_size,
                      signing="Unsigned device IPA; sign with your own sideloading/developer tool")
    except Exception as error:
        report.update(status="failed", error=str(error)); raise
    finally:
        (BUILD / "BUILD-REPORT.json").write_text(json.dumps(report, indent=2) + "\n")

if __name__ == "__main__": main()
