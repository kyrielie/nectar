"""Pins the eight NetNewsWire-origin bundles in Themes/ to upstream, file by file.

Every file in those bundles must be byte-identical to NetNewsWire at UPSTREAM_COMMIT
(path Resources/Themes/), except the files listed in INTENTIONAL_DELTAS, which must
match the SHA-256 recorded there. A drift in either direction fails: an unlisted edit
to a bundle, an edit to a listed file that was not re-pinned, or a listed file that now
equals upstream (remove it from the list).

When a bundle changes on purpose, run `python3 gallery/test_upstream_pins.py --print`
and paste the output over INTENTIONAL_DELTAS, keeping the reasons. See
docs/theme-gallery.md, "Upstream pin test".
"""

import hashlib
import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
THEMES = HERE.parent / "Themes"

UPSTREAM_REPO = "Ranchero-Software/NetNewsWire"
UPSTREAM_COMMIT = "a3e61ddc5ab3c5b8fe49297cbaddb60b6201017f"
BUNDLES = (
    "Appanoose", "Biblioteca", "Hyperlegible", "NewsFax", "Promenade", "Sepia",
    "Tiqoe Dark", "Verdana Revival",
)

# SHA-256 of every file in the eight bundles at UPSTREAM_COMMIT.
UPSTREAM = {
    "Appanoose.nnwtheme/Info.plist": "bab57ade35e5e5f1ff76bdbb47112f37d768777b6ab3bcc74f65cb21efd5fe88",
    "Appanoose.nnwtheme/stylesheet.css": "ad02d4e959563bbc3dfeaa78324ca0ff13bc34dce0c5503888e4b584fe1b6d46",
    "Appanoose.nnwtheme/template.html": "24a3458a9cf541724570aa5de7476dc522cf290b5683147eaf17fb214d373184",
    "Biblioteca.nnwtheme/Info.plist": "faddad23d55a3986fc8b3b0ad20a5460a11ef32218fbdad4e7133d30e8265e8c",
    "Biblioteca.nnwtheme/stylesheet.css": "3f4e6c3b93df077d890f0c6f6255d52a094efeecffd4dd0dc994d6706a480599",
    "Biblioteca.nnwtheme/template.html": "31824e68ac8b9adfec712fe7f9953ad12892347ebf33099f4cff733cdb424fa4",
    "Hyperlegible.nnwtheme/Info.plist": "490df0d6bbef3239831fad330d86f64dd83e5ab48d48a0018c7818d95aa6f170",
    "Hyperlegible.nnwtheme/stylesheet.css": "442165467688bef2a61a97362a16bcdc4235115e794747c734d3e62205fb49a9",
    "Hyperlegible.nnwtheme/template.html": "abdeaf98f2494787bf3a3a395015262f3a36eb840c25bc29267d7c43805d0b2e",
    "NewsFax.nnwtheme/Info.plist": "28a85955db58f5587ad08508c884c8984b4b6acd69803d3bc7bc34f1c83a2465",
    "NewsFax.nnwtheme/License.md": "0da6b583ee7abd878f9db2bcb38d53078f4993f5ef8a0cf3fe36f22994bf656f",
    "NewsFax.nnwtheme/stylesheet.css": "247741e4430d4e04bb82526551c046b00f55865dd323eb5bcaf6c329de9b7591",
    "NewsFax.nnwtheme/template.html": "71b0a9129c0f87efc0243ed9e6fe508f9910d23236e5cf7d36652d3478065054",
    "Promenade.nnwtheme/Info.plist": "0b260f9202c80accc9ea1f276a366ab8a512b866e20eb02fd0c261037dfa7062",
    "Promenade.nnwtheme/stylesheet.css": "35eb8b7c3df090ce1636828fa8faeaeaf9b3961156e7d0c3188aa07d82af02f4",
    "Promenade.nnwtheme/template.html": "c2d0e8e5d9fb9add7915e15e46da7b05bdd18dc2a7c30b7632d220052fe76f49",
    "Sepia.nnwtheme/Info.plist": "46b2929424e2fabf12b97ae821c27568ec35265efb7bc45976340c77dad726c9",
    "Sepia.nnwtheme/stylesheet.css": "0e633de0cf82b95f078a3aba1c73f3a116a5e8d6233e26ef2d2db179e2f077bc",
    "Sepia.nnwtheme/template.html": "39fd7ef19d6008f9c265adadf493b74d77566ba1b062b17740a2d74d67ce1440",
    "Tiqoe Dark.nnwtheme/Info.plist": "31b375cfe7971737b684205354d20c2e624db6773413e6876e1281f4b8cd0563",
    "Tiqoe Dark.nnwtheme/stylesheet.css": "f84d7c6375dd57f3146a17af643a5d4c052752da449acd9b1e34ee0e185aa130",
    "Tiqoe Dark.nnwtheme/template.html": "b830088573e1853432e9571c524a0252cfa278a2128746735216539654b2e8df",
    "Verdana Revival.nnwtheme/Info.plist": "6338a3dc2864acf7693ef24741e6505621656c4d3b30bd5120540bfb1915ad36",
    "Verdana Revival.nnwtheme/stylesheet.css": "200e0fcba7a73f3f5f52ff2d81d30f1eecc9c5225895969e706789e3a0b62881",
    "Verdana Revival.nnwtheme/template.html": "fe896ea2315cf1eaf36c569abefa82103fa71ee7df2324c43e4994dae16cb8b2",
}

# Files that differ from upstream on purpose: path -> (SHA-256 of the Nectar file, reason).
INTENTIONAL_DELTAS = {
    "Appanoose.nnwtheme/Info.plist": (
        "139b754f1b24ad97edf77b7144a84a57dd8ed38e8a91a7155a4ed273ee6e088e",
        "ThemeIdentifier is com.netnewswire.themes.appanoose, not upstream's com.netnewswire.themes.starter. Permanent: gallery/test_build.py test_no_placeholder_metadata rejects any identifier containing \"starter\".",
    ),
    "Appanoose.nnwtheme/template.html": (
        "cce7f570995c57357efa3f14b84e7c9b2e324b2fa7afdee2630f757564a0fb3f",
        "Drops the [[time_short]] line. Permanent: ArticleRenderer strips the time only from datetime_*; time_short is still filled, and every article's time is a meaningless 12:00.",
    ),
    "Biblioteca.nnwtheme/stylesheet.css": (
        "76aae27b34b1858e4e839b80b78134b74fef29918ed7f7919d1bcb72eb29d05e",
        "Appends about 90 lines of AO3 block styling (summary, notes, chapter headings). Permanent: a pure append, nothing upstream is edited.",
    ),
    "Biblioteca.nnwtheme/template.html": (
        "10ed149e8f3f7aeb88ebc89ab2171ce4bbf42f3a049c500743f1fcf9703ee590",
        "Container becomes id=bodyContainer with class articleBody. Permanent: core.css, annotations, ArticleThemeOverrides and main.js all key on them, and the color probe loads no main.js.",
    ),
    "Hyperlegible.nnwtheme/stylesheet.css": (
        "17f522422c6335a473dfb569f2ed48b23d65172b3400994aed48c1440d950e56",
        "PENDING REVERT: still carries a Google Fonts @import instead of the base64 font, plus the font: font-family: typo fix. After the revert only the typo fix remains.",
    ),
    "NewsFax.nnwtheme/stylesheet.css": (
        "8404bee60582d74892ebbf9f8ab0bbc54498922c7390a71e32685e89a3a11691",
        "PENDING REVERT: background changed to background-color for the legacy scanner. Restore once the probe is confirmed.",
    ),
    "Sepia.nnwtheme/stylesheet.css": (
        "699ca461860a491e269b534d6c598a19cd39e3d5d8e81d824898b5d96168417f",
        "PENDING REVERT: extra a { color } rule for the legacy scanner. Restore once the probe is confirmed.",
    ),
    "Tiqoe Dark.nnwtheme/stylesheet.css": (
        "06b8a11747ccd4a0fdc6cf2894fcf3cdcdcdbffaa53c1b54732cb6a432c213ee",
        "PENDING REVERT: extra a { color } rule for the legacy scanner. Restore once the probe is confirmed.",
    ),
    "Verdana Revival.nnwtheme/stylesheet.css": (
        "18a48d8435ac61dc2b9bcbf0ed48db1897dd492629f535662db0bb105b2246b9",
        "PENDING REVERT: p margin and indent read the paragraph variables. Redundant, because the override block appends !important rules after the theme CSS.",
    ),
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bundle_files():
    found = {}
    for name in BUNDLES:
        root = THEMES / f"{name}.nnwtheme"
        for path in sorted(root.rglob("*")):
            if path.is_file():
                found[f"{name}.nnwtheme/{path.relative_to(root).as_posix()}"] = path
    return found


class UpstreamPinTests(unittest.TestCase):
    def test_bundles_hold_exactly_the_upstream_file_set(self):
        self.assertEqual(sorted(bundle_files()), sorted(UPSTREAM))

    def test_unlisted_files_are_byte_identical_to_upstream(self):
        for rel, path in bundle_files().items():
            if rel in INTENTIONAL_DELTAS:
                continue
            with self.subTest(file=rel):
                self.assertEqual(sha256(path), UPSTREAM[rel], "differs from upstream and is not in INTENTIONAL_DELTAS")

    def test_intentional_deltas_are_pinned_and_still_deltas(self):
        files = bundle_files()
        for rel, (pinned, reason) in INTENTIONAL_DELTAS.items():
            with self.subTest(file=rel):
                self.assertIn(rel, UPSTREAM)
                self.assertTrue(reason.strip(), "a delta needs a reason")
                self.assertEqual(sha256(files[rel]), pinned, "edited since it was pinned; re-pin with --print")
                self.assertNotEqual(pinned, UPSTREAM[rel], "now equals upstream; remove it from INTENTIONAL_DELTAS")


def print_deltas():
    for rel, path in bundle_files().items():
        if sha256(path) != UPSTREAM[rel]:
            reason = INTENTIONAL_DELTAS.get(rel, ("", "TODO: reason"))[1]
            print(f"    {rel!r}: (\n        {sha256(path)!r},\n        {reason!r},\n    ),")


if __name__ == "__main__":
    if "--print" in sys.argv:
        print_deltas()
    else:
        unittest.main()
