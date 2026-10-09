#!/usr/bin/env python3
"""Pin the series footer size (contract 3.3) in the migrated Nectar bundles.

core.css sizes `#ao3SeriesFooter` at `0.9em` of the prose, so the font size slider scales
it. core.css now reads `--ao3-series-footer-font-size`; this script sets it in each
migrated bundle's iOS `@supports` block to `0.9 * P0` in `u`, plus one rule per prose
variant (`.tNN`) whose prose size differs from the base. Idempotent.

Usage: pin_series_footer.py [--dry-run] [--check] [--root PATH]
"""

import argparse
import difflib
import re
import sys
from decimal import Decimal
from pathlib import Path

import migrate_theme_contract as m
import migrate_theme_contract_family as fam

VAR = "--ao3-series-footer-font-size"
IOS_OPENER = r"@supports\s*\(\s*-webkit-touch-callout:\s*none\s*\)\s*\{"
FACTOR = Decimal("0.9")


def pin(css):
	if VAR in css:
		return css
	masked = m.mask_comments(css)
	spans = m.block_spans(masked, IOS_OPENER)
	if not spans:
		raise m.MigrationError("no iOS @supports block")
	rules = m.find_rules(masked)
	base, variants = m.prose_sizes(css, masked, rules)
	lines = ["\t:root {\n\t\t%s: %s;\n\t}" % (VAR, m.pinned(m.fmt(FACTOR * base)))]
	for name, p in sorted(variants.items()):
		if p != base:
			lines.append("\t.%s {\n\t\t%s: %s;\n\t}" % (name, VAR, m.pinned(m.fmt(FACTOR * p))))
	end = spans[0][1]
	return css[:end] + "\n" + "\n\n".join(lines) + "\n" + css[end:]


def bundles(root):
	out = []
	for p in sorted((root / "gallery-themes").glob("*.nnwtheme")):
		if m.is_shape_b(p) or fam.is_member(p):
			out.append(p)
	out += sorted(p for p in (root / "Themes").glob("*.nnwtheme") if fam.is_member(p))
	return out


def main(argv=None):
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--dry-run", action="store_true")
	ap.add_argument("--check", action="store_true")
	ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
	args = ap.parse_args(argv)
	dirty = failed = 0
	for b in bundles(Path(args.root)):
		path = b / "stylesheet.css"
		old = path.read_text(encoding="utf-8")
		try:
			new = pin(old)
		except m.MigrationError as exc:
			print("%s: FAIL %s" % (b.name, exc))
			failed += 1
			continue
		if new == old:
			print("%s: ok" % b.name)
			continue
		dirty += 1
		print("%s: changed" % b.name)
		if args.dry_run:
			sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), new.splitlines(True), "a/" + b.name, "b/" + b.name))
		elif not args.check:
			path.write_text(new, encoding="utf-8")
	if args.check:
		return 1 if (dirty or failed) else 0
	return 1 if failed else 0


if __name__ == "__main__":
	sys.exit(main())
