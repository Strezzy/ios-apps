#!/usr/bin/env python3
"""Check the arm64 MiniSDK build for the root-layout corruption fixed in 0.1.1.

Run this on the compiled .o file, before linking. This deliberately checks the
actual generated accessors: an Objective-C runtime can slide offset variables,
but it cannot repair an offset that Clang embedded into an instruction.
The core accessors remain required as the UI grows. All emitted app classes
must reserve the object header; --require-class can also assert that a newly
added controller is present in the compiled object.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path


def command(tool, *arguments):
    return subprocess.check_output([tool, *map(str, arguments)], text=True)


def accessor(disassembly, name):
    match = re.search(r"^-\[" + re.escape(name) + r"\]:\n(.*?)(?=^\S|\Z)",
                      disassembly, re.M | re.S)
    if not match:
        raise ValueError("Missing compiled accessor: " + name)
    return match.group(1)


def resolve_outlined_tail(disassembly, body):
    """Follow an accessor consisting only of a tail branch to an LLVM helper.

    -Oz may share identical setters. Check the emitted helper instructions,
    not an assumed offset, and fail closed for a missing target or cycle.
    Mixed instruction bodies and other branch targets are left unchanged.
    """
    expanded, current, targets = body, body, []
    while True:
        lines = [line.strip() for line in current.splitlines() if line.strip()]
        match = re.fullmatch(r"[0-9a-f]+:\s+b\s+(_OUTLINED_FUNCTION_\d+)", lines[0]) if len(lines) == 1 else None
        if not match:
            return expanded, targets
        target = match.group(1)
        if target in targets or len(targets) >= 16:
            raise ValueError("Invalid outlined accessor tail chain: " + target)
        matches = list(re.finditer(r"^" + re.escape(target) + r":\n(.*?)(?=^\S|\Z)",
                                   disassembly, re.M | re.S))
        if len(matches) != 1:
            raise ValueError("Missing or ambiguous outlined accessor target: " + target)
        current = matches[0].group(1)
        targets.append(target)
        expanded += current


def immediate(body, register):
    match = re.search(r"\bmov\s+[wx]" + str(register)
                      + r",\s*#(0x[0-9a-f]+|[0-9]+)", body)
    return int(match.group(1), 0) if match else None


def byte_store_offset(body):
    match = re.search(r"\bstrb\s+w\d+,\s*\[x0(?:,\s*#(0x[0-9a-f]+|[0-9]+))?\]", body)
    return (int(match.group(1), 0) if match.group(1) else 0) if match else None


def inspect(tool, object_file, required_classes=()):
    disassembly = command(tool, "--macho", "--disassemble",
                          "--no-show-raw-insn", object_file)
    metadata = command(tool, "--macho", "--objc-meta-data", object_file)
    names = ["SceneDelegate setWindow:", "GMTrack setDemo:",
             "GMTrack setMetadataLoaded:", "GMTrack setUrl:",
             "PlayerController setSelectedIndex:", "PlayerController setTracks:"]
    resolved = {name: resolve_outlined_tail(disassembly, accessor(disassembly, name)) for name in names}
    bodies = {name: result[0] for name, result in resolved.items()}
    classes = {
        name: {"instance_start": int(start), "compiled_instance_size": int(size)}
        for name, start, size in re.findall(
            r"data\s+__OBJC_CLASS_RO_\$_(\w+)[^\n]*\n.*?"
            r"instanceStart\s+(\d+)\s+instanceSize\s+(\d+)", metadata, re.S)
    }
    offsets = {
        "SceneDelegate.window": immediate(bodies["SceneDelegate setWindow:"], 3),
        "GMTrack.demo": byte_store_offset(bodies["GMTrack setDemo:"]),
        "GMTrack.metadataLoaded": byte_store_offset(bodies["GMTrack setMetadataLoaded:"]),
        "GMTrack.url": immediate(bodies["GMTrack setUrl:"], 3),
    }
    dynamic = {
        name: "_OBJC_IVAR_$_PlayerController._" + ivar in bodies[name]
        for name, ivar in [("PlayerController setSelectedIndex:", "selectedIndex"),
                           ("PlayerController setTracks:", "tracks")]
    }
    failures = []
    if offsets["SceneDelegate.window"] != 8:
        failures.append("SceneDelegate.window must follow the 8-byte NSObject isa word.")
    for name, offset in offsets.items():
        if offset is None or offset < 8:
            failures.append(name + " accessor overlaps the object header or could not be verified.")
    if offsets["GMTrack.demo"] == offsets["GMTrack.metadataLoaded"]:
        failures.append("GMTrack flags overlap each other.")
    for name, valid in dynamic.items():
        if not valid:
            failures.append(name + " must load its superclass-dependent ivar offset.")
    required = {"GMTrack", "SceneDelegate", "AppDelegate", "PlayerController"}
    required.update(required_classes)
    for name in sorted(required - classes.keys()):
        failures.append("Missing compiled class metadata: " + name)
    # New tab/settings/Now Playing classes need the same NSObject header.
    # Do not freeze their total size: UIKit's private superclass ivars can grow
    # and Objective-C correctly adjusts dynamic ivar offsets at runtime.
    for name, layout in sorted(classes.items()):
        if layout["instance_start"] < 8:
            failures.append(name + " metadata does not reserve NSObject's isa word.")
        if layout["compiled_instance_size"] < layout["instance_start"]:
            failures.append(name + " metadata has an invalid instance size.")
    return {
        "object": str(object_file), "passed": not failures,
        "constant_accessor_offsets": offsets, "dynamic_superclass_offsets": dynamic,
        "classes": classes, "required_classes": sorted(required),
        "all_emitted_class_headers_checked": True, "failures": failures,
        "outlined_accessor_targets": {name: result[1] for name, result in resolved.items() if result[1]},
        "accessor_instructions": {
            name: [line.strip() for line in body.splitlines() if line.strip()]
            for name, body in bodies.items()
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("object", type=Path)
    parser.add_argument("--objdump", default="llvm-objdump")
    parser.add_argument("--before", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--require-class", action="append", default=[],
                        help="Require an additional app class in this object; repeat as needed.")
    args = parser.parse_args()
    after = inspect(args.objdump, args.object, args.require_class)
    report = {"after": after}
    if args.before:
        report["before"] = inspect(args.objdump, args.before)
        report["cause"] = (
            "MiniSDK omitted NSObject's isa word. Clang treats NSObject's layout "
            "as statically known and embeds direct-subclass offsets in instructions. "
            "The old window setter passed offset 0 to objc_setProperty_atomic, "
            "whose runtime implementation invokes object_setClass for offset 0. "
            "The old track flag setters also overwrote the isa word."
        )
        report["primary_sources"] = [
            "https://github.com/llvm/llvm-project/blob/release/20.x/clang/lib/CodeGen/CGObjCMac.cpp",
            "https://github.com/apple-oss-distributions/objc4/blob/main/runtime/NSObject.h",
            "https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-accessors.mm",
        ]
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": after["passed"], "failures": after["failures"],
                      "report": str(args.report) if args.report else None}, indent=2))
    return 0 if after["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
