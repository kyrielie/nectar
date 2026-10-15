#!/usr/bin/env python3
"""Writes the original `.nnwtheme` bundles designed from clean-room-theme-specs.md.

  python3 buildscripts/theme-generation/generate_spec_themes.py [--out gallery-themes] [--only SLUG]

Each entry in spec_themes_*.py is one design: names, palettes (light and dark), fonts and the
CSS for its signature treatment. This file supplies the shared structure (page, header, body,
AO3 blocks, iOS and macOS blocks) and writes Info.plist, template.html, stylesheet.css and
License.md. Nothing is copied from the source Tumblr themes: they are read for technique and
palette only, the layouts are reading layouts, and every bundle carries an "Inspired by" credit.

Rules every bundle here follows (docs/nnwtheme-format.md):
  * no running head and no top clearance padding: the app keeps the page below the notch cover;
  * --nnw-bg / --nnw-ink / --nnw-link are literal in :root and in the single dark :root block;
  * the @import is the first line; every font stack ends in a system fallback.
"""
import argparse, importlib, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>Name</key>
\t<string>{name}</string>
\t<key>ThemeIdentifier</key>
\t<string>com.nectar.themes.{slug}</string>
\t<key>CreatorHomePage</key>
\t<string>https://github.com/kyrielie/nectar</string>
\t<key>CreatorName</key>
\t<string>kyrielie</string>
\t<key>Version</key>
\t<integer>1</integer>
</dict>
</plist>
"""

TEMPLATE = """{top}<div class="t {cls}">
\t<header class="hd">{hd_before}
\t\t<h1 class="articleTitle"><a href="[[preferred_link]]">[[title]]</a></h1>
\t\t<p class="by">[[byline]]</p>{hd_after}
\t</header>
\t<div id="bodyContainer" class="articleBody bd [[text_size_class]]" data-versal-target data-chapter-divider data-chapter-divider-char="{divchar}" data-chapter-divider-class="dv">[[body]]</div>
</div>
"""

PAL_KEYS = ("bg", "ink", "link", "a", "s", "b", "m")


def pal_block(p, extra=""):
    return (f"--nnw-bg:{p['bg']};--nnw-ink:{p['ink']};--nnw-link:{p['link']};--a:{p['a']};--s:{p['s']};"
            f"--b:{p['b']};--m:{p['m']};" + "".join(f"--{k}:{v};" for k, v in p.items() if k not in PAL_KEYS) + extra)


BASE = """/* {name} -- original design for Nectar. {credit}
   Reading layout only; the source's palette ideas and techniques were reimplemented from the written spec.
   Palette tokens (--nnw-*) are literal in :root and in the dark block (the legacy scanner resolves var() one level). */
:root{{--fh:{fh};--fb:{fb};--font-main:var(--fh);--font-body:var(--fb);--font-code:'JetBrains Mono','Courier New',Courier,monospace;{light}}}
html{{background-color:var(--nnw-bg)}}
body{{margin:0;max-width:none;box-sizing:border-box;padding-left:max(0px,calc((100% - 44em) / 2));padding-right:max(0px,calc((100% - 44em) / 2));background-color:var(--nnw-bg);color:var(--nnw-ink);font-family:var(--fb);word-wrap:break-word}}
.articleBody{{color:var(--nnw-ink)}}
a,.articleBody a{{color:var(--nnw-link)}}
.hd a,.hd a:link,.hd a:visited,.articleBody h2.heading a,.articleBody h3.title a{{color:inherit;text-decoration:none}}
body > .systemMessage{{color:var(--nnw-ink)}}
#ao3SyntheticPreface,#ao3Preface{{margin:0;padding:0;border:0;background:none;font-size:inherit;color:inherit}}
.summary.module blockquote.userstuff,.notes.module blockquote.userstuff,.end.notes.module blockquote.userstuff{{margin:0;padding:0;border:0;background:none}}
.summary.module blockquote.userstuff p,.notes.module blockquote.userstuff p{{margin:0}}
.articleBody blockquote{{border-left:3px solid var(--a);margin-left:0;padding:.1em 1em}}
.articleBody pre,.articleBody code{{font-family:var(--font-code)}}
.articleBody pre{{overflow-x:auto}}
.articleBody table{{border-collapse:collapse}}
.articleBody td,.articleBody th{{border:1px solid var(--b);padding:.4em .6em}}
img, figure, video, div, object {{ max-width: 100%; }}
img, video {{ height: auto; }}
.smallText{{font-size:14px}}.mediumText{{font-size:16px}}.largeText{{font-size:18px}}.xlargeText{{font-size:20px}}.xxlargeText{{font-size:22px}}

/* structure: no running head; the app keeps the page below the notch cover, so no top clearance is needed */
.t{{padding:28px var(--gx) 36px;color:var(--nnw-ink);font:calc(var(--u) * 15)/1.65 var(--fb);position:relative}}
.t h1{{margin:0;font-family:var(--fh);font-weight:400;font-size:max(calc(var(--u) * 28 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.4));line-height:1.12}}
.t h2.heading,.t h3.title{{margin:0 0 8px;font-family:var(--fh);font-weight:400;font-size:max(calc(var(--u) * 20 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.2));line-height:1.2}}
.t h3.heading{{margin:0 0 4px;font-family:var(--fh);font-weight:400;font-size:calc(var(--u) * 12)}}
.hd{{position:relative;margin-bottom:18px}}
.by{{margin:8px 0 0;font-size:calc(var(--u) * 12 * var(--nnw-detail-scale, 1));letter-spacing:.05em;color:var(--m)}}
.by:empty{{display:none}}
#bodyContainer dl.tags{{display:grid;grid-template-columns:auto 1fr;gap:3px 12px;margin:0 0 14px;font-size:calc(var(--u) * 12 * var(--nnw-detail-scale, 1))}}
#bodyContainer dl.tags dt{{font-weight:700}}
#bodyContainer dl.tags dd{{margin:0}}
.summary.module{{margin:0 0 14px;padding:10px 12px}}
.summary.module h3.heading{{margin-bottom:4px}}
.dv{{display:block;margin:18px 0 8px}}
.versalCap{{font-variant:small-caps;letter-spacing:.03em}}

/* ---- {name}: signature treatment ---- */
{css}

@media (prefers-color-scheme: dark) {{
\t:root{{{dark}}}
{dark_css}}}

/* iOS Specific */
@supports (-webkit-touch-callout: none) {{
\t:root {{ --gx: 20px; --u: calc([[font-size]]px / 15); }}
\tbody {{ margin-top: 0; margin-bottom: 0; word-break: break-word; -webkit-text-size-adjust: none; font-size: [[font-size]]px; }}

\t:root {{
\t\t--ao3-series-footer-font-size: calc(var(--u) * 13.5 * var(--nnw-detail-scale, 1));
\t}}
}}
/* macOS Specific */
@supports not (-webkit-touch-callout: none) {{
\t:root {{ --gx: 48px; --u: 1px; }}
\tbody {{ margin: 0; padding-top: 0; padding-bottom: 64px; }}
}}
"""

LICENSE = """# {name}

{desc}

Original design for Nectar. {credit} It was read for technique and palette only; the layout, the copy, the names and every drawn shape are new and written from scratch as plain CSS (no code, images, icons or fonts from the source). {extra}

## Third-party assets

{fonts}

## License

License: not yet decided; set one before publishing.
"""


def family_query(fonts):
    return "&".join("family=" + f for f in fonts)


def build(t):
    imports = ""
    if t.get("fonts"):
        imports = f"@import url('https://fonts.googleapis.com/css2?{family_query(t['fonts'])}&display=swap');\n"
    css = BASE.format(
        name=t["name"], credit=t["credit"], fh=t["fh"], fb=t["fb"],
        light=pal_block(t["light"], t.get("light_extra", "")),
        dark=pal_block(t["dark"], t.get("dark_extra", "")), css=t["css"].strip("\n"),
        dark_css=("\t" + t["dark_css"].strip("\n").replace("\n", "\n\t") + "\n") if t.get("dark_css") else "")
    tpl = TEMPLATE.format(cls=t["cls"], top=t.get("top", ""), hd_before=t.get("hd_before", ""),
                          hd_after=t.get("hd_after", ""), divchar=t.get("divchar", "&#8203;"))
    fonts = "; ".join(t.get("font_credits", [])) or "System fonts only."
    if t.get("fonts"):
        fonts = "Fonts are not bundled; they load from Google Fonts at read time and keep their own licenses (" + fonts + ")."
    lic = LICENSE.format(name=t["name"], desc=t["desc"], credit=t["credit"], extra=t.get("extra", ""), fonts=fonts)
    return imports + css, tpl, PLIST.format(name=t["name"], slug=t["slug"]), lic


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "gallery-themes"))
    ap.add_argument("--only")
    a = ap.parse_args()
    themes = []
    for mod in ("spec_themes_a", "spec_themes_b", "spec_themes_c"):
        themes += importlib.import_module(mod).THEMES
    names = [t["name"] for t in themes]
    slugs = [t["slug"] for t in themes]
    classes = [t["cls"] for t in themes]
    assert len(set(names)) == len(names) and len(set(slugs)) == len(slugs) and len(set(classes)) == len(classes)
    for t in themes:
        if a.only and a.only != t["slug"]:
            continue
        css, tpl, plist, lic = build(t)
        d = Path(a.out) / f"{t['name']}.nnwtheme"
        d.mkdir(parents=True, exist_ok=True)
        (d / "stylesheet.css").write_text(css, encoding="utf-8")
        (d / "template.html").write_text(tpl, encoding="utf-8")
        (d / "Info.plist").write_text(plist, encoding="utf-8")
        (d / "License.md").write_text(lic, encoding="utf-8")
        print("wrote", d)
    return 0


if __name__ == "__main__":
    sys.exit(main())
