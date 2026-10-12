"""Every shipped bundle must declare its page color as `background-color` on `body`.

ArticleThemeColorExtractor reads only that property (docs/article-color-pipeline.md); the
`background` shorthand paints the same in the webview but resolves to white/black for the
notch cover, webview/under-page background and the Blend nav bar. Fix offenders with
`fix_body_background_color.py --write`.
"""
import unittest
from pathlib import Path

import migrate_theme_contract as m

REPO = Path(__file__).resolve().parents[2]


class BundleBodyBackground(unittest.TestCase):
	def test_no_bundle_sets_the_page_color_with_the_shorthand(self):
		offenders, manual = [], []
		for top in ("Themes", "gallery-themes"):
			for css_path in sorted((REPO / top).glob("*.nnwtheme/stylesheet.css")):
				_new, renamed, items = m.normalize_body_background(css_path.read_text(encoding="utf-8"))
				name = css_path.parent.name
				if renamed:
					offenders.append(name)
				manual.extend("%s: %s" % (name, i) for i in items)
		self.assertEqual(offenders, [], "body uses `background:`; run fix_body_background_color.py --write")
		self.assertEqual(manual, [], "shorthand the fixer cannot rename; fix by hand")


if __name__ == "__main__":
	unittest.main()
