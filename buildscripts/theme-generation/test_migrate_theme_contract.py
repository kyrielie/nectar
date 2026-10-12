import unittest
from decimal import Decimal

import migrate_theme_contract as m

ZELLIGE_LIKE = """@import url('https://fonts.googleapis.com/css2?family=A:wght@0,400;0,700&display=swap');
:root{--fb:'Amiri',serif;--bg:#f6f1e4;--ink:#12305a;--a:#0f6f8f;--gx:20px;--u:1px}
body{margin:0;background:var(--bg);color:var(--ink)}
a{color:var(--a)}
.articleBody{color:var(--ink)}
.rh{font-family:var(--fb);font-size:calc(var(--u) * 11)}
.t{font:calc(var(--u) * 15)/1.6 var(--fb)}
.t h1{font-size:calc(var(--u) * 30)}
.t h2.heading,.t h3.title{font-size:calc(var(--u) * 21)}
.by{font-size:calc(var(--u) * 12)}
.notes.module{font-size:calc(var(--u) * 13)}
.t1{font-size:calc(var(--u) * 17)}
.t1 h1{font-size:calc(var(--u) * 25)}
@media (prefers-color-scheme: dark){
:root{--bg:#0c1c33;--ink:#e9f1f7;--a:#3fc1d6}
}
@supports (-webkit-touch-callout: none){
:root{--u:calc(1rem / 15)}
}
"""


class MigrateTests(unittest.TestCase):
	def migrate(self, css=ZELLIGE_LIKE):
		new, _changes, notes = m.migrate_css(css, "Test.nnwtheme")
		return new, notes

	def test_tokens_are_renamed_literal_and_terminated(self):
		css, _ = self.migrate()
		self.assertNotIn("var(--bg)", css)
		self.assertNotIn("var(--ink)", css)
		self.assertIn("--nnw-bg:#f6f1e4;--nnw-ink:#12305a;--nnw-link:#0f6f8f;", css)
		self.assertIn("--nnw-bg:#0c1c33;--nnw-ink:#e9f1f7;--nnw-link:#3fc1d6;", css)
		self.assertIn("a{color:var(--nnw-link)}", css)

	def test_pinned_sizes(self):
		css, _ = self.migrate()
		self.assertIn(".rh{font-family:var(--nnw-font-chrome, var(--fb));font-size:calc(var(--u) * 11 * var(--nnw-detail-scale, 1))}", css)
		self.assertIn(".by{font-size:calc(var(--u) * 12 * var(--nnw-detail-scale, 1));font-family:var(--nnw-font-chrome)}", css)

	def test_title_floor_uses_variant_prose_and_caps_k(self):
		css, _ = self.migrate()
		# base: N=30, P0=15 -> K = min(1.4, 2) = 1.4
		self.assertIn("calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.4))", css)
		# variant t1: N=25, P0=17 -> K = min(1.4, 1.470...) = 1.4
		self.assertIn(".t1 h1{font-size:max(calc(var(--u) * 25 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 17)) * 1.4))}", css)
		# chapter heading: N=21, P0=15 -> K = min(1.2, 1.4) = 1.2
		self.assertIn("calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.2))", css)

	def test_floor_never_exceeds_designed_size_at_default(self):
		for n, p0, kmax in (("13", Decimal(15), m.KMAX_HEADING), ("14", Decimal(15), m.KMAX_TITLE), ("19", Decimal(17), m.KMAX_HEADING)):
			_expr, k = m.floored(n, p0, kmax)
			self.assertLessEqual(p0 * k, Decimal(n))

	def test_notes_become_em_of_prose(self):
		css, _ = self.migrate()
		self.assertIn(".notes.module{font-size:0.8667em}", css)

	def test_idempotent(self):
		once, _ = self.migrate()
		twice, _ = self.migrate(once)
		self.assertEqual(once, twice)

	def test_missing_token_fails(self):
		with self.assertRaises(m.MigrationError):
			m.migrate_css(":root{--ink:#000}\nbody{color:var(--ink)}\n", "Bad.nnwtheme")

	def test_background_literal_is_reported(self):
		css = ZELLIGE_LIKE + ".x{background:#f6f1e4}\n"
		_new, notes = self.migrate(css)
		self.assertTrue(any("bg-literal: .x" in n for n in notes))


class BodyBackgroundTests(unittest.TestCase):
	"""The Swift extractor reads only `background-color` on body/.articleBody (see
	docs/article-color-pipeline.md); a `background:` shorthand there resolves to white/black."""

	def test_model_does_not_read_the_shorthand(self):
		colors = m.extractor_colors("body{background:#123456;color:#000}")
		self.assertEqual(colors["bg"], (None, None))

	def test_model_reads_background_color(self):
		colors = m.extractor_colors("body{background-color:#123456;color:#000}")
		self.assertEqual(colors["bg"][0], "#123456")

	def test_single_color_shorthand_is_renamed_by_offset(self):
		css = "body{margin:0;padding:0;background:var(--nnw-bg);color:var(--nnw-ink)}\n.t{background:#fff}\n"
		new, renamed, manual = m.normalize_body_background(css)
		self.assertEqual(new, css.replace("padding:0;background:", "padding:0;background-color:", 1))
		self.assertEqual((renamed, manual), (1, []))

	def test_idempotent(self):
		once, _n, _m = m.normalize_body_background("body{background:#102030;color:#fff}")
		twice, renamed, _m2 = m.normalize_body_background(once)
		self.assertEqual((once, renamed), (twice, 0))

	def test_dark_block_body_rule_is_renamed_but_supports_is_not(self):
		css = ("body{background-color:#fff}\n@media (prefers-color-scheme: dark){\nbody{background:#000}\n}\n"
			"@supports (-webkit-touch-callout: none){\nbody{background:#111}\n}\n")
		new, renamed, _manual = m.normalize_body_background(css)
		self.assertIn("body{background-color:#000}", new)
		self.assertIn("body{background:#111}", new)
		self.assertEqual(renamed, 1)

	def test_leading_import_does_not_hide_the_body_rule(self):
		css = "@import url('https://fonts.googleapis.com/css2?family=A:wght@400;700&display=swap');\nbody{background:#abc}\n"
		self.assertEqual(m.normalize_body_background(css)[1], 1)

	def test_left_alone_and_reported(self):
		for css in ("body{background:none}", "body{background:transparent}", "body{background:inherit}"):
			new, renamed, manual = m.normalize_body_background(css)
			self.assertEqual((new, renamed), (css, 0), css)
		complex_css = "body{background:var(--nnw-bg) url(x.png) repeat-y}"
		new, renamed, manual = m.normalize_body_background(complex_css)
		self.assertEqual((new, renamed, len(manual)), (complex_css, 0, 1))
		both = "body{background:#111;background-color:#222}"
		self.assertEqual(m.normalize_body_background(both), (both, 0, []))
		panel = ".articleBody{background:#eee}"
		new, renamed, manual = m.normalize_body_background(panel)
		self.assertEqual((new, renamed, len(manual)), (panel, 0, 1))

	def test_migrate_css_emits_background_color_for_a_shorthand_body(self):
		new, _changes, notes = m.migrate_css(ZELLIGE_LIKE, "Test.nnwtheme")
		self.assertIn("background-color:var(--nnw-bg)", new.replace(" ", ""))
		self.assertNotIn("background:var(--nnw-bg)", new.replace(" ", "").split("body{", 1)[1].split("}", 1)[0])
		self.assertTrue(any("renamed to background-color" in n for n in notes))


if __name__ == "__main__":
	unittest.main()
