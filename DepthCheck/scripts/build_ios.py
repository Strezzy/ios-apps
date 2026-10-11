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
from run_macos_media_checks import (SPATIAL_TEST_NAME, SUSTAINED_TEST_NAMES, case_passed,
                                    manifest_matches_current_sources, native_result_passed)
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


def validate_spatial_video(report, run_native=True):
    """Run required native media checks early; reuse the same evidence later."""
    previous_native = report.get("native_media_validation", {})
    logs = BUILD / "Logs"
    logs.mkdir(parents=True, exist_ok=True)
    simulator_log = logs / "simulator-tests.log"
    # The first invocation precedes simulator tests. Ignore any log from a
    # previous local build until the current simulator execution has completed.
    transcript = simulator_log.read_text(errors="replace") if not run_native and simulator_log.exists() else ""
    # These lines come from the unchanged spatial XCTest and XCTest's own
    # completion message. Ambiguous or absent observations are never a pass.
    capabilities = re.findall(r"\[DepthCheckTests\] VTIsStereoMVHEVCEncodeSupported = (true|false)", transcript)
    outcomes = re.findall(r"Test Case '[^'\n]*\b" + re.escape(SPATIAL_TEST_NAME)
                          + r"\b[^'\n]*' (passed|failed|skipped)\b", transcript)
    simulator = {
        "encoder_available": (capabilities[0] == "true") if capabilities and len(set(capabilities)) == 1 else None,
        "test": SPATIAL_TEST_NAME,
        "status": "not run" if run_native else (outcomes[0] if len(outcomes) == 1 else ("not observed" if not outcomes else "ambiguous")),
        "observed_completions": len(outcomes),
        "log": "Build/Logs/simulator-tests.log",
    }
    validation = {"status": "not validated", "validated_platforms": [], "simulator": simulator,
                  "physical_iphone": "Not performed"}
    report["spatial_video_validation"] = validation
    host_supported = report.get("macos_host_capabilities", {}).get("stereo_mv_hevc_encoder") is True
    native = (dict(previous_native) if not run_native
              else {"status": "not run", "stereo_encoder_available": host_supported})
    report["native_media_validation"] = native
    if run_native:
        native["status"] = "in progress"
        native["log"] = "Build/Logs/macos-native-media.log"
        result_path = BUILD / "HostChecks/native-media-result.json"
        manifest_path = BUILD / "HostChecks/build-manifest.json"
        artifacts = ((result_path, logs / "macos-native-media-result.json", "result"),
                     (manifest_path, logs / "macos-native-build-manifest.json", "build_manifest"))
        for source, destination, _ in artifacts:
            # Do not report a stale result if tool discovery fails before the
            # harness recreates its generated bundle.
            source.unlink(missing_ok=True)
            destination.unlink(missing_ok=True)
        try:
            native["exit_code"] = run([sys.executable, ROOT / "scripts/run_macos_media_checks.py",
                                      "--stereo-available", "true" if host_supported else "false"],
                                      name="macos-native-media", check=False)
        except Exception as error:
            native["runner_error"] = str(error)
        finally:
            # Logs is already uploaded by the workflow even on failed builds.
            # Embed the same evidence in the release's BUILD-REPORT.json.
            for source, destination, key in artifacts:
                if source.is_file():
                    shutil.copy2(source, destination)
                    try:
                        native[key] = json.loads(source.read_text())
                    except (OSError, ValueError) as error:
                        native[key + "_error"] = str(error)
    # The 874-frame EOF regression, early-audio EOF, three-minute timeline, and
    # both 920-frame and 10,800-frame full 4K60 SBS exports are mandatory even
    # without stereo MV-HEVC.
    # Re-check the same saved evidence after simulator execution; never rebuild
    # or rerun native cases and never count a skipped method as a pass.
    result = native.get("result", {})
    manifest = native.get("build_manifest", {})
    source_match = manifest_matches_current_sources(manifest)
    native_passed = (native.get("exit_code") == 0 and source_match
                     and native_result_passed(result, host_supported))
    native["status"] = "passed" if native_passed else "failed"
    native["compiled_source_hashes_match"] = source_match
    if not native_passed:
        native["reason"] = "The native host did not prove every required sustained media test and available spatial encoder test completed without failures or skips."
    cases = result.get("results", []) if isinstance(result, dict) else []
    cases = cases if isinstance(cases, list) else []
    by_name = {case.get("test"): case for case in cases if isinstance(case, dict)}
    sustained_cases = [by_name.get(name, {"test": name, "status": "not run"}) for name in SUSTAINED_TEST_NAMES]
    sustained_passed = source_match and all(case_passed(case, name)
                                            for case, name in zip(sustained_cases, SUSTAINED_TEST_NAMES))
    report["sustained_video_validation"] = {
        "status": "passed" if sustained_passed else "failed",
        "platform": "macOS host",
        "required_test_names": list(SUSTAINED_TEST_NAMES),
        "cases": [{key: case[key] for key in ("test", "status", "coverage", "duration_seconds",
                                               "process_duration_seconds", "timeout_seconds") if key in case}
                  for case in sustained_cases],
        "depth_inference": "Injected deterministic depth; the production renderer and media pipeline are unchanged.",
        "physical_iphone": "Not performed by this harness",
        "log": "Build/Logs/macos-native-media.log",
    }
    spatial_case = by_name.get(SPATIAL_TEST_NAME, {})
    native_spatial_passed = source_match and case_passed(spatial_case, SPATIAL_TEST_NAME)
    validation["macos_host"] = {
        "encoder_available": host_supported,
        "test": SPATIAL_TEST_NAME,
        "status": "passed" if native_spatial_passed else ("failed" if host_supported else "unsupported"),
        "result": spatial_case,
        "log": "Build/Logs/macos-native-media.log",
    }

    if simulator["status"] == "passed":
        validation["validated_platforms"].append("iOS Simulator")
    if native_spatial_passed:
        validation["validated_platforms"].append("macOS host")
    if host_supported and not native_spatial_passed:
        validation["status"] = "failed"
    elif validation["validated_platforms"]:
        validation["status"] = "passed"
    else:
        if not host_supported and simulator["encoder_available"] is False:
            validation["limitation"] = (
                "Neither the iOS simulator nor the macOS build host exposed a stereo MV-HEVC encoder. "
                "Native spatial video encoding was not validated. A compatible physical device or test host is required. "
                "Passing side-by-side, photo, model, or geometry tests does not validate MV-HEVC video."
            )
        else:
            validation["limitation"] = (
                "No successful execution of the native spatial-video test was recorded. "
                "MV-HEVC video remains unvalidated; other format tests do not establish its correctness."
            )
    print("Spatial video validation: " + json.dumps({key: validation.get(key) for key in
          ("status", "validated_platforms", "limitation")}), flush=True)
    print("Required native sustained video validation: " + report["sustained_video_validation"]["status"], flush=True)
    return native_passed


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
        capability_probe = '''import Foundation
import Metal
import VideoToolbox
let values: [String: Any] = [
    "stereo_mv_hevc_encoder": VTIsStereoMVHEVCEncodeSupported(),
    "metal_device": MTLCreateSystemDefaultDevice()?.name ?? "none",
    "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory
]
let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
'''
        report["macos_host_capabilities"] = json.loads(run(
            ["xcrun", "swift", "-target", "arm64-apple-macosx26.0", "-e", capability_probe], capture=True))
        if run(["xcrun", "--sdk", "iphoneos", "metal", "--version"], name="metal-check", check=False):
            run(["xcodebuild", "-downloadComponent", "metalToolchain"], name="metal-download")
        # Surface native harness/compiler/encoder errors before downloading
        # models or waiting for the simulator's first-boot migration.
        if not validate_spatial_video(report):
            raise RuntimeError("Required native macOS media validation failed; see Build/Logs/macos-native-media.log")
        run([sys.executable, ROOT / "scripts/prepare_models.py"], name="prepare-models")
        report["project"] = generate()
        common = ["xcodebuild", "-project", ROOT / "DepthCheck.xcodeproj", "-scheme", "DepthCheck",
                  "-derivedDataPath", DERIVED]
        signing = ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "DEVELOPMENT_TEAM="]
        device = simulator_device()
        udid = device["udid"]
        sim = common + ["-configuration", "Debug", "-destination", "id=" + udid,
                        "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", *signing]
        run(sim + ["build-for-testing"], name="simulator-build")
        # First-boot migration and Swift compilation compete for the hosted
        # runner's memory. Compile first, then let migration run on its own.
        if device.get("state") != "Booted":
            run(["xcrun", "simctl", "boot", udid])
        run(["xcrun", "simctl", "bootstatus", udid, "-b"], name="simulator-boot")
        simulator_app = DERIVED / "Build/Products/Debug-iphonesimulator/DepthCheck.app"
        metadata(simulator_app)
        results = BUILD / "TestResults.xcresult"
        if results.exists():
            shutil.rmtree(results)
        simulator_test_exit = run(sim + ["-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
                                        "-default-test-execution-time-allowance", "180",
                                        "-maximum-test-execution-time-allowance", "300",
                                        "-resultBundlePath", results, "test-without-building"],
                                  name="simulator-tests", check=False)
        # Combine the current simulator outcome with the already completed
        # native check. Do not compile or run the native harness a second time.
        native_media_passed = validate_spatial_video(report, run_native=False)
        failures = []
        if simulator_test_exit:
            failures.append(f"Simulator tests failed with exit {simulator_test_exit}; see Build/Logs/simulator-tests.log")
        if not native_media_passed:
            failures.append("Required native macOS media validation failed; see Build/Logs/macos-native-media.log")
        if failures:
            raise RuntimeError("; ".join(failures))
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
        results = BUILD / "TestResults.xcresult"
        if results.exists():
            try:
                summary = json.loads(run(["xcrun", "xcresulttool", "get", "test-results", "summary",
                                          "--path", results, "--compact"], capture=True))
                report["tests"] = summary
                (BUILD / "Logs/test-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
                print("Native test summary: " + json.dumps({key: summary.get(key) for key in
                      ["result", "totalTestCount", "passedTests", "failedTests", "skippedTests"]}), flush=True)
            except Exception as summary_error:
                report["test_summary_error"] = str(summary_error)
        (BUILD / "BUILD-REPORT.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
