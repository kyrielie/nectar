"""Tests for gallery/upstream_compat.py and gallery/upstream-compatible.txt.

    python3 -m unittest discover -s gallery

The real `nnw-theme check` (Node 24 and WebKit) is not run here; a stub `npx` stands in.
"""
import os
import plistlib
import stat
import tempfile
import textwrap
import unicodedata
import unittest
from pathlib import Path

import build
import upstream_compat as uc

HERE = Path(__file__).resolve().parent

STUB = textwrap.dedent("""\
    #!/bin/sh
    # Records its arguments and the bundles it sees, writes a report, fails for "Bad".
    echo "$@" >> "$STUB_LOG"
    ls -d *.nnwtheme >> "$STUB_LOG"
    mkdir -p build
    if [ -d Bad.nnwtheme ]; then
        echo "FAIL" > build/check-report.txt
        echo "1 of 3 WebKit renders failed" >&2
        exit 1
    fi
    echo "PASS" > build/check-report.txt
    echo "PASS: 3 WebKit renders"
""")


def write_bundle(root, name):
    path = Path(root) / f"{name}{uc.SUFFIX}"
    path.mkdir(parents=True)
    (path / "Info.plist").write_bytes(plistlib.dumps({"Name": name}))
    (path / "stylesheet.css").write_text("body{}")
    (path / "template.html").write_text("<div></div>")
    return path


class ListFile(unittest.TestCase):
    def write(self, text):
        d = tempfile.mkdtemp()
        self.addCleanup(lambda: __import__("shutil").rmtree(d, ignore_errors=True))
        f = Path(d) / "list.txt"
        f.write_text(text, encoding="utf-8")
        return f

    def test_comments_and_blank_lines_are_skipped(self):
        f = self.write("# note\n\nSepia\n  Tiqoe Dark  \n# Not Listed\n")
        self.assertEqual(uc.read_list(f), ["Sepia", "Tiqoe Dark"])

    def test_duplicates_are_rejected_after_nfc(self):
        nfd = unicodedata.normalize("NFD", "Loter\u00eda")
        nfc = unicodedata.normalize("NFC", "Loter\u00eda")
        f = self.write(f"{nfd}\n{nfc}\n")
        with self.assertRaises(ValueError):
            uc.read_list(f)

    def test_locate_matches_nfc_across_directories(self):
        with tempfile.TemporaryDirectory() as tmp:
            a, b = Path(tmp) / "a", Path(tmp) / "b"
            a.mkdir()
            written = write_bundle(b, unicodedata.normalize("NFD", "Loter\u00eda"))
            found = uc.locate(unicodedata.normalize("NFC", "Loter\u00eda"), [a, b])
            self.assertEqual(found, written)
            self.assertIsNone(uc.locate("Missing", [a, b]))


class ShippedList(unittest.TestCase):
    def test_every_listed_bundle_exists_and_is_upstream_shaped(self):
        names = uc.read_list(uc.DEFAULT_LIST)
        self.assertEqual(
            sorted(names),
            sorted(["Biblioteca", "NewsFax", "Promenade", "Sepia", "Tiqoe Dark", "Verdana Revival"]),
        )
        for name in names:
            with self.subTest(bundle=name):
                path = uc.locate(name, uc.DEFAULT_SRC)
                self.assertIsNotNone(path, "listed bundle not found in Themes/ or gallery-themes/")
                plist = plistlib.loads((path / "Info.plist").read_bytes())
                self.assertEqual(plist["Name"], build.bundle_stem(path))
                css = (path / "stylesheet.css").read_text(encoding="utf-8")
                self.assertNotIn("@import", css, "upstream rejects @import (plan D18)")
                self.assertEqual(build.lint_bundle(path), [])
                self.assertNotIn("url(#", css, "bundle-local url() fails the upstream validator")

    def test_exempt_bundles_are_not_listed(self):
        names = uc.read_list(uc.DEFAULT_LIST)
        for exempt in ("Craft Table", "Illuminated Codex", "Nectar"):
            self.assertNotIn(exempt, names)

    def test_dry_run_succeeds(self):
        self.assertEqual(uc.main(["--dry-run"]), 0)

    def test_pinned_version_matches_ci(self):
        ci = (HERE.parent / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
        self.assertIn(f'NNW_THEME_VERSION: "{uc.DEFAULT_VERSION}"', ci)


class RunCheck(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = Path(self._tmp.name)
        self.stub = self.tmp / "npx"
        self.stub.write_text(STUB)
        self.stub.chmod(self.stub.stat().st_mode | stat.S_IXUSR)
        self.log = self.tmp / "stub.log"
        os.environ["STUB_LOG"] = str(self.log)
        self.addCleanup(os.environ.pop, "STUB_LOG", None)
        self.src = self.tmp / "src"
        self.src.mkdir()

    def test_runs_in_an_isolated_repo_with_one_bundle(self):
        write_bundle(self.src, "Good")
        write_bundle(self.src, "Other")
        reports = self.tmp / "reports"
        ok, output = uc.run_check(self.src / "Good.nnwtheme", "9.9.9", reports, npx=str(self.stub))
        self.assertTrue(ok)
        self.assertIn("PASS", output)
        lines = self.log.read_text().splitlines()
        self.assertEqual(lines, ["--yes nnw-theme@9.9.9 check --no-open", "Good.nnwtheme"])
        self.assertEqual((reports / "Good.txt").read_text().strip(), "PASS")
        self.assertFalse((self.src / "Good.nnwtheme" / "build").exists(), "the source bundle must stay untouched")

    def test_failure_is_reported(self):
        write_bundle(self.src, "Bad")
        ok, output = uc.run_check(self.src / "Bad.nnwtheme", "9.9.9", self.tmp / "r", npx=str(self.stub))
        self.assertFalse(ok)
        self.assertIn("1 of 3 WebKit renders failed", output)
        self.assertEqual((self.tmp / "r" / "Bad.txt").read_text().strip(), "FAIL")

    def test_main_checks_every_bundle_and_fails_if_any_fails(self):
        for n in ("Good", "Bad", "Fine"):
            write_bundle(self.src, n)
        lst = self.tmp / "list.txt"
        lst.write_text("# gate\nGood\nBad\nFine\n")
        rc = uc.main(["--list", str(lst), "--src", str(self.src), "--npx", str(self.stub),
                      "--report-dir", str(self.tmp / "r"), "--nnw-theme-version", "1.2.3"])
        self.assertEqual(rc, 1)
        # a failing bundle does not stop the rest
        self.assertEqual(sorted(p.name for p in (self.tmp / "r").iterdir()), ["Bad.txt", "Fine.txt", "Good.txt"])
        calls = [l for l in self.log.read_text().splitlines() if l.startswith("--yes")]
        self.assertEqual(calls, ["--yes nnw-theme@1.2.3 check --no-open"] * 3)

    def test_main_passes_when_all_pass(self):
        write_bundle(self.src, "Good")
        lst = self.tmp / "list.txt"
        lst.write_text("Good\n")
        self.assertEqual(uc.main(["--list", str(lst), "--src", str(self.src), "--npx", str(self.stub)]), 0)

    def test_main_fails_for_a_missing_bundle_without_running_anything(self):
        write_bundle(self.src, "Good")
        lst = self.tmp / "list.txt"
        lst.write_text("Good\nGone\n")
        rc = uc.main(["--list", str(lst), "--src", str(self.src), "--npx", str(self.stub)])
        self.assertEqual(rc, 1)
        self.assertFalse(self.log.exists())

    def test_main_fails_for_an_empty_list(self):
        lst = self.tmp / "list.txt"
        lst.write_text("# nothing\n")
        self.assertEqual(uc.main(["--list", str(lst), "--src", str(self.src), "--dry-run"]), 1)


if __name__ == "__main__":
    unittest.main()
