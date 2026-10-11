#!/usr/bin/env python3
"""Fetch verified, pinned Core ML packages and compile the two offline models.

Only Python's standard library is needed. Build-time network access downloads
weights; the resulting iPhone app performs no downloads or remote inference.
The hashes below are SHA-256 of the actual file bytes, not Git LFS pointer files.

Usage:
    python3 scripts/prepare_models.py                 # macOS + Xcode
    python3 scripts/prepare_models.py --download-only # any OS, verify all bytes
    python3 scripts/prepare_models.py --check         # no network: verify cache
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CACHE_ROOT = PROJECT_ROOT / "Build" / "ModelSources"
OUTPUT_ROOT = PROJECT_ROOT / "DepthCheck" / "DepthCheckResources" / "Models"

MODELS = (
    {
        "name": "Balanced",
        "title": "Depth Anything V2 Small FP16",
        "repo": "apple/coreml-depth-anything-v2-small",
        "revision": "cfef6f6f2a70783dedc0bfae40cecbc2052285d3",
        "package": "DepthAnythingV2SmallF16.mlpackage",
        "license": "Apache-2.0",
        "files": (
            ("Data/com.apple.CoreML/model.mlmodel", 399433,
             "44ac97a3efcfd52113183fb2862ff59cd0368e9ec2e30a90a54980dd11407042"),
            ("Data/com.apple.CoreML/weights/weight.bin", 49419072,
             "fa60d9b6a155734f59029ebb882fd54e549bfaee3539c1a9cbd2cbbab64a0fed"),
            ("Manifest.json", 617,
             "2883ae290c48fe916dc5ececac03a7d847fa277165a49ef5652fa1d2b9cb55f7"),
        ),
    },
    {
        "name": "Detailed",
        "title": "Depth Anything 3 Base FP16, monocular Core ML conversion",
        "repo": "mlboydaisuke/Depth-Anything-3-Base-CoreML",
        "revision": "8e2e01d73a6b78f89beaac573ce3a009cf1fbb50",
        "package": "DepthAnythingV3_base_504.mlpackage",
        "license": "Apache-2.0",
        "files": (
            ("Data/com.apple.CoreML/model.mlmodel", 317533,
             "1e7e0943bae1c2cd8c58c6d8968f57f7a451b34f152104f80101f1aea535c233"),
            ("Data/com.apple.CoreML/weights/weight.bin", 233223744,
             "7823e9552eef8dff710bb9c51f7b5b7cdbc4c7bd7e06b1a434369f5e8bef1c8b"),
            ("Manifest.json", 617,
             "20b752a53baf0102afce370e2b39288a8d98ebe24c095e987e90fc61542e58a7"),
        ),
    },
)


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def valid_file(path: Path, size: int, digest: str) -> bool:
    return path.is_file() and path.stat().st_size == size and file_hash(path) == digest


def download_file(url: str, target: Path, size: int, digest: str) -> None:
    if valid_file(target, size, digest):
        print(f"Verified cache: {target.relative_to(CACHE_ROOT)}", flush=True)
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "DepthCheck-ModelBuilder/1.0"})
    last_error: Exception | None = None
    for attempt in range(1, 4):
        temporary: Path | None = None
        try:
            print(f"Downloading {target.name} ({size / 1_000_000:.1f} MB, attempt {attempt})", flush=True)
            with tempfile.NamedTemporaryFile(dir=target.parent, suffix=".partial", delete=False) as output:
                temporary = Path(output.name)
                downloaded = 0
                hasher = hashlib.sha256()
                with urllib.request.urlopen(request, timeout=60) as response:
                    if response.status != 200:
                        raise RuntimeError(f"Unexpected HTTP status {response.status}")
                    while chunk := response.read(1024 * 1024):
                        downloaded += len(chunk)
                        if downloaded > size:
                            raise RuntimeError("Download exceeded the verified file size")
                        output.write(chunk)
                        hasher.update(chunk)
                output.flush()
                os.fsync(output.fileno())
            if downloaded != size or hasher.hexdigest() != digest:
                raise RuntimeError(f"Integrity check failed for {target.name}; downloaded {downloaded} bytes")
            temporary.replace(target)
            return
        except (OSError, RuntimeError, urllib.error.URLError) as error:
            last_error = error
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    raise RuntimeError(f"Could not obtain verified model file: {url}\n{last_error}")


def compile_model(model: dict) -> None:
    source = CACHE_ROOT / model["package"]
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    destination = OUTPUT_ROOT / f"{model['name']}.mlmodelc"
    # Always use this Xcode's compiler. A cached .mlmodelc from a different Xcode
    # may have platform/compiler assumptions unsuitable for the current build.
    with tempfile.TemporaryDirectory(prefix="depthcheck-coreml-", dir=CACHE_ROOT) as temporary:
        subprocess.run(["xcrun", "coremlcompiler", "compile", str(source), temporary], check=True)
        compiled = Path(temporary) / f"{source.stem}.mlmodelc"
        if not compiled.is_dir():
            raise RuntimeError(f"coremlcompiler did not produce {compiled.name}")
        if destination.exists():
            shutil.rmtree(destination)
        shutil.move(str(compiled), str(destination))
    print(f"Compiled {model['name']}: {destination.relative_to(PROJECT_ROOT)}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download-only", action="store_true", help="Verify/download source packages without compiling")
    parser.add_argument("--check", action="store_true", help="Verify source cache without network or compilation")
    args = parser.parse_args()
    if not args.download_only and not args.check:
        if platform.system() != "Darwin" or shutil.which("xcrun") is None:
            parser.error("Compiling iOS models requires macOS and Xcode. Use --download-only to validate sources here.")
    for model in MODELS:
        print(f"Preparing {model['name']}: {model['title']}", flush=True)
        for relative, size, digest in model["files"]:
            destination = CACHE_ROOT / model["package"] / relative
            if args.check:
                if not valid_file(destination, size, digest):
                    raise RuntimeError(f"Missing or invalid cached model file: {destination}")
            else:
                url = f"https://huggingface.co/{model['repo']}/resolve/{model['revision']}/{model['package']}/{relative}"
                download_file(url, destination, size, digest)
        if not args.download_only and not args.check:
            compile_model(model)
    total = sum(size for model in MODELS for _, size, _ in model["files"])
    if not args.download_only and not args.check:
        manifest = {"models": list(MODELS), "sourceBytes": total}
        (OUTPUT_ROOT / "ModelSources.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Both pinned model packages verified: {total:,} source bytes.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Model preparation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
