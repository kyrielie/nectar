#!/usr/bin/env python3
"""Run the upstream `nnw-theme check` gate on the bundles in gallery/upstream-compatible.txt.

    python3 gallery/upstream_compat.py [--list FILE] [--src DIR ...] [--nnw-theme-version V]
                                       [--report-dir DIR] [--dry-run] [--npx PATH]

nnw-theme works on a theme repository: exactly one *.nnwtheme at the root of the directory it
runs in, and it writes build/ there. Nectar keeps many bundles in two folders, so each listed
bundle is copied into its own temporary directory and checked there. A bundle that fails does
not stop the others; the exit status is 1 if any bundle failed or the list is invalid.

--dry-run only validates the list and locates the bundles (no Node needed).
Standard library only; the check itself needs Node 24+ and WebKit (see ci.yml).
"""
import argparse
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LIST = Path(__file__).resolve().parent / "upstream-compatible.txt"
DEFAULT_SRC = [ROOT / "Themes", ROOT / "gallery-themes"]
SUFFIX = ".nnwtheme"
# Keep in step with the `upstream-compat` job in ci.yml (that job exports NNW_THEME_VERSION).
DEFAULT_VERSION = "2.0.2"


def read_list(path):
    """Bundle names from the list file. Raises ValueError on a duplicate (after NFC)."""
    names, seen = [], set()
    for lineno, raw in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key = unicodedata.normalize("NFC", line)
        if key in seen:
            raise ValueError(f"{path}:{lineno}: {line!r} is listed twice")
        seen.add(key)
        names.append(line)
    return names


def locate(name, src_dirs):
    """The bundle folder for a listed name (matched after NFC), or None."""
    want = unicodedata.normalize("NFC", name)
    for d in map(Path, src_dirs):
        if not d.is_dir():
            continue
        for path in sorted(d.glob("*" + SUFFIX)):
            if unicodedata.normalize("NFC", path.name[: -len(SUFFIX)]) == want and path.is_dir():
                return path
    return None


def run_check(bundle, version, report_dir=None, npx="npx"):
    """Run `nnw-theme check` on one bundle in a throwaway repository. Returns (ok, output)."""
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp)
        shutil.copytree(bundle, repo / bundle.name)
        proc = subprocess.run(
            [npx, "--yes", f"nnw-theme@{version}", "check", "--no-open"],
            cwd=repo, capture_output=True, text=True,
        )
        output = proc.stdout + proc.stderr
        report = repo / "build" / "check-report.txt"
        if report_dir is not None and report.is_file():
            dest = Path(report_dir)
            dest.mkdir(parents=True, exist_ok=True)
            shutil.copy(report, dest / f"{bundle.name[: -len(SUFFIX)]}.txt")
    return proc.returncode == 0, output


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--list", default=str(DEFAULT_LIST))
    ap.add_argument("--src", nargs="*", default=[str(p) for p in DEFAULT_SRC])
    ap.add_argument("--nnw-theme-version", default=DEFAULT_VERSION)
    ap.add_argument("--report-dir")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--npx", default="npx", help="npx executable (tests substitute a stub)")
    args = ap.parse_args(argv)

    try:
        names = read_list(args.list)
    except ValueError as e:
        print(f"ERROR {e}")
        return 1
    if not names:
        print(f"ERROR {args.list} lists no bundles")
        return 1

    bundles, missing = [], False
    for name in names:
        path = locate(name, args.src)
        if path is None:
            print(f"ERROR {name}: no such bundle in {', '.join(args.src)}")
            missing = True
        else:
            bundles.append(path)
    if missing:
        return 1
    if args.dry_run:
        print(f"{len(bundles)} bundles listed and found")
        return 0

    failed = []
    for path in bundles:
        ok, output = run_check(path, args.nnw_theme_version, args.report_dir, npx=args.npx)
        print(f"{'PASS' if ok else 'FAIL'}  {path.name}")
        if not ok:
            failed.append(path.name)
            print(output.rstrip())
    if failed:
        print(f"ERROR {len(failed)} of {len(bundles)} bundles failed nnw-theme check: {', '.join(failed)}")
        return 1
    print(f"all {len(bundles)} bundles passed nnw-theme check")
    return 0


if __name__ == "__main__":
    sys.exit(main())
