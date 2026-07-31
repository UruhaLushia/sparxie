#!/usr/bin/env bash
# Build an unsigned iOS IPA for sideloading tools that re-sign the app later.
#
# Usage:
#   ./scripts/build-ios-ipa.sh
#   OUTPUT_DIR=out ./scripts/build-ios-ipa.sh
#   IOS_BUILD_NUMBER=123 ./scripts/build-ios-ipa.sh
#   IOS_XCARCHIVE_OUTPUT=out/sparxie-ios-unsigned.xcarchive.zip ./scripts/build-ios-ipa.sh

set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"

: "${OUTPUT_DIR:=build/ios/ipa}"
: "${IOS_RUST_TARGET:=aarch64-apple-ios}"
: "${IPA_NAME:=sparxie-ios.ipa}"
: "${IOS_BUILD_NUMBER:=$(awk -F+ '/^version:/ { print $2; exit }' pubspec.yaml)}"
: "${IOS_XCARCHIVE_OUTPUT:=}"
: "${SPARXIE_UPDATE_CHANNEL:=stable}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 not found. Install it before building the iOS IPA." >&2
    exit 1
  fi
}

require_cmd flutter
require_cmd cargo
require_cmd xcodebuild
require_cmd ditto
require_cmd nm

if command -v rustup >/dev/null 2>&1; then
  rustup target add "$IOS_RUST_TARGET"
fi

echo ">>> Building Rust core for $IOS_RUST_TARGET"
(
  cd core
  cargo build --release --target "$IOS_RUST_TARGET"
)

CORE_LIB="core/target/$IOS_RUST_TARGET/release/libsparxie.a"
if [[ ! -f "$CORE_LIB" ]]; then
  echo "Missing Rust static library: $CORE_LIB" >&2
  exit 1
fi

echo ">>> Fetching Flutter dependencies"
flutter pub get

if [[ -n "$IOS_XCARCHIVE_OUTPUT" ]]; then
  echo ">>> Building unsigned iOS archive"
  flutter build ipa --release --no-codesign \
    --build-number "$IOS_BUILD_NUMBER" \
    --dart-define="SPARXIE_BUILD_NUMBER=$IOS_BUILD_NUMBER" \
    --dart-define="SPARXIE_UPDATE_CHANNEL=$SPARXIE_UPDATE_CHANNEL"

  shopt -s nullglob
  XCARCHIVES=(build/ios/archive/*.xcarchive)
  shopt -u nullglob
  if [[ "${#XCARCHIVES[@]}" -ne 1 ]]; then
    echo "Expected exactly one iOS archive under build/ios/archive" >&2
    exit 1
  fi
  XCARCHIVE="${XCARCHIVES[0]}"
  APP_BUNDLE="$(find "$XCARCHIVE/Products/Applications" -maxdepth 1 -type d -name '*.app' | head -n1)"
else
  echo ">>> Building unsigned iOS app"
  flutter build ios --release --no-codesign \
    --build-number "$IOS_BUILD_NUMBER" \
    --dart-define="SPARXIE_BUILD_NUMBER=$IOS_BUILD_NUMBER" \
    --dart-define="SPARXIE_UPDATE_CHANNEL=$SPARXIE_UPDATE_CHANNEL"
  APP_BUNDLE="$(find build/ios/iphoneos -maxdepth 1 -type d -name '*.app' | head -n1)"
fi

if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  echo "No iOS app bundle found in the build output" >&2
  exit 1
fi

APP_EXECUTABLE="$APP_BUNDLE/Runner"
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "No Runner executable found in $APP_BUNDLE" >&2
  exit 1
fi

SYMBOLS_FILE="$(mktemp)"
if ! nm -g "$APP_EXECUTABLE" >"$SYMBOLS_FILE"; then
  echo "Unable to inspect exported symbols in $APP_EXECUTABLE" >&2
  rm -f "$SYMBOLS_FILE"
  exit 1
fi
if ! grep -q '_frb_get_rust_content_hash' "$SYMBOLS_FILE"; then
  echo "Rust FFI symbols are missing from $APP_EXECUTABLE" >&2
  echo "Check iOS linker settings: DEAD_CODE_STRIPPING must be disabled for Runner." >&2
  rm -f "$SYMBOLS_FILE"
  exit 1
fi
rm -f "$SYMBOLS_FILE"

STAGE="$(mktemp -d)"
cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

mkdir -p "$STAGE/Payload" "$OUTPUT_DIR"
cp -R "$APP_BUNDLE" "$STAGE/Payload/"

IPA_PATH="$PROJECT_ROOT/$OUTPUT_DIR/$IPA_NAME"
rm -f "$IPA_PATH"
(
  cd "$STAGE"
  ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent Payload "$IPA_PATH"
)

echo ">>> IPA: $IPA_PATH"

if [[ -n "$IOS_XCARCHIVE_OUTPUT" ]]; then
  if [[ "$IOS_XCARCHIVE_OUTPUT" = /* ]]; then
    XCARCHIVE_ZIP="$IOS_XCARCHIVE_OUTPUT"
  else
    XCARCHIVE_ZIP="$PROJECT_ROOT/$IOS_XCARCHIVE_OUTPUT"
  fi

  mkdir -p "$(dirname "$XCARCHIVE_ZIP")"
  rm -f "$XCARCHIVE_ZIP"
  (
    cd "$(dirname "$XCARCHIVE")"
    ditto -c -k --sequesterRsrc --keepParent \
      "$(basename "$XCARCHIVE")" "$XCARCHIVE_ZIP"
  )
  echo ">>> XCArchive: $XCARCHIVE_ZIP"
fi
