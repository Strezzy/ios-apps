#!/usr/bin/env python3
"""Validate the shipped arm64 app and its exact offline game resources."""
from __future__ import annotations
import argparse
import hashlib
import json
import plistlib
import stat
import struct
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "com.billy.moonhop"
EXECUTABLE = "ThirdDimension"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version(encoded):
    return f"{encoded >> 16}.{(encoded >> 8) & 255}.{encoded & 255}"


def inspect_macho(binary):
    require(len(binary) >= 32, "The executable is too small for a Mach-O header")
    magic, cpu, subtype, kind, count, size, flags, _ = struct.unpack_from("<8I", binary)
    require(magic == 0xFEEDFACF and cpu == 0x100000C, "Expected a thin arm64 executable")
    require(kind == 2 and flags & 0x200000, "Expected a position-independent executable")
    require(32 + size <= len(binary), "Truncated Mach-O load commands")
    offset = 32
    libraries = []
    platform = minimum = sdk = entry = None
    signature = False
    for _ in range(count):
        require(offset + 8 <= 32 + size, "Truncated load-command header")
        command, length = struct.unpack_from("<II", binary, offset)
        require(length >= 8 and offset + length <= 32 + size, "Malformed load command")
        if command in (0xC, 0x80000018, 0x8000001F):
            name_offset = struct.unpack_from("<I", binary, offset + 8)[0]
            require(name_offset < length, "Invalid library name offset")
            name = binary[offset + name_offset:offset + length].split(b"\0")[0].decode()
            require(name.startswith(("/System/Library/Frameworks/", "/usr/lib/")),
                    "Unexpected library dependency: " + name)
            libraries.append(name)
        elif command == 0x32:
            platform, minimum, sdk = struct.unpack_from("<III", binary, offset + 8)
            require(platform == 2, "A simulator executable cannot be published as an iPhone IPA")
            require(minimum == (16 << 16), "Unexpected iOS deployment target")
            require(sdk >= (26 << 16), "Build using the real iPhoneOS SDK 26 or later")
        elif command == 0x80000028:
            entry = struct.unpack_from("<Q", binary, offset + 8)[0]
            require(0 < entry < len(binary), "Invalid application entry point")
        elif command == 0x2C:
            require(struct.unpack_from("<I", binary, offset + 16)[0] == 0, "App must be unencrypted")
        elif command == 0x1D:
            start, length_signature = struct.unpack_from("<II", binary, offset + 8)
            require(start + length_signature <= len(binary), "Truncated code signature")
            signature = length_signature > 0
        offset += length
    require(platform == 2 and entry is not None and signature, "Missing platform, entry point, or signature")
    for framework in ("UIKit", "WebKit", "Foundation"):
        require(any(f"/{framework}.framework/" in name for name in libraries), "Missing " + framework)
    return {"architecture": "arm64", "platform": "iOS device", "minimum_ios": version(minimum),
            "linked_sdk": version(sdk), "entry_point": entry, "dynamic_libraries": libraries,
            "signature_blob_present": signature, "executable_bytes": len(binary)}


def verify(path, resource_root=None):
    path = Path(path)
    resource_root = Path(resource_root) if resource_root else ROOT / "Resources"
    with zipfile.ZipFile(path) as archive:
        require(archive.testzip() is None, "ZIP integrity check failed")
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate ZIP member names")
        require(all(not name.startswith("/") and ".." not in Path(name).parts for name in names), "Unsafe ZIP path")
        prefix = "Payload/ThirdDimension.app/"
        require(all(name.startswith(prefix) or name in ("Payload/", "Payload/ThirdDimension.app/") for name in names), "Unexpected IPA bundle layout")
        require(not any(name.startswith(prefix + "Resources/") for name in names), "Reserved root Resources folder is not allowed")
        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        for key, expected in {"CFBundleIdentifier": BUNDLE, "CFBundleExecutable": EXECUTABLE,
                              "CFBundleDisplayName": "Enter the Third Dimension",
                              "CFBundleShortVersionString": "2.2", "CFBundleVersion": "4",
                              "MinimumOSVersion": "16.0", "CFBundleSupportedPlatforms": ["iPhoneOS"]}.items():
            require(info.get(key) == expected, f"Unexpected {key}: {info.get(key)!r}")
        landscape = {"UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"}
        require(set(info.get("UISupportedInterfaceOrientations", [])) == landscape, "iPhone must support landscape only")
        require(set(info.get("UISupportedInterfaceOrientations~ipad", [])) == landscape, "iPad must support landscape only")
        binary_info = archive.getinfo(prefix + EXECUTABLE)
        require((binary_info.external_attr >> 16) & stat.S_IXUSR, "Executable permission was lost")
        result = inspect_macho(archive.read(prefix + EXECUTABLE))
        require(prefix + "Assets.car" in names, "Compiled icon asset catalog is missing")
        require(info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon"), "App icon metadata is missing")
        privacy = plistlib.loads(archive.read(prefix + "PrivacyInfo.xcprivacy"))
        require(privacy.get("NSPrivacyTracking") is False, "Unexpected tracking declaration")
        require(not privacy.get("NSPrivacyCollectedDataTypes", []), "Unexpected data collection declaration")
        require(privacy == plistlib.loads((resource_root / "PrivacyInfo.xcprivacy").read_bytes()),
                "Packaged privacy manifest differs from source")
        source_game = resource_root / "Game"
        files = sorted(p for p in source_game.rglob("*") if p.is_file())
        require(files and (source_game / "index.html").is_file(), "Source game resources are missing")
        require((source_game / "water.js").is_file(), "The smooth raindrop character renderer is missing")
        require((source_game / "rainforest.js").is_file(), "The smooth rainforest and creature geometry is missing")
        expected_game = {prefix + "Game/" + p.relative_to(source_game).as_posix() for p in files}
        actual_game = {n for n in names if n.startswith(prefix + "Game/") and not n.endswith("/")}
        require(actual_game == expected_game, "Packaged Game directory differs from the source file set")
        require((source_game / "visuals.js").is_file(), "The current rainforest lighting shaders are missing")
        resources = []
        for file in files:
            relative = "Game/" + file.relative_to(source_game).as_posix()
            data = archive.read(prefix + relative)
            require(data == file.read_bytes(), "Packaged game file differs from source: " + relative)
            resources.append({"path": relative, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        html = archive.read(prefix + "Game/index.html").decode()
        require("connect-src 'none'" in html and "viewport-fit=cover" in html, "Offline CSP or safe-area viewport is missing")
        require("water.js" in html, "The bundled entry does not load the raindrop renderer")
        require("rainforest.js" in html, "The bundled entry does not load the rainforest renderer")
        require("visuals.js" in html, "The bundled entry does not load the current lighting shaders")
        result.update({"bundle_identifier": BUNDLE, "display_name": info["CFBundleDisplayName"],
                       "version": "2.2", "build": "4", "zip_integrity": "passed",
                       "executable_permissions": "passed", "resource_byte_equality": "passed",
                       "game_resources": resources, "privacy_manifest": "present, no collection",
                       "ipa_bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                       "signing": "Ad-hoc signed; the user's sideloading installer supplies device provisioning",
                       "physical_iphone_test": "Not performed by this package verifier"})
        return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--resources", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report = verify(args.ipa, args.resources)
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
