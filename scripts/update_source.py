#!/usr/bin/env python3
"""
Merge a newly released app version into source.json for AltStore Classic.

Reads:
  --template   path to appstore/source.template.json (static, hand-edited metadata)
  --existing   path to the current gh-pages source.json, if any (pass "" if none yet)
  --output     path to write the merged source.json

Version fields come from environment variables, set by the workflow:
  VERSION, BUILD_VERSION, RELEASE_DATE, RELEASE_NOTES,
  DOWNLOAD_URL, SIZE_BYTES, MIN_OS_VERSION, MARKETING_VERSION_DISPLAY

NOTES_ONLY_REFRESH ("true"/"false", default "false"): set by the workflow's
`release` (edited) trigger, which re-runs this script without rebuilding the
IPA. On that path, BUILD_VERSION/DOWNLOAD_URL/SIZE_BYTES/MIN_OS_VERSION/
MARKETING_VERSION_DISPLAY are *recomputed* by the workflow from a fresh
GITHUB_RUN_NUMBER and a fresh `xcodebuild -showBuildSettings`, but the IPA
asset itself is untouched -- so trusting those recomputed values would let
source.json's buildVersion drift past what's actually embedded in the
already-published IPA (AltStore refuses to install when they disagree; see
release.yml). When NOTES_ONLY_REFRESH is true and an existing entry for
VERSION is already published, this script ignores the recomputed build
metadata and carries the existing entry's buildVersion/downloadURL/size/
minOSVersion/marketingVersion forward unchanged, updating only date and
localizedDescription. If no existing entry for VERSION is found (first
publish, or the tag's version genuinely changed), it falls back to the
freshly computed values, since there is nothing yet to preserve.
"""
import json
import os
import sys


def load_json(path):
    if not path:
        return None
    if not os.path.isfile(path):
        return None
    with open(path) as f:
        return json.load(f)


def main():
    args = dict(a.split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    template_path = args.get("--template")
    existing_path = args.get("--existing")
    output_path = args.get("--output")

    if not template_path or not output_path:
        print("usage: update_source.py --template=PATH --existing=PATH_OR_EMPTY --output=PATH", file=sys.stderr)
        sys.exit(1)

    template = load_json(template_path)
    if template is None:
        print(f"template not found: {template_path}", file=sys.stderr)
        sys.exit(1)

    existing = load_json(existing_path)

    version = os.environ["VERSION"]
    build_version = os.environ["BUILD_VERSION"]
    release_date = os.environ["RELEASE_DATE"]
    release_notes = os.environ.get("RELEASE_NOTES", "")
    download_url = os.environ["DOWNLOAD_URL"]
    size_bytes = int(os.environ["SIZE_BYTES"])
    min_os_version = os.environ.get("MIN_OS_VERSION", "")
    # Display-only version string (e.g. the git tag, "0.4.2"), decoupled
    # from the upstream-pinned MARKETING_VERSION/CURRENT_PROJECT_VERSION
    # pair so releases are distinguishable in the AltStore/SideStore UI
    # without touching the shared NetNewsWire xcconfig.
    marketing_version_display = os.environ.get("MARKETING_VERSION_DISPLAY", "")
    notes_only_refresh = os.environ.get("NOTES_ONLY_REFRESH", "false").lower() == "true"

    new_entry = {
        "version": version,
        "buildVersion": build_version,
        "date": release_date,
        "localizedDescription": release_notes or f"Release {version}",
        "downloadURL": download_url,
        "size": size_bytes,
    }
    if min_os_version:
        new_entry["minOSVersion"] = min_os_version
    if marketing_version_display:
        new_entry["marketingVersion"] = marketing_version_display

    if notes_only_refresh:
        previous_entry = None
        if existing is not None:
            for app in existing.get("apps", []):
                for v in app.get("versions", []):
                    if v.get("version") == version:
                        previous_entry = v
                        break
                if previous_entry is not None:
                    break
        if previous_entry is not None:
            # A release-notes edit never rebuilds the IPA, so nothing about
            # the shipped asset is allowed to change here -- only what a
            # person actually edited (the notes) and when we noticed (date).
            for key in ("buildVersion", "downloadURL", "size", "minOSVersion", "marketingVersion"):
                if key in previous_entry:
                    new_entry[key] = previous_entry[key]
                else:
                    new_entry.pop(key, None)
        else:
            print(
                f"NOTES_ONLY_REFRESH=true but no existing published entry for version {version!r} "
                "was found -- publishing freshly computed build metadata instead, since there is "
                "nothing to preserve.",
                file=sys.stderr,
            )

    # Start from the existing published source (to keep version history),
    # falling back to the template on first publish.
    merged = existing if existing is not None else json.loads(json.dumps(template))

    # Refresh every hand-edited, top-level source field from the template
    # on every run, so editing source.template.json on main always takes
    # effect -- including "news" and any field added later (fediUsername,
    # nsfw, headerURL, etc). Only "apps" is excluded: its version history
    # is merged separately below, not overwritten wholesale.
    #
    # NOTE: this previously used a hardcoded field tuple with plain
    # `if key in template: merged[key] = ...`, plus a *separate*
    # `merged.setdefault("news", ...)` line. setdefault only writes when
    # the key is absent from `merged` -- but `merged` starts as the
    # *existing* published source.json, which already has a "news" key
    # (even if "[]") after the very first publish. So template edits to
    # "news" (and any field outside the tuple) silently stopped applying
    # after day one. Mirroring the whole template here removes that trap.
    for key, value in template.items():
        if key == "apps":
            continue
        merged[key] = value
    merged.setdefault("apps", [])

    template_app = template["apps"][0]
    bundle_id = template_app["bundleIdentifier"]

    existing_app = None
    for app in merged["apps"]:
        if app.get("bundleIdentifier") == bundle_id:
            existing_app = app
            break

    if existing_app is None:
        existing_app = {"versions": []}
        merged["apps"].append(existing_app)

    for key in ("name", "developerName", "subtitle", "localizedDescription",
                "iconURL", "tintColor", "category", "screenshots", "appPermissions"):
        if key in template_app:
            existing_app[key] = template_app[key]
    existing_app["bundleIdentifier"] = bundle_id

    versions = [v for v in existing_app.get("versions", []) if v.get("version") != version]
    versions.insert(0, new_entry)
    existing_app["versions"] = versions

    with open(output_path, "w") as f:
        json.dump(merged, f, indent=4)
        f.write("\n")


if __name__ == "__main__":
    main()
