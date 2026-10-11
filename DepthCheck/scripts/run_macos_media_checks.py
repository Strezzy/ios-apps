#!/usr/bin/env python3
"""Run existing sustained-video and spatial XCTests against the actual code on macOS.

The iOS build requires the sustained tests on its native Mac. The spatial test
is additionally required whenever that host exposes an MV-HEVC encoder.
This does not build or modify the iPhone app. It uses the selected Xcode's own
Swift, Metal and XCTest tools, and never downloads or loads the depth models.

Usage: python3 scripts/run_macos_media_checks.py
Evidence: Build/HostChecks/native-media-result.json and build-manifest.json

The production module and XCTest executable compile once. Exact individual
tests then run in order, each in a fresh process, retaining every prior result
if a later case fails or times out. The full 4K60 test has a 900-second deadline.
An unsupported required capability, missing test, skipped test, failure, or
missing evidence is an unsuccessful validation and never produces a pass.
"""

from __future__ import annotations

import argparse
from fractions import Fraction
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "Build" / "HostChecks"
SPATIAL_TEST_NAME = "testSpatialVideoPreservesBothEyeLayersAndLastFrameDurationWithLongerAudio"
SUSTAINED_TEST_NAMES = (
    "test874FramesWithAudioTailReproduce920FrameEstimate",
    "test920FramesOf60FPSSBSWithAACEndingBeforeVideo",
    "testThreeMinute60FPSSBSWithDelayedAAC",
    "test920FramesOf4K60FPSPreservesFullSBSWithAAC",
)
TEST_TIMEOUTS = {
    SUSTAINED_TEST_NAMES[0]: 300,
    SUSTAINED_TEST_NAMES[1]: 300,
    SUSTAINED_TEST_NAMES[2]: 600,
    SUSTAINED_TEST_NAMES[3]: 900,
    SPATIAL_TEST_NAME: 300,
}
SUSTAINED_REQUIREMENTS = {
    SUSTAINED_TEST_NAMES[0]: (640, 360, 874, Fraction(920, 60)),
    SUSTAINED_TEST_NAMES[1]: (640, 360, 920, Fraction(920, 60)),
    SUSTAINED_TEST_NAMES[2]: (160, 90, 10_800, Fraction(180) + Fraction(137, 1000)),
    SUSTAINED_TEST_NAMES[3]: (3840, 2160, 920, Fraction(920, 60) + Fraction(137, 1000)),
}
SUSTAINED_AUDIO_RANGES = {
    SUSTAINED_TEST_NAMES[0]: (Fraction(0), Fraction(920, 60)),
    SUSTAINED_TEST_NAMES[1]: (Fraction(0), Fraction(920, 60) - 2),
    SUSTAINED_TEST_NAMES[2]: (Fraction(9, 4), Fraction(180) + Fraction(137, 1000)),
    SUSTAINED_TEST_NAMES[3]: (Fraction(0), Fraction(920, 60) + Fraction(137, 1000)),
}
RESULT_PATH = BUILD / "native-media-result.json"
PRODUCTION_FILES = (
    "DepthCheck/Core/Domain.swift",
    "DepthCheck/Imaging/StereoRenderer.swift",
    "DepthCheck/Media/VideoExporter.swift",
    "DepthCheck/Media/ConversionEngine.swift",
    "DepthCheck/Media/PhotoExporter.swift",
    "DepthCheck/Depth/DepthEstimator.swift",
    "DepthCheck/Depth/DepthNormalization.swift",
)
TEST_FILES = ("DepthCheckTests/MediaExportTests.swift", "DepthCheckTests/SustainedVideoExportTests.swift")
RUNNER_FILE = "HostChecks/NativeMediaChecks.swift"
SHADER_FILE = "DepthCheck/Imaging/StereoShaders.metal"


def query(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True).strip()


def run(label: str, arguments: list[str], *, timeout: int = 300) -> None:
    print(label, flush=True)
    subprocess.run(arguments, cwd=ROOT, check=True, timeout=timeout)


def existing_directories(candidates: list[Path]) -> list[Path]:
    result: list[Path] = []
    for path in candidates:
        if path.is_dir() and path not in result:
            result.append(path)
    return result


def rational_time(value):
    match = re.fullmatch(r"(-?\d+)/(\d+)@(-?\d+)", value) if isinstance(value, str) else None
    if not match or int(match[2]) <= 0 or int(match[3]) != 0:
        return None
    return Fraction(int(match[1]), int(match[2]))


def sustained_coverage_passed(coverage: dict, test_name: str) -> bool:
    """Check the measured contract, not just a test's self-described pass label."""
    if not isinstance(coverage, dict) or test_name not in SUSTAINED_REQUIREMENTS:
        return False
    width, height, frames, duration = SUSTAINED_REQUIREMENTS[test_name]
    source, output = coverage.get("source"), coverage.get("output")
    if not isinstance(source, dict) or not isinstance(output, dict):
        return False
    if not (coverage.get("test") == test_name and coverage.get("status") == "passed"
            and coverage.get("terminal_frame_verified") is True and coverage.get("memory_saver") is True
            and coverage.get("progress_max_frames") == frames
            and (source.get("width"), source.get("height"), source.get("frame_count")) == (width, height, frames)
            and (output.get("width"), output.get("height"), output.get("frame_count")) == (width * 2, height, frames)
            and rational_time(source.get("duration")) == duration
            and rational_time(output.get("duration")) == duration
            and rational_time(source.get("video_end")) == Fraction(frames, 60)
            and rational_time(output.get("video_end")) == Fraction(frames, 60)):
        return False
    if test_name == SUSTAINED_TEST_NAMES[0] and source.get("estimated_frame_count") != 920:
        return False
    for key in ("video_timing_sha256", "audio_timing_sha256", "audio_payload_sha256"):
        value = source.get(key)
        if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None or output.get(key) != value:
            return False
    packets = source.get("audio_packet_count")
    byte_count = source.get("audio_payload_bytes")
    if not (source.get("audio_codec") == output.get("audio_codec") == "AAC"
            and isinstance(packets, int) and packets > 500 and output.get("audio_packet_count") == packets
            and isinstance(byte_count, int) and byte_count > 0 and output.get("audio_payload_bytes") == byte_count):
        return False
    for key in ("audio_first_pts", "audio_end"):
        value = rational_time(source.get(key))
        if value is None or rational_time(output.get(key)) != value:
            return False
    for key, expected in zip(("audio_track_start", "audio_track_end"), SUSTAINED_AUDIO_RANGES[test_name]):
        if rational_time(source.get(key)) != expected or rational_time(output.get(key)) != expected:
            return False
    elapsed = coverage.get("elapsed_seconds", {})
    return (isinstance(elapsed, dict)
            and all(isinstance(elapsed.get(key), (int, float)) and math.isfinite(elapsed[key]) and elapsed[key] >= 0
                    for key in ("fixture", "source_inspection", "prepare", "export", "output_verification",
                                "final_frame_decode", "total")))


def case_passed(result: dict, test_name: str) -> bool:
    """Require XCTest's completed execution and the test's own measured evidence."""
    return (isinstance(result, dict) and result.get("test") == test_name
            and result.get("status") == "passed" and result.get("runner_exit_code") == 0
            and result.get("execution_count") == 1 and result.get("test_case_count") == 1
            and result.get("skip_count") == 0 and result.get("failure_count") == 0
            and result.get("completed") is True
            and (result.get("native_mvhevc_supported") is True if test_name == SPATIAL_TEST_NAME
                 else sustained_coverage_passed(result.get("coverage"), test_name)))


def native_result_passed(result: dict, stereo_supported: bool) -> bool:
    """Shared build gate; aggregate status alone is insufficient proof of a run."""
    if not isinstance(result, dict):
        return False
    required = [*SUSTAINED_TEST_NAMES, *([SPATIAL_TEST_NAME] if stereo_supported else [])]
    cases = result.get("results", [])
    return (result.get("status") == "passed" and result.get("completed") is True
            and result.get("native_mvhevc_supported") is stereo_supported
            and result.get("required_test_names") == required
            and isinstance(cases, list) and len(cases) == len(required)
            and result.get("execution_count") == len(required)
            and result.get("test_case_count") == len(required)
            and result.get("skip_count") == 0 and result.get("failure_count") == 0
            and all(case_passed(case, name) and case.get("native_mvhevc_supported") is stereo_supported
                    for case, name in zip(cases, required)))


def manifest_matches_current_sources(manifest: dict) -> bool:
    if not isinstance(manifest, dict):
        return False
    names = (*PRODUCTION_FILES, *TEST_FILES, RUNNER_FILE, SHADER_FILE)
    try:
        expected = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in names}
    except OSError:
        return False
    return (manifest.get("sources") == expected and manifest.get("swift_optimization") == "-O"
            and manifest.get("case_timeouts_seconds", {}).get(SUSTAINED_TEST_NAMES[3]) == 900)


def save_result(result: dict) -> None:
    RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
    temporary = RESULT_PATH.with_suffix(".tmp")
    temporary.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    temporary.replace(RESULT_PATH)


def run_case(executable: Path, name: str, index: int) -> dict:
    result_path = BUILD / f"case-{index:02d}.json"
    environment = os.environ.copy()
    environment["DEPTHCHECK_RUN_THREE_MINUTE_SUSTAINED"] = "1"
    environment["DEPTHCHECK_RUN_4K_SUSTAINED"] = "1"
    timeout = TEST_TIMEOUTS[name]
    started = time.monotonic()
    print(f"Running required native test {name} (deadline {timeout} seconds)", flush=True)
    try:
        completed = subprocess.run([str(executable), "--test", name, "--result", str(result_path)],
                                   cwd=ROOT, env=environment, timeout=timeout)
        exit_code = completed.returncode
        timed_out = False
    except subprocess.TimeoutExpired:
        exit_code = None
        timed_out = True
    if result_path.is_file():
        try:
            case = json.loads(result_path.read_text())
            if not isinstance(case, dict):
                raise ValueError("A case result must be a JSON object.")
        except (OSError, ValueError) as error:
            case = {"test": name, "status": "invalid_result", "error": str(error)}
    else:
        case = {"test": name, "status": "missing_result", "completed": False}
    case["runner_exit_code"] = exit_code
    case["timeout_seconds"] = timeout
    case["process_duration_seconds"] = time.monotonic() - started
    case["result_file"] = str(result_path.relative_to(ROOT))
    if timed_out:
        case["status"] = "timed_out"
        case["completed"] = False
        case["error"] = f"The required native test did not finish within {timeout} seconds."
    return case


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--stereo-available", choices=("true", "false"),
                        help="Use the build's observed native VideoToolbox capability; otherwise probe it.")
    arguments = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise RuntimeError("Native validation requires an Apple silicon Mac running macOS 26 or later.")
    if int(platform.mac_ver()[0].split(".")[0]) < 26:
        raise RuntimeError("The app's ready/tagged sample-buffer API requires macOS 26 or later.")

    # Remove only this script's generated output, including prior case evidence.
    if BUILD.exists():
        shutil.rmtree(BUILD)
    BUILD.mkdir(parents=True)
    stereo_supported = (arguments.stereo_available == "true" if arguments.stereo_available is not None else
                        query("xcrun", "swift", "-target", "arm64-apple-macosx26.0", "-e",
                              "import VideoToolbox; print(VTIsStereoMVHEVCEncodeSupported())") == "true")
    required_tests = [*SUSTAINED_TEST_NAMES, *([SPATIAL_TEST_NAME] if stereo_supported else [])]
    evidence = {"status": "building", "completed": False, "platform": "macOS",
                "native_mvhevc_supported": stereo_supported, "required_test_names": required_tests,
                "results": [], "execution_count": 0, "test_case_count": 0, "skip_count": 0,
                "failure_count": 0, "physical_iphone": "Not performed by this harness",
                "depth_inference": "Injected deterministic depth; this test isolates the unchanged renderer and media pipeline."}
    save_result(evidence)
    sdk = query("xcrun", "--sdk", "macosx", "--show-sdk-path")
    platform_path = Path(query("xcrun", "--sdk", "macosx", "--show-sdk-platform-path"))
    # Deriving this from xcrun respects DEVELOPER_DIR as well as xcode-select.
    developer_path = platform_path.parent.parent
    swiftc = query("xcrun", "--sdk", "macosx", "--find", "swiftc")
    metal = query("xcrun", "--sdk", "macosx", "--find", "metal")
    metallib = query("xcrun", "--sdk", "macosx", "--find", "metallib")
    framework_paths = existing_directories([
        platform_path / "Developer/Library/Frameworks",
        platform_path / "Developer/Library/PrivateFrameworks",
        developer_path / "Library/Frameworks",
        developer_path / "Library/PrivateFrameworks",
    ])
    if not any((path / "XCTest.framework").is_dir() for path in framework_paths):
        raise RuntimeError("The selected Xcode does not provide its macOS XCTest framework.")
    library_paths = existing_directories([
        platform_path / "Developer/usr/lib",
        developer_path / "usr/lib",
    ])
    inputs = [ROOT / name for name in (*PRODUCTION_FILES, *TEST_FILES, RUNNER_FILE, SHADER_FILE)]
    for source in inputs:
        if not source.is_file():
            raise RuntimeError(f"Required unmodified validation source is missing: {source}")

    app = BUILD / "DepthCheckHostChecks.app"
    contents = app / "Contents"
    resources = contents / "Resources"
    frameworks = contents / "Frameworks"
    executable = contents / "MacOS" / "NativeMediaChecks"
    modules = BUILD / "Modules"
    for directory in (resources, frameworks, executable.parent, modules):
        directory.mkdir(parents=True, exist_ok=True)
    with (contents / "Info.plist").open("wb") as stream:
        plistlib.dump({
            "CFBundleIdentifier": "com.depthcheck.validation.native-media",
            "CFBundleName": "Depth Check Native Media Validation",
            "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "LSMinimumSystemVersion": "26.0",
            "LSUIElement": True,
        }, stream)
    manifest = {
        "target": "arm64-apple-macosx26.0",
        "swift_optimization": "-O",
        "testability": "-enable-testing; -DDEBUG; existing XCTest assertions remain in the native test executable",
        "sdk": sdk,
        "xcode_developer_directory": str(developer_path),
        "framework_paths": [str(path) for path in framework_paths],
        "library_paths": [str(path) for path in library_paths],
        "tests": required_tests,
        "case_timeouts_seconds": {name: TEST_TIMEOUTS[name] for name in required_tests},
        "sources": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs},
    }
    (BUILD / "build-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    air = BUILD / "StereoShaders.air"
    run("Compiling the unchanged stereo shaders for macOS", [
        metal, "-isysroot", sdk, "-mmacosx-version-min=26.0",
        "-c", str(ROOT / SHADER_FILE), "-o", str(air),
    ])
    run("Bundling the native default Metal library", [
        metallib, str(air), "-o", str(resources / "default.metallib"),
    ])
    common = [swiftc, "-sdk", sdk, "-target", "arm64-apple-macosx26.0",
              "-swift-version", "5", "-strict-concurrency=targeted", "-O", "-g", "-DDEBUG"]
    production_library = frameworks / "libDepthCheck.dylib"
    run("Compiling the unchanged production media pipeline", common + [
        "-enable-testing", "-emit-library", "-emit-module", "-module-name", "DepthCheck",
        "-emit-module-path", str(modules / "DepthCheck.swiftmodule"),
        "-Xlinker", "-install_name", "-Xlinker", "@rpath/libDepthCheck.dylib",
        "-o", str(production_library),
    ] + [str(ROOT / name) for name in PRODUCTION_FILES])

    search_flags: list[str] = []
    for path in framework_paths:
        search_flags += ["-F", str(path), "-Xlinker", "-rpath", "-Xlinker", str(path)]
    for path in library_paths:
        # XCTest's Swift support library/modules ship in Developer/usr/lib.
        search_flags += ["-I", str(path), "-L", str(path),
                         "-Xlinker", "-rpath", "-Xlinker", str(path)]
    run("Compiling the unchanged sustained-video and spatial XCTests with the native runner", common + [
        "-parse-as-library", "-module-name", "DepthCheckHostChecks",
        "-I", str(modules), "-L", str(frameworks), "-lDepthCheck", "-framework", "XCTest",
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
    ] + search_flags + [str(ROOT / name) for name in TEST_FILES]
        + [str(ROOT / RUNNER_FILE), "-o", str(executable)])
    run("Ad-hoc signing the generated local validation bundle", [
        "/usr/bin/codesign", "--force", "--sign", "-", str(production_library),
    ])
    run("Signing the local validation executable and resources", [
        "/usr/bin/codesign", "--force", "--sign", "-", str(app),
    ])

    evidence["status"] = "in progress"
    started = time.monotonic()
    for index, name in enumerate(required_tests, start=1):
        evidence["active_test"] = name
        save_result(evidence)
        case = run_case(executable, name, index)
        evidence["results"].append(case)
        for key in ("execution_count", "test_case_count", "skip_count", "failure_count"):
            evidence[key] = sum(item.get(key, 0) for item in evidence["results"])
        evidence["duration_seconds"] = time.monotonic() - started
        if not case_passed(case, name):
            evidence["status"] = "failed"
            evidence["failed_test"] = name
            evidence["error"] = "A required native case failed, skipped, timed out, or did not record its measured verification."
            save_result(evidence)
            print(f"Required native media validation failed: {name}; evidence: {RESULT_PATH}", file=sys.stderr)
            return 1
        save_result(evidence)
    evidence.pop("active_test", None)
    evidence["status"] = "passed"
    evidence["completed"] = True
    save_result(evidence)
    if not native_result_passed(evidence, stereo_supported):
        raise RuntimeError("The aggregate native result does not prove every required completed, unskipped case.")
    print(f"All {len(required_tests)} required native media checks passed. Evidence: {RESULT_PATH}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        if RESULT_PATH.is_file():
            try:
                evidence = json.loads(RESULT_PATH.read_text())
                evidence.update(status="failed", completed=False, error=str(error))
                save_result(evidence)
            except (OSError, ValueError):
                pass
        print(f"Native media validation failed: {error}", file=sys.stderr)
        sys.exit(1)
