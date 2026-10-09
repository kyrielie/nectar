#!/usr/bin/env python3
"""Migrate the Sepia-derived Nectar bundles to the theme contract (WP5).

These bundles share one template.html (NetNewsWire's Sepia structure: a
`headerContainer` table, `.articleTitle h1`, dateline, `#bodyContainer`) and size
everything in `em` of the prose or in `rem`, so the in-app font size slider scales the
title, dateline and chapter headings, which the contract pins (docs/nnwtheme-format.md).

Per bundle, idempotent:

1. Tokens: `--nnw-bg`, `--nnw-ink`, `--nnw-link` as literals in `:root` (and the dark
   `:root` block when the bundle has one). The `body` rule and the exact `a` rule point
   at them, `.articleBody` and `.articleBody a` rules are added. Other paint
   declarations holding a literal copy of the page color use the token.
2. `--u: calc(1rem / 15)` globally (so macOS keeps its current rem-based sizes) and
   `html { font: -apple-system-body }` in the iOS block.
3. `rem` lengths become `calc(var(--u) * N)` with N = rem * 15.
4. Pinned sizes in the iOS block: title and chapter headings get the hierarchy floor,
   dateline and external link are pinned, `--ao3-preface-font-size` is pinned, and the
   header table font size is pinned.
5. Chrome font: header table and dateline use `var(--nnw-font-chrome, <own stack>)`.

No `--gx` is declared: these bundles inset through `body` padding, and declaring `--gx`
without consuming it would make the horizontal-margin override do nothing.

Usage: migrate_theme_contract_family.py [--dry-run] [--check] [--only NAME] [--root PATH]
"""

import argparse
import difflib
import hashlib
import re
import sys
from decimal import Decimal
from pathlib import Path

import migrate_theme_contract as m

FAMILY_TEMPLATES = {"f8e5b6", "320447"}
THEMES_DIR_MEMBERS = {"Black & White", "Duskbloom", "Ember", "Powder Pink", "Tumblr Blue"}
P0 = Decimal(15)
IOS_OPENER = r"@supports\s*\(\s*-webkit-touch-callout:\s*none\s*\)\s*\{"
REM = re.compile(r"(?<![\w.-])(\d*\.?\d+)rem\b")
HEX = re.compile(r"^#[0-9a-fA-F]{3,8}$")


def is_member(bundle):
	template = bundle / "template.html"
	if not template.exists():
		return False
	digest = hashlib.md5(template.read_bytes()).hexdigest()[:6]
	if digest not in FAMILY_TEMPLATES:
		return False
	if bundle.parent.name == "Themes":
		return bundle.name[: -len(".nnwtheme")] in THEMES_DIR_MEMBERS
	return True


def root_rules(css, masked, rules, context):
	return [r for r in rules
		if r.context == context and m.split_selectors(masked[r.sel_start:r.sel_end]) == [":root"]]


def merged_vars(css, rs):
	out = {}
	for r in rs:
		out.update(m.parse_root_vars(css[r.body_start:r.body_end] + ";"))
	return out


def rule_decls(css, rule):
	return m.declarations(css[rule.body_start:rule.body_end])


def find_rule(css, masked, rules, selector, context="light"):
	hits = [r for r in rules if r.context == context and m.split_selectors(masked[r.sel_start:r.sel_end]) == [selector]]
	return hits


def resolve(value, light, dark=None):
	local = dark if dark is not None else {}
	return m.resolve_one_level(value, local, light)


def token_edit(css, rule, tokens):
	"""Insert tokens before the rule's closing brace, terminating the last declaration."""
	body = css[rule.body_start:rule.body_end]
	stripped = body.rstrip()
	cut = rule.body_start + len(stripped)
	lead = "" if (not stripped or stripped.endswith(";") or stripped.endswith("*/")) else ";"
	trailing = body[len(stripped):]
	indent = trailing.rsplit("\n", 1)[1] if "\n" in trailing else ""
	return (cut, rule.body_end, lead + tokens + indent)


def migrate_css(css, name):
	"""Return (new_css, notes). Raises MigrationError."""
	notes = []
	if "--nnw-bg" in css:
		return css, notes
	masked = m.mask_comments(css)
	rules = m.find_rules(masked)

	light_roots = root_rules(css, masked, rules, "light")
	dark_roots = root_rules(css, masked, rules, "dark")
	if not light_roots:
		raise m.MigrationError("no :root block")
	light = merged_vars(css, light_roots)
	dark = merged_vars(css, dark_roots) if dark_roots else None

	bodies = [r for r in find_rule(css, masked, rules, "body")
		if any(p in ("background", "background-color") for _s, _e, p, _v in rule_decls(css, r))]
	if not bodies:
		raise m.MigrationError("no body rule with a background")
	body = bodies[0]
	body_decls = rule_decls(css, body)
	bg_decl = next(d for d in body_decls if d[2] in ("background", "background-color"))
	ink_decl = next((d for d in body_decls if d[2] == "color"), None)
	if ink_decl is None:
		raise m.MigrationError("body rule has no color")

	a_rules = find_rule(css, masked, rules, "a")
	a_decl = None
	for r in a_rules:
		a_decl = next((d for d in rule_decls(css, r) if d[2] == "color"), None)
		if a_decl:
			a_rule = r
			break

	def lit(value, label, use_dark):
		v = resolve(value, light, dark if use_dark else None)
		if v is None or not HEX.match(v.strip()):
			raise m.MigrationError("%s does not resolve to a literal color (%r)" % (label, value))
		return v.strip()

	bg_v, ink_v = bg_decl[3], ink_decl[3]
	link_v = a_decl[3] if a_decl else ink_v
	if not a_decl:
		notes.append("no exact `a` color rule; --nnw-link falls back to the ink color")
	tokens_light = "\n\t--nnw-bg: %s;\n\t--nnw-ink: %s;\n\t--nnw-link: %s;\n\t--u: calc(1rem / 15);\n" % (
		lit(bg_v, "page", False), lit(ink_v, "ink", False), lit(link_v, "link", False))
	tokens_dark = None
	if dark_roots:
		tokens_dark = "\n\t--nnw-bg: %s;\n\t--nnw-ink: %s;\n\t--nnw-link: %s;\n" % (
			lit(bg_v, "page (dark)", True), lit(ink_v, "ink (dark)", True), lit(link_v, "link (dark)", True))

	bg_hexes = m.hex_variants(lit(bg_v, "page", False))
	if dark_roots:
		bg_hexes |= m.hex_variants(lit(bg_v, "page (dark)", True))

	edits = []  # (start, end, replacement); applied from the end

	def replace_value(rule, decl, new):
		start = rule.body_start + decl[0]
		text = css[start:rule.body_start + decl[1]]
		colon = text.index(":")
		gap = len(text[colon + 1:]) - len(text[colon + 1:].lstrip())
		edits.append((start + colon + 1 + gap, rule.body_start + decl[1], new))

	replace_value(body, bg_decl, "var(--nnw-bg)")
	replace_value(body, ink_decl, "var(--nnw-ink)")
	if a_decl:
		replace_value(a_rule, a_decl, "var(--nnw-link)")

	# Tokens go at the end of the first light and first dark :root rule.
	first_light = light_roots[0]
	edits.append(token_edit(css, first_light, tokens_light))
	if dark_roots:
		first_dark = dark_roots[0]
		edits.append(token_edit(css, first_dark, tokens_dark))

	# Literal copies of the page color elsewhere.
	for r in rules:
		if r.context == "supports":
			continue
		sel = " ".join(masked[r.sel_start:r.sel_end].split())
		if sel == ":root" or r is body:
			continue
		for d in rule_decls(css, r):
			if d[2].startswith("--") or not m.PAINT_PROPS.match(d[2]):
				continue
			new, n = d[3], 0
			for h in bg_hexes:
				new, k = re.subn(re.escape(h) + r"(?![0-9a-fA-F])", "var(--nnw-bg)", new, flags=re.I)
				n += k
			if n:
				replace_value(r, d, new)
				notes.append("bg-literal replaced: %s { %s }" % (sel, d[2]))

	# rem -> u, everywhere outside the rules rewritten below.
	header_td = set()
	for r in rules:
		sel = " ".join(masked[r.sel_start:r.sel_end].split())
		is_header = ".headerTable" in sel
		for d in rule_decls(css, r):
			if d[2].startswith("--") and "font-size" not in d[2]:
				continue
			if not REM.search(d[3]):
				continue
			if d[2] == "font-size" and is_header and r.context != "supports":
				n = fmt_n(REM.fullmatch(d[3].strip()), d[3])
				if n is not None:
					header_td.add(sel)
					replace_value(r, d, m.pinned(n))
					continue
			new = REM.sub(lambda mo: "calc(var(--u) * %s)" % m.fmt(Decimal(mo.group(1)) * 15), d[3])
			replace_value(r, d, new)

	# Chrome font on the header table.
	for r in rules:
		sel = " ".join(masked[r.sel_start:r.sel_end].split())
		if ".headerTable" not in sel or r.context == "supports":
			continue
		for d in rule_decls(css, r):
			if d[2] == "font-family" and "--nnw-font-chrome" not in d[3]:
				replace_value(r, d, "var(--nnw-font-chrome, %s)" % d[3])

	# iOS block: title, headings, dateline, preface, html font, body stack for the dateline.
	spans = m.block_spans(masked, IOS_OPENER)
	if not spans:
		raise m.MigrationError("no iOS @supports block")
	ios_start, ios_end = spans[0]
	ios_rules = [r for r in rules if r.context == "supports" and ios_start <= r.sel_start < ios_end]
	h1 = next((r for r in ios_rules
		if ".articleTitle h1" in " ".join(masked[r.sel_start:r.sel_end].split())), None)
	if h1 is None:
		raise m.MigrationError("no .articleTitle h1 in the iOS block")
	h1_size = next((d for d in rule_decls(css, h1) if d[2] == "font-size"), None)
	mo = re.fullmatch(r"([\d.]+)em", h1_size[3]) if h1_size else None
	if not mo:
		raise m.MigrationError("iOS h1 font-size is not in em (%r)" % (h1_size[3] if h1_size else None))
	title_n = Decimal(mo.group(1)) * P0
	title_value, k_title = m.floored(m.fmt(title_n), P0, m.KMAX_TITLE)
	replace_value(h1, h1_size, title_value)
	heading_n = Decimal("1.5") * P0
	heading_value, _k = m.floored(m.fmt(heading_n), P0, m.KMAX_HEADING)

	preface_set = False
	for r in rules:
		for d in rule_decls(css, r):
			if d[2] == "--ao3-preface-font-size":
				em = re.fullmatch(r"([\d.]+)em", d[3])
				if not em:
					raise m.MigrationError("--ao3-preface-font-size is not in em (%r)" % d[3])
				replace_value(r, d, m.pinned(m.fmt(Decimal(em.group(1)) * P0)))
				preface_set = True

	stack = None
	for r in ios_rules:
		if " ".join(masked[r.sel_start:r.sel_end].split()) == "body":
			stack = next((d[3] for d in rule_decls(css, r) if d[2] == "font-family"), None)
	dateline_n = P0
	for r in rules:
		if r.context == "light" and m.split_selectors(masked[r.sel_start:r.sel_end]) == [".articleDateline"]:
			for d in rule_decls(css, r):
				em = re.fullmatch(r"([\d.]+)em", d[3]) if d[2] == "font-size" else None
				if em:
					dateline_n = Decimal(em.group(1)) * P0
	added = [
		"\thtml {\n\t\tfont: -apple-system-body;\n\t}",
		"\t.articleDateline,\n\t.articleDatelineTitle {\n\t\tfont-size: %s;\n\t}\n\n\t.externalLink {\n\t\tfont-size: %s;\n\t}" % (m.pinned(m.fmt(dateline_n)), m.pinned(m.fmt(P0))),
		"\t.chapter.preface.group > h2.heading {\n\t\tfont-size: %s;\n\t}" % heading_value,
	]
	if not preface_set:
		added.insert(1, "\t:root {\n\t\t--ao3-preface-font-size: %s;\n\t}" % m.pinned(m.fmt(Decimal("0.9") * P0)))
	if stack:
		added.append("\t.articleDateline,\n\t.articleDatelineTitle {\n\t\tfont-family: var(--nnw-font-chrome, %s);\n\t}" % stack)
	else:
		notes.append("no body font-family in the iOS block; dateline not routed to --nnw-font-chrome")
	edits.append((ios_end, ios_end, "\n" + "\n\n".join(added) + "\n"))

	# Contract selectors the color extractor reads, added once at the end.
	tail = "\n/* Theme contract: exact selectors read by ArticleThemeColorExtractor. */\n.articleBody {\n\tcolor: var(--nnw-ink);\n}\n\n.articleBody a {\n\tcolor: var(--nnw-link);\n}\n"
	out = css
	for start, end, text in sorted(edits, key=lambda e: (e[0], e[1]), reverse=True):
		out = out[:start] + text + out[end:]
	if not out.endswith("\n"):
		out += "\n"
	out += tail
	notes.append("title N=%s K=%s" % (m.fmt(title_n), m.fmt(k_title)))
	return out, notes


def fmt_n(match, raw):
	if not match:
		return None
	return m.fmt(Decimal(match.group(1)) * 15)


def main(argv=None):
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--dry-run", action="store_true")
	ap.add_argument("--check", action="store_true")
	ap.add_argument("--only")
	ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
	args = ap.parse_args(argv)
	root = Path(args.root)
	bundles = sorted(
		p for d in ("Themes", "gallery-themes") for p in (root / d).glob("*.nnwtheme") if is_member(p))
	if args.only:
		wanted = args.only if args.only.endswith(".nnwtheme") else args.only + ".nnwtheme"
		bundles = [b for b in bundles if b.name == wanted]
		if not bundles:
			print("no family bundle named %s" % args.only, file=sys.stderr)
			return 2
	dirty = failed = 0
	for bundle in bundles:
		path = bundle / "stylesheet.css"
		original = path.read_text(encoding="utf-8")
		try:
			new, notes = migrate_css(original, bundle.name)
		except m.MigrationError as exc:
			print("%s: FAIL %s" % (bundle.name, exc))
			failed += 1
			continue
		if new == original:
			print("%s: ok" % bundle.name)
		else:
			dirty += 1
			print("%s: changed" % bundle.name)
			if args.dry_run:
				sys.stdout.writelines(difflib.unified_diff(
					original.splitlines(True), new.splitlines(True),
					"a/%s/%s/stylesheet.css" % (bundle.parent.name, bundle.name),
					"b/%s/%s/stylesheet.css" % (bundle.parent.name, bundle.name)))
			elif not args.check:
				path.write_text(new, encoding="utf-8")
		for note in notes:
			print("  note: %s" % note)
	if args.check:
		return 1 if (dirty or failed) else 0
	return 1 if failed else 0


if __name__ == "__main__":
	sys.exit(main())
