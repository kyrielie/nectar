#!/usr/bin/env python3
"""Counts about the theme bundles, computed from the files instead of written into docs.

The theme docs used to carry numbers ("117 shape B", "150 gallery bundles", "85 at last
count") that drifted and disagreed with each other. Run this instead:

	theme_inventory.py            # counts
	theme_inventory.py --details  # also list the bundles behind each count

What it can detect mechanically:
- bundles per directory (`Themes/` ships in the app, `gallery-themes/` is gallery-only)
- template shape: shape B has `class="rh"` (compact running head); `headerTable` is the
  stock NetNewsWire header (shape A, and some older shape C themes); anything else is a
  custom wrapper or hand-built design (shapes C and D). Telling C from D needs a human.
- `ThemeIdentifier` prefixes, `Version` values, bundles with `Family`
- bundles without `License.md`
- templates without `data-versal-target` (no drop cap / versal), overall and for shape B
"""
import argparse
import collections
import plistlib
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DIRECTORIES = ("Themes", "gallery-themes")


def shape_of(template):
	if 'class="rh"' in template:
		return "B (compact running head)"
	if "headerTable" in template:
		return "header table (shape A, some C)"
	return "other (custom wrapper or hand-built; shapes C, D)"


def collect(repo=REPO):
	data = {
		"per_directory": collections.Counter(),
		"shapes": collections.Counter(),
		"id_prefixes": collections.Counter(),
		"versions": collections.Counter(),
		"family": [],
		"no_license": [],
		"no_versal": [],
		"no_versal_b": [],
		"total": 0,
	}
	for top in DIRECTORIES:
		for bundle in sorted((repo / top).glob("*.nnwtheme")):
			name = bundle.name[: -len(".nnwtheme")]
			info = plistlib.loads((bundle / "Info.plist").read_bytes())
			template = (bundle / "template.html").read_text(encoding="utf-8") if (bundle / "template.html").exists() else ""
			data["total"] += 1
			data["per_directory"][top] += 1
			data["shapes"][shape_of(template)] += 1
			data["id_prefixes"][".".join(info["ThemeIdentifier"].split(".")[:3])] += 1
			data["versions"][info["Version"]] += 1
			if "Family" in info:
				data["family"].append("%s (%s / %s)" % (name, info["Family"], info.get("FamilyVariant", "")))
			if not (bundle / "License.md").exists():
				data["no_license"].append(name)
			if "data-versal-target" not in template:
				data["no_versal"].append(name)
				if shape_of(template).startswith("B"):
					data["no_versal_b"].append(name)
	return data


def main(argv=None):
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--details", action="store_true", help="list the bundles behind each count")
	args = ap.parse_args(argv)
	d = collect()
	print("bundles: %d total" % d["total"])
	for top in DIRECTORIES:
		print("  %-15s %d" % (top + "/", d["per_directory"][top]))
	print("template shapes:")
	for k, v in sorted(d["shapes"].items()):
		print("  %-52s %d" % (k, v))
	print("ThemeIdentifier prefixes:")
	for k, v in sorted(d["id_prefixes"].items()):
		print("  %-30s %d" % (k, v))
	print("Version values: " + ", ".join("%s x%d" % (k, v) for k, v in sorted(d["versions"].items())))
	for label, key in (("with Family", "family"), ("without License.md", "no_license"), ("without data-versal-target", "no_versal"), ("shape B without data-versal-target", "no_versal_b")):
		print("%s: %d" % (label, len(d[key])))
		if args.details:
			for item in d[key]:
				print("    " + item)
	return 0


if __name__ == "__main__":
	sys.exit(main())
