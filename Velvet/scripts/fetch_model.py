#!/usr/bin/env python3
"""Build-time only: fetch an immutable, SHA-256-verified model into app resources.

This script is not shipped as executable app code. Velvet never downloads models.
"""
import hashlib
import os
from pathlib import Path
import sys
import urllib.request

REPOSITORY = "litert-community/embeddinggemma-2-text-vision-440m-litert-lm"
REVISION = "e301f74d5551b0c2641bd5cb4652a76239d5c5f8"
FILENAME = "embeddinggemma-2-text-vision-440m.litertlm"
SIZE = 387_710_976
SHA256 = "92dcbea108899e5d6e30d919b0744f90d9967e80c67a4ab5503ac16d54f62eb0"
URL = f"https://huggingface.co/{REPOSITORY}/resolve/{REVISION}/{FILENAME}"
DESTINATION = Path(__file__).resolve().parents[1] / "Velvet" / "Resources" / "Models" / FILENAME


def verified(path: Path) -> bool:
    if not path.is_file() or path.stat().st_size != SIZE:
        return False
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest() == SHA256


def main() -> None:
    if verified(DESTINATION):
        print(f"Verified bundled model: {SIZE:,} bytes, SHA-256 {SHA256}")
        return
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    partial = DESTINATION.with_suffix(".download")
    try:
        request = urllib.request.Request(URL, headers={"User-Agent": "Velvet-build/1.0"})
        with urllib.request.urlopen(request, timeout=120) as response, partial.open("wb") as output:
            written = 0
            while block := response.read(1024 * 1024):
                written += len(block)
                if written > SIZE:
                    raise RuntimeError("Model response exceeded the pinned size")
                output.write(block)
            output.flush()
            os.fsync(output.fileno())
        if not verified(partial):
            raise RuntimeError("Model size or SHA-256 verification failed; refusing to bundle it")
        partial.replace(DESTINATION)
        print(f"Bundled verified model: {SIZE:,} bytes, SHA-256 {SHA256}")
    finally:
        partial.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Model preparation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
