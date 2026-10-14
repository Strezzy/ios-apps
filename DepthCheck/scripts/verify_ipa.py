#!/usr/bin/env python3
"""Inspect a real arm64 iOS executable and its IPA, without running app code.

This detects a simulator binary, bad ZIP layout, missing resources, incorrect
startup metadata, compiled Metal libraries, and missing execute bits. It does not test image quality or
claim that an iPhone launched the app.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import plistlib
import stat
import struct
import re
import zipfile
from pathlib import Path

from generate_project import configuration


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version(encoded):
    return f"{encoded >> 16}.{(encoded >> 8) & 255}.{encoded & 255}"


def inspect_macho(binary, required_frameworks=()):
    require(len(binary) >= 32, "Executable is missing or too small for a Mach-O header")
    magic, cpu, subtype, kind, count, size, flags, _ = struct.unpack_from("<8I", binary)
    require(magic == 0xFEEDFACF, "App must contain a thin 64-bit Mach-O device executable")
    require(cpu == 0x100000C, "App executable must target arm64")
    require(kind == 2, "Mach-O file type must be an executable")
    require(flags & 0x200000, "Executable must use position-independent code")
    require(32 + size <= len(binary), "Mach-O load commands exceed the executable")
    offset = 32
    libraries = []
    platform = minimum = sdk = entry = None
    signature = False
    for _ in range(count):
        require(offset + 8 <= 32 + size, "Truncated Mach-O load command")
        command, length = struct.unpack_from("<II", binary, offset)
        require(length >= 8 and offset + length <= 32 + size, "Malformed Mach-O load command")
        if command in (0xC, 0x80000018, 0x8000001F):
            name_offset = struct.unpack_from("<I", binary, offset + 8)[0]
            require(name_offset < length, "Invalid dynamic-library name offset")
            name = binary[offset + name_offset:offset + length].split(b"\0")[0].decode()
            require(name.startswith(("/System/Library/Frameworks/", "/usr/lib/", "@rpath/")),
                    "Unexpected dynamic library path: " + name)
            libraries.append(name)
        elif command == 0x32:
            platform, minimum, sdk = struct.unpack_from("<III", binary, offset + 8)
            require(platform == 2, "Executable is not built for iOS devices (simulators use platform 7)")
            require(minimum >= (26 << 16) and sdk >= (26 << 16),
                    "Native Liquid Glass app must require and link iOS 26 or later")
        elif command == 0x80000028:
            entry = struct.unpack_from("<Q", binary, offset + 8)[0]
            require(0 < entry < len(binary), "Executable has no valid entry point")
        elif command == 0x2C:
            require(struct.unpack_from("<I", binary, offset + 16)[0] == 0,
                    "Packaged executable must be unencrypted")
        elif command == 0x1D:
            sig_offset, sig_size = struct.unpack_from("<II", binary, offset + 8)
            require(sig_offset + sig_size <= len(binary), "Truncated code signature")
            signature = sig_size > 0
        offset += length
    require(platform == 2 and entry is not None, "Missing iOS platform or entry-point load command")
    for framework in required_frameworks:
        require(any(f"/{framework}.framework/" in name for name in libraries),
                "The executable does not link its required inference framework: " + framework)
    return {"architecture": "arm64", "platform": "iOS device", "minimum_ios": version(minimum),
            "linked_sdk": version(sdk), "entry_point": entry, "dynamic_libraries": libraries,
            "signature_blob_present": signature, "executable_bytes": len(binary)}


def verify(path):
    path = Path(path)
    config = configuration()
    with zipfile.ZipFile(path) as archive:
        require(archive.testzip() is None, "ZIP integrity check failed")
        names = archive.namelist()
        require(len(names) == len(set(names)), "IPA contains duplicate ZIP member names")
        require(all(not name.startswith("/") and ".." not in Path(name).parts for name in names),
                "IPA contains an unsafe path")
        prefix = "Payload/DepthCheck.app/"
        require(all(name.startswith(prefix) or name in ("Payload/", "Payload/DepthCheck.app/")
                    for name in names), "IPA contains files outside the expected app bundle")
        require(not any(name.startswith(prefix + "Resources/") for name in names),
                "A reserved root Resources directory changes CFBundle's Info.plist lookup")
        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        require(info["CFBundleIdentifier"] == "com.billy.facet", "Incorrect app bundle identifier")
        require(info["CFBundleExecutable"] == "DepthCheck", "Incorrect app executable name")
        require(info["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "Bundle describes a simulator app")
        require(info.get("NSPhotoLibraryAddUsageDescription"), "Photo saving permission description is missing")
        require("metal" in info.get("UIRequiredDeviceCapabilities", []), "Metal device capability is missing")
        require(not info.get("UIDesignRequiresCompatibility", False), "App opts out of native Liquid Glass")
        binary_info = archive.getinfo(prefix + "DepthCheck")
        require((binary_info.external_attr >> 16) & stat.S_IXUSR, "Executable mode bit was lost during ZIP packaging")
        result = inspect_macho(archive.read(prefix + "DepthCheck"), config["required_frameworks"])
        model_ids = ["Balanced", "Detailed"]
        for model_id in model_ids:
            folder = prefix + "DepthCheckResources/Models/" + model_id + ".mlmodelc/"
            files = [name for name in names if name.startswith(folder)]
            require(files, "Bundled compiled depth model is missing: " + model_id)
            require(any("weight" in name.lower() for name in files), "Model weights are missing: " + model_id)
        require(prefix + "DepthCheckResources/Model-Licenses.txt" in names,
                "Bundled model license acknowledgments are missing")
        metal_libraries = []
        for name in names:
            if not name.endswith(".metallib"):
                continue
            data = archive.read(name)
            require(len(data) > 64 and data[:4] == b"MTLB", "Invalid compiled Metal library: " + name)
            relative = name[len(prefix):]
            metal_libraries.append({"path": relative, "bytes": len(data),
                                    "sha256": hashlib.sha256(data).hexdigest()})
        require(any(entry["path"] == "default.metallib" for entry in metal_libraries),
                "Compiled stereo Metal shaders are missing")
        package_resources = []
        privacy = plistlib.loads(archive.read(prefix + "PrivacyInfo.xcprivacy"))
        require(not privacy.get("NSPrivacyTracking", False), "Unexpected tracking declaration")
        require(not privacy.get("NSPrivacyCollectedDataTypes", []), "Unexpected collected-data declaration")
        result.update({"bundle_identifier": info["CFBundleIdentifier"],
            "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
            "zip_integrity": "passed", "executable_permissions": "passed",
            "model_catalog": model_ids, "privacy_manifest": "present",
            "compiled_metal_libraries": metal_libraries,
            "inference_package_resources": package_resources,
            "ipa_bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "signing": "Built without an Apple provisioning profile; installer must re-sign for the device",
            "physical_iphone_test": "Not performed by this packaging verifier"})
        return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = verify(args.ipa)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))

