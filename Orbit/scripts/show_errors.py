#!/usr/bin/env python3
"""Keep build output focused on actionable compiler diagnostics."""
import sys
from pathlib import Path

lines = Path(sys.argv[1]).read_text(errors="replace").splitlines()
indices = set()
for index, line in enumerate(lines):
    if any(term in line for term in ("error:", "failed", "FAIL", "** BUILD", "** TEST")):
        indices.update(range(max(0, index - 2), min(len(lines), index + 7)))
for index in sorted(indices):
    print(lines[index])
if not indices:
    print("\n".join(lines[-80:]))
