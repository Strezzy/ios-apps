#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build
xcodebuild -version > Build/toolchain.txt
swift scripts/GenerateIcon.swift
python3 scripts/synthesize_audio.py
xcodegen generate
xcodebuild -project Moonwake.xcodeproj -scheme Moonwake -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath Build/Device CODE_SIGNING_ALLOWED=NO build > Build/device-build.log 2>&1 || {
  python3 scripts/show_errors.py Build/device-build.log
  exit 1
}
python3 scripts/package.py
