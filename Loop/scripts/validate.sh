#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(python3 scripts/verify_release.py --mode)" = 'build-only' ]; then
  python3 scripts/verify_release.py --record-build-only
else
  bash scripts/test.sh
fi
python3 scripts/verify_release.py
