#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build
# Promotion preserves the exact tested commit and IPA, rather than rebuilding it.
gh api "repos/$GH_REPO/actions/runs?head_sha=$GITHUB_SHA&status=success&per_page=50" > Build/previous-runs.json
VERIFIED_RUN=$(python3 - <<'PY'
import json,os
runs=json.load(open('Build/previous-runs.json'))['workflow_runs']
matches=[r for r in runs if r['head_sha']==os.environ['GITHUB_SHA']
         and r['path']=='.github/workflows/moonwake.yml'
         and r['head_branch'].startswith('moonwake/')
         and r['conclusion']=='success' and r['event']=='push']
print(matches[0]['id'] if matches else '')
PY
)
if [ -z "$VERIFIED_RUN" ]; then
  echo 'No previously verified candidate for this exact commit; building normally.'
  exit 0
fi
gh run download "$VERIFIED_RUN" --name Moonwake-Build-and-Tests --dir Build
python3 - <<'PY'
import hashlib,json,os
from pathlib import Path
r=json.load(open('Build/BUILD-REPORT.json')); t=json.load(open('Build/TEST-RESULTS.json'))
assert r['sourceCommit']==os.environ['GITHUB_SHA'], 'Build commit differs from source'
assert t['failedTests']==0 and t['passedTests']>=30 and t['skippedTests']==0
assert hashlib.sha256(Path('Build/Moonwake.ipa').read_bytes()).hexdigest()==r['sha256']
for name in ['Moonwake-Source.zip','Moonwake-XcodeProject.zip','Moonwake-Title.png','Moonwake-Gameplay.png','Moonwake-Icon.png']:
    assert (Path('Build')/name).is_file(), f'Missing verified artifact: {name}'
PY
echo 'reused=true' >> "$GITHUB_OUTPUT"
echo "Promoting verified candidate run $VERIFIED_RUN without changing its IPA."
