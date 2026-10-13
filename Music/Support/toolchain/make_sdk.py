#!/usr/bin/env python3
"""Create narrowly scoped TAPI link stubs; this is not an Apple header SDK."""
import argparse
import json
from pathlib import Path, PurePosixPath


def make_sdk(output, manifest_path=None):
    manifest_path = manifest_path or Path(__file__).with_name("symbols.json")
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("format_version") != 1 or manifest.get("target") != "arm64-ios":
        raise ValueError("Unsupported symbol manifest")
    linker_arguments, exported = [], set()
    for library in manifest["libraries"]:
        name = library["install_name"]
        path = PurePosixPath(name)
        if path.parts[:4] == ("/", "System", "Library", "Frameworks"):
            framework = path.name
            if path.parent.name != framework + ".framework":
                raise ValueError("Unsupported framework layout: " + name)
            target = output / Path(*path.parts[1:])
            target = target.with_suffix(".tbd")
            linker_arguments.extend(["-framework", framework])
        elif name in ("/usr/lib/libSystem.B.dylib", "/usr/lib/libobjc.A.dylib"):
            stem = "System" if "libSystem." in name else "objc"
            target = output / "usr/lib" / ("lib" + stem + ".tbd")
            linker_arguments.append("-l" + stem)
        else:
            raise ValueError("Unsupported or non-public install name: " + name)
        symbols = library["symbols"]
        if not isinstance(symbols, list) or any(not isinstance(x, str) or not x for x in symbols):
            raise ValueError("Invalid export list: " + name)
        duplicates = exported.intersection(symbols)
        if duplicates:
            raise ValueError("Ambiguous namespaces: " + ", ".join(sorted(duplicates)))
        exported.update(symbols)
        text = "--- !tapi-tbd\ntbd-version: 4\ntargets: [ arm64-ios ]\n"
        text += "install-name: " + json.dumps(name) + "\n"
        text += "current-version: 1.0.0\ncompatibility-version: 1.0.0\n"
        text += "exports:\n  - targets: [ arm64-ios ]\n    symbols: " + json.dumps(symbols) + "\n...\n"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    return linker_arguments


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    arguments = make_sdk(args.output, args.manifest)
    print(json.dumps({"sdk": str(args.output), "linker_arguments": arguments}))
