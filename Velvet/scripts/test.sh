#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun simctl list devices available -j > Build/simulators.json
DEVICE=$(python3 -c 'import json; d=json.load(open("Build/simulators.json")); print(next(x["udid"] for k,v in d["devices"].items() if "iOS-27" in k for x in v if "iPhone" in x["name"]))')
TEST_STATUS=0
xcodebuild -project Velvet.xcodeproj -scheme Velvet -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath Build/Simulator -resultBundlePath Build/Tests.xcresult CODE_SIGNING_ALLOWED=NO test > Build/test.log 2>&1 || TEST_STATUS=$?
if [ -d Build/Tests.xcresult ]; then
    xcrun xcresulttool get test-results summary --path Build/Tests.xcresult --format json > Build/TEST-RESULTS.json || true
fi
if [ "$TEST_STATUS" -ne 0 ]; then tail -150 Build/test.log; exit "$TEST_STATUS"; fi
test -s Build/TEST-RESULTS.json
