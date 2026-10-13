#!/usr/bin/env python3
"""Recover exact public dylib namespaces from a known-working arm64 Mach-O.

This records the executable's imported symbols, not an Apple SDK's complete
exports. New APIs must be verified and added explicitly; unknown symbols must
never be made to link through an invented catch-all framework.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path


def capture(path):
    data = path.read_bytes()
    if len(data) < 32:
        raise ValueError("Truncated Mach-O header")
    magic, cpu, _, kind, count, command_bytes, _, _ = struct.unpack_from("<8I", data)
    if magic != 0xFEEDFACF or cpu != 0x100000C or kind != 2:
        raise ValueError("Expected a thin little-endian arm64 Mach-O executable")
    command_end = 32 + command_bytes
    if command_end > len(data):
        raise ValueError("Truncated Mach-O load commands")
    libraries, symtab, offset = [], None, 32
    for _ in range(count):
        if offset + 8 > command_end:
            raise ValueError("Truncated Mach-O command")
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > command_end:
            raise ValueError("Invalid Mach-O command size")
        if command in (0xC, 0x80000018, 0x8000001F, 0x20, 0x80000023):
            if size < 24:
                raise ValueError("Truncated dylib command")
            name_offset = struct.unpack_from("<I", data, offset + 8)[0]
            if name_offset < 24 or name_offset >= size:
                raise ValueError("Invalid dylib name offset")
            name = data[offset + name_offset:offset + size].split(b"\0", 1)[0].decode()
            if not name.startswith(("/usr/lib/", "/System/Library/Frameworks/")):
                raise ValueError("Non-public dylib path requires explicit review: " + name)
            libraries.append({"install_name": name, "symbols": []})
        elif command == 2:
            if size < 24:
                raise ValueError("Truncated symbol-table command")
            symtab = struct.unpack_from("<4I", data, offset + 8)
        offset += size
    if offset != command_end or not symtab:
        raise ValueError("Missing or invalid Mach-O symbol table")
    sym_offset, sym_count, str_offset, str_size = symtab
    if sym_offset + sym_count * 16 > len(data) or str_offset + str_size > len(data):
        raise ValueError("Truncated Mach-O symbols or strings")
    strings = data[str_offset:str_offset + str_size]
    for index in range(sym_count):
        string_index, symbol_type, _, description, _ = struct.unpack_from("<IBBHQ", data, sym_offset + index * 16)
        if symbol_type & 0xE0 or (symbol_type & 0x0E) != 0 or not (symbol_type & 1):
            continue
        if string_index >= len(strings) or b"\0" not in strings[string_index:]:
            raise ValueError("Invalid symbol name")
        name = strings[string_index:].split(b"\0", 1)[0].decode()
        ordinal = (description >> 8) & 0xFF
        if not 1 <= ordinal <= len(libraries):
            raise ValueError("Import has no concrete dylib namespace: " + name)
        libraries[ordinal - 1]["symbols"].append(name)
    for library in libraries:
        library["symbols"] = sorted(set(library["symbols"]))
    return {
        "format_version": 1,
        "description": "Explicit link-only public framework exports recovered from the user-confirmed Music 0.10 executable.",
        "baseline_sha256": hashlib.sha256(data).hexdigest(),
        "baseline_import_count": sum(len(x["symbols"]) for x in libraries),
        "target": "arm64-ios",
        "libraries": libraries,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    manifest = capture(args.executable)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Recorded {manifest['baseline_import_count']} imports from {len(manifest['libraries'])} dylibs.")
