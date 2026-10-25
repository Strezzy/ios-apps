#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build
xcodebuild -version > Build/toolchain.txt
xcodebuild -showsdks >> Build/toolchain.txt
xcodegen generate
xcodebuild -project Loop.xcodeproj -scheme Loop -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath Build/Device \
  CODE_SIGNING_ALLOWED=NO build > Build/device-build.log 2>&1 || {
    python3 scripts/show_errors.py Build/device-build.log
    exit 1
  }
python3 scripts/package.py
