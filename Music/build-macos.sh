#!/bin/bash
set -euo pipefail

# Rebuild with Apple's public SDK using Xcode's command-line tools.
# Produces an ad-hoc-signed IPA for your own sideloading tool to re-sign.
project_root="$(cd "$(dirname "$0")" && pwd)"
build_root="$project_root/Build-Mac"
app_root="$build_root/Payload/Music.app"
ios_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$app_root"
cp -R "$project_root/Resources/." "$app_root/"
xcrun --sdk iphoneos clang \
  -arch arm64 -isysroot "$ios_sdk" -miphoneos-version-min=16.0 \
  -Oz -fobjc-arc -fblocks -Wall -Wextra -Wno-unused-parameter \
  -framework Foundation -framework UIKit -framework AVFoundation \
  -framework AVFAudio -framework MediaPlayer -framework AVKit \
  -framework UniformTypeIdentifiers -framework QuartzCore \
  -framework PhotosUI -framework ImageIO -framework CoreGraphics -framework CoreText \
  -framework WebKit -framework CoreMotion \
  "$project_root/Sources/main.m" -o "$app_root/GlassMusic"
chmod 755 "$app_root/GlassMusic"
codesign --force --sign - "$app_root"
cd "$build_root"
if [ -f Music.ipa ]; then rm Music.ipa; fi
# Select only this app so an older GlassMusic.app staging folder is excluded.
zip -qry Music.ipa Payload/Music.app
printf 'Created %s\n' "$build_root/Music.ipa"
