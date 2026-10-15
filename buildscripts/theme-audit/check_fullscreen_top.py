#!/usr/bin/env python3
"""Measures how far down the first title line and the first painted content sit in every theme.

In full-screen reading the web view starts at the top edge of the screen and
`notchCoverView` paints the theme's page color over the top inset (about 62pt on
current iPhones). Anything above that line is hidden. docs/nnwtheme-format.md
("Full-screen reading: space above the title") requires 68px above the title.

  python3 buildscripts/theme-audit/check_fullscreen_top.py [DIR_OR_BUNDLE ...]
      [--cover 62] [--min-title 68] [--json out.json] [--markdown out.md]
      [--chromium /path/to/chromium]

With no paths it audits Themes/ and gallery-themes/. Needs Playwright and a
Chromium (`pip install playwright && playwright install chromium`, or pass
--chromium). Fonts are @imported from Google Fonts in the real app; here the
@import lines are dropped and system fonts are used, so line counts are
approximate while the distance from the top is mostly layout and holds.

Per theme and scenario it reports:
  title_top      top of the first line of the title, px from the top of the page
  content_top    top of the first painted thing (text, background, border, svg, img,
                 pseudo-element host). Approximate: a pseudo-element is measured at
                 its host element's top.
  title_top_nohd the title position with the running head (anything before the title that
                 holds feed link, date or byline tokens) hidden, to show whether the head
                 is what supplies the clearance.
Statuses: FAIL (no title, title above --min-title, or not hit-testable); HEAD-CUT (the title
clears --min-title but a running head starts above --cover, so it is partly or wholly under
the notch cover); ORNAMENT-CUT (no running head, but other painted content starts above
--cover); OK. Bundles listed in buildscripts/theme-audit/intentional-bleed.txt are reported as
BLEED instead of HEAD-CUT or ORNAMENT-CUT. Exit status is 1 when any theme FAILs.
"""
import argparse, json, plistlib, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "Shared/Article Rendering/core.css"
DEFAULT_TEMPLATE = ROOT / "Shared/Article Rendering/template.html"
DEFAULT_CSS = ROOT / "Shared/Article Rendering/stylesheet.css"
BLEED_FILE = Path(__file__).with_name("intentional-bleed.txt")

BODY = "".join(
    f"<p>Paragraph {i}. The quick brown fox jumps over the lazy dog while the committee reviews the minutes of the previous meeting at length.</p>"
    for i in range(1, 7)
)
BODY = "<h2>First chapter</h2>" + BODY
TITLES = {
    "short": "A Quiet Morning",
    "long": "The Unabridged and Remarkably Lengthy Account of a Voyage Across the Northern Sea",
}
MACRO = re.compile(r"\[\[([A-Za-z0-9_-]+)\]\]")
IMPORT = re.compile(r"@import\s+(?:url\([^)]*\)|\"[^\"]*\"|'[^']*')[^;]*;", re.I)

JS = r"""
(opts) => {
  const title = document.querySelector('.articleTitle') || document.querySelector('h1') || document.querySelector('[class$="Title"]');
  if (!title) return {error: 'no title element'};
  const range = document.createRange(); range.selectNodeContents(title);
  const rects = Array.from(range.getClientRects()).filter(r => r.width > 0 && r.height > 0);
  if (!rects.length) return {error: 'title has no box'};
  const titleTop = Math.min(...rects.map(r => r.top)) + window.scrollY;
  const first = rects[0];
  const pts = [0.15, 0.5, 0.85].map(f => [first.left + first.width * f, first.top + first.height / 2]);
  let hit = 0;
  for (const [x, y] of pts) {
    if (x < 0 || x >= innerWidth || y < 0 || y >= innerHeight) continue;
    if (document.elementsFromPoint(x, y).some(e => title.contains(e) || e.contains(title) && e === title)) hit++;
  }
  const sideOut = rects.some(r => r.left < -1 || r.right > innerWidth + 1);
  const hasAlpha = c => { const m = c.match(/rgba?\(([^)]+)\)/); if (!m) return false; const p = m[1].split(/[ ,\/]+/).filter(Boolean); return p.length < 4 || parseFloat(p[3]) > 0.02; };
  let contentTop = Infinity;
  const consider = (top) => { if (isFinite(top) && top < contentTop) contentTop = top; };
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let n; while ((n = walker.nextNode())) {
    if (!n.nodeValue.trim()) continue;
    const r = document.createRange(); r.selectNodeContents(n);
    for (const b of r.getClientRects()) if (b.width > 0 && b.height > 0) consider(b.top + scrollY);
  }
  for (const el of document.body.querySelectorAll('*')) {
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity) === 0) continue;
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 1) continue;
    const isAncestor = el.contains(title);
    const border = ['Top'].some(s => parseFloat(cs['border' + s + 'Width']) > 0 && cs['border' + s + 'Style'] !== 'none');
    const bg = cs.backgroundImage !== 'none' || hasAlpha(cs.backgroundColor);
    const shadow = cs.boxShadow !== 'none';
    const media = ['SVG', 'IMG', 'HR', 'CANVAS', 'VIDEO'].includes(el.tagName.toUpperCase());
    const pseudo = ['::before', '::after'].some(p => { const c = getComputedStyle(el, p).content; return c && c !== 'none' && c !== 'normal'; });
    // A wrapper that holds the title paints the page; only its own top border counts.
    if (isAncestor) { if (border) consider(r.top + scrollY); continue; }
    if (bg || border || shadow || media || pseudo) consider(r.top + scrollY);
  }
  return {titleTop, lines: rects.length, hit, sideOut, contentTop: isFinite(contentTop) ? contentTop : null,
          titleCss: (() => { const c = getComputedStyle(title); return {lineHeight: c.lineHeight, fontSize: c.fontSize, overflow: c.overflow, whiteSpace: c.whiteSpace, textOverflow: c.textOverflow}; })()};
}
"""

HIDE_HEAD = r"""
() => {
  const title = document.querySelector('.articleTitle') || document.querySelector('h1') || document.querySelector('[class$="Title"]');
  if (!title) return {n: 0};
  const marks = /@@(FEED|DATE|BYLINE)@@/;
  let hidden = 0, top = Infinity, bottom = -Infinity;
  const all = Array.from(document.body.querySelectorAll('*'));
  for (const el of all) {
    if (el.contains(title) || title.contains(el)) continue;
    if (!(title.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_PRECEDING)) continue;
    if (!marks.test(el.textContent || '')) continue;
    // hide the outermost such element (skip ones inside an already hidden one)
    if (el.closest('[data-hid]')) continue;
    const r = el.getBoundingClientRect();
    if (r.height > 0) { top = Math.min(top, r.top + scrollY); bottom = Math.max(bottom, r.bottom + scrollY); }
    el.setAttribute('data-hid', '1'); el.style.display = 'none'; hidden++;
  }
  return {n: hidden, top: isFinite(top) ? top : null, bottom: isFinite(bottom) ? bottom : null};
}
"""

REMOVE_EMPTY_LINKS = r"""
() => { for (const l of Array.from(document.querySelectorAll('a[href]'))) { if (!l.getAttribute('href').trim() || l.textContent.trim()) continue; const nx = l.nextSibling; l.remove(); if (nx && nx.nodeName === 'BR') nx.remove(); } }
"""


def render(template, mapping):
    return MACRO.sub(lambda m: mapping.get(m.group(1), ""), template)


def bundles(paths):
    out = []
    for p in paths:
        p = Path(p)
        if (p / "template.html").exists() or (p / "stylesheet.css").exists() or p.suffix == ".nnwtheme":
            out.append(p)
        else:
            out += sorted(x for x in p.glob("*.nnwtheme"))
    return out


def page(bundle, scenario, mark=False):
    tpl = (bundle / "template.html")
    tpl = tpl.read_text(encoding="utf-8") if tpl.exists() else DEFAULT_TEMPLATE.read_text(encoding="utf-8")
    css = (bundle / "stylesheet.css")
    css = css.read_text(encoding="utf-8") if css.exists() else DEFAULT_CSS.read_text(encoding="utf-8")
    css = IMPORT.sub("", css)
    # Chromium does not match the iOS-only feature query, so force the iOS branch (the app's
    # web view is WKWebView) and drop the macOS one, which adds body padding the app never has.
    css = re.sub(r"@supports\s+not\s*\(\s*-webkit-touch-callout\s*:\s*none\s*\)", "@media not all", css)
    css = re.sub(r"@supports\s*\(\s*-webkit-touch-callout\s*:\s*none\s*\)", "@media all", css)
    css = render(css, {"font-size": "17"})
    feed = scenario["feed"]
    byline = scenario["byline"]
    m = {
        "title": TITLES[scenario["title"]], "preferred_link": "https://example.com/post",
        "body": BODY, "byline": ("@@BYLINE@@" if mark and byline else byline),
        "feed_link": "https://example.com/feed",
        "feed_link_title": ("@@FEED@@" if mark and feed else feed),
        "date_medium": "@@DATE@@" if mark else "Oct 14, 2026", "date_long": "@@DATE@@" if mark else "October 14, 2026",
        "date_short": "@@DATE@@" if mark else "10/14/26", "datetime_long": "2026-10-14", "datetime_medium": "2026-10-14",
        "datetime_short": "2026-10-14", "time_medium": "12:00 PM", "time_long": "12:00 PM", "time_short": "12:00 PM",
        "avatar_src": "", "dateline_style": "articleDateline", "external_link_label": "", "external_link_stripped": "",
        "external_link": "",
    }
    html = render(tpl, m)
    return ("<!doctype html><html><head><meta charset=utf-8>"
            "<meta name=viewport content='width=device-width,initial-scale=1'><style>"
            + CORE.read_text(encoding="utf-8") + "\n" + css + "</style></head><body>" + html + "</body></html>")


SCENARIOS = [
    {"name": "app-default", "title": "short", "feed": "", "byline": "Jane Author"},
    {"name": "feed-on", "title": "short", "feed": "Example Feed", "byline": "Jane Author"},
    {"name": "long-title", "title": "long", "feed": "Example Feed", "byline": "Jane Author"},
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--cover", type=float, default=62)
    ap.add_argument("--min-title", type=float, default=68)
    ap.add_argument("--json")
    ap.add_argument("--markdown")
    ap.add_argument("--chromium")
    ap.add_argument("--width", type=int, default=393)
    ap.add_argument("--only", help="substring filter on bundle name")
    a = ap.parse_args()
    from playwright.sync_api import sync_playwright
    paths = a.paths or [ROOT / "Themes", ROOT / "gallery-themes"]
    items = bundles(paths)
    if a.only:
        items = [b for b in items if a.only.lower() in b.name.lower()]
    bleed = set()
    if BLEED_FILE.exists():
        bleed = {l.strip() for l in BLEED_FILE.read_text().splitlines() if l.strip() and not l.startswith("#")}
    launch = {"args": ["--no-sandbox", "--disable-gpu"]}
    if a.chromium:
        launch["executable_path"] = a.chromium
        launch["args"] += ["--single-process", "--no-zygote"]
    results = []
    with sync_playwright() as p:
        br = p.chromium.launch(**launch)
        # One page for the whole run: a --single-process Chromium cannot open more contexts.
        pg = br.new_page(viewport={"width": a.width, "height": 852})
        for b in items:
            name = b.name.removesuffix(".nnwtheme")
            rec = {"name": name, "where": b.parent.name, "runs": {}}
            tpl_text = (b / "template.html").read_text(encoding="utf-8") if (b / "template.html").exists() else ""
            rec["template"] = {
                "feed": "[[feed_link" in tpl_text, "date": bool(re.search(r"\[\[(date|datetime)_", tpl_text)),
                "byline": "[[byline]]" in tpl_text,
            }
            for scheme in ("light", "dark"):
                pg.emulate_media(color_scheme=scheme)
                for sc in SCENARIOS:
                    pg.set_content(page(b, sc), wait_until="load")
                    pg.evaluate(REMOVE_EMPTY_LINKS)
                    r = pg.evaluate(JS, {})
                    if "error" not in r:
                        pg.set_content(page(b, sc, mark=True), wait_until="load")
                        pg.evaluate(REMOVE_EMPTY_LINKS)
                        hh = pg.evaluate(HIDE_HEAD)
                        r["head_hidden"], r["head_top"], r["head_bottom"] = hh["n"], hh.get("top"), hh.get("bottom")
                        r2 = pg.evaluate(JS, {})
                        r["title_top_nohd"] = r2.get("titleTop")
                    rec["runs"][f"{scheme}/{sc['name']}"] = r
            runs = [r for r in rec["runs"].values() if "error" not in r]
            if not runs:
                rec["status"] = "FAIL"; rec["why"] = "no title element"
            else:
                tmin = min(r["titleTop"] for r in runs)
                cmins = [r["contentTop"] for r in runs if r["contentTop"] is not None]
                cmin = min(cmins) if cmins else None
                rec.update(title_top_min=round(tmin, 1), content_top_min=None if cmin is None else round(cmin, 1))
                nohd = [r["title_top_nohd"] for r in runs if r.get("title_top_nohd") is not None]
                rec["title_top_nohd_min"] = round(min(nohd), 1) if nohd else None
                rec["head_hidden"] = max((r.get("head_hidden", 0) for r in runs), default=0)
                tops = [r["head_top"] for r in runs if r.get("head_top") is not None]
                bots = [r["head_bottom"] for r in runs if r.get("head_bottom") is not None]
                rec["head_top"] = round(min(tops), 1) if tops else None
                rec["head_bottom"] = round(max(bots), 1) if bots else None
                if rec["head_bottom"] is None:
                    rec["head_state"] = "none"
                elif rec["head_bottom"] <= a.cover:
                    rec["head_state"] = "hidden"
                elif rec["head_top"] < a.cover:
                    rec["head_state"] = "partly hidden"
                else:
                    rec["head_state"] = "visible"
                clipped = any(r["hit"] < 1 for r in runs)
                css_bad = any((r["titleCss"]["overflow"] not in ("visible",) or "nowrap" in r["titleCss"]["whiteSpace"]
                               or r["titleCss"]["textOverflow"] == "ellipsis") for r in runs)
                if tmin < a.min_title:
                    rec["status"], rec["why"] = "FAIL", f"title starts at {tmin:.0f}px"
                elif clipped:
                    rec["status"], rec["why"] = "FAIL", "title not hit-testable (clipped or covered)"
                elif cmin is not None and cmin < a.cover:
                    if name in bleed:
                        rec["status"] = "BLEED"
                    else:
                        rec["status"] = "HEAD-CUT" if rec["head_hidden"] else "ORNAMENT-CUT"
                    rec["why"] = f"painted content starts at {cmin:.0f}px, under the {a.cover:.0f}px cover"
                else:
                    rec["status"], rec["why"] = "OK", ""
                rec["css_note"] = css_bad
                rec["needs_head"] = bool(rec["head_hidden"]) and (rec["title_top_nohd_min"] or 0) < a.min_title
            results.append(rec)
            print(f"{rec['status']:6} {name:36} title {rec.get('title_top_min')}  content {rec.get('content_top_min')}  nohd {rec.get('title_top_nohd_min')}  {rec.get('why','')}", flush=True)
        br.close()
    if a.json:
        Path(a.json).write_text(json.dumps(results, indent=1))
    if a.markdown:
        lines = ["| Theme | Where | Status | Title top | Content top | Title w/o head | Head | Note |", "|---|---|---|---|---|---|---|---|"]
        for r in results:
            head = "none" if not r.get("head_hidden") else r.get("head_state", "") + (", needed for clearance" if r.get("needs_head") else ", optional")
            lines.append(f"| {r['name']} | {r['where']} | {r['status']} | {r.get('title_top_min')} | {r.get('content_top_min')} | {r.get('title_top_nohd_min')} | {head} | {r.get('why','')} |")
        Path(a.markdown).write_text("\n".join(lines) + "\n")
    fails = [r for r in results if r["status"] == "FAIL"]
    print(f"\n{len(results)} themes: " + ", ".join(f"{s} {sum(1 for r in results if r['status']==s)}" for s in ("OK", "HEAD-CUT", "ORNAMENT-CUT", "BLEED", "FAIL")))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
