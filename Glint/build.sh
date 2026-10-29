#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${RUNNER_TEMP:-/tmp}/glint-build-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
ENGINE="$WORK/engine"
HDR="$WORK/hdr"
OUT="$REPO_ROOT/Glint/dist"
export GLINT_BUILD="${GITHUB_RUN_NUMBER:-1}.${GITHUB_RUN_ATTEMPT:-1}"
export GLINT_TAG="glint-0.1.0-build${GLINT_BUILD}"
mkdir -p "$WORK" "$OUT"
exec > >(tee "$OUT/build.log") 2>&1
python3 -m venv "$WORK/venv"
python3 -m venv "$WORK/clean-tests"
PY="$WORK/venv/bin/python"
CLEAN="$WORK/clean-tests/bin/python"
"$PY" -m pip install --disable-pip-version-check 'Pillow==11.3.0' 'yt-dlp[default]==2026.8.19' 'yt-dlp-apple-webkit-jsi==0.1.1'
fetch_commit() {
  local repo="$1" sha="$2" destination="$3"
  git init -q "$destination"
  git -C "$destination" remote add origin "https://github.com/$repo.git"
  git -C "$destination" fetch --depth 1 origin "$sha"
  git -C "$destination" checkout -q --detach FETCH_HEAD
  test "$(git -C "$destination" rev-parse HEAD)" = "$sha"
}
fetch_commit tfourj/Palladium 9793491d168b63a36c50bee425140f2459d08c5a "$ENGINE"
fetch_commit viniciusron7/yt-dlp-instagram-hdr 812fbd7ad2b33e1f4b03f49b386e065f199054fd "$HDR"
"$PY" "$REPO_ROOT/Glint/assemble.py" "$ENGINE"
"$PY" -m compileall -q "$ENGINE/Palladium/Services/Python" "$REPO_ROOT/Glint"
tar -czf "$OUT/Assembled-Source.tar.gz" --exclude=.git --exclude=Frameworks -C "$ENGINE" .
while IFS= read -r -d '' source; do
  xcrun swiftc -frontend -parse "$source"
done < <(find "$ENGINE/Palladium" -name '*.swift' -print0)

# Package installation/removal tests intentionally require an empty environment.
# Format tests require real yt-dlp. Never let one suite contaminate the other.
(
  cd "$ENGINE"
  PYTHONDONTWRITEBYTECODE=1 "$CLEAN" -m unittest scripts.test_package_source_modes
  PYTHONDONTWRITEBYTECODE=1 "$CLEAN" -m unittest discover -s scripts/python_tests -t .
  PYTHONDONTWRITEBYTECODE=1 "$PY" -m unittest scripts.test_format_resolution
) 2>&1 | tee "$OUT/engine-tests.txt"
"$PY" "$REPO_ROOT/Glint/test_media.py" 2>&1 | tee "$OUT/glint-tests.txt"
if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then brew install ffmpeg; fi
"$PY" "$REPO_ROOT/Glint/test_media_real.py" 2>&1 | tee "$OUT/remux-tests.txt"
"$PY" "$REPO_ROOT/Glint/test_catalog.py" 2>&1 | tee "$OUT/catalog-tests.txt"
swiftc "$REPO_ROOT/Glint/GlintQuality.swift" "$REPO_ROOT/Glint/QualityProbe.swift" -o "$WORK/quality-probe"
"$WORK/quality-probe" > "$OUT/quality-arguments.json"
GLINT_QUALITY_ARGUMENTS="$OUT/quality-arguments.json" "$PY" "$REPO_ROOT/Glint/test_selection.py" 2>&1 | tee "$OUT/selection-tests.txt"
swiftc "$REPO_ROOT/Glint/GlintPaste.swift" "$ENGINE/Palladium/Models/ClipboardLinkDetector.swift" "$REPO_ROOT/Glint/PasteProbe.swift" -o "$WORK/paste-probe"
"$WORK/paste-probe" 2>&1 | tee "$OUT/paste-tests.txt"
"$PY" "$REPO_ROOT/Glint/test_origin.py" 2>&1 | tee "$OUT/origin-tests.txt"
swiftc "$REPO_ROOT/Glint/GlintOrigin.swift" "$REPO_ROOT/Glint/OriginProbe.swift" -o "$WORK/origin-probe"
"$WORK/origin-probe" 2>&1 | tee -a "$OUT/origin-tests.txt"
(cd "$HDR" && "$PY" -m unittest discover -s tests) 2>&1 | tee "$OUT/hdr-plugin-tests.txt"

mkdir -p "$ENGINE/Frameworks" "$WORK/downloads" "$OUT/dependency-sources"
get_release() {
  local repo="$1" pattern="$2" name="$3"
  mkdir -p "$WORK/downloads/$name"
  gh api "repos/$repo/releases/latest" > "$WORK/downloads/$name/release.json"
  local tag
  tag=$("$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["tag_name"])' "$WORK/downloads/$name/release.json")
  gh release download "$tag" --repo "$repo" --pattern "$pattern" --dir "$WORK/downloads/$name"
  curl --fail --location --retry 3 "https://api.github.com/repos/$repo/tarball/$tag" -o "$OUT/dependency-sources/$name-source.tar.gz"
  printf '%s %s\n' "$repo" "$tag" >> "$OUT/DEPENDENCIES.txt"
}
get_release beeware/Python-Apple-support '*iOS-support*.tar.gz' python
mkdir -p "$WORK/python-extracted"
tar -xzf "$(find "$WORK/downloads/python" -name '*iOS-support*.tar.gz' -print -quit)" -C "$WORK/python-extracted"
PY_FRAMEWORK=$(find "$WORK/python-extracted" -type d -name Python.xcframework -print -quit)
test -n "$PY_FRAMEWORK"
cp -R "$PY_FRAMEWORK" "$ENGINE/Frameworks/Python.xcframework"
HEADER="$ENGINE/Frameworks/Python.xcframework/ios-arm64/Python.framework/Headers/patchlevel.h"
grep -Eq '^#define PY_VERSION[[:space:]]+"3\.15\.' "$HEADER"
for name in SwiftFFmpeg-iOS SwiftCurlCffi-iOS; do
  get_release "tfourj/$name" "$name.zip" "$name"
  mkdir -p "$WORK/$name-extracted"
  ditto -x -k "$WORK/downloads/$name/$name.zip" "$WORK/$name-extracted"
  PACKAGE=$(find "$WORK/$name-extracted" -maxdepth 3 -name Package.swift -print -quit)
  test -n "$PACKAGE"
  cp -R "$(dirname "$PACKAGE")" "$ENGINE/Frameworks/$name"
done
CURL_PAYLOAD="$ENGINE/Frameworks/SwiftCurlCffi-iOS/Sources/SwiftCurlCffiIOS/Resources/curl_cffi_ios_payload.zip"
test -f "$CURL_PAYLOAD"
if unzip -Z1 "$CURL_PAYLOAD" | grep '\.so$' | grep -v '\.cpython-315-'; then
  echo 'Python and curl-cffi binary versions do not match.' >&2; exit 1
fi
curl --fail --location --retry 3 https://github.com/quickjs-ng/quickjs/archive/refs/tags/v0.16.2.tar.gz -o "$WORK/downloads/quickjs.tar.gz"
echo '97c80625b26775a4c7ca618c004d4ea24cf99cbf867e4eba78bd927a8b23d106  '"$WORK/downloads/quickjs.tar.gz" | shasum -a 256 -c -
mkdir -p "$ENGINE/Frameworks/QuickJS"
tar -xzf "$WORK/downloads/quickjs.tar.gz" --strip-components=1 -C "$ENGINE/Frameworks/QuickJS"
cp "$WORK/downloads/quickjs.tar.gz" "$OUT/dependency-sources/quickjs-source.tar.gz"

cd "$ENGINE"
export PALLADIUM_DISABLE_PYTHON_DYLIB_CODESIGN=1
xcodebuild archive -project Palladium.xcodeproj -scheme Palladium -configuration Release \
  -destination 'generic/platform=iOS' -sdk iphoneos -derivedDataPath "$WORK/DerivedData" \
  -archivePath "$WORK/Glint.xcarchive" MARKETING_VERSION=0.1.0 CURRENT_PROJECT_VERSION="$GLINT_BUILD" \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  PALLADIUM_DISABLE_PYTHON_DYLIB_CODESIGN=1 2>&1 | tee "$OUT/xcodebuild.log"
APP="$WORK/Glint.xcarchive/Products/Applications/Palladium.app"
test -d "$APP"
# Only platform-independent wheels go into the bundled package directory.
"$PY" -m pip install --disable-pip-version-check --target "$APP/python-packages" --no-compile --no-deps \
  --only-binary=:all: --platform any --implementation py --abi none --python-version 3.15 \
  'yt-dlp==2026.8.19' 'yt-dlp-apple-webkit-jsi==0.1.1' 'yt-dlp-ejs==0.8.0' gallery-dl mutagen pip certifi requests urllib3 idna charset-normalizer
mkdir -p "$APP/python-packages/yt_dlp_plugins"
cp -R "$HDR/yt_dlp_plugins/." "$APP/python-packages/yt_dlp_plugins/"
if find "$APP/python-packages" -type f \( -name '*.so' -o -name '*.dylib' \) | grep .; then
  echo 'Host binary found in pure-Python package payload.' >&2; exit 1
fi
mkdir -p "$APP/GlintLicenses"
cp "$ENGINE/LICENSE" "$APP/GlintLicenses/Palladium-GPL-3.0.txt"
cp "$HDR/LICENSE" "$APP/GlintLicenses/InstagramHDR-MIT.txt"
cp "$REPO_ROOT/Glint/README.md" "$APP/GlintLicenses/Glint-README.md"
cp "$ENGINE/Palladium/Resources/Assets.xcassets/GlintIcon.appiconset/Glint.png" "$OUT/Glint.png"
export APP OUT ENGINE HDR REPO_ROOT WORK
"$PY" - <<'PY'
import importlib.metadata, json, os, pathlib, plistlib
app = pathlib.Path(os.environ['APP'])
out = pathlib.Path(os.environ['OUT'])
info = plistlib.loads((app/'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.strezzy.glint', info['CFBundleIdentifier']
assert info['CFBundleDisplayName'] == 'Glint'
versions = sorted(({'name': d.metadata['Name'], 'version': d.version} for d in importlib.metadata.distributions(path=[str(app/'python-packages')])), key=lambda d:d['name'].lower())
manifest = {'name':'Glint','version':'0.1.0','build':os.environ['GLINT_BUILD'],'tag':os.environ['GLINT_TAG'],
 'minimumOS':info.get('MinimumOSVersion','26.0'),'bundleIdentifier':info['CFBundleIdentifier'],
 'engineRevision':'9793491d168b63a36c50bee425140f2459d08c5a','hdrRevision':'812fbd7ad2b33e1f4b03f49b386e065f199054fd',
 'overlayRevision':os.environ.get('GITHUB_SHA','local'),'packages':versions,
 'verification':'Native archive and automated tests; physical iPhone HDR/login/background behavior not yet verified.'}
(out/'build-info.json').write_text(json.dumps(manifest,indent=2)+'\n')
(app/'GlintLicenses/build-info.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
find "$APP" -type d -name _CodeSignature -prune -exec rm -rf {} +
find "$APP" -name embedded.mobileprovision -delete
mkdir -p "$WORK/standard/Payload"
cp -R "$APP" "$WORK/standard/Payload/Glint.app"
(cd "$WORK/standard" && ditto -c -k --keepParent Payload "$OUT/Glint.ipa")
rm -rf "$WORK/standard/Payload/Glint.app/PlugIns"
(cd "$WORK/standard" && ditto -c -k --keepParent Payload "$OUT/Glint-LiveContainer.ipa")

mkdir -p "$WORK/corresponding-source/Glint/Engine" "$WORK/corresponding-source/Glint/Overlay"
rsync -a --exclude .git --exclude Frameworks --exclude build "$ENGINE/" "$WORK/corresponding-source/Glint/Engine/"
rsync -a --exclude dist --exclude __pycache__ "$REPO_ROOT/Glint/" "$WORK/corresponding-source/Glint/Overlay/"
cp -R "$APP/python-packages" "$WORK/corresponding-source/Glint/PythonPackages"
cp -R "$HDR" "$WORK/corresponding-source/Glint/InstagramHDR"
rm -rf "$WORK/corresponding-source/Glint/InstagramHDR/.git"
cp -R "$OUT/dependency-sources" "$WORK/corresponding-source/Glint/DependencySources"
cp "$OUT/DEPENDENCIES.txt" "$WORK/corresponding-source/Glint/DEPENDENCIES.txt"
(cd "$WORK/corresponding-source" && ditto -c -k --keepParent Glint "$OUT/Glint-Source.zip")
rm -rf "$OUT/dependency-sources"
cd "$OUT"
shasum -a 256 Glint.ipa Glint-LiveContainer.ipa Glint-Source.zip Glint.png build-info.json > SHA256SUMS.txt
printf '\nBuilt Glint %s. No physical-device test was performed by CI.\n' "$GLINT_BUILD"
