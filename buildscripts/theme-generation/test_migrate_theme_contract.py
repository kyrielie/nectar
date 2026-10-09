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


if __name__ == "__main__":
	unittest.main()
