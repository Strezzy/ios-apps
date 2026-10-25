#!/usr/bin/env python3
"""Require every checked-in XCTest method to run successfully before publication."""
import json
import re
import sys
from pathlib import Path


def validate_report(path):
    root = Path(__file__).resolve().parents[1]
    expected = sum(
        len(re.findall(r"\bfunc\s+test\w*\s*\(\s*\)", source.read_text()))
        for folder in (root / "Tests", root / "UITests")
        for source in folder.rglob("*.swift")
    )
    report = json.loads(Path(path).read_text())
    assert expected >= 60, "The complete encoder, engine and interface suite is required."
    assert report["failedTests"] == 0, report
    assert report["skippedTests"] == 0, report
    assert report["passedTests"] == expected, (expected, report)
    print(f"Verified {expected} tests passed, zero failures, zero skipped.")
    return report


if __name__ == "__main__":
    validate_report(sys.argv[1])
