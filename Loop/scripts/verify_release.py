#!/usr/bin/env python3
"""Verify the release's declared validation scope without inventing test results.

The build-only exception is tied to a specific version/build in
release-validation.json. Other releases retain the complete XCTest gate.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path

from verify_tests import validate_report

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "Build"


def build_only_profile():
    path = ROOT / "release-validation.json"
    if not path.is_file():
        return None
    profile = json.loads(path.read_text())
    project = (ROOT / "project.yml").read_text()
    version = re.search(r"MARKETING_VERSION:\s*['\"]?([\d.]+)", project).group(1)
    number = re.search(r"CURRENT_PROJECT_VERSION:\s*['\"]?(\d+)", project).group(1)
    if (profile.get("profile"), profile.get("version"), profile.get("build")) != (
        "build-only", version, number
    ):
        return None
    assert profile.get("reason"), "An explicit reason is required for build-only validation."
    return profile


def verify_binary():
    report = json.loads((BUILD / "BUILD-REPORT.json").read_text())
    assert report["configuration"] == "Release"
    assert report["architecture"] == "arm64"
    assert report["bundleIdentifier"] == "com.billy.loop"
    assert report["sdk"].startswith("iphoneos")
    assert re.fullmatch(r"[0-9a-f]{40}", report["sourceCommit"])
    if os.environ.get("GITHUB_SHA"):
        assert report["sourceCommit"] == os.environ["GITHUB_SHA"]
    ipa = BUILD / "Loop.ipa"
    assert ipa.stat().st_size == report["ipaBytes"]
    assert hashlib.sha256(ipa.read_bytes()).hexdigest() == report["sha256"]
    return report


def record_build_only():
    profile = build_only_profile()
    assert profile is not None, "Build-only validation is not enabled for this version."
    build = verify_binary()
    assert (build["version"], build["build"]) == (profile["version"], profile["build"])
    assert "** BUILD SUCCEEDED **" in (BUILD / "device-build.log").read_text()
    # A fresh build-only release must not inherit a previous release's test report.
    assert not (BUILD / "TEST-RESULTS.json").exists()
    report = {
        "profile": "build-only",
        "version": build["version"],
        "build": build["build"],
        "sourceCommit": build["sourceCommit"],
        "ipaSHA256": build["sha256"],
        "nativeReleaseBuild": "passed",
        "automatedTests": "not-run",
        "simulatorUIValidation": "not-run",
        "physicalDeviceValidation": "not-run; app owner will test",
        "reason": profile["reason"],
    }
    (BUILD / "VALIDATION-REPORT.json").write_text(json.dumps(report, indent=2) + "\n")
    print("Native arm64 Release build verified. Simulator tests were not run, as requested.")


def verify_release():
    build = verify_binary()
    profile = build_only_profile()
    if profile is None:
        return validate_report(BUILD / "TEST-RESULTS.json")
    assert (build["version"], build["build"]) == (profile["version"], profile["build"])
    report = json.loads((BUILD / "VALIDATION-REPORT.json").read_text())
    assert (report["version"], report["build"]) == (build["version"], build["build"])
    assert report["sourceCommit"] == build["sourceCommit"]
    assert report["ipaSHA256"] == build["sha256"]
    assert report["profile"] == "build-only"
    assert report["nativeReleaseBuild"] == "passed"
    assert report["automatedTests"] == "not-run"
    assert report["simulatorUIValidation"] == "not-run"
    assert report["reason"] == profile["reason"]
    print("Verified the version-specific build-only release and its unrun-test disclosure.")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--mode", action="store_true")
    group.add_argument("--record-build-only", action="store_true")
    args = parser.parse_args()
    if args.mode:
        print("build-only" if build_only_profile() else "full")
    elif args.record_build_only:
        record_build_only()
    else:
        verify_release()
