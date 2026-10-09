import unittest

import migrate_theme_contract as base
import migrate_theme_contract_family as fam

SAMPLE = """:root {
	--secondary-accent-color: #900;
}
body {
	background-color: #080808;
	color: #f2f2f2;
}
a {
	color: var(--secondary-accent-color);
}
.rule {
	background: #080808;
	font-size: 0.9rem;
}
@supports (-webkit-touch-callout: none) {
	body {
		font-family: "Source Serif 4", serif;
	}

	.articleTitle h1 {
		font-size: 1.5em;
	}
}
"""


class FamilyTests(unittest.TestCase):
	def migrate(self, css=SAMPLE):
		return fam.migrate_css(css, "Test.nnwtheme")[0]

	def test_tokens_are_literal_and_body_uses_them(self):
		css = self.migrate()
		self.assertIn("--nnw-bg: #080808;", css)
		self.assertIn("--nnw-link: #900;", css)
		self.assertIn("background-color: var(--nnw-bg);", css)
		self.assertIn("color: var(--nnw-link);", css)

	def test_literal_copy_of_background_uses_token(self):
		self.assertIn("background: var(--nnw-bg);", self.migrate())

	def test_rem_becomes_u_and_title_is_floored(self):
		css = self.migrate()
		self.assertNotIn("rem;", css.replace("1rem / 15", ""))
		self.assertIn("calc(var(--u) * 22.5 * var(--nnw-detail-scale, 1))", css)
		self.assertIn("* 1.4))", css)

	def test_no_gx_is_declared(self):
		self.assertNotIn("--gx", self.migrate())

	def test_idempotent(self):
		once = self.migrate()
		self.assertEqual(once, fam.migrate_css(once, "Test.nnwtheme")[0])

	def test_non_literal_page_color_fails(self):
		with self.assertRaises(base.MigrationError):
			fam.migrate_css(SAMPLE.replace("#080808;\n\tcolor", "var(--missing);\n\tcolor", 1), "T")


if __name__ == "__main__":
	unittest.main()
