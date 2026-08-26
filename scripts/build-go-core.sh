#!/usr/bin/env bash
# Build the Go kernel wrapper into Android jniLibs.

set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"

: "${ANDROID_NDK_HOME:=/opt/android-ndk}"
: "${ABIS:=arm64-v8a x86_64}"

if [[ ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "ANDROID_NDK_HOME not found at $ANDROID_NDK_HOME" >&2
  exit 1
fi

if [[ ! -f "$PROJECT_ROOT/core/go/mihomo/go.mod" ]]; then
  echo "mihomo submodule is missing; run: git submodule update --init" >&2
  exit 1
fi

# mihomo's mobile integration (external-fd TUN, android DNS patch) lives behind
# the cmfa build tag; with_gvisor bundles the userspace gvisor stack.
TAGS="cmfa,with_gvisor"
GO_TARGETS=(
  "arm64-v8a|arm64|aarch64-linux-android24-clang"
  "x86_64|amd64|x86_64-linux-android24-clang"
)

for abi in $ABIS; do
  case "$abi" in
    arm64-v8a|x86_64) ;;
    *)
      echo "unsupported Go kernel ABI: $abi" >&2
      exit 1
      ;;
  esac
done

JNI_LIBS="$PROJECT_ROOT/android/app/src/main/jniLibs"
mkdir -p "$JNI_LIBS"

# Version aligns with the pinned submodule's Alpha commit (alpha-<short>),
# matching the upstream alpha-channel versioning style.
MIHOMO_COMMIT="$(git -C "$PROJECT_ROOT/core/go/mihomo" rev-parse --short HEAD)"
LDFLAGS="-s -w -buildid= -X github.com/metacubex/mihomo/constant.Version=alpha-${MIHOMO_COMMIT}"

for entry in "${GO_TARGETS[@]}"; do
  abi="${entry%%|*}"; rest="${entry#*|}"
  goarch="${rest%%|*}"; cc="${rest#*|}"

  case " $ABIS " in
    *" $abi "*) ;;
    *) continue ;;
  esac

  CC_PATH="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/$cc"
  if [[ ! -x "$CC_PATH" ]]; then
    echo "missing toolchain: $CC_PATH" >&2
    exit 1
  fi

  echo ">>> building libmihomo.so ($abi)"
  (
    cd "$PROJECT_ROOT/core/go"
    GOOS=android GOARCH="$goarch" CGO_ENABLED=1 CC="$CC_PATH" \
      go build -buildmode=c-shared -buildvcs=false -tags "$TAGS" \
      -trimpath \
      -ldflags "$LDFLAGS" \
      -o "$JNI_LIBS/$abi/libmihomo.so" ./wrapper
    rm -f "$JNI_LIBS/$abi/libmihomo.h"
  )
done

echo
echo "Artifacts:"
find "$JNI_LIBS" -name 'libmihomo.so' -printf '  %p\t%s bytes\n' | sort
