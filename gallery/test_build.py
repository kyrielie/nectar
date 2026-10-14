"""Tests for gallery/build.py.

    python3 -m unittest discover -s gallery

Standard library only.
"""
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import unicodedata
import zipfile
from pathlib import Path

import build

HERE = Path(__file__).resolve().parent


def make_bundle(root, stem, plist_overrides=None, css="body { color: #000; }\n",
                template='<div id="bodyContainer" class="articleBody">[[body]]</div>\n'):
    path = root / f"{stem}{build.BUNDLE_SUFFIX}"
    path.mkdir(parents=True)
    plist = {
        "Name": stem,
        "ThemeIdentifier": f"com.example.{build.slugify(stem)}",
        "CreatorHomePage": "https://example.com",
        "CreatorName": "Tester",
        "Version": 1,
    }
    plist.update(plist_overrides or {})
    (path / "Info.plist").write_bytes(plistlib.dumps(plist))
    (path / "stylesheet.css").write_text(css, encoding="utf-8")
    (path / "template.html").write_text(template, encoding="utf-8")
    return path


class ImportProblems(unittest.TestCase):
    def test_leading_imports_are_fine(self):
        css = (
            "/* fonts */\n"
            '@import url("https://fonts.googleapis.com/css2?family=A;B&display=swap");\n'
            "@import url('https://x.example/y.css') screen;\n\n"
            "body { color: red; }\n"
        )
        self.assertEqual(build.import_problems(css), [])

    def test_no_imports_is_fine(self):
        self.assertEqual(build.import_problems("body { color: red; }"), [])
        self.assertEqual(build.import_problems(""), [])

    def test_semicolon_inside_quotes_does_not_end_the_rule(self):
        css = '@import url("https://x.example/a;b.css");\nbody{}\n'
        self.assertEqual(build.import_problems(css), [])

    def test_non_leading_import(self):
        css = "body { color: red; }\n@import url(x.css);\n"
        self.assertEqual(len(build.import_problems(css)), 1)
        self.assertIn("non-leading", build.import_problems(css)[0])

    def test_non_leading_import_after_leading_block(self):
        css = "@import url(a.css);\nbody {}\n@import url(b.css);\n"
        self.assertIn("non-leading", build.import_problems(css)[0])

    def test_non_leading_import_is_case_insensitive(self):
        self.assertIn("non-leading", build.import_problems("body{}\n@IMPORT url(x.css);")[0])

    def test_unterminated_import(self):
        problems = build.import_problems('@import url("https://x.example/a.css")\nbody { color: red; }\n')
        self.assertEqual(len(problems), 1)
        self.assertIn("unterminated", problems[0])

    def test_missing_semicolon_before_a_rule_is_unterminated(self):
        css = "@import url(a.css)\nbody { color: red; }\n"
        self.assertIn("unterminated", build.import_problems(css)[0])

    def test_unterminated_when_quote_swallows_semicolon(self):
        self.assertIn("unterminated", build.import_problems('@import "a.css;\nbody{}')[0])

    def test_import_text_in_comment_or_string_is_ignored(self):
        css = '@import url(a.css);\n/* @import url(b.css); */\nbody::after { content: "@import x;"; }\n'
        self.assertEqual(build.import_problems(css), [])

    def test_import_identifier_prefix_is_not_an_import(self):
        self.assertEqual(build.import_problems("body{}\n@imported-thing { }\n"), [])

    def test_escaped_quote_inside_string(self):
        css = '@import url("a\\";b.css");\nbody{}\n'
        self.assertEqual(build.import_problems(css), [])


class TemplateProblems(unittest.TestCase):
    def test_macro_in_comment(self):
        problems = build.template_problems("<!-- uses [[title]] here -->\n<h1>[[title]]</h1>")
        self.assertEqual(len(problems), 1)
        self.assertIn("[[title]]", problems[0])

    def test_multiline_comment_and_count(self):
        problems = build.template_problems("<!--\n[[a]]\n[[b_c]]\n-->")
        self.assertIn("[[a]]", problems[0])
        self.assertIn("1 more", problems[0])

    def test_macro_outside_comment_is_fine(self):
        self.assertEqual(build.template_problems("<!-- note -->\n<h1>[[title]]</h1>"), [])

    def test_non_macro_brackets_in_comment_are_fine(self):
        self.assertEqual(build.template_problems("<!-- a [[ not a macro ]] b -->"), [])


class VersionProblems(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(build.version_problems({"Version": 1}), [])
        self.assertEqual(build.version_problems({"Version": 12}), [])

    def test_invalid(self):
        for bad in (0, -1, "1", 1.0, 1.5, True, False):
            with self.subTest(bad=bad):
                self.assertEqual(len(build.version_problems({"Version": bad})), 1)

    def test_missing_is_left_to_required_keys(self):
        self.assertEqual(build.version_problems({}), [])


class DuplicateIdentifiers(unittest.TestCase):
    def test_duplicate(self):
        problems = build.duplicate_identifier_problems([("A", "x.y"), ("B", "x.y"), ("C", "z")])
        self.assertEqual(len(problems), 1)
        self.assertIn("x.y", problems[0])
        self.assertIn("A, B", problems[0])

    def test_unique(self):
        self.assertEqual(build.duplicate_identifier_problems([("A", "x"), ("B", "y")]), [])

    def test_blank_identifiers_are_not_duplicates(self):
        self.assertEqual(build.duplicate_identifier_problems([("A", ""), ("B", "")]), [])


class ZipLayout(unittest.TestCase):
    def test_zip_name_and_single_top_level(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            src = tmp / "src"
            src.mkdir()
            path = make_bundle(src, "Rose & Pine")
            (path / "License.md").write_text("MIT\n")
            (path / ".DS_Store").write_bytes(b"junk")
            theme, problems, _ = build.load_theme(path)
            self.assertEqual(problems, [])
            dest = build.write_zip(theme, tmp / "out")
            self.assertEqual(dest.name, "Rose & Pine.nnwtheme.zip")
            with zipfile.ZipFile(dest) as z:
                names = z.namelist()
            self.assertEqual({n.split("/")[0] for n in names}, {"Rose & Pine.nnwtheme"})
            self.assertEqual(
                sorted(n for n in names if not n.endswith("/")),
                [f"Rose & Pine.nnwtheme/{f}" for f in ("Info.plist", "License.md", "stylesheet.css", "template.html")],
            )

    def test_zip_url_path_encodes_reserved_characters(self):
        self.assertEqual(build.zip_url_path("Rose & Pine.nnwtheme.zip"), "Rose%20%26%20Pine.nnwtheme.zip")
        self.assertEqual(build.zip_url_path("Plain.nnwtheme.zip"), "Plain.nnwtheme.zip")


class BuildRuns(unittest.TestCase):
    def run_build(self, src, out):
        return subprocess.run(
            [sys.executable, str(HERE / "build.py"), "--out", str(out), "--src", str(src)],
            capture_output=True, text=True,
        )

    def test_bad_bundles_fail_the_build(self):
        cases = {
            "comment": dict(template='<!-- [[title]] -->\n<div id="bodyContainer" class="articleBody">[[body]]</div>'),
            "late-import": dict(css="body{}\n@import url(x.css);\n"),
            "open-import": dict(css="@import url(x.css)\nbody{}\n"),
            "version": dict(plist_overrides={"Version": 0}),
        }
        for label, kwargs in cases.items():
            with self.subTest(label), tempfile.TemporaryDirectory() as tmp:
                tmp = Path(tmp)
                make_bundle(tmp / "src", "Case", **kwargs)
                result = self.run_build(tmp / "src", tmp / "out")
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("ERROR Case.nnwtheme", result.stdout)

    def test_duplicate_identifier_across_bundles_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            make_bundle(tmp / "src", "One", plist_overrides={"ThemeIdentifier": "com.example.same"})
            make_bundle(tmp / "src", "Two", plist_overrides={"ThemeIdentifier": "com.example.same"})
            result = self.run_build(tmp / "src", tmp / "out")
            self.assertEqual(result.returncode, 1)
            self.assertIn("com.example.same", result.stdout)

    def test_duplicate_with_bundled_theme_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            make_bundle(tmp / "src", "Duskbloom", plist_overrides={"ThemeIdentifier": "com.example.same"})
            make_bundle(tmp / "src", "Other", plist_overrides={"ThemeIdentifier": "com.example.same"})
            result = self.run_build(tmp / "src", tmp / "out")
            self.assertEqual(result.returncode, 1)

    def test_good_bundle_builds_with_encoded_link(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            make_bundle(tmp / "src", "Good & Plain")
            result = self.run_build(tmp / "src", tmp / "out")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((tmp / "out" / "zips" / "Good & Plain.nnwtheme.zip").is_file())
            self.assertIn("zips/Good%20%26%20Plain.nnwtheme.zip", (tmp / "out" / "index.html").read_text())


GIT_ENV = ["-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false"]


def git(repo, *args):
    subprocess.run(["git", "-C", str(repo), *GIT_ENV, *args], check=True, capture_output=True)


def commit_all(repo, message="c"):
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", message)


class ReleaseIdentity(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.repo = Path(self._tmp.name)
        git(self.repo, "init", "-q", "-b", "main")
        self.themes = self.repo / "Themes"
        self.gallery = self.repo / "gallery-themes"
        self.themes.mkdir()
        self.gallery.mkdir()
        make_bundle(self.gallery, "Alpha", css="body { color: #111; }\n")
        make_bundle(self.themes, "Beta", css="body { color: #222; }\n")
        commit_all(self.repo, "base")
        git(self.repo, "branch", "base")

    def check(self, ref="base"):
        return build.check_release_identity(ref, [self.themes, self.gallery], root=self.repo)

    def set_plist(self, bundle, **changes):
        f = bundle / "Info.plist"
        plist = plistlib.loads(f.read_bytes())
        plist.update(changes)
        f.write_bytes(plistlib.dumps(plist))

    def test_unchanged_is_ok(self):
        self.assertEqual(self.check(), [])

    def test_stylesheet_change_requires_version_bump(self):
        bundle = self.gallery / "Alpha.nnwtheme"
        (bundle / "stylesheet.css").write_text("body { color: #333; }\n")
        problems = self.check()
        self.assertEqual(len(problems), 1)
        self.assertIn("Alpha.nnwtheme", problems[0])
        self.assertIn("stylesheet.css", problems[0])
        self.set_plist(bundle, Version=2)
        self.assertEqual(self.check(), [])

    def test_template_change_requires_version_bump(self):
        bundle = self.themes / "Beta.nnwtheme"
        (bundle / "template.html").write_text('<div id="bodyContainer" class="articleBody">x[[body]]</div>\n')
        self.assertIn("template.html", self.check()[0])
        self.set_plist(bundle, Version=3)
        self.assertEqual(self.check(), [])

    def test_version_must_strictly_increase(self):
        bundle = self.gallery / "Alpha.nnwtheme"
        self.set_plist(bundle, Version=5)
        commit_all(self.repo, "bump to 5")
        git(self.repo, "branch", "-f", "base")
        (bundle / "stylesheet.css").write_text("body { color: #444; }\n")
        self.set_plist(bundle, Version=5)
        self.assertEqual(len(self.check()), 1)
        self.set_plist(bundle, Version=4)
        self.assertEqual(len(self.check()), 1)
        self.set_plist(bundle, Version=6)
        self.assertEqual(self.check(), [])

    def test_non_integer_version_is_reported_when_content_changed(self):
        bundle = self.gallery / "Alpha.nnwtheme"
        (bundle / "stylesheet.css").write_text("body { color: #555; }\n")
        self.set_plist(bundle, Version="2")
        self.assertIn("not comparable", self.check()[0])

    def test_metadata_only_change_needs_no_bump(self):
        self.set_plist(self.gallery / "Alpha.nnwtheme", CreatorName="Someone Else")
        (self.gallery / "Alpha.nnwtheme" / "License.md").write_text("MIT\n")
        self.assertEqual(self.check(), [])

    def test_identifier_change_is_an_error(self):
        self.set_plist(self.gallery / "Alpha.nnwtheme", ThemeIdentifier="com.example.other")
        problems = self.check()
        self.assertEqual(len(problems), 1)
        self.assertIn("ThemeIdentifier changed", problems[0])

    def test_bundle_rename_is_an_error(self):
        (self.gallery / "Alpha.nnwtheme").rename(self.gallery / "Alpha Two.nnwtheme")
        problems = self.check()
        self.assertEqual(len(problems), 1)
        self.assertIn("bundle name changed", problems[0])
        self.assertIn("'Alpha'", problems[0])

    def test_plist_name_change_alone_is_not_a_rename(self):
        self.set_plist(self.gallery / "Alpha.nnwtheme", Name="Alpha and Co")
        self.assertEqual(self.check(), [])

    def test_nfc_reencoding_of_the_folder_name_is_not_a_rename(self):
        nfd = unicodedata.normalize("NFD", "Loter\u00eda")
        nfc = unicodedata.normalize("NFC", "Loter\u00eda")
        self.assertNotEqual(nfd, nfc)
        make_bundle(self.gallery, nfd, plist_overrides={"Name": nfc})
        commit_all(self.repo, "nfd bundle")
        git(self.repo, "branch", "-f", "base")
        (self.gallery / f"{nfd}.nnwtheme").rename(self.gallery / f"{nfc}.nnwtheme")
        self.assertEqual(self.check(), [])

    def test_move_between_directories_is_not_a_rename(self):
        shutil.move(str(self.gallery / "Alpha.nnwtheme"), str(self.themes / "Alpha.nnwtheme"))
        self.assertEqual(self.check(), [])

    def test_new_and_deleted_bundles_are_not_checked(self):
        make_bundle(self.gallery, "Gamma")
        shutil.rmtree(self.themes / "Beta.nnwtheme")
        self.assertEqual(self.check(), [])

    def test_changes_on_the_base_branch_are_not_blamed_on_the_branch(self):
        git(self.repo, "checkout", "-q", "-b", "feature")
        make_bundle(self.gallery, "Gamma")
        commit_all(self.repo, "feature work")
        git(self.repo, "checkout", "-q", "main")
        bundle = self.gallery / "Alpha.nnwtheme"
        (bundle / "stylesheet.css").write_text("body { color: #666; }\n")
        self.set_plist(bundle, Version=2)
        commit_all(self.repo, "main moves on")
        git(self.repo, "checkout", "-q", "feature")
        self.assertEqual(self.check("main"), [])

    def test_unknown_ref_is_reported(self):
        problems = self.check("no-such-ref")
        self.assertEqual(len(problems), 1)
        self.assertIn("cannot read base ref", problems[0])

    def test_src_outside_the_repo_is_reported(self):
        with tempfile.TemporaryDirectory() as other:
            problems = build.check_release_identity("base", [other], root=self.repo)
        self.assertIn("cannot read base ref", problems[0])

    def test_cli_exit_codes(self):
        (self.repo / "gallery").mkdir()
        shutil.copy(HERE / "build.py", self.repo / "gallery" / "build.py")
        commit_all(self.repo, "add build.py")
        git(self.repo, "branch", "-f", "base")

        def run():
            return subprocess.run(
                [sys.executable, str(self.repo / "gallery" / "build.py"), "--check-release-identity", "base",
                 "--src", str(self.themes), str(self.gallery)],
                capture_output=True, text=True)

        ok = run()
        self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)
        self.assertIn("release identity ok", ok.stdout)
        (self.gallery / "Alpha.nnwtheme" / "stylesheet.css").write_text("body { color: #777; }\n")
        bad = run()
        self.assertEqual(bad.returncode, 1)
        self.assertIn("ERROR Alpha.nnwtheme", bad.stdout)


class ShippedCorpus(unittest.TestCase):
    """The checked-in bundles must pass every build check and publish under D20."""

    def test_full_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out"
            result = subprocess.run(
                [sys.executable, str(HERE / "build.py"), "--out", str(out)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            zips = sorted((out / "zips").glob("*.nnwtheme.zip"))
            self.assertGreater(len(zips), 0)
            for z in zips:
                stem = z.name[: -len(".nnwtheme.zip")]
                with zipfile.ZipFile(z) as zf:
                    tops = {n.split("/")[0] for n in zf.namelist()}
                self.assertEqual(tops, {f"{stem}.nnwtheme"}, z.name)

    def bundles(self):
        root = HERE.parent
        found = sorted((root / "Themes").glob("*.nnwtheme")) + sorted((root / "gallery-themes").glob("*.nnwtheme"))
        self.assertGreater(len(found), 0)
        return found

    def test_bundle_names_are_nfc_and_match_info_plist_name(self):
        """Upstream requires Info.plist Name to equal the bundle name; NFC keeps the two byte-identical."""
        for path in self.bundles():
            stem = build.bundle_stem(path)
            name = plistlib.loads((path / "Info.plist").read_bytes())["Name"]
            with self.subTest(bundle=stem):
                self.assertTrue(unicodedata.is_normalized("NFC", stem), "bundle folder name is not NFC")
                self.assertTrue(unicodedata.is_normalized("NFC", name), "Info.plist Name is not NFC")
                self.assertEqual(name, stem)

    def test_no_placeholder_metadata(self):
        """The upstream validator's placeholder tokens (nnw-theme src/validate.ts PLACEHOLDERS)."""
        tokens = ("starter", "example.com", "your name", "change me", "todo")
        for path in self.bundles():
            plist = plistlib.loads((path / "Info.plist").read_bytes())
            for key in ("ThemeIdentifier", "Name", "CreatorHomePage", "CreatorName"):
                with self.subTest(bundle=path.name, key=key):
                    value = str(plist.get(key, "")).lower()
                    self.assertFalse([tok for tok in tokens if tok in value], f"{key}={value!r}")

    def test_default_template_has_no_macro_inside_a_comment(self):
        template = (HERE.parent / "Shared" / "Article Rendering" / "template.html").read_text(encoding="utf-8")
        self.assertEqual(build.template_problems(template), [])
        # The macro itself must still be used where the class list is built.
        self.assertIn('class="articleBody [[text_size_class]]"', template)

    def test_system_bundle_matches_the_builtin_fallback(self):
        """Themes/System.nnwtheme and the built-in fallback are one design in two places."""
        fallback = HERE.parent / "Shared" / "Article Rendering"
        bundle = HERE.parent / "Themes" / "System.nnwtheme"
        for name in ("stylesheet.css", "template.html"):
            with self.subTest(file=name):
                self.assertEqual((bundle / name).read_bytes(), (fallback / name).read_bytes())

    def test_fallback_template_keeps_the_selector_coverage_hooks(self):
        """ArticleThemeSelectorCoverageTests reads this file; keep its hooks (and System's copy) intact."""
        template = (HERE.parent / "Shared" / "Article Rendering" / "template.html").read_text(encoding="utf-8")
        for hook in ("headerContainer", "headerTable", "header", "feedlink"):
            with self.subTest(hook=hook):
                self.assertIn(hook, template)

    def test_fresh_install_default_theme_is_a_bundled_theme(self):
        """AppDefaults registers the fresh-install theme by bundle name; it must exist in Themes/."""
        source = (HERE.parent / "iOS" / "AppDefaults.swift").read_text(encoding="utf-8")
        found = re.findall(r'Key\.currentThemeName:\s*"([^"]+)"', source)
        self.assertEqual(len(found), 1, found)
        self.assertTrue((HERE.parent / "Themes" / f"{found[0]}.nnwtheme").is_dir(), found[0])
        self.assertEqual(found[0], "System")

    def test_bundled_set_equals_the_bundles_in_themes_dir(self):
        """BUNDLED must list exactly the bundles that ship in the app (Themes/)."""
        shipped = {build.bundle_stem(p) for p in (HERE.parent / "Themes").glob("*.nnwtheme")}
        self.assertEqual(build.BUNDLED, shipped)

    def test_no_bundled_theme_is_published_and_no_gallery_theme_is_skipped(self):
        gallery = {build.bundle_stem(p) for p in (HERE.parent / "gallery-themes").glob("*.nnwtheme")}
        self.assertEqual(build.BUNDLED & gallery, set())


if __name__ == "__main__":
    unittest.main()
