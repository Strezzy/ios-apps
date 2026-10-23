#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build
xcodebuild -version > Build/toolchain.txt
xcodebuild -showsdks >> Build/toolchain.txt
python3 scripts/fetch_model.py
xcodegen generate
xcodebuild -resolvePackageDependencies -project Velvet.xcodeproj -scheme Velvet
xcodebuild -project Velvet.xcodeproj -scheme Velvet -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath Build/Device CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" build > Build/device-build.log 2>&1 || { tail -120 Build/device-build.log; exit 1; }
python3 scripts/package.py
