#!/usr/bin/env python3
"""
Merge a newly released app version into source.json for AltStore Classic.

Reads:
  --template   path to appstore/source.template.json (static, hand-edited metadata)
  --existing   path to the current gh-pages source.json, if any (pass "" if none yet)
  --output     path to write the merged source.json

Version fields come from environment variables, set by the workflow:
  VERSION, BUILD_VERSION, RELEASE_DATE, RELEASE_NOTES,
  DOWNLOAD_URL, SIZE_BYTES, MIN_OS_VERSION
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

    # Start from the existing published source (to keep version history),
    # falling back to the template on first publish.
    merged = existing if existing is not None else json.loads(json.dumps(template))

    # Refresh all hand-edited, non-version fields from the template every run,
    # so editing source.template.json on main always takes effect.
    for key in ("name", "subtitle", "description", "iconURL", "headerURL",
                "website", "tintColor", "featuredApps"):
        if key in template:
            merged[key] = template[key]
    merged.setdefault("apps", [])
    merged.setdefault("news", template.get("news", []))

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
