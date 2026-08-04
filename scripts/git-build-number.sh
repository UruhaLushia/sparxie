#!/usr/bin/env bash

set -euo pipefail

if [[ "$(git rev-parse --is-shallow-repository)" == true ]]; then
  echo "Cannot derive the build number from a shallow Git checkout." >&2
  exit 1
fi

BUILD_NUMBER="$(git rev-list --count HEAD)"
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "Unable to derive a valid build number from the Git history." >&2
  exit 1
fi

printf '%s\n' "$BUILD_NUMBER"
