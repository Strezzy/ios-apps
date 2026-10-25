#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# The first candidate passed its checks; only its publication script failed.
# Reuse unit evidence only; capture and validate the interface on this commit.
ORBIT_TEST_SOURCE=8abeda5be908b06b3a49c715d06d6d142f6d34fe
ORBIT_REUSE_DIR=$(mktemp -d)
trap 'rm -rf "$ORBIT_REUSE_DIR"' EXIT
rm -f Build/CHECK-REUSE.json
if [ -n "${GH_TOKEN:-}" ] && \
   (git cat-file -e "${ORBIT_TEST_SOURCE}^{commit}" 2>/dev/null || \
    git fetch --no-tags --depth=1 origin "$ORBIT_TEST_SOURCE") && \
   git -C .. diff --quiet "$ORBIT_TEST_SOURCE" HEAD -- \
     Orbit/App Orbit/Core Orbit/Rendering Orbit/Tests/Unit Orbit/project.yml Orbit/Resources/Assets.xcassets; then
  if gh run download 40185812644 --name Orbit-Build-and-Checks --dir "$ORBIT_REUSE_DIR" \
       > Build/reuse-download.log 2>&1 && \
     python3 scripts/reuse_checks.py "$ORBIT_REUSE_DIR"; then
    ORBIT_UI_ONLY=1 bash scripts/validate.sh
    exit 0
  fi
  echo 'Prior check evidence was unavailable or failed verification; running fresh checks.'
fi
rm -f Build/CHECK-REUSE.json
bash scripts/validate.sh
