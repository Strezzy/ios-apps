#!/usr/bin/env python3
"""Build with Apple's SDK, prove native WebGL startup, and package the iPhone IPA.

Requires macOS with Xcode 26+ and an installed iPhone simulator. No third-party
Python packages, SDK downloads, signing credentials, or remote game assets.
"""
from __future__ import annotations
import hashlib
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
from build_project import generate
from verify_ipa import verify, require

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "Build"
DERIVED = BUILD / "DerivedData"
BUNDLE = "com.billy.moonhop"
IPA_NAME = "EnterTheThirdDimension.ipa"
SOURCE_NAME = "EnterTheThirdDimension-Source.zip"


def run(arguments, name=None, timeout=180, check=True):
    arguments = [str(arg) for arg in arguments]
    print("+ " + shlex.join(arguments), flush=True)
    result = subprocess.run(arguments, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=timeout)
    if name:
        logs = BUILD / "Logs"
        logs.mkdir(parents=True, exist_ok=True)
        (logs / (name + ".log")).write_text(result.stdout)
    if result.returncode and check:
        print(result.stdout[-10000:], flush=True)
        raise RuntimeError(f"{name or arguments[0]} failed with exit {result.returncode}")
    if name:
        for line in result.stdout.splitlines():
            if "error:" in line.lower() or "warning:" in line.lower():
                print(line[:500], flush=True)
    return result


def simulator_device():
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "--json"]).stdout)
    choices = []
    for runtime, items in devices["devices"].items():
        match = re.search(r"iOS-(\d+)(?:-(\d+))?", runtime)
        if not match or int(match.group(1)) < 16:
            continue
        version = (int(match.group(1)), int(match.group(2) or 0))
        for item in items:
            if item.get("isAvailable") and item.get("name", "").startswith("iPhone"):
                choices.append(((item["name"] == "iPhone 17 Pro", version, item["name"]), item, runtime))
    if not choices:
        raise RuntimeError("No available iPhone simulator is installed in Xcode")
    _, device, runtime = max(choices, key=lambda choice: choice[0])
    return device, runtime


def metadata(app, platform):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    expected = {"CFBundleIdentifier": BUNDLE, "CFBundleExecutable": "ThirdDimension",
                "CFBundleShortVersionString": "2.1", "CFBundleVersion": "3",
                "CFBundleSupportedPlatforms": [platform]}
    for key, value in expected.items():
        require(info.get(key) == value, f"Built bundle has incorrect {key}: {info.get(key)!r}")
    require(not (app / "Resources").exists(), "Reserved root Resources folder would break bundle lookup")
    require((app / "Game/index.html").is_file(), "Game folder was not preserved during resource copying")
    return info


def validate_native_readiness(result):
    require(result.get("ready") is True, "The native host did not observe game readiness")
    require(result.get("errors") == [], "The bundled game raised a startup JavaScript error")
    require(result.get("bundleIdentifier") == BUNDLE, "Readiness report came from the wrong app")
    require(result.get("version") == "2.1" and result.get("build") == "3", "Readiness report has the wrong app version")
    require(result.get("bundledEntry") == "index.html", "The native host did not load the bundled game entry")
    require(result.get("nativeViewWidth", 0) > result.get("nativeViewHeight", 0) > 0, "Native view did not launch in landscape")
    state = result.get("state")
    require(isinstance(state, dict), "The initialized game returned no state")
    renderer = state.get("renderer")
    require(isinstance(renderer, dict), "The initialized game returned no renderer state")
    require("webgl" in str(renderer.get("api", "")).lower(), "The renderer did not report a WebGL context")
    require(renderer.get("artStyle") == "smooth mystical rainforest", "The current rainforest renderer did not initialize")
    require(renderer.get("contextLost") is False, "The renderer reports a lost or unknown graphics context")
    frames = renderer.get("frames")
    require(isinstance(frames, (int, float)) and frames > 0, "No frame was rendered before native readiness")
    water = renderer.get("water")
    require(isinstance(water, dict) and water.get("initialized") is True,
            "The raindrop character's shader did not initialize")
    require(isinstance(water.get("draws"), (int, float)) and water["draws"] > 0,
            "The raindrop character was not rendered before native readiness")
    require(water.get("errors") == [], "The raindrop material reported a graphics error")


def smoke_launch(app, device, runtime):
    udid = device["udid"]
    if device.get("state") != "Booted":
        run(["xcrun", "simctl", "boot", udid], name="simulator-boot-command")
    run(["xcrun", "simctl", "bootstatus", udid, "-b"], name="simulator-boot", timeout=360)
    # Build evidence must be produced by this launch, not a prior installation.
    run(["xcrun", "simctl", "uninstall", udid, BUNDLE], check=False)
    run(["xcrun", "simctl", "install", udid, app], name="simulator-install")
    container = Path(run(["xcrun", "simctl", "get_app_container", udid, BUNDLE, "data"]).stdout.strip())
    proof = container / "Documents/ThirdDimension-Native-Smoke.json"
    proof.unlink(missing_ok=True)
    run(["xcrun", "simctl", "launch", "--terminate-running-process", udid, BUNDLE,
         "--native-smoke-test"], name="simulator-launch")
    deadline = time.monotonic() + 90
    result = None
    while time.monotonic() < deadline:
        if proof.is_file():
            try:
                candidate = json.loads(proof.read_text())
            except (OSError, json.JSONDecodeError):
                candidate = None
            if candidate and not candidate.get("loading"):
                result = candidate
                break
        time.sleep(0.25)
    require(result is not None, "No native JavaScript readiness proof arrived within 90 seconds")
    (BUILD / "Native-Launch.json").write_text(json.dumps(result, indent=2) + "\n")
    validate_native_readiness(result)
    launch_list = run(["xcrun", "simctl", "spawn", udid, "launchctl", "list"]).stdout
    alive = any(BUNDLE in line and line.split() and line.split()[0].isdigit() for line in launch_list.splitlines())
    require(alive, "The app terminated after its native readiness handshake")
    run(["xcrun", "simctl", "io", udid, "screenshot", BUILD / "Simulator-Launch.png"], name="simulator-screenshot")
    run(["xcrun", "simctl", "terminate", udid, BUNDLE], check=False)
    return {"status": "passed", "simulator": device["name"], "runtime": runtime,
            "native_process_alive": True, "landscape_view": True,
            "bundled_javascript_ready": True, "webgl_frame_rendered": True,
            "water_material_initialized": True, "water_character_rendered": True,
            "rainforest_renderer": "smooth mystical rainforest",
            "readiness_evidence": "Native-Launch.json", "screenshot": "Simulator-Launch.png"}


def package(app):
    payload = BUILD / "Payload"
    if payload.exists():
        shutil.rmtree(payload)
    destination = payload / "ThirdDimension.app"
    shutil.copytree(app, destination, symlinks=True)
    executable = destination / "ThirdDimension"
    executable.chmod(executable.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    ipa = BUILD / IPA_NAME
    with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
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


def package_sources():
    target = BUILD / SOURCE_NAME
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(ROOT.rglob("*")):
            relative = path.relative_to(ROOT)
            if not path.is_file() or any(part in {"Build", "Build-Mac", ".git", "__pycache__", ".DS_Store"} for part in relative.parts):
                continue
            archive.write(path, "EnterTheThirdDimension/" + relative.as_posix())
        workflow = ROOT.parent / ".github/workflows/third-dimension.yml"
        if workflow.is_file():
            archive.write(workflow, ".github/workflows/third-dimension.yml")
    return target


def main():
    if sys.platform != "darwin":
        raise SystemExit("Run build-macos.sh on macOS with Xcode, or use the third-dimension GitHub Actions workflow.")
    BUILD.mkdir(exist_ok=True)
    report = {"status": "in progress", "app": "Enter the Third Dimension", "version": "2.1", "build": "3",
              "source_revision": os.environ.get("GITHUB_SHA"), "native_headers": "Apple SDK only",
              "physical_iphone_validation": "Not performed", "simulator_validation": "Not run"}
    try:
        report["xcode"] = run(["xcodebuild", "-version"]).stdout.strip()
        report["iphoneos_sdk"] = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"]).stdout.strip()
        require(int(report["iphoneos_sdk"].split(".")[0]) >= 26, "Xcode with iPhoneOS SDK 26+ is required")
        project = generate()
        device, runtime = simulator_device()
        base = ["xcodebuild", "-quiet", "-project", project, "-scheme", "ThirdDimension",
                "-derivedDataPath", DERIVED]
        signing = ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "DEVELOPMENT_TEAM="]
        run(base + ["-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", "id=" + device["udid"],
                    "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", *signing, "build"], name="simulator-build", timeout=600)
        simulator_app = DERIVED / "Build/Products/Debug-iphonesimulator/ThirdDimension.app"
        metadata(simulator_app, "iPhoneSimulator")
        run(["codesign", "--force", "--sign", "-", "--timestamp=none", simulator_app], name="simulator-sign")
        report["simulator_validation"] = smoke_launch(simulator_app, device, runtime)
        run(base + ["-configuration", "Release", "-sdk", "iphoneos", "-destination", "generic/platform=iOS",
                    "ARCHS=arm64", "ONLY_ACTIVE_ARCH=NO", *signing, "build"], name="iphone-build", timeout=600)
        device_app = DERIVED / "Build/Products/Release-iphoneos/ThirdDimension.app"
        metadata(device_app, "iPhoneOS")
        run(["codesign", "--force", "--sign", "-", "--timestamp=none", device_app], name="iphone-sign")
        run(["codesign", "--verify", "--deep", "--strict", device_app], name="verify-signature")
        ipa = package(device_app)
        report["packaging"] = verify(ipa)
        source = package_sources()
        report["source_archive"] = {"filename": source.name, "bytes": source.stat().st_size,
                                    "sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
        report["status"] = "passed"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        raise
    finally:
        (BUILD / "BUILD-REPORT.json").write_text(json.dumps(report, indent=2) + "\n")
    files = [BUILD / name for name in (IPA_NAME, SOURCE_NAME, "BUILD-REPORT.json", "Native-Launch.json", "Simulator-Launch.png")]
    (BUILD / "SHA256SUMS.txt").write_text("".join(hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name + "\n" for path in files))
    print(json.dumps({"status": report["status"], "ipa": str(BUILD / IPA_NAME),
                      "native_simulator_smoke": "passed", "device_compile_and_package": "passed",
                      "sha256": report["packaging"]["sha256"]}, indent=2), flush=True)


if __name__ == "__main__":
    main()
