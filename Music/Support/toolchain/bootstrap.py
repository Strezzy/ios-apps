#!/usr/bin/env python3
"""Restore LLVM 20.1.2 in a local directory without apt/root installation.

Packages come from the pinned official Ubuntu snapshot and must match the
recorded SHA-256 and exact byte count. This supports Linux x86_64 with glibc
2.38 or newer (the build environment is Ubuntu 24.04). No Apple SDK is fetched.
"""
import argparse
import ctypes.util
import hashlib
import json
import platform
import shutil
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


def valid_package(path, record):
    if not path.is_file() or path.stat().st_size != int(record["Size"]):
        return False
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest() == record["SHA256"]


def obtain(name, record, archive, downloads):
    path = downloads / Path(record["Filename"]).name
    if valid_package(path, record):
        print(name + ": verified cached package", flush=True)
        return path
    temporary = path.with_suffix(path.suffix + ".part")
    limit = int(record["Size"])
    try:
        with urllib.request.urlopen(archive + record["Filename"], timeout=30) as response, temporary.open("wb") as stream:
            total = 0
            while True:
                block = response.read(1024 * 1024)
                if not block:
                    break
                total += len(block)
                if total > limit:
                    raise ValueError(name + ": response exceeds the pinned package size")
                stream.write(block)
        if not valid_package(temporary, record):
            raise ValueError(name + ": package size or SHA-256 did not match the pinned record")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    print(name + ": downloaded and verified", flush=True)
    return path


def main():
    support = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", type=Path, default=support.parents[1].parent / "ios-toolchain")
    parser.add_argument("--bundle-llvm", action="store_true", help="Extract libLLVM even if the host already has its matching soname")
    args = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "amd64"):
        parser.error("This bootstrap is for Linux x86_64; use build-macos.sh on a Mac")
    libc, version = platform.libc_ver()
    if libc != "glibc" or tuple(map(int, version.split(".")[:2])) < (2, 38):
        parser.error("The pinned Ubuntu compiler requires glibc 2.38 or newer")
    if not shutil.which("dpkg-deb"):
        parser.error("dpkg-deb is required to extract the verified packages")
    manifest = json.loads((support / "ubuntu-packages.json").read_text())
    if manifest.get("format_version") != 1:
        parser.error("Unsupported package manifest")
    prefix = args.prefix.resolve()
    downloads = prefix / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    names = ["clang-20", "libclang-cpp20", "libclang-common-20-dev", "lld-20", "llvm-20"]
    if args.bundle_llvm or not ctypes.util.find_library("LLVM-20"):
        names.append("libllvm20")
    records = manifest["packages"]
    packages = {}
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(obtain, name, records[name], manifest["archive_base"], downloads): name for name in names}
        for future in as_completed(futures):
            packages[futures[future]] = future.result()
    for name in names:
        subprocess.run(["dpkg-deb", "--extract", str(packages[name]), str(prefix)], check=True)
    # LLVM binaries use a sibling-library rpath. Preserve it when libLLVM is
    # extracted locally, rather than requiring a global LD_LIBRARY_PATH change.
    bundled_llvm = prefix / "usr/lib/x86_64-linux-gnu/libLLVM.so.20.1"
    sibling = prefix / "usr/lib/llvm-20/lib/libLLVM.so.20.1"
    if bundled_llvm.exists() and not sibling.exists():
        sibling.parent.mkdir(parents=True, exist_ok=True)
        sibling.symlink_to("../../x86_64-linux-gnu/libLLVM.so.20.1")
    # Older package_and_verify.py versions use ios-toolchain/root/usr/....
    compatibility = prefix / "root/usr"
    if not compatibility.exists():
        compatibility.parent.mkdir(parents=True, exist_ok=True)
        compatibility.symlink_to("../usr")
    binary_dir = prefix / "usr/lib/llvm-20/bin"
    versions = {}
    for name in ("clang", "ld64.lld", "llvm-objdump"):
        result = subprocess.run([str(binary_dir / name), "--version"], check=True, capture_output=True, text=True)
        versions[name] = result.stdout.splitlines()[0]
    report = {"toolchain": str(prefix), "packages": {name: records[name] for name in names}, "tools": versions}
    (prefix / "bootstrap-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"ready": True, "binary_directory": str(binary_dir), "versions": versions}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("Toolchain recovery failed: " + str(error), file=sys.stderr)
        sys.exit(1)
