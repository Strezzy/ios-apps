#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify_release.py
python3 - <<'PY'
import json, os, re, hashlib, sys
from pathlib import Path
sys.path.insert(0, 'scripts')
from verify_release import build_only_profile
r = json.load(open('Build/BUILD-REPORT.json'))
assert r['sourceCommit'] == os.environ['GITHUB_SHA']
assert re.fullmatch(r'\d+(?:\.\d+)*', r['version']) and r['build'].isdigit()
assert hashlib.sha256(Path('Build/Loop.ipa').read_bytes()).hexdigest() == r['sha256']
with open('Build/RELEASE-NOTES.md', 'w') as f:
    f.write(open('docs/RELEASE.md').read())
    if build_only_profile():
        focused = json.load(open('Build/FOCUSED-REALISM-TESTS.json'))
        assert focused['sourceCommit'] == r['sourceCommit']
        assert focused['passedTests'] >= 24 and focused['failedTests'] == 0 and focused.get('skippedTests', 0) == 0
        f.write(f"\nValidation: native arm64 Release build and package/checksum verification passed. "
                f"Focused simulator renderer/model/migration checks: {focused['passedTests']} passed, "
                f"{focused['failedTests']} failed, {focused.get('skippedTests', 0)} skipped. "
                "The complete editor interface suite and physical-device tests were not run.\n")
    else:
        t = json.load(open('Build/TEST-RESULTS.json'))
        f.write(f"\nAutomated tests: {t['passedTests']} passed, {t['failedTests']} failed, {t['skippedTests']} skipped.\n")
    f.write(f"\nSource commit: {r['sourceCommit']}\n\nIPA SHA-256: `{r['sha256']}`\n")
PY
LOOP_TAG=$(python3 -c 'import json;r=json.load(open("Build/BUILD-REPORT.json"));print("loop-"+r["version"]+"-build"+r["build"])')
LOOP_VERSION=$(python3 -c 'import json;r=json.load(open("Build/BUILD-REPORT.json"));print(r["version"]+" ("+r["build"]+")")')
LOOP_ASSETS=(Build/Loop.ipa Build/Loop-Source.zip Build/Loop-XcodeProject.zip
  Build/BUILD-REPORT.json Build/SHA256SUMS.txt Build/Loop-Icon.png)
if [ "$(python3 scripts/verify_release.py --mode)" = 'build-only' ]; then
  LOOP_ASSETS+=(Build/VALIDATION-REPORT.json Build/FOCUSED-REALISM-TESTS.json Build/REALISM-ASSET-REPORT.json Build/REALISM-RESEARCH.md Build/Loop-Realism-Samples.zip)
else
  LOOP_ASSETS+=(Build/TEST-RESULTS.json Build/Loop-Home.png Build/Loop-Editor.png
    Build/Loop-Live-Effects.png Build/Loop-Live-Pixelation.png Build/Loop-Precision-Zoom.png
    Build/Loop-Emoji-Keyboard.png Build/Loop-Trim-Playback.png Build/Loop-Subject-Selection.png
    Build/Loop-Subject-Result.png Build/Loop-Subject-Follow.png
    Build/Loop-4K60-Selection.png Build/Loop-4K60-Tracked.png Build/Loop-4K60-Restored.png)
fi
gh release create "$LOOP_TAG" "${LOOP_ASSETS[@]}" \
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
