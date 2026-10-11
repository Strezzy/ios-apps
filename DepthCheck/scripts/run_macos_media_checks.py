#!/usr/bin/env python3
"""Run the existing spatial-video XCTest against the actual code on macOS.

The iOS build invokes this when the native Mac exposes an MV-HEVC encoder.
This does not build or modify the iPhone app. It uses the selected Xcode's own
Swift, Metal and XCTest tools, and never downloads or loads the depth models.

Usage: python3 scripts/run_macos_media_checks.py
Evidence: Build/HostChecks/native-mvhevc-result.json and build-manifest.json

An unsupported host, missing test, skipped test, failure, or missing result is
an unsuccessful validation. None of those conditions produces a passing exit.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "Build" / "HostChecks"
TEST_NAME = "testSpatialVideoPreservesBothEyeLayersAndLastFrameDurationWithLongerAudio"
PRODUCTION_FILES = (
    "DepthCheck/Core/Domain.swift",
    "DepthCheck/Imaging/StereoRenderer.swift",
    "DepthCheck/Media/VideoExporter.swift",
    "DepthCheck/Media/ConversionEngine.swift",
    "DepthCheck/Media/PhotoExporter.swift",
    "DepthCheck/Depth/DepthEstimator.swift",
    "DepthCheck/Depth/DepthNormalization.swift",
)
TEST_FILE = "DepthCheckTests/MediaExportTests.swift"
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise RuntimeError("Native validation requires an Apple silicon Mac running macOS 26 or later.")
    if int(platform.mac_ver()[0].split(".")[0]) < 26:
        raise RuntimeError("The app's ready/tagged sample-buffer API requires macOS 26 or later.")

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
    inputs = [ROOT / name for name in (*PRODUCTION_FILES, TEST_FILE, RUNNER_FILE, SHADER_FILE)]
    for source in inputs:
        if not source.is_file():
            raise RuntimeError(f"Required unmodified validation source is missing: {source}")

    # Remove only this script's generated output, including any prior result.
    if BUILD.exists():
        shutil.rmtree(BUILD)
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
        "sdk": sdk,
        "xcode_developer_directory": str(developer_path),
        "framework_paths": [str(path) for path in framework_paths],
        "library_paths": [str(path) for path in library_paths],
        "test": TEST_NAME,
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
              "-swift-version", "5", "-strict-concurrency=targeted", "-Onone", "-g", "-DDEBUG"]
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
    run("Compiling the existing spatial-video XCTest and native runner", common + [
        "-parse-as-library", "-module-name", "DepthCheckHostChecks",
        "-I", str(modules), "-L", str(frameworks), "-lDepthCheck", "-framework", "XCTest",
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
    ] + search_flags + [str(ROOT / TEST_FILE), str(ROOT / RUNNER_FILE), "-o", str(executable)])
    run("Ad-hoc signing the generated local validation bundle", [
        "/usr/bin/codesign", "--force", "--sign", "-", str(production_library),
    ])
    run("Signing the local validation executable and resources", [
        "/usr/bin/codesign", "--force", "--sign", "-", str(app),
    ])

    result_path = BUILD / "native-mvhevc-result.json"
    print("Running exactly the existing native MV-HEVC format test", flush=True)
    completed = subprocess.run([str(executable), "--result", str(result_path)],
                               cwd=ROOT, env=os.environ.copy(), timeout=300)
    if completed.returncode != 0:
        return completed.returncode if completed.returncode > 0 else 1
    if not result_path.is_file():
        raise RuntimeError("The native runner exited without a validation result.")
    result = json.loads(result_path.read_text())
    if not (result.get("status") == "passed" and result.get("test") == TEST_NAME
            and result.get("execution_count") == 1 and result.get("skip_count") == 0
            and result.get("failure_count") == 0 and result.get("native_mvhevc_supported") is True
            and result.get("completed") is True):
        raise RuntimeError("The native result did not prove one completed, unskipped, passing MV-HEVC test.")
    print(f"Native MV-HEVC validation passed. Evidence: {result_path}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"Native MV-HEVC validation failed: {error}", file=sys.stderr)
        sys.exit(1)
