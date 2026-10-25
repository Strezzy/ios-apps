#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build
xcrun simctl list devices available -j > Build/simulators.json
ORBIT_DEVICE=$(python3 - <<'PY'
import json
data = json.load(open('Build/simulators.json'))
choices = [(runtime, device) for runtime, devices in data['devices'].items()
           if 'iOS-27' in runtime or 'iOS-26' in runtime
           for device in devices if 'iPhone' in device['name']]
assert choices, 'An iOS 26 or later iPhone simulator is required'
choices.sort(key=lambda value: ('17 Pro' in value[1]['name'], 'iOS-27' in value[0]), reverse=True)
print(choices[0][1]['udid'])
PY
)
printf '%s' "$ORBIT_DEVICE" > Build/simulator-udid.txt
xcrun simctl boot "$ORBIT_DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$ORBIT_DEVICE" -b
xcrun simctl status_bar "$ORBIT_DEVICE" override --time '9:41' --dataNetwork wifi \
  --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
ORBIT_TEST_STATUS=0
xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug \
  -destination "platform=iOS Simulator,id=$ORBIT_DEVICE" -derivedDataPath Build/Simulator \
  -resultBundlePath Build/Tests.xcresult -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 45 \
  -maximum-test-execution-time-allowance 90 CODE_SIGNING_ALLOWED=NO test \
  > Build/test.log 2>&1 || ORBIT_TEST_STATUS=$?
if [ -d Build/Tests.xcresult ]; then
  xcrun xcresulttool get test-results summary --path Build/Tests.xcresult --format json > Build/TEST-RESULTS.json || true
  xcrun xcresulttool export attachments --path Build/Tests.xcresult --output-path Build/Screenshots || true
fi
if [ "$ORBIT_TEST_STATUS" -ne 0 ]; then
  python3 scripts/show_errors.py Build/test.log
  exit "$ORBIT_TEST_STATUS"
fi
python3 - <<'PY'
import json
import shutil
from pathlib import Path
root = Path('Build/Screenshots')
manifest = json.loads((root / 'manifest.json').read_text())
attachments = [item for test in manifest for item in test['attachments']]
for name in ['Orbit-Home-Portrait', 'Orbit-Home-Landscape']:
    matches = [item for item in attachments if item['suggestedHumanReadableName'].startswith(name)]
    assert matches, f'Missing native capture: {name}'
    item = max(matches, key=lambda value: value['timestamp'])
    shutil.copyfile(root / item['exportedFileName'], Path('Build') / (name + '.png'))
PY
python3 scripts/verify_release.py --record
