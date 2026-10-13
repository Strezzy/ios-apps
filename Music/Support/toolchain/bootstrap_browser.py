#!/usr/bin/env python3
"""Restore the official Chromium shell used for local WebGL renderer checks.

This optional tool is not bundled in the IPA. It opens no user browser/profile.
The version matches the task environment's Playwright Chromium revision 1234.
"""
import argparse
import hashlib
import platform
import stat
import subprocess
import urllib.request
import zipfile
from pathlib import Path

VERSION = "151.0.7922.34"
URL = "https://storage.googleapis.com/chrome-for-testing-public/" + VERSION + "/linux64/chrome-headless-shell-linux64.zip"
SIZE = 120231126
SHA256 = "3cfc2bd00d1bafcf8a68dc74c9c92bb7150ddc8d26ade948a776316e1cec4f14"


def verified(path):
    if not path.is_file() or path.stat().st_size != SIZE:
        return False
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest() == SHA256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    project = Path(__file__).resolve().parents[2]
    parser.add_argument("--prefix", type=Path, default=project.parent / "ios-toolchain/browser")
    args = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "amd64"):
        parser.error("This pinned Chromium shell requires Linux x86_64")
    prefix = args.prefix.resolve()
    prefix.mkdir(parents=True, exist_ok=True)
    archive = prefix / "chrome-headless-shell-linux64.zip"
    if not verified(archive):
        temporary = archive.with_suffix(".zip.part")
        try:
            with urllib.request.urlopen(URL, timeout=30) as response, temporary.open("wb") as stream:
                total = 0
                while True:
                    block = response.read(1024 * 1024)
                    if not block:
                        break
                    total += len(block)
                    if total > SIZE:
                        raise ValueError("Chrome response exceeds the pinned archive size")
                    stream.write(block)
            if not verified(temporary):
                raise ValueError("Chrome archive size/SHA-256 mismatch")
            temporary.replace(archive)
        finally:
            temporary.unlink(missing_ok=True)
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise ValueError("Corrupt Chrome ZIP")
        for entry in bundle.infolist():
            if entry.is_dir():
                continue
            mode = entry.external_attr >> 16
            destination = (prefix / entry.filename).resolve()
            if not destination.is_relative_to(prefix) or stat.S_ISLNK(mode):
                raise ValueError("Unsafe Chrome archive path")
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(bundle.read(entry))
            destination.chmod(mode & 0o777 or 0o644)
    executable = prefix / "chrome-headless-shell-linux64/chrome-headless-shell"
    subprocess.run([str(executable), "--version"], check=True)
    print("executablePath: " + str(executable))
    print("Playwright args: --no-sandbox --disable-dev-shm-usage --use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader")


if __name__ == "__main__":
    main()
