#!/usr/bin/env bash
# Export a cloud-built unsigned xcarchive as an App Store Connect IPA.
#
# Required environment variables:
#   XCARCHIVE_ZIP, MOBILEPROVISION_PATH, IOS_BUILD_NUMBER, KEYCHAIN_PASSWORD
# Optional:
#   OUTPUT_DIR=out, IPA_NAME=sparxie-ios-testflight.ipa

set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"

: "${XCARCHIVE_ZIP:?XCARCHIVE_ZIP is required}"
: "${MOBILEPROVISION_PATH:?MOBILEPROVISION_PATH is required}"
: "${IOS_BUILD_NUMBER:?IOS_BUILD_NUMBER is required}"
: "${KEYCHAIN_PASSWORD:?KEYCHAIN_PASSWORD is required}"
: "${OUTPUT_DIR:=out}"
: "${IPA_NAME:=sparxie-ios-testflight.ipa}"

EXPECTED_BUNDLE_ID="zip.atri.sparxie"
EXPECTED_TEAM_ID="7P8CLHDH5G"
EXPECTED_APPLICATION_ID="$EXPECTED_TEAM_ID.$EXPECTED_BUNDLE_ID"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 not found." >&2
    exit 1
  fi
}

require_cmd base64
require_cmd codesign
require_cmd ditto
require_cmd plutil
require_cmd security
require_cmd xcodebuild

if [[ "$XCARCHIVE_ZIP" != /* ]]; then
  XCARCHIVE_ZIP="$PROJECT_ROOT/$XCARCHIVE_ZIP"
fi
if [[ "$MOBILEPROVISION_PATH" != /* ]]; then
  MOBILEPROVISION_PATH="$PROJECT_ROOT/$MOBILEPROVISION_PATH"
fi
if [[ "$OUTPUT_DIR" != /* ]]; then
  OUTPUT_DIR="$PROJECT_ROOT/$OUTPUT_DIR"
fi

test -s "$XCARCHIVE_ZIP"
test -s "$MOBILEPROVISION_PATH"
[[ "$IOS_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]

task_temp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
work_dir="$(mktemp -d "$task_temp_root/sparxie-export.XXXXXX")"
installed_profile=""
installed_profile_created=0

cleanup() {
  if [[ "$installed_profile_created" -eq 1 && -n "$installed_profile" ]]; then
    rm -f -- "$installed_profile"
  fi
  rm -rf -- "$work_dir"
}
trap cleanup EXIT

profile_plist="$work_dir/profile.plist"
profile_certificate="$work_dir/distribution.cer"
security cms -D -i "$MOBILEPROVISION_PATH" > "$profile_plist"

profile_name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$profile_plist")"
profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$profile_plist")"
profile_team="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$profile_plist")"
profile_app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$profile_plist")"
beta_reports="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:beta-reports-active' "$profile_plist")"
get_task_allow="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$profile_plist")"
expiration="$(plutil -extract ExpirationDate raw -o - "$profile_plist")"

test "$profile_team" = "$EXPECTED_TEAM_ID"
test "$profile_app_id" = "$EXPECTED_APPLICATION_ID"
test "$beta_reports" = "true"
test "$get_task_allow" = "false"

expiration_epoch="$(date -juf '%Y-%m-%dT%H:%M:%SZ' "$expiration" '+%s')"
test "$expiration_epoch" -gt "$(date -u '+%s')"

plutil -extract DeveloperCertificates.0 raw -o - "$profile_plist" |
  base64 --decode > "$profile_certificate"
profile_certificate_sha1="$(
  shasum -a 1 "$profile_certificate" | awk '{print toupper($1)}'
)"

identities="$(security find-identity -v -p codesigning)"
printf '%s\n' "$identities"
printf '%s\n' "$identities" | grep -Fq "$profile_certificate_sha1"

runner_keychain="$(security default-keychain -d user | tr -d ' \"')"
test -f "$runner_keychain"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$runner_keychain"
security list-keychains -d user -s "$runner_keychain"
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASSWORD" "$runner_keychain"

profile_install_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$profile_install_dir"
installed_profile="$profile_install_dir/$profile_uuid.mobileprovision"
if [[ -e "$installed_profile" ]]; then
  cmp -s "$MOBILEPROVISION_PATH" "$installed_profile"
else
  cp "$MOBILEPROVISION_PATH" "$installed_profile"
  installed_profile_created=1
fi

archive_unpack_dir="$work_dir/archive"
mkdir -p "$archive_unpack_dir"
ditto -x -k "$XCARCHIVE_ZIP" "$archive_unpack_dir"
xcarchive="$(find "$archive_unpack_dir" -maxdepth 1 -type d -name '*.xcarchive' | head -n1)"
test -n "$xcarchive"

archive_app="$(find "$xcarchive/Products/Applications" -maxdepth 1 -type d -name '*.app' | head -n1)"
test -n "$archive_app"
archive_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$archive_app/Info.plist")"
archive_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$archive_app/Info.plist")"
test "$archive_bundle_id" = "$EXPECTED_BUNDLE_ID"
test "$archive_build_number" = "$IOS_BUILD_NUMBER"

export_options="$work_dir/ExportOptions.plist"
plutil -create xml1 "$export_options"
/usr/libexec/PlistBuddy -c 'Add :destination string export' "$export_options"
/usr/libexec/PlistBuddy -c 'Add :method string app-store-connect' "$export_options"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string manual' "$export_options"
/usr/libexec/PlistBuddy -c "Add :teamID string $EXPECTED_TEAM_ID" "$export_options"
/usr/libexec/PlistBuddy -c "Add :signingCertificate string $profile_certificate_sha1" "$export_options"
/usr/libexec/PlistBuddy -c 'Add :manageAppVersionAndBuildNumber bool false' "$export_options"
/usr/libexec/PlistBuddy -c 'Add :uploadSymbols bool true' "$export_options"
/usr/libexec/PlistBuddy -c 'Add :stripSwiftSymbols bool true' "$export_options"
/usr/libexec/PlistBuddy -c 'Add :testFlightInternalTestingOnly bool false' "$export_options"
/usr/libexec/PlistBuddy -c 'Add :provisioningProfiles dict' "$export_options"
/usr/libexec/PlistBuddy \
  -c "Add :provisioningProfiles:$EXPECTED_BUNDLE_ID string $profile_uuid" \
  "$export_options"

export_dir="$work_dir/export"
xcodebuild -exportArchive \
  -archivePath "$xcarchive" \
  -exportPath "$export_dir" \
  -exportOptionsPlist "$export_options"

exported_ipa="$(find "$export_dir" -maxdepth 1 -type f -name '*.ipa' | head -n1)"
test -n "$exported_ipa"
mkdir -p "$OUTPUT_DIR"
output_ipa="$OUTPUT_DIR/$IPA_NAME"
cp "$exported_ipa" "$output_ipa"

signed_unpack_dir="$work_dir/signed"
mkdir -p "$signed_unpack_dir"
ditto -x -k "$output_ipa" "$signed_unpack_dir"
signed_app="$(find "$signed_unpack_dir/Payload" -maxdepth 1 -type d -name '*.app' | head -n1)"
test -n "$signed_app"

signed_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$signed_app/Info.plist")"
signed_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$signed_app/Info.plist")"
test "$signed_bundle_id" = "$EXPECTED_BUNDLE_ID"
test "$signed_build_number" = "$IOS_BUILD_NUMBER"

codesign --verify --deep --strict --verbose=4 "$signed_app"

signed_entitlements="$work_dir/signed-entitlements.plist"
codesign -d --entitlements :- "$signed_app" > "$signed_entitlements" 2>/dev/null
test "$(plutil -extract application-identifier raw -o - "$signed_entitlements")" = "$EXPECTED_APPLICATION_ID"
test "$(plutil -extract beta-reports-active raw -o - "$signed_entitlements")" = "true"
test "$(plutil -extract get-task-allow raw -o - "$signed_entitlements")" = "false"

embedded_profile_plist="$work_dir/embedded-profile.plist"
security cms -D -i "$signed_app/embedded.mobileprovision" > "$embedded_profile_plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$embedded_profile_plist")" = "$profile_uuid"

printf 'Exported TestFlight IPA: %s\n' "$output_ipa"
printf 'Provisioning profile: %s (%s)\n' "$profile_name" "$profile_uuid"
printf 'Signing certificate: %s\n' "$profile_certificate_sha1"
