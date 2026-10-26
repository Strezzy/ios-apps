#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify_release.py
python3 - <<'PY'
import json,os,re
from pathlib import Path
r=json.loads(Path('Build/BUILD-REPORT.json').read_text());t=json.loads(Path('Build/FOCUSED-CREATIVE-TESTS.json').read_text())
assert r['sourceCommit']==os.environ['GITHUB_SHA']==t['sourceCommit']
assert re.fullmatch(r'\d+(?:\.\d+)*',r['version']) and r['build'].isdigit()
text=Path('docs/RELEASE.md').read_text()
text+=f"\nFocused native tests: {t['passedTests']} passed, {t['failedTests']} failed, {t.get('skippedTests',0)} skipped. Full editor UI suite and physical-device testing were not run.\n\nSource commit: {r['sourceCommit']}\n\nIPA SHA-256: `{r['sha256']}`\n"
Path('Build/RELEASE-NOTES.md').write_text(text)
PY
LOOP_TAG=$(python3 -c 'import json;r=json.load(open("Build/BUILD-REPORT.json"));print("loop-"+r["version"]+"-build"+r["build"])')
LOOP_VERSION=$(python3 -c 'import json;r=json.load(open("Build/BUILD-REPORT.json"));print(r["version"]+" ("+r["build"]+")")')
gh release create "$LOOP_TAG" Build/Loop.ipa Build/Loop-Source.zip Build/Loop-XcodeProject.zip \
 Build/BUILD-REPORT.json Build/SHA256SUMS.txt Build/Loop-Icon.png Build/VALIDATION-REPORT.json \
 Build/FOCUSED-CREATIVE-TESTS.json Build/SCENE-MODELS.json Build/CREATIVE-RESEARCH.md Build/Loop-Creative-Samples.zip \
 --target "$GITHUB_SHA" --title "Loop $LOOP_VERSION · Simple controls, deeper possibilities" --notes-file Build/RELEASE-NOTES.md
cd ..
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git checkout main
git pull --ff-only origin main
python3 scripts/update_catalog.py --tag "$LOOP_TAG"
git add apps.json README.md
if ! git diff --cached --quiet; then
 git commit -m 'Publish Loop 2 in the iPhone app catalog'
 git push origin HEAD:main
fi
