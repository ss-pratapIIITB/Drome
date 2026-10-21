#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found. Install Xcode 26 from the App Store." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found. Install it with 'brew install xcodegen'." >&2
  exit 1
fi

echo "==> Generating Drome.xcodeproj"
xcodegen generate

echo "==> Resolving Swift packages"
xcodebuild -project Drome.xcodeproj -scheme Drome -resolvePackageDependencies

echo
echo "Ready. Open Drome.xcodeproj, set your signing team, and run on a device."
