#!/usr/bin/env bash
# Cross-compile libsparxie.so for Android and drop the artifacts into
# android/app/src/main/jniLibs/<abi>/, where Flutter packs them into the
# APK and dart:ffi can DynamicLibrary.open them at runtime.
#
# Usage:
#   ./scripts/build-android.sh                    # release, all default abis
#   ./scripts/build-android.sh --debug            # debug build
#   ABIS="arm64-v8a" ./scripts/build-android.sh   # subset of abis

set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"

PROFILE="release"
[[ "${1:-}" == "--debug" ]] && PROFILE="debug"

: "${ANDROID_NDK_HOME:=/opt/android-ndk}"
: "${ABIS:=arm64-v8a x86_64}"

if [[ ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "ANDROID_NDK_HOME not found at $ANDROID_NDK_HOME" >&2
  exit 1
fi

JNI_LIBS="$PROJECT_ROOT/android/app/src/main/jniLibs"
# Wipe before populating so a renamed lib (or a since-dropped ABI) doesn't
# linger and get packaged into the APK alongside the new artifacts.
rm -rf "$JNI_LIBS"
mkdir -p "$JNI_LIBS"

"$PROJECT_ROOT/scripts/build-go-core.sh"

NDK_ARGS=(--platform 24 -o "$JNI_LIBS")
for abi in $ABIS; do
  NDK_ARGS+=(-t "$abi")
done

CARGO_ARGS=(build)
[[ "$PROFILE" == "release" ]] && CARGO_ARGS+=(--release)

echo ">>> cargo ndk ${NDK_ARGS[*]} -- ${CARGO_ARGS[*]}"
(
  cd core
  ANDROID_NDK_HOME="$ANDROID_NDK_HOME" cargo ndk "${NDK_ARGS[@]}" -- "${CARGO_ARGS[@]}"
)

echo
echo "Artifacts:"
find "$JNI_LIBS" -name 'libsparxie.so' -printf '  %p\t%s bytes\n' | sort
