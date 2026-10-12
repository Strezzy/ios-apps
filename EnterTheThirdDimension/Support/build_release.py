#!/usr/bin/env python3
"""Publish verified release assets without replacing any existing public bytes."""
from __future__ import annotations
import hashlib
import json
import os
import subprocess
from pathlib import Path
from verify_ipa import verify, require

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "Build"
REPO = "Strezzy/ios-apps"
TAG = "enter-third-dimension-2.2-build4"
NAMES = ["EnterTheThirdDimension.ipa", "EnterTheThirdDimension-Source.zip",
         "BUILD-REPORT.json", "SHA256SUMS.txt", "Native-Launch.json", "Simulator-Launch.png"]


def command(args):
    result = subprocess.run([str(x) for x in args], cwd=ROOT.parent, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout[-1000:] or "GitHub command failed")
    return result.stdout


def api(path, allow_missing=False):
    result = subprocess.run(["gh", "api", f"repos/{REPO}/{path}"], capture_output=True, text=True)
    if result.returncode:
        if allow_missing and "HTTP 404" in result.stderr:
            return None
        raise RuntimeError("GitHub release lookup failed: " + result.stderr[-1200:])
    return json.loads(result.stdout)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    revision = os.environ.get("GITHUB_SHA")
    require(os.environ.get("GITHUB_REPOSITORY") == REPO, "Release publication is limited to the configured app repository")
    require(revision and len(revision) == 40, "A precise source revision is required")
    report = json.loads((BUILD / "BUILD-REPORT.json").read_text())
    require(report.get("status") == "passed" and report.get("source_revision") == revision,
            "A passing build report for this exact revision is required")
    require(report.get("simulator_validation", {}).get("webgl_frame_rendered") is True,
            "Native WebGL startup did not pass")
    require(report.get("simulator_validation", {}).get("water_character_rendered") is True,
            "The native raindrop character rendering check did not pass")
    for effect in ("dynamic_shadows_rendered", "bloom_rendered", "fxaa_rendered"):
        require(report.get("simulator_validation", {}).get(effect) is True,
                "Native visual quality validation did not pass: " + effect)
    verify(BUILD / "EnterTheThirdDimension.ipa")
    for name in NAMES:
        require((BUILD / name).is_file(), "Missing release asset: " + name)
    notes = ROOT / "RELEASE-NOTES.md"
    require(notes.is_file(), "RELEASE-NOTES.md is required")
    release = api(f"releases/tags/{TAG}", allow_missing=True)
    tag_ref = api(f"git/ref/tags/{TAG}", allow_missing=True)
    if tag_ref:
        tag_commit = api(f"commits/{TAG}")["sha"]
        require(tag_commit == revision, "This immutable release tag points to another revision; increase the version/build")
    created = release is None
    if created:
        command(["gh", "release", "create", TAG, *[BUILD / name for name in NAMES],
                 "--repo", REPO, "--target", revision,
                 "--title", "Enter the Third Dimension 2.2 (4)", "--notes-file", notes])
        release = api(f"releases/tags/{TAG}")
    else:
        require(not release.get("draft") and not release.get("prerelease"),
                "An existing draft/prerelease cannot be silently replaced by this publisher")
        require(tag_ref is not None, "The existing release has no verifiable tag")
        print("Existing release found. Its assets will be verified and reused; none will be overwritten.", flush=True)
    require(not release.get("draft") and not release.get("prerelease"), "Only a normal published release may enter the catalog")
    assets = {asset["name"]: asset for asset in release["assets"]}
    for name in NAMES:
        require(name in assets and assets[name].get("state") == "uploaded", "Published release asset is missing: " + name)
        if created:
            require(assets[name]["size"] == (BUILD / name).stat().st_size, "Published size differs for " + name)
            if assets[name].get("digest"):
                require(assets[name]["digest"] == "sha256:" + digest(BUILD / name), "Published digest differs for " + name)
    # A retry can reuse a previous successful publication from this revision.
    # Use its exact public IPA for catalog metadata, even if a fresh Xcode build
    # changed timestamps/signature bytes. No release asset is ever overwritten.
    published = BUILD / "Published"
    published.mkdir(exist_ok=True)
    needed = ["EnterTheThirdDimension.ipa", "BUILD-REPORT.json", "SHA256SUMS.txt"]
    for name in needed:
        (published / name).unlink(missing_ok=True)
    args = ["gh", "release", "download", TAG, "--repo", REPO, "--dir", published]
    for name in needed:
        args += ["--pattern", name]
    command(args)
    actual_report = json.loads((published / "BUILD-REPORT.json").read_text())
    require(actual_report.get("status") == "passed" and actual_report.get("source_revision") == revision,
            "Published build evidence does not match the source revision")
    require(actual_report.get("simulator_validation", {}).get("webgl_frame_rendered") is True,
            "Published build evidence does not prove native graphics startup")
    require(actual_report.get("simulator_validation", {}).get("water_character_rendered") is True,
            "Published build evidence does not prove native raindrop rendering")
    for effect in ("dynamic_shadows_rendered", "bloom_rendered", "fxaa_rendered"):
        require(actual_report.get("simulator_validation", {}).get(effect) is True,
                "Published evidence does not prove the visual pipeline: " + effect)
    checksums = {}
    for line in (published / "SHA256SUMS.txt").read_text().splitlines():
        value, name = line.split(None, 1)
        checksums[name.strip()] = value
    for name in ("EnterTheThirdDimension.ipa", "BUILD-REPORT.json"):
        require(checksums.get(name) == digest(published / name), "Published checksum mismatch for " + name)
        require((published / name).stat().st_size == assets[name]["size"], "Downloaded size mismatch for " + name)
    packaged = verify(published / "EnterTheThirdDimension.ipa")
    summary = {"release_tag": TAG, "release_url": release["html_url"], "published_at": release["published_at"],
               "download_url": assets["EnterTheThirdDimension.ipa"]["browser_download_url"],
               "created": created, "public_ipa_sha256": packaged["sha256"],
               "public_ipa_bytes": packaged["ipa_bytes"], "source_revision": revision,
               "catalog_ipa": "Build/Published/EnterTheThirdDimension.ipa"}
    (BUILD / "PUBLICATION.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == "__main__":
    main()
