#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="${SCHEME:-Drome}"

EXTRA_ARGS=()
if [ -n "${XCODEBUILD_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS=($XCODEBUILD_ARGS)
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found. Install Xcode 26 from the App Store." >&2
  exit 1
fi

if [ ! -d "$ROOT/Drome.xcodeproj" ]; then
  echo "error: Drome.xcodeproj is missing. Run 'xcodegen generate' first." >&2
  exit 1
fi

if [ -n "${SIMULATOR_UDID:-}" ]; then
  UDID="$SIMULATOR_UDID"
else
  UDID="$(xcrun simctl list devices available --json | python3 -c '
import json, sys

try:
    devices = json.load(sys.stdin)["devices"]
except Exception:
    sys.exit(0)

for runtime in sorted(devices):
    for device in devices[runtime]:
        if device.get("isAvailable") and "iPhone" in device.get("name", ""):
            print(device["udid"])
            sys.exit(0)
')"
fi

if [ -z "${UDID:-}" ]; then
  echo "error: no available iPhone simulator runtime found." >&2
  echo "Install an iOS simulator from Xcode → Settings → Components, or set SIMULATOR_UDID." >&2
  exit 1
fi

echo "==> Testing $SCHEME on simulator $UDID"
xcodebuild \
  -project "$ROOT/Drome.xcodeproj" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  CODE_SIGNING_ALLOWED=NO \
  "${EXTRA_ARGS[@]}" \
  test
