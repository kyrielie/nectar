#!/usr/bin/env python3
"""Rename the page-color shorthand on `body` to `background-color` in theme bundles.

ArticleThemeColorExtractor reads only the literal `background-color` property on
`body`/`.articleBody`. A bundle that paints its page with `body { background: var(--nnw-bg) }`
looks right in the webview but resolves to white (light) / black (dark) for the full-screen
notch cover, the webview and under-page background and the Blend nav bar
(docs/article-color-pipeline.md). This rewrites those declarations by text offset
(`background` -> `background-color`, nothing else), in light and dark blocks, never in @supports.

Only a single color token is renamed (hex, rgb()/rgba(), var(--x), a color keyword).
Anything else, or a `.articleBody`-only shorthand, is listed as manual and left alone.

Usage (from buildscripts/theme-generation, or anywhere):
	fix_body_background_color.py                 # dry run over Themes/ and gallery-themes/
	fix_body_background_color.py --write         # apply
	fix_body_background_color.py --check         # exit 1 if anything needs fixing (CI)
	fix_body_background_color.py "path/X.nnwtheme" ...
"""
import argparse
import sys
from pathlib import Path

import migrate_theme_contract as m

REPO = Path(__file__).resolve().parents[2]


def bundle_dirs(paths):
	if paths:
		return [Path(p) for p in paths]
	out = []
	for top in ("Themes", "gallery-themes"):
		out.extend(sorted((REPO / top).glob("*.nnwtheme")))
	return out


def main(argv=None):
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("bundles", nargs="*", help="bundle directories (default: every bundle under Themes/ and gallery-themes/)")
	mode = ap.add_mutually_exclusive_group()
	mode.add_argument("--write", action="store_true", help="apply the rename")
	mode.add_argument("--check", action="store_true", help="exit 1 if any bundle needs a fix")
	args = ap.parse_args(argv)

	fixed, manual_total, files = 0, 0, 0
	for bundle in bundle_dirs(args.bundles):
		css_path = bundle / "stylesheet.css"
		if not css_path.exists():
			continue
		files += 1
		css = css_path.read_text(encoding="utf-8")
		new, renamed, manual = m.normalize_body_background(css)
		name = bundle.name[: -len(".nnwtheme")] if bundle.name.endswith(".nnwtheme") else bundle.name
		if renamed:
			fixed += 1
			print("%s: %d rule(s)%s" % (name, renamed, "" if args.write else " (dry run)"))
			if args.write:
				css_path.write_text(new, encoding="utf-8")
		for item in manual:
			manual_total += 1
			print("%s: MANUAL %s" % (name, item))
	print("%d stylesheet(s) scanned, %d %s, %d manual" % (files, fixed, "fixed" if args.write else "need fixing", manual_total))
	if args.check and (fixed or manual_total):
		return 1
	return 0


if __name__ == "__main__":
	sys.exit(main())
