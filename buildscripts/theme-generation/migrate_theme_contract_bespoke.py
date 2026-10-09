#!/usr/bin/env python3
"""Migrate the 17 bespoke Nectar bundles to the theme contract (WP5, pass 5).

These bundles each have their own template and size title, byline, preface and chapter
headings in nested `em`, so the in-app size slider scales them. The contract pins them
(docs/nnwtheme-format.md). Compounding `em` makes arithmetic unreliable, so every pin value
is read from a headless-Chromium measurement of the unmigrated bundle (html at 17px, the
iOS block enabled, light and dark) and converted with N = px * 15 / 17.

The tool appends pinned rules to the bundle's iOS `@supports` block instead of rewriting
the bundle's own `em` rules. Per bundle, idempotent (a bundle that already declares
`--nnw-bg` is left alone):

1. Tokens: `--nnw-bg`, `--nnw-ink`, `--nnw-link` as literals in `:root` (and the dark
   `:root` block). `body`, the exact `a` rule and generic link rules point at them; the
   `.articleBody` and `.articleBody a` contract rules are added when missing. A custom
   property that held the page color is replaced by `var(--nnw-bg)` wherever it is used.
2. `--u: calc(1rem / 15)` globally, `html { font: -apple-system-body }` in the iOS block,
   and every `rem` length converted to `calc(var(--u) * N)`.
3. Pinned sizes (iOS block): a wrapper pinned to 15u so everything derived from it keeps
   its size, then the title and chapter headings with the hierarchy floor, and header,
   byline, dateline, footer and ornament parts pinned. The preface and series footer are
   pinned through `--ao3-preface-font-size` / `--ao3-series-footer-font-size`, or through
   the bundle's own preface rule when it has one. Values that differ in dark mode get a
   dark rule.
4. Chrome font: `var(--nnw-font-chrome, <own stack>)` on header, byline, dateline and
   footer text.
5. Broadsheet's inline `<script>` is removed (it never ran in the reader).

Usage: migrate_theme_contract_bespoke.py [--dry-run] [--check] [--only NAME] [--root PATH]
Needs `pip install playwright` and a Chromium install for the measurement.
"""

import argparse
import difflib
import re
import sys
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

import migrate_theme_contract as m
import migrate_theme_contract_family as fam

IOS_OPENER = fam.IOS_OPENER
P0_BASE = Decimal(15)
HTML_PX = Decimal(17)
HEADING_SEL = "%s h2.heading, %s h3.title"


def part(role, css, probe=None, chrome=None, chrome_target=None, mult=1):
	return dict(role=role, css=css, probe=probe or css, chrome=chrome, chrome_target=chrome_target, mult=mult)


def al_parts(flower=None):
	"""Aldine-layout bundles: header bar, dateline bar, article title, ornament, footer."""
	parts = [
		part("wrapper", ".fontSize"),
		part("pin", ".headerBar", chrome="wrap"),
		part("pin", ".headerBar .byline", ".byline", chrome="wrap", chrome_target=".byline"),
		part("pin", ".datelineBar", chrome="wrap"),
		part("title", ".articleTitle"),
	]
	if flower:
		parts.append(part("pin", flower))
	parts += [
		part("pin", "body .footer", ".footer", chrome="wrap"),
		part("heading", HEADING_SEL % (".articleBody", ".articleBody"), "h2.heading"),
	]
	return parts


def page_parts(prefix, body):
	"""Page-layout bundles: .xHeader / .byline / .xFooter around an h1 title."""
	return [
		part("wrapper", ".fontSize"),
		part("title", ".%sHeader .articleTitle h1" % prefix, "h1"),
		part("pin", ".%sHeader .byline" % prefix, ".byline", chrome="add"),
		part("pin", ".%sFooter" % prefix, chrome="wrap"),
		part("heading", HEADING_SEL % ("." + body, "." + body), "h2.heading"),
	]


SPECS = {
	"Aldine": dict(parts=al_parts(".printersFlower"), link="var(--link-color)"),
	"Deco Line": dict(parts=al_parts(), link="var(--link-color)"),
	"Kennerley": dict(parts=al_parts(".pressMark"), link="var(--link-color)"),
	"Marigold Press": dict(parts=al_parts(".sunburst"), link="var(--link-color)"),
	"Rosarivo": dict(parts=al_parts(), link="var(--link-color)"),
	"Craft Table": dict(parts=page_parts("craft", "craftBody")),
	"Didone Editorial": dict(parts=page_parts("didone", "didoneBody")),
	"Four Nations": dict(parts=page_parts("nations", "nationsBody")),
	"Illuminated Codex": dict(parts=page_parts("codex", "codexBody")),
	"Mid-century Jost": dict(parts=page_parts("jost", "jostBody")),
	"Screenplay": dict(parts=page_parts("script", "scriptBody")),
	"Sticker Pop": dict(parts=page_parts("sticker", "stickerBody")),
	"Kelmscott": dict(parts=[
		part("wrapper", ".fontSize"),
		part("pin", ".kelmscottHeaderInner", chrome="wrap"),
		part("pin", ".kelmscottByline", chrome="wrap"),
		part("title", ".kelmscottTitle"),
		part("pin", ".kelmscottDateline", chrome="wrap"),
		part("pin", ".kelmscottFooter", chrome="wrap"),
		part("heading", HEADING_SEL % (".kelmscottBody", ".kelmscottBody"), "h2.heading"),
	], link="var(--link-color)"),
	"Heist Night": dict(parts=[
		part("wrapper", ".sc-page"),
		part("pin", ".sc-top", chrome="wrap"),
		part("title", ".sc-title"),
		part("pin", ".sc-by", chrome="add"),
		part("heading", HEADING_SEL % (".articleBody", ".articleBody"), "h2.heading"),
	], bgvar="--bg"),
	"Undercity Dusk": dict(parts=[
		part("wrapper", ".ar-page"),
		part("pin", ".ar-top", chrome="wrap"),
		part("title", ".ar-title"),
		part("pin", ".ar-by", chrome="add"),
		part("heading", HEADING_SEL % (".articleBody", ".articleBody"), "h2.heading"),
	], bgvar="--bg"),
	"Broadsheet": dict(parts=[
		part("wrapper", ".feedHeader"),
		part("wrapper", "article"),
		part("title", ".articleTitle h1", "h1"),
		part("pin", ".feedHeader .byline", ".byline", chrome="add"),
		part("pin", ".externalLink"),
		part("heading", HEADING_SEL % (".articleBody", ".articleBody"), "h2.heading"),
	], strip_script=True,
		# Broadsheet declares no page colors: it relies on the web view's defaults, which are
		# the extractor's own fallbacks, and its iOS block's accent color for links.
		defaults=dict(bg="#ffffff", ink="#000000", link="#000000", dbg="#000000", dink="#ffffff", dlink="#ffffff")),
	"Vintage Letter Green": dict(parts=[
		part("wrapper", ".letter"),
		part("pin", ".letter-header", chrome="wrap"),
		part("pin", ".letter-byline", chrome="wrap"),
		part("title", ".letter-title h1", "h1"),
		part("pin", ".letter-dateline", chrome="wrap"),
		part("pin", ".letter-flourish"),
		part("pin", ".externalLink", chrome="wrap"),
		part("heading", HEADING_SEL % (".articleBody", ".articleBody"), "h2.heading"),
	]),
}


def n_of(px):
	"""Pin value in u for a measured px size (html 17px, so 15u is 17px)."""
	return (Decimal(str(round(px, 3))) * 15 / HTML_PX).quantize(Decimal("0.001"), rounding=ROUND_HALF_UP).normalize()


# ---------------------------------------------------------------- measurement

PROBE_JS = """(sels)=>{const o={};for(const k in sels){const e=document.querySelector(sels[k]);
o[k]=e?parseFloat(getComputedStyle(e).fontSize):null}return o}"""


def measure(bundle, parts):
	"""{scheme: {key: px}} for the parts, the prose, the preface and the series footer."""
	import measure_theme_sizes as M
	from playwright.sync_api import sync_playwright
	sels = {"prose": "#chapters p", "preface": "#ao3Preface", "series": "#ao3SeriesFooter"}
	for i, p in enumerate(parts):
		sels["p%d" % i] = p["probe"]
	out = {}
	with sync_playwright() as pw:
		browser = pw.chromium.launch()
		for scheme in ("light", "dark"):
			page = browser.new_page(viewport={"width": 390, "height": 844}, color_scheme=scheme)
			page.set_content(M.build(str(bundle)))
			out[scheme] = page.evaluate(PROBE_JS, sels)
			page.close()
		browser.close()
	return out


# ---------------------------------------------------------------- css editing

def migrate_css(css, name, spec, measured):
	"""Return (new_css, notes). Raises MigrationError."""
	notes = []
	if "--nnw-bg" in css:
		return css, notes
	masked = m.mask_comments(css)
	rules = m.find_rules(masked)
	light_roots = fam.root_rules(css, masked, rules, "light")
	dark_roots = fam.root_rules(css, masked, rules, "dark")
	if not light_roots:
		raise m.MigrationError("no :root block")
	light = fam.merged_vars(css, light_roots)
	dark = fam.merged_vars(css, dark_roots) if dark_roots else None

	def sel_of(r):
		return " ".join(masked[r.sel_start:r.sel_end].split())

	defaults = spec.get("defaults")
	bodies = [r for r in fam.find_rule(css, masked, rules, "body")
		if any(d[2] in ("background", "background-color") for d in fam.rule_decls(css, r))]
	bg_decl = ink_decl = None
	if bodies:
		body = bodies[0]
		bdecls = fam.rule_decls(css, body)
		bg_decl = next(d for d in bdecls if d[2] in ("background", "background-color"))
		ink_decl = next((d for d in bdecls if d[2] == "color"), None)
		if ink_decl is None:
			raise m.MigrationError("body rule has no color")
	elif defaults:
		plain = fam.find_rule(css, masked, rules, "body")
		if not plain:
			raise m.MigrationError("no body rule")
		body = plain[0]
	else:
		raise m.MigrationError("no body rule with a background")

	a_decl, a_rule = None, None
	for r in fam.find_rule(css, masked, rules, "a"):
		a_decl = next((d for d in fam.rule_decls(css, r) if d[2] == "color"), None)
		if a_decl:
			a_rule = r
			break
	link_v = a_decl[3] if a_decl else spec.get("link")
	if link_v is None and not defaults:
		raise m.MigrationError("no exact `a` color rule and no link expression in the spec")

	def lit(value, label, use_dark):
		v = fam.resolve(value, light, dark if use_dark else None)
		if v is None or not fam.HEX.match(v.strip()):
			raise m.MigrationError("%s does not resolve to a literal color (%r)" % (label, value))
		return v.strip()

	if defaults:
		tokens_light = "\n\t--nnw-bg: %s;\n\t--nnw-ink: %s;\n\t--nnw-link: %s;\n\t--u: calc(1rem / 15);\n" % (
			defaults["bg"], defaults["ink"], defaults["link"])
		tokens_dark = "\n\t--nnw-bg: %s;\n\t--nnw-ink: %s;\n\t--nnw-link: %s;\n" % (
			defaults["dbg"], defaults["dink"], defaults["dlink"]) if dark_roots else None
		bg_hexes = m.hex_variants(defaults["bg"]) | m.hex_variants(defaults["dbg"])
		bg_v = ink_v = None
	else:
		bg_v, ink_v = bg_decl[3], ink_decl[3]
		tokens_light = "\n\t--nnw-bg: %s;\n\t--nnw-ink: %s;\n\t--nnw-link: %s;\n\t--u: calc(1rem / 15);\n" % (
			lit(bg_v, "page", False), lit(ink_v, "ink", False), lit(link_v, "link", False))
		tokens_dark = None
		if dark_roots:
			tokens_dark = "\n\t--nnw-bg: %s;\n\t--nnw-ink: %s;\n\t--nnw-link: %s;\n" % (
				lit(bg_v, "page (dark)", True), lit(ink_v, "ink (dark)", True), lit(link_v, "link (dark)", True))
		bg_hexes = m.hex_variants(lit(bg_v, "page", False))
		if dark_roots:
			bg_hexes |= m.hex_variants(lit(bg_v, "page (dark)", True))

	bgvar = spec.get("bgvar")
	if bgvar is None and bg_v:
		mo = re.fullmatch(r"var\(\s*(--[\w-]+)\s*\)", bg_v)
		bgvar = mo.group(1) if mo else None
	bgvar_use = re.compile(r"var\(\s*%s\s*\)" % re.escape(bgvar)) if bgvar else None

	edits = []

	def replace_value(rule, decl, new):
		start = rule.body_start + decl[0]
		text = css[start:rule.body_start + decl[1]]
		colon = text.index(":")
		gap = len(text[colon + 1:]) - len(text[colon + 1:].lstrip())
		edits.append((start + colon + 1 + gap, rule.body_start + decl[1], new))

	if bg_decl:
		replace_value(body, bg_decl, "var(--nnw-bg)")
		replace_value(body, ink_decl, "var(--nnw-ink)")
	else:
		edits.append(fam.token_edit(css, body, "\n\tbackground-color: var(--nnw-bg);\n\tcolor: var(--nnw-ink);\n"))
	if a_decl:
		replace_value(a_rule, a_decl, "var(--nnw-link)")
	elif defaults:
		a_plain = fam.find_rule(css, masked, rules, "a")
		if not a_plain:
			raise m.MigrationError("no exact `a` rule to carry the link token")
		a_rule = a_plain[0]
		edits.append(fam.token_edit(css, a_rule, "\n\tcolor: var(--nnw-link);\n"))
	edits.append(fam.token_edit(css, light_roots[0], tokens_light))
	if dark_roots:
		edits.append(fam.token_edit(css, dark_roots[0], indent_tokens(css, dark_roots[0], tokens_dark)))

	# Literal and variable copies of the page color, and generic link rules.
	link_rule_sels = {"body a", "body a *", "a", "a *"}
	for r in rules:
		sel = sel_of(r)
		if r.context == "supports" and sel == ":root":
			continue
		if sel == ":root" or r is body:
			continue
		for d in fam.rule_decls(css, r):
			if d[2].startswith("--"):
				continue
			if d[2] == "color" and set(m.split_selectors(masked[r.sel_start:r.sel_end])) <= link_rule_sels \
					and (d[3] == link_v) and not (a_rule is r):
				replace_value(r, d, "var(--nnw-link)")
				notes.append("link rule: %s" % sel)
				continue
			if not m.PAINT_PROPS.match(d[2]) and not (bgvar_use and bgvar_use.search(d[3])):
				continue
			new, n = d[3], 0
			for h in bg_hexes:
				new, k = re.subn(re.escape(h) + r"(?![0-9a-fA-F])", "var(--nnw-bg)", new, flags=re.I)
				n += k
			if bgvar_use:
				new, k = bgvar_use.subn("var(--nnw-bg)", new)
				n += k
			if n:
				replace_value(r, d, new)
				notes.append("page color: %s { %s }" % (sel[:50], d[2]))

	# rem lengths become u.
	for r in rules:
		for d in fam.rule_decls(css, r):
			if d[2].startswith("--") and "font-size" not in d[2]:
				continue
			if fam.REM.search(d[3]):
				new = fam.REM.sub(lambda mo: "calc(var(--u) * %s)" % m.fmt(Decimal(mo.group(1)) * 15), d[3])
				replace_value(r, d, new)

	# Chrome font: wrap existing family declarations, add one where there is none.
	body_family = next((d[3] for r in fam.find_rule(css, masked, rules, "body") for d in fam.rule_decls(css, r)
		if d[2] == "font-family"), None)
	added_chrome = []
	for p in spec["parts"]:
		if not p["chrome"]:
			continue
		target = p["chrome_target"] or p["css"]
		hit = False
		for r in rules:
			if r.context == "supports" or sel_of(r) != target:
				continue
			for d in fam.rule_decls(css, r):
				if d[2] == "font-family":
					hit = True
					if "--nnw-font-chrome" not in d[3]:
						replace_value(r, d, "var(--nnw-font-chrome, %s)" % d[3])
		if not hit and p["chrome"] == "add":
			if not body_family:
				raise m.MigrationError("no body font-family to fall back to for %s" % target)
			added_chrome.append("\t%s {\n\t\tfont-family: var(--nnw-font-chrome, %s);\n\t}" % (target, body_family))

	# iOS block additions from the measurements.
	spans = m.block_spans(masked, IOS_OPENER)
	if not spans:
		raise m.MigrationError("no iOS @supports block")
	ios_end = spans[0][1]
	has_preface_rule = None
	for r in rules:
		if r.context == "light" and set(m.split_selectors(masked[r.sel_start:r.sel_end])) == {"#ao3SyntheticPreface", "#ao3Preface"}:
			if any(d[2] == "font-size" for d in fam.rule_decls(css, r)):
				has_preface_rule = sel_of(r)

	def block_for(scheme):
		res, mz = [], measured[scheme]
		p0 = n_of(mz["prose"])
		decls = {}
		for i, p in enumerate(spec["parts"]):
			px = mz["p%d" % i]
			if px is None:
				raise m.MigrationError("probe %r matched nothing" % p["probe"])
			if p["role"] == "wrapper":
				decls[p["css"]] = "calc(var(--u) * 15)"
			elif p["role"] == "pin":
				decls[p["css"]] = m.pinned(m.fmt(n_of(px)))
			else:
				kmax = (m.KMAX_TITLE if p["role"] == "title" else m.KMAX_HEADING) / p["mult"]
				decls[p["css"]] = m.floored(m.fmt(n_of(px)), p0, kmax)[0]
		props = {}
		if mz["preface"] is not None:
			value = m.pinned(m.fmt(n_of(mz["preface"])))
			if has_preface_rule:
				decls[has_preface_rule] = value
			else:
				props["--ao3-preface-font-size"] = value
		if mz["series"] is not None:
			props["--ao3-series-footer-font-size"] = m.pinned(m.fmt(n_of(mz["series"])))
		return decls, props

	light_decls, light_props = block_for("light")
	dark_decls, dark_props = block_for("dark")
	added = ["\thtml {\n\t\tfont: -apple-system-body;\n\t}"]
	if light_props:
		added.append("\t:root {\n%s\t}" % "".join("\t\t%s: %s;\n" % kv for kv in light_props.items()))
	for sel, value in light_decls.items():
		added.append("\t%s {\n\t\tfont-size: %s;\n\t}" % (sel, value))
	added += added_chrome
	dark_rules = ["\t\t%s {\n\t\t\tfont-size: %s;\n\t\t}" % (s, v) for s, v in dark_decls.items() if v != light_decls[s]]
	dark_vars = {k: v for k, v in dark_props.items() if light_props.get(k) != v}
	if dark_vars:
		dark_rules.insert(0, "\t\t:root {\n%s\t\t}" % "".join("\t\t\t%s: %s;\n" % kv for kv in dark_vars.items()))
	if dark_rules:
		added.append("\t@media (prefers-color-scheme: dark) {\n%s\n\t}" % "\n\n".join(dark_rules))
	edits.append((ios_end, ios_end, "\n" + "\n\n".join(added) + "\n"))

	# Contract selectors the color extractor reads, added when missing.
	def has_exact(selector):
		return any(r.context == "light" and m.split_selectors(masked[r.sel_start:r.sel_end]) == [selector]
			and any(d[2] == "color" for d in fam.rule_decls(css, r)) for r in rules)

	tail = "\n/* Theme contract: exact selectors read by ArticleThemeColorExtractor. */\n"
	if not has_exact(".articleBody"):
		tail += ".articleBody {\n\tcolor: var(--nnw-ink);\n}\n\n"
	else:
		for r in rules:
			if r.context == "light" and m.split_selectors(masked[r.sel_start:r.sel_end]) == [".articleBody"]:
				d = next((d for d in fam.rule_decls(css, r) if d[2] == "color"), None)
				if d and d[3] != "var(--nnw-ink)":
					replace_value(r, d, "var(--nnw-ink)")
	if not has_exact(".articleBody a"):
		tail += ".articleBody a {\n\tcolor: var(--nnw-link);\n}\n"
	else:
		for r in rules:
			if r.context == "light" and m.split_selectors(masked[r.sel_start:r.sel_end]) == [".articleBody a"]:
				d = next((d for d in fam.rule_decls(css, r) if d[2] == "color"), None)
				if d and d[3] != "var(--nnw-link)":
					replace_value(r, d, "var(--nnw-link)")
	out = css
	for start, end, text in sorted(edits, key=lambda e: (e[0], e[1]), reverse=True):
		out = out[:start] + text + out[end:]
	if not out.endswith("\n"):
		out += "\n"
	if tail.strip().count("{"):
		out += tail
	notes.append("title N=%s" % next(m.fmt(n_of(measured["light"]["p%d" % i]))
		for i, p in enumerate(spec["parts"]) if p["role"] == "title"))
	return out, notes


def indent_tokens(css, rule, tokens):
	"""Indent the token lines one level deeper than the rule's closing brace."""
	line_start = css.rfind("\n", 0, rule.body_end) + 1
	closing = css[line_start:rule.body_end]
	base = closing if not closing.strip() else ""
	return tokens.replace("\n\t", "\n" + base + "\t").replace("\n" + base + "\t", "\n" + base + "\t", 1) if base else tokens


def bundle_dirs(root):
	found = {}
	for d in ("Themes", "gallery-themes"):
		for p in (root / d).glob("*.nnwtheme"):
			key = p.name[: -len(".nnwtheme")]
			if key in SPECS:
				found[key] = p
	return found


def main(argv=None):
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--dry-run", action="store_true")
	ap.add_argument("--check", action="store_true")
	ap.add_argument("--only")
	ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
	args = ap.parse_args(argv)
	root = Path(args.root)
	bundles = bundle_dirs(root)
	missing = sorted(set(SPECS) - set(bundles))
	if missing:
		print("missing bundles: %s" % ", ".join(missing), file=sys.stderr)
		return 2
	names = sorted(bundles)
	if args.only:
		names = [n for n in names if n == args.only]
		if not names:
			print("no bespoke bundle named %s" % args.only, file=sys.stderr)
			return 2
	dirty = failed = 0
	for name in names:
		bundle = bundles[name]
		path = bundle / "stylesheet.css"
		original = path.read_text(encoding="utf-8")
		spec = SPECS[name]
		template = bundle / "template.html"
		tpl_old = template.read_text(encoding="utf-8")
		tpl_new = tpl_old
		if spec.get("strip_script"):
			tpl_new = re.sub(r"\n?<script\b.*?</script>\n?", "\n", tpl_old, flags=re.S)
			if not tpl_new.endswith("\n"):
				tpl_new += "\n"
		if "--nnw-bg" in original and tpl_new == tpl_old:
			print("%s: ok" % name)
			continue
		try:
			if "--nnw-bg" in original:
				new, notes = original, []
			else:
				new, notes = migrate_css(original, name, spec, measure(bundle, spec["parts"]))
		except m.MigrationError as exc:
			print("%s: FAIL %s" % (name, exc))
			failed += 1
			continue
		dirty += 1
		print("%s: changed" % name)
		for label, a, b, fn in (("stylesheet.css", original, new, path), ("template.html", tpl_old, tpl_new, template)):
			if a == b:
				continue
			if args.dry_run:
				sys.stdout.writelines(difflib.unified_diff(a.splitlines(True), b.splitlines(True),
					"a/%s/%s/%s" % (bundle.parent.name, bundle.name, label),
					"b/%s/%s/%s" % (bundle.parent.name, bundle.name, label)))
			elif not args.check:
				fn.write_text(b, encoding="utf-8")
		for note in notes:
			print("  note: %s" % note)
	if args.check:
		return 1 if (dirty or failed) else 0
	return 1 if failed else 0


if __name__ == "__main__":
	sys.exit(main())
