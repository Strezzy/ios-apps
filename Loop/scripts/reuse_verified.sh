#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build
gh api "repos/$GH_REPO/actions/runs?head_sha=$GITHUB_SHA&status=success&per_page=50" > Build/previous-runs.json
LOOP_VERIFIED_RUN=$(python3 - <<'PY'
import json, os
runs = json.load(open('Build/previous-runs.json'))['workflow_runs']
matches = [r for r in runs if r['head_sha'] == os.environ['GITHUB_SHA']
           and r['path'] == '.github/workflows/loop.yml'
           and r['head_branch'].startswith('loop/')
           and r['conclusion'] == 'success' and r['event'] == 'push']
print(matches[0]['id'] if matches else '')
PY
)
if [ -z "$LOOP_VERIFIED_RUN" ]; then
  echo 'No previously tested candidate for this commit; building normally.'
  exit 0
fi
gh run download "$LOOP_VERIFIED_RUN" --name Loop-Build-and-Tests --dir Build
python3 scripts/verify_tests.py Build/TEST-RESULTS.json
python3 - <<'PY'
import hashlib, json, os
from pathlib import Path
r = json.load(open('Build/BUILD-REPORT.json'))
t = json.load(open('Build/TEST-RESULTS.json'))
assert r['sourceCommit'] == os.environ['GITHUB_SHA']
assert hashlib.sha256(Path('Build/Loop.ipa').read_bytes()).hexdigest() == r['sha256']
for name in ['Loop-Source.zip', 'Loop-XcodeProject.zip', 'Loop-Home.png', 'Loop-Icon.png',
             'Loop-Editor.png', 'Loop-Live-Effects.png', 'Loop-Live-Pixelation.png',
             'Loop-Precision-Zoom.png', 'Loop-Emoji-Keyboard.png']:
    assert (Path('Build') / name).is_file(), name
PY
echo 'reused=true' >> "$GITHUB_OUTPUT"
echo "Publishing the tested candidate from run $LOOP_VERIFIED_RUN."
