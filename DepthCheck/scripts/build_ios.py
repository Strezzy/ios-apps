#!/usr/bin/env python3
"""Compile, test and package Depth Check with Apple's actual iPhone SDK."""
from __future__ import annotations
import json
import os
import plistlib
import re
import shlex
import shutil
import stat
import subprocess
import sys
import time
import zipfile
from pathlib import Path
from generate_project import generate
from verify_ipa import verify

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "Build"
DERIVED = BUILD / "DerivedData"
BUNDLE = "com.billy.depthcheck"


def run(arguments, name=None, capture=False, check=True):
    arguments = [str(arg) for arg in arguments]
    print("+ " + shlex.join(arguments), flush=True)
    if name:
        logs = BUILD / "Logs"
        logs.mkdir(parents=True, exist_ok=True)
        with (logs / (name + ".log")).open("w") as log:
            process = subprocess.Popen(arguments, cwd=ROOT, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True, bufsize=1)
            for line in process.stdout:
                log.write(line)
                if not line.startswith(("    /", "    builtin-", "    cd ", "    export ")):
                    print(line, end="", flush=True)
            result = process.wait()
        if check and result:
            raise RuntimeError(f"{name} failed with exit {result}; see Build/Logs/{name}.log")
        return result
    result = subprocess.run(arguments, cwd=ROOT, capture_output=capture, text=True, check=check)
    return result.stdout if capture else result.returncode


def simulator_device():
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "--json"], capture=True))
    choices = []
    for runtime, items in devices["devices"].items():
        match = re.search(r"iOS-(\d+)(?:-(\d+))?", runtime)
        if not match or int(match.group(1)) < 26:
            continue
        version = (int(match.group(1)), int(match.group(2) or 0))
        for item in items:
            if item.get("isAvailable") and item.get("name", "").startswith("iPhone"):
                choices.append(((item["name"] == "iPhone 17 Pro", version), item))
    if not choices:
        raise RuntimeError("No iOS 26 or later iPhone simulator is installed on the runner.")
    return max(choices, key=lambda pair: pair[0])[1]


def metadata(app):
    if (app / "Resources").exists():
        raise RuntimeError("Reserved root Resources folder would break iOS bundle lookup.")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    for key, expected in {"CFBundleIdentifier": BUNDLE, "CFBundleExecutable": "DepthCheck",
                          "CFBundlePackageType": "APPL"}.items():
        if info.get(key) != expected:
            raise RuntimeError(f"Built bundle has incorrect {key}: {info.get(key)!r}")
    return info


def package(app):
    staging = BUILD / "Payload"
    if staging.exists():
        shutil.rmtree(staging)
    destination = staging / "DepthCheck.app"
    shutil.copytree(app, destination, symlinks=True)
    binary = destination / "DepthCheck"
    binary.chmod(binary.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    ipa = BUILD / "DepthCheck.ipa"
    with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(destination.rglob("*")):
            relative = path.relative_to(BUILD).as_posix()
            if path.is_symlink():
                entry = zipfile.ZipInfo(relative)
                entry.create_system = 3
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(entry, os.readlink(path))
            elif path.is_file():
                archive.write(path, relative)
    return ipa


def main():
    if sys.platform != "darwin":
        raise SystemExit("Depth Check must compile on macOS using Xcode 26 or later. Run the included GitHub Actions workflow.")
    BUILD.mkdir(exist_ok=True)
    source_plist = ROOT / "DepthCheck/Info.plist"
    info = plistlib.loads(source_plist.read_bytes())
    if os.environ.get("DEPTHCHECK_BUILD_NUMBER"):
        info["CFBundleVersion"] = os.environ["DEPTHCHECK_BUILD_NUMBER"]
        source_plist.write_bytes(plistlib.dumps(info))
    report = {"status": "in progress", "physical_iphone_validation": "Not performed",
              "source_revision": os.environ.get("GITHUB_SHA"),
              "xcode": run(["xcodebuild", "-version"], capture=True).strip(),
              "sdk": run(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], capture=True).strip()}
    try:
        if int(report["sdk"].split(".")[0]) < 26:
            raise RuntimeError("The native Liquid Glass build requires iOS SDK 26 or later.")
        if run(["xcrun", "--sdk", "iphoneos", "metal", "--version"], name="metal-check", check=False):
            run(["xcodebuild", "-downloadComponent", "metalToolchain"], name="metal-download")
        run([sys.executable, ROOT / "scripts/prepare_models.py"], name="prepare-models")
        report["project"] = generate()
        common = ["xcodebuild", "-project", ROOT / "DepthCheck.xcodeproj", "-scheme", "DepthCheck",
                  "-derivedDataPath", DERIVED]
        signing = ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "DEVELOPMENT_TEAM="]
        device = simulator_device()
        udid = device["udid"]
        if device.get("state") != "Booted":
            run(["xcrun", "simctl", "boot", udid])
        sim = common + ["-configuration", "Debug", "-destination", "id=" + udid,
                        "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", *signing]
        run(sim + ["build-for-testing"], name="simulator-build")
        run(["xcrun", "simctl", "bootstatus", udid, "-b"], name="simulator-boot")
        simulator_app = DERIVED / "Build/Products/Debug-iphonesimulator/DepthCheck.app"
        metadata(simulator_app)
        results = BUILD / "TestResults.xcresult"
        if results.exists():
            shutil.rmtree(results)
        run(sim + ["-parallel-testing-enabled", "NO", "-resultBundlePath", results, "test-without-building"], name="simulator-tests")
        report["tests"] = "passed; see TestResults.xcresult for executed and skipped tests"
        run(["xcrun", "simctl", "install", udid, simulator_app])
        run(["xcrun", "simctl", "launch", "--terminate-running-process", udid, BUNDLE], name="simulator-launch")
        time.sleep(3)
        launch_list = run(["xcrun", "simctl", "spawn", udid, "launchctl", "list"], capture=True)
        alive = any(BUNDLE in line and line.split() and line.split()[0].isdigit() for line in launch_list.splitlines())
        if not alive:
            raise RuntimeError("The app did not remain alive after its simulator launch.")
        run(["xcrun", "simctl", "io", udid, "screenshot", BUILD / "Simulator-Launch.png"])
        report["launch"] = {"status": "passed", "simulator": device["name"]}
        run(["xcrun", "simctl", "terminate", udid, BUNDLE], check=False)
        run(common + ["-configuration", "Release", "-sdk", "iphoneos", "-destination", "generic/platform=iOS",
                      "ARCHS=arm64", "ONLY_ACTIVE_ARCH=NO", *signing, "build"], name="iphone-build")
        app = DERIVED / "Build/Products/Release-iphoneos/DepthCheck.app"
        metadata(app)
        # Ad-hoc signature is for bundle integrity/LiveContainer; SideStore will
        # replace it with the user's device provisioning signature when installing.
        run(["codesign", "--force", "--sign", "-", "--timestamp=none", app], name="adhoc-sign")
        run(["codesign", "--verify", "--deep", "--strict", app], name="verify-signature")
        ipa = package(app)
        report["packaging"] = verify(ipa)
        report["status"] = "passed"
        print("Created " + str(ipa), flush=True)
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        raise
    finally:
        (BUILD / "BUILD-REPORT.json").write_text(json.dumps(report, indent=2) + "\n")
        results = BUILD / "TestResults.xcresult"
        if results.exists():
            run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", results,
                 "--compact"], name="test-summary", check=False)


if __name__ == "__main__":
    main()
