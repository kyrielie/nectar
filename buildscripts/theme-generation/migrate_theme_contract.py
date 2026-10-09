#!/usr/bin/env python3
"""Migrate shape B gallery bundles to the theme contract (docs/nnwtheme-format.md).

Operates on gallery-themes/*.nnwtheme whose template.html contains class="rh".
Idempotent. Transformations, in order:

1. Tokens: rename --bg/--ink to --nnw-bg/--nnw-ink everywhere, add --nnw-link with
   the literal color the a / .articleBody a rule resolves to today (light and dark),
   and point those link rules at var(--nnw-link).
2. Pinned sizes: title, byline, running head, preface (dl.tags), chapter headings
   get calc(var(--u) * N * var(--nnw-detail-scale, 1)); title and chapter headings
   also get the prose-relative hierarchy floor.
3. Summary and notes sized in u become em of the prose size.
4. Chrome font: .rh and .by use var(--nnw-font-chrome, <existing stack>).
5. Reports (does not fix) paint declarations holding a literal copy of the page color.

Usage:
  migrate_theme_contract.py [--dry-run] [--check] [--only NAME] [--root PATH]

--dry-run prints a unified diff and writes nothing. --check writes nothing and exits
non-zero if any bundle would change or fail.
"""

import argparse
import difflib
import re
import sys
from decimal import Decimal, ROUND_DOWN
from pathlib import Path

KMAX_TITLE = Decimal("1.4")
KMAX_HEADING = Decimal("1.2")
DEFAULT_P0 = Decimal("15")

U_TOKEN = re.compile(r"calc\(var\(--u\) \* ([\d.]+)\)")
HEX_OR_RGB = re.compile(r"^(#[0-9a-fA-F]{3,8}|rgba?\([^)]*\))$")


class MigrationError(Exception):
	pass


# ---------------------------------------------------------------- scanning

def mask_comments(css):
	return re.sub(r"/\*.*?\*/", lambda m: " " * len(m.group(0)), css, flags=re.S)


def block_spans(masked, opener_pattern):
	"""Spans (content_start, content_end) of every at-rule block matching the opener."""
	spans = []
	for m in re.finditer(opener_pattern, masked):
		depth = 1
		i = m.end()
		start = i
		while i < len(masked) and depth:
			if masked[i] == "{":
				depth += 1
			elif masked[i] == "}":
				depth -= 1
			i += 1
		spans.append((start, i - 1))
	return spans


DARK_OPENER = r"@media\s*\(\s*prefers-color-scheme:\s*dark\s*\)\s*\{"
SUPPORTS_OPENER = r"@supports\s+(?:not\s+)?\([^)]*\)\s*\{"


class Rule:
	def __init__(self, sel_start, sel_end, body_start, body_end, context):
		self.sel_start, self.sel_end = sel_start, sel_end
		self.body_start, self.body_end = body_start, body_end
		self.context = context  # "light", "dark" or "supports"


def find_rules(masked):
	dark = block_spans(masked, DARK_OPENER)
	supports = block_spans(masked, SUPPORTS_OPENER)
	rules = []
	for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", masked):
		sel_start = m.start(1)
		# Skip leading statements such as @import url('...;...'); that share the chunk.
		lead = re.match(r"\s*@(?:import|charset|namespace)[^\n]*?(?:\)|['\"])\s*;", masked[sel_start:m.end(1)])
		while lead:
			sel_start += lead.end()
			lead = re.match(r"\s*@(?:import|charset|namespace)[^\n]*?(?:\)|['\"])\s*;", masked[sel_start:m.end(1)])
		sel = masked[sel_start:m.end(1)]
		if sel.lstrip().startswith("@"):
			continue
		pos = sel_start
		if any(s <= pos < e for s, e in dark):
			ctx = "dark"
		elif any(s <= pos < e for s, e in supports):
			ctx = "supports"
		else:
			ctx = "light"
		rules.append(Rule(sel_start, m.end(1), m.start(2), m.end(2), ctx))
	return rules


def split_selectors(selector_text):
	parts, depth, cur = [], 0, ""
	for ch in selector_text:
		if ch in "([":
			depth += 1
		elif ch in ")]":
			depth -= 1
		if ch == "," and depth == 0:
			parts.append(cur)
			cur = ""
		else:
			cur += ch
	parts.append(cur)
	return [" ".join(p.split()) for p in parts if p.strip()]


def declarations(body):
	"""[(start, end, prop, value)] offsets relative to body; end excludes the ';'."""
	out = []
	pos = 0
	depth = 0
	start = 0
	for i, ch in enumerate(body + ";"):
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
		elif ch == ";" and depth == 0:
			chunk = body[start:i]
			if ":" in chunk and chunk.strip():
				lead = len(chunk) - len(chunk.lstrip())
				colon = chunk.index(":")
				prop = chunk[:colon].strip()
				out.append((start + lead, i, prop, chunk[colon + 1:].strip()))
			start = i + 1
	return out


# ---------------------------------------------------------------- roles

def role_of(part):
	if "::" in part or ":before" in part or ":after" in part:
		return None
	tokens = [t for t in re.split(r"[\s>+~]+", part) if t]
	if not tokens:
		return None
	last = tokens[-1]
	if last == "h1":
		return "title"
	if last in ("h2.heading", "h3.title"):
		return "chapter"
	if last == ".by":
		return "byline"
	if part == ".rh":
		return "rh"
	if any(t == "dl.tags" for t in tokens):
		return "preface"
	if last in (".notes.module", ".summary.module", ".end.notes.module") or part.startswith(":is(.notes.module"):
		return "note"
	return None


def variant_of(part):
	first = part.split(" ")[0]
	m = re.fullmatch(r"\.(t\d+)", first)
	return m.group(1) if m else None


# ---------------------------------------------------------------- numbers

def fmt(d):
	s = format(d.normalize(), "f")
	return s


def floor3(d):
	return d.quantize(Decimal("0.001"), rounding=ROUND_DOWN)


def pinned(n):
	return "calc(var(--u) * %s * var(--nnw-detail-scale, 1))" % n


def floored(n, p0, kmax):
	k = floor3(min(kmax, Decimal(n) / p0))
	return (
		"max(calc(var(--u) * %s * var(--nnw-detail-scale, 1)), "
		"calc(var(--nnw-prose-size, calc(var(--u) * %s)) * %s))" % (n, fmt(p0), fmt(k))
	), k


def em_of(n, p0):
	return fmt((Decimal(n) / p0).quantize(Decimal("0.0001"))) + "em"


# ---------------------------------------------------------------- prose sizes

def prose_sizes(css, masked, rules):
	"""P0 per variant and the base, read from the .t / .tNN prose rules."""
	base = DEFAULT_P0
	variants = {}
	for r in rules:
		if r.context != "light":
			continue
		parts = split_selectors(masked[r.sel_start:r.sel_end])
		if len(parts) != 1:
			continue
		for _s, _e, prop, value in declarations(css[r.body_start:r.body_end]):
			if prop not in ("font", "font-size"):
				continue
			m = U_TOKEN.search(value)
			if not m:
				continue
			if parts[0] == ".t":
				base = Decimal(m.group(1))
			elif re.fullmatch(r"\.t\d+", parts[0]) and prop == "font-size":
				variants[parts[0][1:]] = Decimal(m.group(1))
	return base, variants


# ---------------------------------------------------------------- color model (mirrors ArticleThemeColorExtractor)

def parse_root_vars(css_block):
	return {m.group(1): m.group(2).strip() for m in re.finditer(r"--([A-Za-z0-9_-]+)\s*:\s*([^;}]+);", css_block)}


def resolve_one_level(value, local, fallback):
	m = re.fullmatch(r"var\(\s*--([A-Za-z0-9_-]+)\s*(?:,\s*(.+))?\)", value)
	if not m:
		return value
	name = m.group(1)
	if name in local:
		return local[name]
	if name in fallback:
		return fallback[name]
	return m.group(2).strip() if m.group(2) else None


def exact_last_value(css, masked, rules, contexts, selectors, prop):
	last = None
	for r in rules:
		if r.context not in contexts:
			continue
		parts = split_selectors(masked[r.sel_start:r.sel_end])
		if not any(p in selectors for p in parts):
			continue
		for _s, _e, p, v in declarations(css[r.body_start:r.body_end]):
			if p == prop:
				last = re.sub(r"\s*!important\s*$", "", v)
	return last


def extractor_colors(css):
	"""(text, bg, link) for light and dark, as raw literal strings, like the Swift extractor."""
	masked = mask_comments(css)
	rules = find_rules(masked)
	light_vars, dark_vars = {}, {}
	for r in rules:
		if split_selectors(masked[r.sel_start:r.sel_end]) == [":root"]:
			target = {"light": light_vars, "dark": dark_vars}.get(r.context)
			if target is not None:
				target.update(parse_root_vars(css[r.body_start:r.body_end] + ";"))

	def compute(prop, selectors):
		uncond = exact_last_value(css, masked, rules, ("light",), selectors, prop)
		dark_override = exact_last_value(css, masked, rules, ("dark",), selectors, prop)
		light = resolve_one_level(uncond, light_vars, {}) if uncond else None
		dark_raw = dark_override or uncond
		dark = resolve_one_level(dark_raw, dark_vars, light_vars) if dark_raw else None
		# Like the Swift extractor, a value that is not a parseable color counts as not found.
		return tuple(
			v if v is not None and (HEX_OR_RGB.match(v.strip()) or re.fullmatch(r"[a-zA-Z]+", v.strip())) else None
			for v in (light, dark)
		)

	text = compute("color", ["body", ".articleBody"])
	bg = compute("background-color", ["body", ".articleBody"])
	if bg == (None, None):
		bg = compute("background", ["body", ".articleBody"])
	link = compute("color", ["a", ".articleBody a"])
	return {"text": text, "bg": bg, "link": link, "raw_link": link}


def effective(colors):
	"""Per-mode values the way the Swift extractor falls back: link -> text, dark -> light."""
	text_l, text_d = colors["text"]
	bg_l, bg_d = colors["bg"]
	link_l, link_d = colors["raw_link"]
	# Swift: light falls back to black/white; dark falls back to the *found* light value,
	# then to white/black.
	text_d = text_d or text_l or "#ffffff"
	bg_d = bg_d or bg_l or "#000000"
	text_l = text_l or "#000000"
	bg_l = bg_l or "#ffffff"
	link_d = link_d or link_l or text_d
	link_l = link_l or text_l
	return {
		"text": (text_l, text_d),
		"bg": (bg_l, bg_d),
		"link": (link_l, link_d),
	}


def norm_color(value):
	if value is None:
		return None
	v = value.strip().lower()
	m = re.fullmatch(r"#([0-9a-f])([0-9a-f])([0-9a-f])", v)
	if m:
		return "#" + "".join(c * 2 for c in m.groups())
	return v


# ---------------------------------------------------------------- the migration

# Bundles that need a hand edit the script cannot make safely. They are reported, not
# changed, and not counted as failures by --check. Remove an entry once hand-edited.
MANUAL = {}


def migrate_css(css, name):
	"""Return (new_css, changed_rule_count, notes)."""
	notes = []
	if name in MANUAL:
		return css, 0, ["skipped (manual): " + MANUAL[name]]
	changes = 0
	original = css

	before_colors = extractor_colors(original)

	# --- 1a. rename tokens everywhere
	new = css
	already = re.search(r"(?<![\w-])--nnw-bg\s*:", new) is not None
	if not already:
		masked = mask_comments(new)
		rules = find_rules(masked)
		light_root = None
		for r in rules:
			if r.context == "light" and split_selectors(masked[r.sel_start:r.sel_end]) == [":root"]:
				body = masked[r.body_start:r.body_end]
				if re.search(r"(?<![\w-])--bg\s*:", body) or re.search(r"(?<![\w-])--ink\s*:", body):
					light_root = r
					break
		if light_root is None:
			raise MigrationError("no :root declaring --bg/--ink")
		body = masked[light_root.body_start:light_root.body_end]
		for var in ("bg", "ink"):
			if not re.search(r"(?<![\w-])--%s\s*:" % var, body):
				raise MigrationError("--%s missing from :root" % var)
		new = re.sub(r"(?<![\w-])--bg(?![\w-])", "--nnw-bg", new)
		new = re.sub(r"(?<![\w-])--ink(?![\w-])", "--nnw-ink", new)
		changes += 1

	# --- 1b. literal tokens and --nnw-link
	new, link_changes = ensure_tokens(new, before_colors)
	changes += link_changes

	# --- 2/3/4. sizes, summary/notes, chrome font
	masked = mask_comments(new)
	rules = find_rules(masked)
	base_p0, variant_p0 = prose_sizes(new, masked, rules)
	edits = []  # (start, end, replacement)
	rule_changes = 0
	for r in rules:
		if r.context == "supports":
			continue
		parts = split_selectors(masked[r.sel_start:r.sel_end])
		roles = {role_of(p) for p in parts}
		body = new[r.body_start:r.body_end]
		decls = declarations(body)
		has_size = any(
			p in ("font", "font-size") and (U_TOKEN.search(v) or "--nnw-detail-scale" in v or "em" in v)
			for _s, _e, p, v in decls
		)
		chrome_role = roles & {"rh", "byline"}
		if roles == {None}:
			continue
		sized_roles = roles & {"title", "chapter", "byline", "rh", "preface", "note"}
		if len(roles) > 1:
			has_u = any(p in ("font", "font-size") and U_TOKEN.search(v) for _s, _e, p, v in decls)
			if has_u:
				raise MigrationError("selector list mixes roles with a u-size: %s" % " | ".join(parts))
			continue
		role = next(iter(roles))
		if role is None:
			continue
		variants = {variant_of(p) for p in parts}
		variant = next(iter(variants)) if len(variants) == 1 else None
		p0 = variant_p0.get(variant, base_p0) if variant else base_p0
		rule_edits = []
		for s, e, prop, value in decls:
			if prop not in ("font", "font-size"):
				continue
			if "--nnw-detail-scale" in value or "--nnw-prose-size" in value:
				continue
			m = U_TOKEN.search(value)
			if not m and prop == "font-size" and role in ("title", "byline", "preface", "chapter") and variant:
				# em sized relative to the variant's prose size (parent assumed to be the
				# prose-sized wrapper, which holds for header/preface children of .tNN).
				em = re.fullmatch(r"(\d*\.?\d+)em", value.strip())
				if em:
					n_value = (Decimal(em.group(1)) * p0).quantize(Decimal("0.01")).normalize()
					value = "calc(var(--u) * %s)" % format(n_value, "f")
					m = U_TOKEN.search(value)
					notes.append("converted: %s font-size %sem -> %s u (parent assumed %s u)" % (" ".join(parts), em.group(1), format(n_value, "f"), fmt(p0)))
			if not m and prop == "font-size" and role == "title" and re.fullmatch(r"clamp\(\s*(\d+)px\s*,[^)]*\)", value.strip()):
				min_px = Decimal(re.match(r"clamp\(\s*(\d+)px", value.strip()).group(1))
				k = floor3(KMAX_TITLE)
				# Fluid px title: keep the clamp, add only the hierarchy floor. Safe when the
				# floor at the default prose size (at 17px body) stays under the clamp minimum.
				if p0 * k * Decimal(17) / Decimal(15) > min_px:
					raise MigrationError("clamp title floor would change the default look: %s" % " ".join(parts))
				expr = "max(%s, calc(var(--nnw-prose-size, calc(var(--u) * %s)) * %s))" % (value.strip(), fmt(p0), fmt(k))
				abs_start = r.body_start + s
				colon = new[abs_start:r.body_start + e].index(":") + 1
				rule_edits.append((abs_start + colon, r.body_start + e, expr))
				continue
			if not m:
				continue
			n = m.group(1)
			if role in ("title", "chapter"):
				kmax = KMAX_TITLE if role == "title" else KMAX_HEADING
				expr, _k = floored(n, p0, kmax)
			elif role in ("byline", "rh", "preface"):
				expr = pinned(n)
			else:  # note
				expr = em_of(n, p0)
			new_value = value[:m.start()] + expr + value[m.end():]
			abs_start = r.body_start + s
			colon = new[abs_start:r.body_start + e].index(":") + 1
			rule_edits.append((abs_start + colon, r.body_start + e, new_value))
		if chrome_role:
			rule_edits.extend(chrome_edits(new, r, decls))
		if rule_edits:
			rule_changes += 1
			edits.extend(rule_edits)
	for start, end, repl in sorted(edits, key=lambda x: -x[0]):
		new = new[:start] + repl + new[end:]
	changes += rule_changes

	# non-u size on a pinned role: report
	masked = mask_comments(new)
	rules = find_rules(masked)
	for r in rules:
		if r.context == "supports":
			continue
		parts = split_selectors(masked[r.sel_start:r.sel_end])
		roles = {role_of(p) for p in parts} - {None, "note"}
		if len(roles) != 1:
			continue
		for _s, _e, prop, value in declarations(new[r.body_start:r.body_end]):
			if prop in ("font-size",) and not U_TOKEN.search(value) and "--nnw-detail-scale" not in value:
				notes.append("manual: %s { font-size: %s } is not in u" % (" ".join(parts), value))

	# --- 5. report literal copies of the page color
	notes.extend(background_literals(new))

	# --- self-check: extractor view must not change
	after_colors = effective(extractor_colors(new))
	before_eff = effective(before_colors)
	for key in ("text", "bg", "link"):
		for i, label in enumerate(("light", "dark")):
			a, b = norm_color(before_eff[key][i]), norm_color(after_colors[key][i])
			if a != b:
				raise MigrationError("extractor %s %s changed: %s -> %s" % (key, label, a, b))
	return new, changes, notes


def ensure_tokens(css, before_colors):
	"""Make --nnw-bg/--nnw-ink/--nnw-link literal and terminated in both root blocks, and
	point the a / .articleBody a rules at var(--nnw-link). Returns (css, change_count)."""
	changes = 0
	masked = mask_comments(css)
	rules = find_rules(masked)
	roots = {"light": None, "dark": None}
	for r in rules:
		if split_selectors(masked[r.sel_start:r.sel_end]) == [":root"] and r.context in roots:
			body = masked[r.body_start:r.body_end]
			if roots[r.context] is None and re.search(r"--nnw-(bg|ink)\s*:", body):
				roots[r.context] = r
			elif roots[r.context] is None and r.context == "dark":
				roots[r.context] = r
	if roots["light"] is None:
		raise MigrationError("no light :root with tokens")

	light_vars = parse_root_vars(css[roots["light"].body_start:roots["light"].body_end] + ";")
	dark_vars = {}
	if roots["dark"] is not None:
		dark_vars = parse_root_vars(css[roots["dark"].body_start:roots["dark"].body_end] + ";")

	def literal(v, what):
		if v is None or not HEX_OR_RGB.match(v.strip()):
			raise MigrationError("%s is not a literal color: %r" % (what, v))
		return v.strip()

	def cascade(name, dark):
		"""Literal value of --nnw-<name> in the given mode, resolving a chained var() once."""
		order = [dark_vars, light_vars] if dark else [light_vars]
		raw = None
		for scope in order:
			if "nnw-" + name in scope:
				raw = scope["nnw-" + name]
				break
		m = re.fullmatch(r"var\(\s*--([A-Za-z0-9_-]+)\s*\)", raw or "")
		if m:
			for scope in order:
				if m.group(1) in scope:
					return scope[m.group(1)]
		return raw

	has_dark = roots["dark"] is not None
	light_bg = literal(cascade("bg", False), "light --nnw-bg")
	light_ink = literal(cascade("ink", False), "light --nnw-ink")
	raw_link = before_colors["raw_link"]
	rewire_links = raw_link[0] is not None
	light_link = literal(raw_link[0] or light_ink, "light link color")
	dark_bg = dark_ink = dark_link = None
	if has_dark:
		dark_bg = literal(cascade("bg", True), "dark --nnw-bg")
		dark_ink = literal(cascade("ink", True), "dark --nnw-ink")
		dark_link = literal(raw_link[1] or raw_link[0] or dark_ink, "dark link color")

	edits = []

	def root_edit(r, wanted, existing):
		body = css[r.body_start:r.body_end]
		for key, value in wanted:
			m = re.search(r"(--nnw-%s\s*:\s*)([^;}]*)" % key, body)
			if m and not HEX_OR_RGB.match(m.group(2).strip()):
				body = body[:m.start(2)] + value + body[m.end(2):]
		stripped = body.rstrip()
		trailing = body[len(stripped):]
		add = ""
		for key, value in wanted:
			if not re.search(r"--nnw-%s\s*:" % key, stripped):
				add += "--nnw-%s:%s;" % (key, value)
		terminated = stripped if (stripped.endswith(";") or not stripped) else stripped + ";"
		if add:
			# after --nnw-ink's declaration when present, else at the end
			m = re.search(r"--nnw-ink\s*:[^;]*;", terminated)
			if m:
				terminated = terminated[:m.end()] + add + terminated[m.end():]
			else:
				terminated = terminated + add
		new_body = terminated + trailing
		if new_body != css[r.body_start:r.body_end]:
			edits.append((r.body_start, r.body_end, new_body))
			return True
		return False

	if root_edit(roots["light"], [("bg", light_bg), ("ink", light_ink), ("link", light_link)], light_vars):
		changes += 1
	if has_dark:
		if root_edit(roots["dark"], [("bg", dark_bg), ("ink", dark_ink), ("link", dark_link)], dark_vars):
			changes += 1

	# a / .articleBody a color -> var(--nnw-link). Skipped when the rule's color is not
	# resolvable today (an undefined var(), so the link inherits): rewiring it would
	# change the look inside colored panels. The token still carries the effective color.
	for r in rules:
		if r.context == "supports" or not rewire_links:
			continue
		parts = split_selectors(masked[r.sel_start:r.sel_end])
		if not parts or not all(p in ("a", ".articleBody a") for p in parts):
			continue
		for s, e, prop, value in declarations(css[r.body_start:r.body_end]):
			if prop == "color" and "--nnw-link" not in value:
				abs_start = r.body_start + s
				colon = css[abs_start:r.body_start + e].index(":") + 1
				important = " !important" if re.search(r"!\s*important\s*$", value) else ""
				edits.append((abs_start + colon, r.body_start + e, "var(--nnw-link)" + important))
				changes += 1
	for start, end, repl in sorted(edits, key=lambda x: -x[0]):
		css = css[:start] + repl + css[end:]
	return css, changes


def chrome_edits(css, rule, decls):
	"""font-family for .rh/.by through --nnw-font-chrome."""
	out = []
	body_start = rule.body_start
	has_family = False
	for s, e, prop, value in decls:
		if prop == "font-family" and "--nnw-font-chrome" not in value:
			has_family = True
			abs_start = body_start + s
			colon = css[abs_start:body_start + e].index(":") + 1
			out.append((abs_start + colon, body_start + e, "var(--nnw-font-chrome, %s)" % value))
		elif prop == "font-family":
			has_family = True
	for s, e, prop, value in decls:
		if prop != "font" or "--nnw-font-chrome" in css[body_start:body_start + e + 1 + 200]:
			continue
		m = re.match(r"(.*?(?:calc\(var\(--u\) \* [\d.]+\)|max\(.*?\)\)|[\d.]+em))(/[\d.]+)?\s+(.+)$", value, re.S)
		if not m:
			continue
		family = m.group(3).strip()
		if any(p == "font-family" for _s, _e, p, _v in decls):
			continue
		has_family = True
		out.append((body_start + e, body_start + e, ";font-family:var(--nnw-font-chrome, %s)" % family))
	if not has_family and not any(p == "font" for _s, _e, p, _v in decls):
		# no family of its own: inherit through an undefined variable (invalid at computed
		# value time, which behaves as inherit for font-family)
		is_variant_rule = variant_of(" ".join(css[rule.sel_start:rule.sel_end].split())) is not None
		if not is_variant_rule and "--nnw-font-chrome" not in css[body_start:rule.body_end]:
			end = rule.body_end
			stripped_len = len(css[body_start:end].rstrip())
			sep = "" if css[body_start:end].rstrip().endswith(";") else ";"
			out.append((body_start + stripped_len, body_start + stripped_len, sep + "font-family:var(--nnw-font-chrome)"))
	return out


PAINT_PROPS = re.compile(r"^(background|border|box-shadow|outline)")


def hex_variants(h):
	h = h.lower()
	m = re.fullmatch(r"#([0-9a-f])([0-9a-f])([0-9a-f])", h)
	full = "#" + "".join(c * 2 for c in m.groups()) if m else h
	short = None
	m2 = re.fullmatch(r"#([0-9a-f])\1([0-9a-f])\2([0-9a-f])\3", full)
	if m2:
		short = "#" + "".join(m2.groups())
	return {v for v in (full, short) if v}


def background_literals(css):
	masked = mask_comments(css)
	rules = find_rules(masked)
	values = set()
	for r in rules:
		if split_selectors(masked[r.sel_start:r.sel_end]) == [":root"] and r.context in ("light", "dark"):
			v = parse_root_vars(css[r.body_start:r.body_end] + ";").get("nnw-bg")
			if v and v.startswith("#"):
				values |= hex_variants(v)
	found = []
	for r in rules:
		if r.context == "supports":
			continue
		sel = " ".join(masked[r.sel_start:r.sel_end].split())
		if sel == ":root":
			continue
		for _s, _e, prop, value in declarations(css[r.body_start:r.body_end]):
			if prop.startswith("--") or not PAINT_PROPS.match(prop):
				continue
			low = value.lower()
			for v in values:
				if re.search(re.escape(v) + r"(?![0-9a-f])", low):
					found.append("bg-literal: %s { %s: %s }" % (sel, prop, value if len(value) < 70 else value[:67] + "..."))
					break
	return found


# ---------------------------------------------------------------- driver

def is_shape_b(bundle):
	template = bundle / "template.html"
	return template.exists() and 'class="rh"' in template.read_text(encoding="utf-8")


def main(argv=None):
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--dry-run", action="store_true")
	ap.add_argument("--check", action="store_true")
	ap.add_argument("--only", help="bundle name, with or without .nnwtheme")
	ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
	args = ap.parse_args(argv)

	root = Path(args.root)
	bundles = sorted(p for p in (root / "gallery-themes").glob("*.nnwtheme") if is_shape_b(p))
	if args.only:
		wanted = args.only if args.only.endswith(".nnwtheme") else args.only + ".nnwtheme"
		bundles = [b for b in bundles if b.name == wanted]
		if not bundles:
			print("no shape B bundle named %s" % args.only, file=sys.stderr)
			return 2

	dirty = failed = 0
	for bundle in bundles:
		path = bundle / "stylesheet.css"
		original = path.read_text(encoding="utf-8")
		try:
			new, changes, notes = migrate_css(original, bundle.name)
		except MigrationError as exc:
			print("%s: FAIL %s" % (bundle.name, exc))
			failed += 1
			continue
		if new == original:
			print("%s: ok" % bundle.name)
		else:
			dirty += 1
			print("%s: changed (%d rules)" % (bundle.name, changes))
			if args.dry_run:
				sys.stdout.writelines(difflib.unified_diff(
					original.splitlines(True), new.splitlines(True),
					"a/gallery-themes/%s/stylesheet.css" % bundle.name,
					"b/gallery-themes/%s/stylesheet.css" % bundle.name))
			elif not args.check:
				path.write_text(new, encoding="utf-8")
		for note in notes:
			print("  note: %s" % note)
	if args.check:
		return 1 if (dirty or failed) else 0
	return 1 if failed else 0


if __name__ == "__main__":
	sys.exit(main())
