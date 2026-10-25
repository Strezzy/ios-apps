#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify_release.py
python3 - <<'PY'
import json
from pathlib import Path
build = json.load(open('Build/BUILD-REPORT.json'))
tests = json.load(open('Build/TEST-RESULTS.json'))
notes = Path('docs/RELEASE.md').read_text()
notes += f"\nValidation: native arm64 Release build, {tests['passedTests']} focused automated tests passed, {tests.get('skippedTests', 0)} skipped, and native portrait/landscape interface captures. Unsupported hardware checks are explicitly skipped, not counted as passed. Physical iPhone testing has not been performed.\n"
if Path('Build/CHECK-REUSE.json').is_file():
    reuse = json.load(open('Build/CHECK-REUSE.json'))
    notes += f"\nSix unit passes and one hardware skip were reused from verified commit {reuse['unitTestSourceCommit']} (Actions run {reuse['sourceRunID']}) after verifying unchanged runtime, unit-test, project and icon sources. The UI check and both screenshots ran afresh on this source commit. The current arm64 Release IPA was built and verified afresh. The original UI result is excluded from the combined totals.\n"
notes += f"\nSource commit: {build['sourceCommit']}\n\nIPA SHA-256: `{build['sha256']}`\n"
Path('Build/RELEASE-NOTES.md').write_text(notes)
PY
ORBIT_TAG=$(python3 -c 'import json;r=json.load(open("Build/BUILD-REPORT.json"));print("orbit-"+r["version"]+"-build"+r["build"])')
ORBIT_VERSION=$(python3 -c 'import json;r=json.load(open("Build/BUILD-REPORT.json"));print(r["version"]+" ("+r["build"]+")")')
ORBIT_REUSE_ASSETS=()
if [ -f Build/CHECK-REUSE.json ]; then
  ORBIT_REUSE_ASSETS+=(Build/CHECK-REUSE.json Build/UNIT-TEST-RESULTS.json
    Build/UI-TEST-RESULTS.json Build/ORIGINAL-TEST-RESULTS.json)
fi
if gh release view "$ORBIT_TAG" >/dev/null 2>&1; then
  # A rerun may finish an interrupted catalog update, but never replace a published IPA.
  ORBIT_EXISTING=$(mktemp -d)
  gh release download "$ORBIT_TAG" --pattern Orbit.ipa --dir "$ORBIT_EXISTING"
  cmp Build/Orbit.ipa "$ORBIT_EXISTING/Orbit.ipa"
  rm -rf "$ORBIT_EXISTING"
else
  gh release create "$ORBIT_TAG" \
    Build/Orbit.ipa Build/Orbit-Source.zip Build/Orbit-XcodeProject.zip \
    Build/BUILD-REPORT.json Build/VALIDATION-REPORT.json Build/TEST-RESULTS.json \
    Build/SHA256SUMS.txt Build/Orbit-Icon.png \
    Build/Orbit-Home-Portrait.png Build/Orbit-Home-Landscape.png \
    "${ORBIT_REUSE_ASSETS[@]}" \
    --target "$GITHUB_SHA" --title "Orbit $ORBIT_VERSION · A little more depth" \
    --notes-file Build/RELEASE-NOTES.md --draft
  gh release edit "$ORBIT_TAG" --draft=false --latest=false
fi
cd ..
# Use an isolated worktree so generated project files cannot enter the catalog commit.
ORBIT_CATALOG_DIR=$(mktemp -d)
git fetch origin main
git worktree add --detach "$ORBIT_CATALOG_DIR" origin/main
trap 'git worktree remove --force "$ORBIT_CATALOG_DIR" >/dev/null 2>&1 || true' EXIT
git -C "$ORBIT_CATALOG_DIR" config user.name 'github-actions[bot]'
git -C "$ORBIT_CATALOG_DIR" config user.email '41898282+github-actions[bot]@users.noreply.github.com'
for ORBIT_ATTEMPT in 1 2 3 4; do
  git -C "$ORBIT_CATALOG_DIR" fetch origin main
  git -C "$ORBIT_CATALOG_DIR" reset --hard origin/main
  (cd "$ORBIT_CATALOG_DIR" && python3 scripts/update_catalog.py --tag "$ORBIT_TAG")
  git -C "$ORBIT_CATALOG_DIR" add apps.json README.md
  if git -C "$ORBIT_CATALOG_DIR" diff --cached --quiet; then
    exit 0
  fi
  git -C "$ORBIT_CATALOG_DIR" commit -m 'Publish Orbit in the iPhone app catalog'
  if git -C "$ORBIT_CATALOG_DIR" push origin HEAD:main; then
    exit 0
  fi
done
echo 'Orbit is released, but its catalog update needs to be retried after concurrent repository changes.' >&2
exit 1
