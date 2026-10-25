#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, os, re, hashlib
from pathlib import Path
r = json.load(open('Build/BUILD-REPORT.json'))
t = json.load(open('Build/TEST-RESULTS.json'))
assert r['sourceCommit'] == os.environ['GITHUB_SHA']
assert t['failedTests'] == 0 and t['passedTests'] >= 25 and t['skippedTests'] == 0
assert re.fullmatch(r'\d+(?:\.\d+)*', r['version']) and r['build'].isdigit()
assert hashlib.sha256(Path('Build/Loop.ipa').read_bytes()).hexdigest() == r['sha256']
with open('Build/RELEASE-NOTES.md', 'w') as f:
    f.write(open('docs/RELEASE.md').read())
    f.write(f"\nAutomated tests: {t['passedTests']} passed, {t['failedTests']} failed, {t['skippedTests']} skipped.\n")
    f.write(f"\nSource commit: {r['sourceCommit']}\n\nIPA SHA-256: `{r['sha256']}`\n")
PY
LOOP_TAG=$(python3 -c 'import json;r=json.load(open("Build/BUILD-REPORT.json"));print("loop-"+r["version"]+"-build"+r["build"])')
LOOP_VERSION=$(python3 -c 'import json;r=json.load(open("Build/BUILD-REPORT.json"));print(r["version"]+" ("+r["build"]+")")')
gh release create "$LOOP_TAG" Build/Loop.ipa Build/Loop-Source.zip Build/Loop-XcodeProject.zip \
  Build/BUILD-REPORT.json Build/TEST-RESULTS.json Build/SHA256SUMS.txt Build/Loop-Icon.png Build/Loop-Home.png \
  --target "$GITHUB_SHA" --title "Loop $LOOP_VERSION · Moments, on repeat" --notes-file Build/RELEASE-NOTES.md
cd ..
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
# Re-read the latest catalog before adding the new release; preserve unrelated apps and histories.
git checkout main
git pull --ff-only origin main
python3 scripts/update_catalog.py --tag "$LOOP_TAG"
git add apps.json README.md
if ! git diff --cached --quiet; then
  git commit -m 'Publish Loop in the iPhone app catalog'
  git push origin HEAD:main
fi
