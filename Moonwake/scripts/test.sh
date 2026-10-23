#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build
xcrun simctl list devices available -j > Build/simulators.json
DEVICE=$(python3 - <<'PY'
import json
d=json.load(open('Build/simulators.json'))
candidates=[(k,x) for k,v in d['devices'].items() if 'iOS-27' in k or 'iOS-26' in k for x in v if 'iPhone' in x['name']]
assert candidates, 'No supported iPhone simulator installed'
candidates.sort(key=lambda item:('17 Pro' in item[1]['name'],'iOS-27' in item[0]),reverse=True)
print(candidates[0][1]['udid'])
PY
)
printf '%s' "$DEVICE" > Build/simulator-udid.txt
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
TEST_STATUS=0
xcodebuild -project Moonwake.xcodeproj -scheme Moonwake -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath Build/Simulator -resultBundlePath Build/Tests.xcresult -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 90 -maximum-test-execution-time-allowance 150 CODE_SIGNING_ALLOWED=NO test > Build/test.log 2>&1 || TEST_STATUS=$?
if [ -d Build/Tests.xcresult ]; then
  xcrun xcresulttool get test-results summary --path Build/Tests.xcresult --format json > Build/TEST-RESULTS.json || true
  xcrun xcresulttool export attachments --path Build/Tests.xcresult --output-path Build/Screenshots || true
fi
if [ "$TEST_STATUS" -ne 0 ]; then python3 scripts/show_errors.py Build/test.log; exit "$TEST_STATUS"; fi
test -s Build/TEST-RESULTS.json
python3 - <<'PY'
import json
r=json.load(open('Build/TEST-RESULTS.json'))
assert r['failedTests']==0 and r['passedTests']>=20,r
print(json.dumps(r,indent=2))
PY
