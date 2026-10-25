#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build
xcrun simctl list devices available -j > Build/simulators.json
LOOP_DEVICE=$(python3 - <<'PY'
import json
d = json.load(open('Build/simulators.json'))
candidates = [(k, x) for k, v in d['devices'].items() if 'iOS-27' in k or 'iOS-26' in k for x in v if 'iPhone' in x['name']]
assert candidates, 'No supported iPhone simulator installed'
candidates.sort(key=lambda item: ('17 Pro' in item[1]['name'], 'iOS-27' in item[0]), reverse=True)
print(candidates[0][1]['udid'])
PY
)
printf '%s' "$LOOP_DEVICE" > Build/simulator-udid.txt
xcrun simctl boot "$LOOP_DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$LOOP_DEVICE" -b
xcrun simctl status_bar "$LOOP_DEVICE" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
LOOP_TEST_STATUS=0
xcodebuild -project Loop.xcodeproj -scheme Loop -configuration Debug \
  -destination "platform=iOS Simulator,id=$LOOP_DEVICE" -derivedDataPath Build/Simulator \
  -resultBundlePath Build/Tests.xcresult -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 90 \
  -maximum-test-execution-time-allowance 300 CODE_SIGNING_ALLOWED=NO test \
  > Build/test.log 2>&1 || LOOP_TEST_STATUS=$?
if [ -d Build/Tests.xcresult ]; then
  xcrun xcresulttool get test-results summary --path Build/Tests.xcresult --format json > Build/TEST-RESULTS.json || true
  xcrun xcresulttool export attachments --path Build/Tests.xcresult --output-path Build/Screenshots || true
fi
if [ "$LOOP_TEST_STATUS" -ne 0 ]; then
  python3 scripts/show_errors.py Build/test.log
  exit "$LOOP_TEST_STATUS"
fi
python3 scripts/verify_tests.py Build/TEST-RESULTS.json
python3 - <<'PY'
import json, shutil
from pathlib import Path
root = Path('Build/Screenshots')
manifest = json.loads((root / 'manifest.json').read_text())
attachments = [a for test in manifest for a in test['attachments']]
for name in ['Loop-Editor', 'Loop-Live-Effects', 'Loop-Live-Pixelation', 'Loop-Precision-Zoom', 'Loop-Emoji-Keyboard', 'Loop-Trim-Playback', 'Loop-Subject-Selection', 'Loop-Subject-Result', 'Loop-Subject-Follow']:
    matches = [a for a in attachments if a['suggestedHumanReadableName'].startswith(name + '_')]
    assert matches, f'Missing native interface capture: {name}'
    chosen = max(matches, key=lambda a: a['timestamp'])
    shutil.copyfile(root / chosen['exportedFileName'], Path('Build') / (name + '.png'))
PY
xcrun simctl launch --terminate-running-process "$LOOP_DEVICE" com.billy.loop --uitesting
sleep 3
xcrun simctl io "$LOOP_DEVICE" screenshot Build/Loop-Home.png
xcrun simctl terminate "$LOOP_DEVICE" com.billy.loop
