#!/usr/bin/env python3
"""Build the Nectar theme gallery (static site for GitHub Pages).

    python3 gallery/build.py [--out gallery/dist] [--base-url URL] [--src DIR ...]

For every .nnwtheme bundle found in the --src directories (default: Themes/ and
gallery-themes/) that is not listed in BUNDLED, this:
  1. validates the constraints from docs/nnwtheme-format.md,
  2. writes dist/zips/<slug>.nnwtheme.zip (folder inside keeps the real bundle
     name, because the app derives the theme name from that folder),
  3. writes dist/index.html with every theme's CSS/template inlined, so the page
     needs no fetches and also works when opened straight from disk.

Standard library only.
"""
import argparse
import base64
import json
import plistlib
import re
import shutil
import sys
import unicodedata
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE_CSS = ROOT / "Shared" / "Article Rendering" / "core.css"
TEMPLATE = Path(__file__).resolve().parent / "index.template.html"
FONTS = Path(__file__).resolve().parent / "fonts"

# Themes that stay inside the app and are never published to the gallery.
# Promenade is a hard dependency (see the fallback comment near
# AppDefaults.swift:2265). Biblioteca, Appanoose, Hyperlegible, Sepia and
# Verdana Revival are the NetNewsWire starter themes; NewsFax is Stuart
# Breckenridge's. Anything not listed here is published to the gallery.
BUNDLED = {"Appanoose", "Biblioteca", "Hyperlegible", "NewsFax", "Promenade", "Sepia", "Verdana Revival"}
# Any bundle whose ThemeIdentifier starts with one of these is also excluded,
# so a new NetNewsWire starter theme added to Themes/ is skipped automatically.
BUNDLED_ID_PREFIXES = ("com.netnewswire.themes.",)

DEFAULT_BASE = "https://kyrielie.github.io/nectar/themes/"
REQUIRED_KEYS = ("Name", "ThemeIdentifier", "CreatorHomePage", "CreatorName", "Version")
ZIP_TIME = (2026, 1, 1, 0, 0, 0)


def slugify(name):
    ascii_name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", ascii_name.lower()).strip("-")


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
    dest = out_dir / "zips" / f"{theme['slug']}.nnwtheme.zip"
    dest.parent.mkdir(parents=True, exist_ok=True)
    top = f"{theme['dir'].name}"  # real bundle name, e.g. "Ros\u00e9 Pine.nnwtheme"
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


def font_css():
    """Inline the OFL webfonts as data URIs so the page stays a single file."""
    faces = []
    for style in ("normal", "italic"):
        f = FONTS / f"sorts-mill-goudy-latin-400-{style}.woff2"
        b64 = base64.b64encode(f.read_bytes()).decode()
        faces.append(
            "@font-face{font-family:'Sorts Mill Goudy';font-style:%s;font-weight:400;font-display:swap;"
            "src:url(data:font/woff2;base64,%s) format('woff2')}" % (style, b64)
        )
    return "\n".join(faces)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "gallery" / "dist"))
    ap.add_argument("--base-url", default=DEFAULT_BASE)
    ap.add_argument("--src", nargs="*", default=[str(ROOT / "Themes"), str(ROOT / "gallery-themes")])
    args = ap.parse_args()
    out = Path(args.out)
    shutil.rmtree(out / "zips", ignore_errors=True)  # no stale zips from earlier builds
    out.mkdir(parents=True, exist_ok=True)

    themes, failed = [], False
    for src in map(Path, args.src):
        if not src.is_dir():
            continue
        for path in sorted(src.glob("*.nnwtheme")):
            if path.name[: -len(".nnwtheme")] in BUNDLED:
                continue
            theme, problems, warnings = load_theme(path)
            if theme["id"].startswith(BUNDLED_ID_PREFIXES):
                print(f"skip  {path.name}: bundled by identifier ({theme['id']})")
                continue
            for w in warnings:
                print(f"warn  {path.name}: {w}")
            for p in problems:
                print(f"ERROR {path.name}: {p}")
                failed = True
            themes.append(theme)
    if failed:
        sys.exit(1)

    themes.sort(key=lambda t: t["name"].lower())
    for t in themes:
        zp = write_zip(t, out)
        t["zip"] = f"zips/{zp.name}"
        t["kb"] = round(zp.stat().st_size / 1024, 1)
        del t["dir"]

    data = {"base": args.base_url, "scheme": "nectar", "themes": themes}
    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    core = json.dumps(CORE_CSS.read_text(encoding="utf-8")).replace("</", "<\\/")
    html = TEMPLATE.read_text(encoding="utf-8").replace("__DATA__", payload).replace("__CORE__", core).replace("__FONTS__", font_css())
    (out / "index.html").write_text(html, encoding="utf-8")
    (out / ".nojekyll").write_text("")
    print(f"built {len(themes)} themes -> {out}")
    for t in themes:
        print(f"  {t['tone']:5} {t['name']}")


if __name__ == "__main__":
    main()
