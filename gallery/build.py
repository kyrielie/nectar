#!/usr/bin/env python3
"""Build the Nectar theme gallery (static site for GitHub Pages).

    python3 gallery/build.py [--out gallery/dist] [--base-url URL] [--src DIR ...]
    python3 gallery/build.py --check-release-identity <base-ref> [--src DIR ...]

For every .nnwtheme bundle found in the --src directories (default: Themes/ and
gallery-themes/) that is not listed in BUNDLED, this:
  1. validates the constraints from docs/nnwtheme-format.md,
  2. writes dist/zips/<BundleStem>.nnwtheme.zip containing exactly one top-level
     <BundleStem>.nnwtheme (the real bundle folder name: the app derives the theme
     name from that folder, and the name matches the upstream marketplace rules),
  3. writes dist/index.html with every theme's CSS/template inlined, so the page
     needs no fetches for its own data and also works when opened straight from
     disk. Web fonts (the page's own Sorts Mill Goudy, and any theme @import) load
     from Google Fonts; offline they fall back to each stack's system serif.

--check-release-identity builds nothing. It compares every changed bundle against the same
bundle at <base-ref> (see check_release_identity) and exits 1 on an identity violation.

Standard library only (the identity check shells out to git).
"""
import argparse
import json
import plistlib
import re
import shutil
import subprocess
import sys
import unicodedata
import urllib.parse
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE_CSS = ROOT / "Shared" / "Article Rendering" / "core.css"
TEMPLATE = Path(__file__).resolve().parent / "index.template.html"

# Themes that ship inside the app (everything in Themes/) and are never published
# to the gallery. Anything else, i.e. everything in gallery-themes/, is published.
# gallery/test_build.py checks that this set equals the bundle stems in Themes/, so
# moving a bundle between the two folders means editing this set in the same change.
BUNDLED = {
    "System", "Reversi", "Duskbloom", "Midnight Blue", "OLED Black", "Night Amber",
    "Solarized", "Dark Academia", "Nectar", "High Contrast",
}

DEFAULT_BASE = "https://kyrielie.github.io/nectar/themes/"
REQUIRED_KEYS = ("Name", "ThemeIdentifier", "CreatorHomePage", "CreatorName", "Version")
ZIP_TIME = (2026, 1, 1, 0, 0, 0)
BUNDLE_SUFFIX = ".nnwtheme"
MACRO_RE = re.compile(r"\[\[[A-Za-z0-9_-]+\]\]")
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)


def slugify(name):
    ascii_name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", ascii_name.lower()).strip("-")


def bundle_stem(path):
    """Bundle folder name without the .nnwtheme suffix (what zips and the app are named after)."""
    return path.name[: -len(BUNDLE_SUFFIX)]


def _ident_boundary(ch):
    """Mirror of CSSImportExtractor.isCSSIdentifierBoundary."""
    return not (ch.isalnum() or ch in "-_")


def _scan_import(css, i):
    """Scan one @import statement starting at css[i].

    Returns ("ok", end) when terminated by an unquoted ';', ("unterminated", len(css)) when the
    statement never ends (or runs into an unquoted '{' or '}' first, the sign of a missing ';'),
    or None when css[i] does not start an @import rule. Quote-aware, like
    CSSImportExtractor.scanImport: Google Fonts URLs carry ';' inside quotes.
    """
    if not css.startswith("@import", i):
        return None
    j = i + len("@import")
    if j < len(css) and not _ident_boundary(css[j]):
        return None
    quote, prev_backslash = None, False
    while j < len(css):
        ch = css[j]
        if quote:
            if ch == quote and not prev_backslash:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == ";":
            return "ok", j + 1
        elif ch in "{}":
            # A missing ';' would otherwise let the statement swallow the next rule up to its
            # first ';' (CSSImportExtractor would lift that whole span as "imports").
            return "unterminated", len(css)
        prev_backslash = ch == "\\" and not prev_backslash
        j += 1
    return "unterminated", len(css)


def import_problems(css):
    """Errors for @import placement. Mirrors CSSImportExtractor's notion of a leading block.

    Leading: only whitespace, comments and terminated @import rules precede it. An @import that
    is unterminated, or that appears after any other content, is an error, because the app lifts
    only the leading block and prepends core.css to the rest, where an @import is ignored.
    """
    problems = []
    i, n = 0, len(css)
    while i < n:
        if css[i].isspace():
            i += 1
            continue
        if css.startswith("/*", i):
            end = css.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        res = _scan_import(css, i)
        if res is None:
            break
        kind, i = res
        if kind == "unterminated":
            problems.append("unterminated @import (no closing ';')")
            return problems
    # Everything left must contain no @import at all (outside comments and strings).
    quote, prev_backslash = None, False
    while i < n:
        ch = css[i]
        if quote:
            if ch == quote and not prev_backslash:
                quote = None
            prev_backslash = ch == "\\" and not prev_backslash
            i += 1
            continue
        if css.startswith("/*", i):
            end = css.find("*/", i + 2)
            i = n if end < 0 else end + 2
            prev_backslash = False
            continue
        if ch in "\"'":
            quote = ch
        elif css[i:i + 7].lower() == "@import" and (i + 7 >= n or _ident_boundary(css[i + 7])):
            problems.append("non-leading @import (only a leading block of @import rules is supported)")
            return problems
        prev_backslash = False
        i += 1
    return problems


def template_problems(template):
    """Macros written inside an HTML comment are substituted like any other and can end the comment early."""
    found = []
    for comment in HTML_COMMENT_RE.finditer(template):
        for m in MACRO_RE.finditer(comment.group(0)):
            if m.group(0) not in found:
                found.append(m.group(0))
    if not found:
        return []
    more = f" and {len(found) - 1} more" if len(found) > 1 else ""
    return [f"template.html has a macro inside an HTML comment ({found[0]}{more})"]


def version_problems(plist):
    v = plist.get("Version")
    if v is None:
        return []  # a missing key is reported by the required-keys check
    if isinstance(v, bool) or not isinstance(v, int) or v < 1:
        return [f"Info.plist Version must be an integer >= 1 (got {v!r})"]
    return []


def lint_bundle(path):
    """Checks that apply to every bundle in --src, bundled or published."""
    problems = []
    plist = plistlib.loads((path / "Info.plist").read_bytes())
    problems += version_problems(plist)
    problems += template_problems((path / "template.html").read_text(encoding="utf-8"))
    problems += import_problems((path / "stylesheet.css").read_text(encoding="utf-8"))
    return problems


def duplicate_identifier_problems(entries):
    """entries: [(bundle name, ThemeIdentifier)]. One error per identifier used more than once."""
    seen = {}
    for name, ident in entries:
        if ident:
            seen.setdefault(ident, []).append(name)
    return [
        f"ThemeIdentifier {ident} is used by {len(names)} bundles: {', '.join(sorted(names))}"
        for ident, names in sorted(seen.items())
        if len(names) > 1
    ]


class GitError(Exception):
    pass


def _git(root, *args):
    """Run git in root and return stdout bytes. Raises GitError on a non-zero exit."""
    proc = subprocess.run(["git", "-C", str(root), "-c", "core.quotepath=off", *args],
                          capture_output=True)
    if proc.returncode != 0:
        raise GitError(proc.stderr.decode("utf-8", "replace").strip() or f"git {' '.join(args)} failed")
    return proc.stdout


def _nfc(text):
    return unicodedata.normalize("NFC", text)


def _bundle_of(rel_path):
    """For a repo-relative path inside a *.nnwtheme folder, return that folder's path, else None."""
    parts = rel_path.split("/")
    for i, part in enumerate(parts[:-1]):
        if part.endswith(BUNDLE_SUFFIX):
            return "/".join(parts[: i + 1])
    return None


def _plist_or_none(data):
    try:
        return plistlib.loads(data)
    except Exception:
        return None


def check_release_identity(base_ref, src_dirs, root=ROOT):
    """Compare each changed bundle against its copy at base_ref. Returns a list of problems.

    Compares the working tree with the merge-base of base_ref and HEAD. Rules, per bundle
    (a bundle that did not change cannot violate any of them):
      * ThemeIdentifier is unchanged.
      * The bundle name (the folder name, which is what the app looks themes up by) is unchanged.
        Names are compared after NFC normalization and a bundle is matched by name across the
        --src directories, so moving a bundle between Themes/ and gallery-themes/ is fine and
        re-encoding a folder name to NFC is not a rename. Info.plist's Name is not compared:
        the folder name is the authority (upstream requires Name to equal it).
      * Version is strictly greater when stylesheet.css or template.html changed.
    New bundles (no base copy by name or identifier) and deleted bundles are not checked.
    """
    root = Path(root)
    try:
        try:
            base = _git(root, "merge-base", base_ref, "HEAD").decode().strip()
        except GitError:
            base = _git(root, "rev-parse", "--verify", f"{base_ref}^{{commit}}").decode().strip()
            print(f"note  no merge-base with {base_ref}; comparing against it directly "
                  "(use a full checkout, fetch-depth: 0, for pull-request runs)")
        prefixes = []
        for d in src_dirs:
            d = Path(d).resolve()
            try:
                prefixes.append(d.relative_to(root.resolve()).as_posix())
            except ValueError:
                raise GitError(f"--src {d} is not inside the repository at {root}")
        tracked = _git(root, "ls-tree", "-r", "-z", "--name-only", base, "--", *prefixes)
        base_files = [f for f in tracked.decode("utf-8").split("\0") if f]
    except GitError as e:
        return [f"cannot read base ref {base_ref!r}: {e}"]

    # base bundles by NFC name: {name: (folder path at base, ThemeIdentifier, Version)}
    base_bundles = {}
    for folder in sorted({b for f in base_files if (b := _bundle_of(f))}):
        data = None
        try:
            data = _plist_or_none(_git(root, "show", f"{base}:{folder}/Info.plist"))
        except GitError:
            pass
        if data is not None:
            name = _nfc(folder.rsplit("/", 1)[-1][: -len(BUNDLE_SUFFIX)])
            base_bundles[name] = (folder, data.get("ThemeIdentifier"), data.get("Version"))
    base_by_id = {v[1]: n for n, v in base_bundles.items() if v[1]}

    problems = []
    for d in map(Path, src_dirs):
        if not d.is_dir():
            continue
        for path in sorted(d.glob("*" + BUNDLE_SUFFIX)):
            label = path.name
            head = _plist_or_none((path / "Info.plist").read_bytes()) if (path / "Info.plist").is_file() else None
            if head is None:
                problems.append(f"{label}: Info.plist is missing or unreadable")
                continue
            name = _nfc(bundle_stem(path))
            ident = head.get("ThemeIdentifier")
            if name not in base_bundles:
                old_name = base_by_id.get(ident)
                if old_name is not None:
                    problems.append(
                        f"{label}: bundle name changed from {old_name!r} to {name!r} "
                        f"(ThemeIdentifier {ident} is unchanged); keep the bundle name stable")
                continue  # otherwise a new bundle
            folder, base_ident, base_version = base_bundles[name]
            if ident != base_ident:
                problems.append(f"{label}: ThemeIdentifier changed from {base_ident!r} to {ident!r}")
            changed = []
            for fname in ("stylesheet.css", "template.html"):
                try:
                    old = _git(root, "show", f"{base}:{folder}/{fname}")
                except GitError:
                    old = None
                f = path / fname
                if old != (f.read_bytes() if f.is_file() else None):
                    changed.append(fname)
            if not changed:
                continue
            version = head.get("Version")
            ints = all(isinstance(v, int) and not isinstance(v, bool) for v in (version, base_version))
            if not ints:
                problems.append(f"{label}: {' and '.join(changed)} changed but Version "
                                f"({base_version!r} -> {version!r}) is not comparable integers")
            elif version <= base_version:
                problems.append(f"{label}: {' and '.join(changed)} changed but Version is "
                                f"{version} (base {base_version}); bump Info.plist Version")
    return problems


def split_imports(css):
    """Lift line-leading @import rules out (they are invalid once core.css is prepended)."""
    pat = re.compile(r"^@import\s+url\(.+?\)[^;]*;[ \t]*$", re.M)
    return "\n".join(pat.findall(css)), pat.sub("", css)


def resolve_color(css, value):
    m = re.match(r"var\((--[\w-]+)\)", value.strip())
    if m:
        d = re.search(re.escape(m.group(1)) + r"\s*:\s*([^;]+);", css)
        return d.group(1).strip() if d else value
    return value


def luminance(hex_color):
    m = re.match(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})\b", hex_color.strip())
    if not m:
        return None
    h = m.group(1)
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def light_luminance(css):
    """Background luminance of the first body rule, ignoring the dark media block."""
    light_only = re.split(r"@media\s*\(\s*prefers-color-scheme\s*:\s*dark", css)[0]
    m = re.search(r"(?m)^body\s*\{[^}]*?background(?:-color)?\s*:\s*([^;]+);", light_only)
    return luminance(resolve_color(light_only, m.group(1))) if m else None


def load_theme(path):
    problems, warnings = [], []
    plist = plistlib.loads((path / "Info.plist").read_bytes())
    for k in REQUIRED_KEYS:
        if k not in plist:
            problems.append(f"Info.plist missing {k}")
    template = (path / "template.html").read_text(encoding="utf-8")
    css = (path / "stylesheet.css").read_text(encoding="utf-8")
    if not re.search(r'id="bodyContainer"[^>]*\barticleBody\b|\barticleBody\b[^>]*id="bodyContainer"', template):
        problems.append('#bodyContainer must keep id="bodyContainer" and class "articleBody"')
    if not re.search(r"max-width:\s*100%", css):
        warnings.append("no 'max-width: 100%' media rule (overflow guard)")
    # Retired rule: the app keeps the page below the notch cover in full-screen reading, so
    # a theme needs no top clearance (docs/nnwtheme-format.md, "Full-screen reading").
    if re.search(r"Full-screen clearance|html\s*\{\s*padding-top:\s*\d+px\s*\}", css):
        warnings.append("leftover full-screen clearance rule (html padding-top); the app now keeps "
                        "the page below the notch cover, so remove it")
    imports, css = split_imports(css)
    has_dark = bool(re.search(r"prefers-color-scheme\s*:\s*dark", css))
    lum = light_luminance(css)
    if has_dark:
        tone = "both"
    else:
        tone = "dark" if (lum is not None and lum < 0.4) else "light"
    name = plist["Name"]
    return {
        "name": name,
        "id": plist.get("ThemeIdentifier", ""),
        "slug": slugify(name),
        "family": plist.get("Family"),
        "variant": plist.get("FamilyVariant"),
        "by": plist.get("CreatorName", ""),
        "home": plist.get("CreatorHomePage", ""),
        "tone": tone,
        "dark": has_dark,
        "imp": imports,
        "css": css,
        "template": template,
        "dir": path,
    }, problems, warnings


def write_zip(theme, out_dir):
    stem = bundle_stem(theme["dir"])
    dest = out_dir / "zips" / f"{stem}{BUNDLE_SUFFIX}.zip"
    dest.parent.mkdir(parents=True, exist_ok=True)
    top = f"{stem}{BUNDLE_SUFFIX}"  # the real bundle name, e.g. "Rose Pine.nnwtheme"
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
        d = zipfile.ZipInfo(top + "/", ZIP_TIME)
        d.external_attr = (0o40755 << 16) | 0x10
        z.writestr(d, b"")
        for f in sorted(theme["dir"].iterdir()):
            if f.is_file() and not f.name.startswith("."):
                zi = zipfile.ZipInfo(f"{top}/{f.name}", ZIP_TIME)
                zi.external_attr = 0o644 << 16
                zi.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(zi, f.read_bytes())
    return dest


def zip_url_path(zip_name):
    """URL path segment for a zip file name (bundle stems contain spaces, '&' and non-ASCII)."""
    return urllib.parse.quote(zip_name, safe="")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "gallery" / "dist"))
    ap.add_argument("--base-url", default=DEFAULT_BASE)
    ap.add_argument("--src", nargs="*", default=[str(ROOT / "Themes"), str(ROOT / "gallery-themes")])
    ap.add_argument("--check-release-identity", metavar="BASE_REF",
                    help="compare changed bundles with BASE_REF's copies instead of building")
    args = ap.parse_args()
    if args.check_release_identity:
        problems = check_release_identity(args.check_release_identity, args.src)
        for p in problems:
            print(f"ERROR {p}")
        if problems:
            sys.exit(1)
        print(f"release identity ok against {args.check_release_identity}")
        return
    out = Path(args.out)
    shutil.rmtree(out / "zips", ignore_errors=True)  # no stale zips from earlier builds
    out.mkdir(parents=True, exist_ok=True)

    themes, failed = [], False
    identifiers = []
    for src in map(Path, args.src):
        if not src.is_dir():
            continue
        for path in sorted(src.glob("*.nnwtheme")):
            bundled = bundle_stem(path) in BUNDLED
            for p in lint_bundle(path):
                print(f"ERROR {path.name}: {p}")
                failed = True
            if bundled:
                plist = plistlib.loads((path / "Info.plist").read_bytes())
                identifiers.append((path.name, plist.get("ThemeIdentifier", "")))
                continue
            theme, problems, warnings = load_theme(path)
            identifiers.append((path.name, theme["id"]))
            for w in warnings:
                print(f"warn  {path.name}: {w}")
            for p in problems:
                print(f"ERROR {path.name}: {p}")
                failed = True
            themes.append(theme)
    for p in duplicate_identifier_problems(identifiers):
        print(f"ERROR {p}")
        failed = True
    if failed:
        sys.exit(1)

    themes.sort(key=lambda t: t["name"].lower())
    for t in themes:
        zp = write_zip(t, out)
        t["zip"] = f"zips/{zip_url_path(zp.name)}"
        t["kb"] = round(zp.stat().st_size / 1024, 1)
        del t["dir"]

    data = {"base": args.base_url, "scheme": "nectar", "themes": themes}
    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    core = json.dumps(CORE_CSS.read_text(encoding="utf-8")).replace("</", "<\\/")
    html = TEMPLATE.read_text(encoding="utf-8").replace("__DATA__", payload).replace("__CORE__", core)
    (out / "index.html").write_text(html, encoding="utf-8")
    (out / ".nojekyll").write_text("")
    print(f"built {len(themes)} themes -> {out}")
    for t in themes:
        print(f"  {t['tone']:5} {t['name']}")


if __name__ == "__main__":
    main()
