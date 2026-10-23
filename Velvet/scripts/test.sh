#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun simctl list devices available -j > Build/simulators.json
DEVICE=$(python3 -c 'import json; d=json.load(open("Build/simulators.json")); print(next(x["udid"] for k,v in d["devices"].items() if "iOS-27" in k for x in v if "iPhone" in x["name"]))')
xcodebuild -project Velvet.xcodeproj -scheme Velvet -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath Build/Simulator -resultBundlePath Build/Tests.xcresult CODE_SIGNING_ALLOWED=NO test > Build/test.log 2>&1 || { tail -150 Build/test.log; exit 1; }
xcrun xcresulttool get test-results summary --path Build/Tests.xcresult --format json > Build/TEST-RESULTS.json
