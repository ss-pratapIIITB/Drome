#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="${SCHEME:-Drome}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
ARCHIVE="$BUILD_DIR/Drome.xcarchive"
STAGE="$BUILD_DIR/ipa"
OUTPUT="${OUTPUT:-$BUILD_DIR/Drome-unsigned.ipa}"
ENTITLEMENTS="$ROOT/Drome/Drome.Sideload.entitlements"

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

if [ ! -f "$ENTITLEMENTS" ]; then
  echo "error: $ENTITLEMENTS is missing." >&2
  exit 1
fi

echo "==> Archiving $SCHEME ($CONFIGURATION)"
rm -rf "$ARCHIVE" "$STAGE" "$OUTPUT" "$OUTPUT.sha256"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$ROOT/Drome.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  "${EXTRA_ARGS[@]}" \
  archive

APP_PATH="$(find "$ARCHIVE/Products/Applications" -type d -name '*.app' | head -n 1)"
if [ -z "${APP_PATH:-}" ]; then
  echo "error: no .app found in $ARCHIVE/Products/Applications" >&2
  exit 1
fi

echo "==> Packaging $(basename "$APP_PATH")"
mkdir -p "$STAGE/Payload"
cp -R "$APP_PATH" "$STAGE/Payload/"
(cd "$STAGE" && zip -qry "$OUTPUT" Payload)

echo "==> Writing checksum"
(cd "$BUILD_DIR" && shasum -a 256 "$(basename "$OUTPUT")" > "$(basename "$OUTPUT").sha256")

echo
echo "Unsigned IPA: $OUTPUT"
echo "Checksum:     $OUTPUT.sha256"
echo
echo "This IPA is not signed. Install it with Sideloadly, AltStore, or Xcode."
echo "See docs/install.md for step-by-step instructions."
