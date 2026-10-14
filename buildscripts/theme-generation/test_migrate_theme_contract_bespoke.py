import unittest
from decimal import Decimal

import migrate_theme_contract as base
import migrate_theme_contract_bespoke as bespoke

SAMPLE = """:root {
	--bg-var: #f7f0dc;
	--text-var: #2b1f14;
	--link-var: #7b1e1e;
}
@media (prefers-color-scheme: dark) {
	:root {
		--bg-var: #241c12;
		--text-var: #e8dcc0;
		--link-var: #d68a8a;
	}
}
body {
	background-color: var(--bg-var);
	color: var(--text-var);
}
.box {
	background: var(--bg-var);
	max-width: 42rem;
}
.headerBar {
	font-family: var(--font-sans);
	font-size: 1em;
}
@supports (-webkit-touch-callout: none) {
	body {
		font-size: [[font-size]]px;
	}
}
"""

PARTS = [
	bespoke.part("wrapper", ".fontSize"),
	bespoke.part("pin", ".headerBar", chrome="wrap"),
	bespoke.part("title", ".articleTitle"),
	bespoke.part("heading", ".articleBody h2.heading"),
]
SPEC = dict(parts=PARTS, link="var(--link-var)")


def measured(prose=17.0, title=28.9, header=17.0, heading=23.8, preface=15.3, series=15.3):
	one = {"prose": prose, "preface": preface, "series": series, "p0": 17.0, "p1": header, "p2": title, "p3": heading}
	return {"light": dict(one), "dark": dict(one)}


class BespokeTests(unittest.TestCase):
	def migrate(self, mz=None):
		return bespoke.migrate_css(SAMPLE, "Test.nnwtheme", SPEC, mz or measured())[0]

	def test_pin_value_is_px_in_u(self):
		self.assertEqual(bespoke.n_of(17), Decimal(15))
		self.assertEqual(bespoke.n_of(28.9), Decimal("25.5"))

	def test_tokens_are_literal_and_body_uses_them(self):
		css = self.migrate()
		self.assertIn("--nnw-bg: #f7f0dc;", css)
		self.assertIn("--nnw-bg: #241c12;", css)
		self.assertIn("--nnw-link: #7b1e1e;", css)
		self.assertIn("background-color: var(--nnw-bg);", css)

	def test_page_color_variable_is_replaced_elsewhere(self):
		css = self.migrate()
		self.assertIn("background: var(--nnw-bg);", css)

	def test_rem_becomes_u(self):
		self.assertIn("max-width: calc(var(--u) * 630);", self.migrate())

	def test_pins_are_appended_to_the_ios_block(self):
		css = self.migrate()
		ios = css[css.index("@supports"):]
		self.assertIn("html {\n\t\tfont: -apple-system-body;", ios)
		self.assertIn(".fontSize {\n\t\tfont-size: calc(var(--u) * 15);", ios)
		self.assertIn("max(calc(var(--u) * 25.5 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.4))", ios)
		self.assertIn("--ao3-preface-font-size: calc(var(--u) * 13.5 * var(--nnw-detail-scale, 1));", ios)

	def test_chrome_font_wraps_the_existing_stack(self):
		self.assertIn("font-family: var(--nnw-font-chrome, var(--font-sans));", self.migrate())

	def test_dark_rule_only_when_the_value_differs(self):
		self.assertNotIn("@media (prefers-color-scheme: dark) {\n\t\t.", self.migrate().split("@supports")[1])
		mz = measured()
		mz["dark"]["p2"] = 32.0
		ios = self.migrate(mz).split("@supports")[1]
		self.assertIn("@media (prefers-color-scheme: dark)", ios)

	def test_heading_floor_is_capped_by_the_designed_ratio(self):
		css = self.migrate(measured(heading=17.0))
		self.assertIn("calc(var(--u) * 15 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1))", css)

	def test_idempotent(self):
		once = self.migrate()
		self.assertEqual(bespoke.migrate_css(once, "Test.nnwtheme", SPEC, measured())[0], once)

	def test_missing_dark_literal_fails(self):
		with self.assertRaises(base.MigrationError):
			bespoke.migrate_css(SAMPLE.replace("#241c12", "red"), "Test.nnwtheme", SPEC, measured())


if __name__ == "__main__":
	unittest.main()
