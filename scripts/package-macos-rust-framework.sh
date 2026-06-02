#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <libsparxie.dylib> <Sparxie.app>" >&2
  exit 2
fi

SOURCE_DYLIB=$1
APP_BUNDLE=$2

if [[ ! -f "$SOURCE_DYLIB" ]]; then
  echo "missing Rust dylib: $SOURCE_DYLIB" >&2
  exit 1
fi

if [[ ! -d "$APP_BUNDLE/Contents" ]]; then
  echo "missing macOS app bundle: $APP_BUNDLE" >&2
  exit 1
fi

FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
FRAMEWORK_DIR="$FRAMEWORKS_DIR/sparxie.framework"
FRAMEWORK_BINARY="$FRAMEWORK_DIR/sparxie"

mkdir -p "$FRAMEWORK_DIR"
rm -f "$FRAMEWORKS_DIR/libsparxie.dylib"
cp "$SOURCE_DYLIB" "$FRAMEWORK_BINARY"
chmod 755 "$FRAMEWORK_BINARY"

install_name_tool -id "@rpath/sparxie.framework/sparxie" "$FRAMEWORK_BINARY"
codesign \
  --force \
  --deep \
  --sign "${MACOS_CODESIGN_IDENTITY:--}" \
  --preserve-metadata=entitlements \
  "$APP_BUNDLE"
