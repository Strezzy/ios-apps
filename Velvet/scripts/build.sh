#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build
xcodebuild -version > Build/toolchain.txt
xcodebuild -showsdks >> Build/toolchain.txt
python3 scripts/fetch_model.py
xcodegen generate
xcodebuild -resolvePackageDependencies -project Velvet.xcodeproj -scheme Velvet
set --
if [[ -n "${VELVET_BUILD_NUMBER:-}" ]]; then
    [[ "$VELVET_BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo 'Build number must be numeric'; exit 1; }
    set -- "CURRENT_PROJECT_VERSION=$VELVET_BUILD_NUMBER"
fi
xcodebuild -project Velvet.xcodeproj -scheme Velvet -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath Build/Device CODE_SIGNING_ALLOWED=NO "$@" build > Build/device-build.log 2>&1 || {
    python3 - <<'LOG'
from pathlib import Path
lines = Path('Build/device-build.log').read_text().splitlines()
for i, line in enumerate(lines):
    if ': error:' in line:
        print('\n'.join(lines[max(0, i-1):i+7]))
print('\n'.join(line for line in lines[-30:] if len(line) < 1000))
LOG
    exit 1
}
python3 scripts/package.py
