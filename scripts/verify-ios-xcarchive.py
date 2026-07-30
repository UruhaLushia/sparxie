#!/usr/bin/env python3
"""Validate the provenance and digest of a TestFlight xcarchive artifact."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import zipfile
from pathlib import Path


ARCHIVE_FILE = "sparxie-ios-unsigned.xcarchive.zip"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--artifact-directory", required=True, type=Path)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--run-id", required=True, type=int)
    parser.add_argument("--run-attempt", required=True, type=int)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--source-path", required=True)
    parser.add_argument("--source-head-branch", required=True)
    parser.add_argument("--bundle-id", required=True)
    return parser.parse_args()


def fail(message: str) -> None:
    raise SystemExit(message)


def main() -> None:
    args = parse_args()
    if not args.manifest.is_file():
        fail(f"manifest does not exist: {args.manifest}")

    with args.manifest.open(encoding="utf-8") as handle:
        manifest = json.load(handle)

    expected = {
        "schema_version": 1,
        "run_id": args.run_id,
        "head_sha": args.head_sha,
        "repository": args.repository,
        "bundle_id": args.bundle_id,
        "archive_file": ARCHIVE_FILE,
        "xcode_version": "26.3",
        "xcode_build": "17C529",
        "ios_sdk": "26.2",
    }
    for key, value in expected.items():
        if manifest.get(key) != value:
            fail(f"manifest field {key!r} was {manifest.get(key)!r}, expected {value!r}")

    manifest_attempt = manifest.get("run_attempt")
    if (
        not isinstance(manifest_attempt, int)
        or isinstance(manifest_attempt, bool)
        or not 1 <= manifest_attempt <= args.run_attempt
    ):
        fail(
            "manifest run_attempt must be a positive integer no greater than "
            f"the source run attempt ({args.run_attempt})"
        )

    placeholder = str(manifest.get("placeholder_build_number", ""))
    if not re.fullmatch(r"[1-9][0-9]*", placeholder):
        fail("manifest placeholder_build_number is not a positive integer")
    for key in ("marketing_version", "flutter_version", "rust_version"):
        value = manifest.get(key)
        if not isinstance(value, str) or not value.strip():
            fail(f"manifest field {key!r} is empty or invalid")

    source_ref = manifest.get("ref", "")
    if args.source_path == ".github/workflows/release.yml":
        if manifest.get("workflow") != "Release":
            fail("release manifest has an unexpected workflow name")
        if not re.fullmatch(r"refs/tags/v.+", source_ref):
            fail(f"release source ref is not a v* tag: {source_ref!r}")
        if source_ref != f"refs/tags/{args.source_head_branch}":
            fail("release manifest ref does not match the source run tag")
    elif args.source_path == ".github/workflows/pre-release.yml":
        if manifest.get("workflow") != "Pre-release":
            fail("pre-release manifest has an unexpected workflow name")
        expected_ref = f"refs/heads/{args.source_head_branch}"
        if source_ref != expected_ref:
            fail(f"pre-release source ref was {source_ref!r}, expected {expected_ref!r}")
    else:
        fail(f"unapproved source workflow: {args.source_path!r}")

    expected_digest = manifest.get("archive_sha256", "")
    if not re.fullmatch(r"[0-9a-f]{64}", expected_digest):
        fail("archive_sha256 is not a lowercase SHA-256 digest")

    archive_path = args.artifact_directory / ARCHIVE_FILE
    if not archive_path.is_file():
        fail(f"archive does not exist: {archive_path}")
    digest = hashlib.sha256()
    with archive_path.open("rb") as archive:
        for chunk in iter(lambda: archive.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected_digest:
        fail("archive SHA-256 does not match the manifest")

    with zipfile.ZipFile(archive_path) as archive_zip:
        app_info_paths = [
            name
            for name in archive_zip.namelist()
            if re.fullmatch(
                r"[^/]+\.xcarchive/Products/Applications/[^/]+\.app/Info\.plist",
                name,
            )
        ]
        if len(app_info_paths) != 1:
            fail("archive must contain exactly one root application Info.plist")
        archive_info_paths = [
            name
            for name in archive_zip.namelist()
            if re.fullmatch(r"[^/]+\.xcarchive/Info\.plist", name)
        ]
        if len(archive_info_paths) != 1:
            fail("archive must contain exactly one xcarchive Info.plist")
        app_archive_root = app_info_paths[0].split("/Products/Applications/", 1)[0]
        metadata_archive_root = archive_info_paths[0].removesuffix("/Info.plist")
        if app_archive_root != metadata_archive_root:
            fail("application and metadata plists belong to different xcarchives")
        app_info = plistlib.loads(archive_zip.read(app_info_paths[0]))
        archive_info = plistlib.loads(archive_zip.read(archive_info_paths[0]))

    if app_info.get("CFBundleIdentifier") != args.bundle_id:
        fail("archive app bundle ID does not match the manifest")
    if str(app_info.get("CFBundleVersion", "")) != placeholder:
        fail("archive app build number does not match the manifest")
    application_properties = archive_info.get("ApplicationProperties", {})
    if application_properties.get("CFBundleIdentifier") != args.bundle_id:
        fail("xcarchive metadata bundle ID does not match the manifest")
    if str(application_properties.get("CFBundleVersion", "")) != placeholder:
        fail("xcarchive metadata build number does not match the manifest")

    print(archive_path.resolve())


if __name__ == "__main__":
    main()
