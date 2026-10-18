#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"
export SDK_VERSION
SIMULATOR_ID="$(xcrun simctl list devices available --json | python3 -c '
import json, os, sys
sdk = tuple(map(int, os.environ["SDK_VERSION"].split(".")))
devices = json.load(sys.stdin)["devices"]
candidates = []
for runtime, entries in devices.items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(map(int, runtime.split(".iOS-")[1].split("-")))
    if (16,) <= version <= sdk:
        candidates.extend((version, "Max" in device["name"], device["udid"]) for device in entries if device["name"].startswith("iPhone"))
if not candidates:
    sys.exit("No compatible iPhone simulator is installed.")
print(sorted(candidates, reverse=True)[0][2])
')"
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcodebuild test \
    -project NetScan/NetScan.xcodeproj -scheme NetScan \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath build/UITests \
    -resultBundlePath "build/UITestResults-$(date +%s).xcresult" \
    -only-testing:NetScanUITests -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO
