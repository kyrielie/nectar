"""Measure computed font sizes of the pinned theme parts (docs/nnwtheme-format.md).

Renders a sample AO3 article with each bundle at the default prose size and with the
override CSS for 12px and 32px (plan section 6.2), in headless Chromium with the iOS
@supports block enabled and html at 17px. Needs `pip install playwright` and a Chromium
install. Usage: measure_theme_sizes.py BUNDLE_DIR...  (prints JSON), or
`measure_theme_sizes.py compare OLD_ROOT NEW_ROOT GLOB` to compare a migrated tree with
its pre-migration copy (default sizes must match; pinned parts must not follow the slider).
"""
import glob, json, os, re, sys
from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORE = os.path.join(ROOT, "Shared", "Article Rendering", "core.css")
BODY = """
<div id="ao3Preface"><dl class='tags'><dt>Rating:</dt><dd><a href="#">General Audiences</a></dd><dt>Fandom:</dt><dd><a href="#">Some Fandom</a></dd><dt class='wide'>Series:</dt><dd class='wide'><span class='ao3SeriesPrefaceEntry'>Part 1 of S</span> <span class='ao3SeriesPrefaceLinks'><a href="#">Next</a></span></dd></dl></div>
<div id="workskin"><div class="preface group"><div class="summary module"><h3 class="heading">Summary:</h3><blockquote class="userstuff"><p>Summary text here.</p></blockquote></div><div class="notes module"><h3 class="heading">Notes:</h3><blockquote class="userstuff"><p>Notes text.</p></blockquote></div></div>
<div id="chapters"><div class="chapter preface group"><h2 class="heading">Chapter 1</h2></div><div class="userstuff module"><p>Prose paragraph one with enough words to wrap across a line or two on a phone sized viewport for measuring.</p><p>Second paragraph.</p></div></div>
<div class="end notes module"><h3 class="heading">Notes:</h3><blockquote class="userstuff"><p>End notes.</p></blockquote></div></div>
<div id="ao3SeriesFooter"><p class='ao3SeriesFooterHeading'>This work is part of a series:</p><div class='ao3SeriesFooterEntry'><span class='ao3SeriesFooterName'>Part 1 of S</span><span class='ao3SeriesFooterLinks'><a href="#">Next</a></span></div></div>
"""
SEL = {
 "title": "h1", "byline": ".byline, .by, .headerTable td.header, .rh", "dateline": ".articleDateline, .articleDatelineTitle, .dateline, .dl",
 "preface_dd": "#ao3Preface dd", "preface_dt": "#ao3Preface dt", "heading": "h2.heading", "prose": "#chapters p",
 "summary_p": ".summary.module p", "notes_p": ".notes.module p", "series": ".ao3SeriesFooterLinks", "series_footer": "#ao3SeriesFooter",
}

def build(bundle, override=""):
    css = open(os.path.join(bundle, "stylesheet.css")).read()
    tpl = open(os.path.join(bundle, "template.html")).read()
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    css = re.sub(r"@import\s+url\([^)]*\)\s*;", "", css)
    css = css.replace("@supports (-webkit-touch-callout: none)", "@supports (display:block)")
    css = css.replace("@supports not (-webkit-touch-callout: none)", "@supports not (display:block)")
    css = css.replace("-apple-system-body", "17px sans-serif").replace("[[font-size]]", "17")
    tpl = re.sub(r"<!--.*?-->", "", tpl, flags=re.S)
    def fill(mo):
        k = mo.group(1)
        return {"body": BODY, "dateline_style": "articleDateline", "text_size_class": "", "title": "A Title", "byline": "by Author"}.get(k, "x")
    html = re.sub(r"\[\[(\w+)\]\]", fill, tpl)
    page = "<!doctype html><html><head><meta name=viewport content='width=device-width'><style>html{font-size:17px}\n%s\n%s\n%s</style></head><body>%s</body></html>" % (
        open(CORE).read(), css, override, html)
    return page

CONDS = {
 "default": "",
 "p12": ":root{--nnw-prose-size:12px} body,.articleBody{font-size:12px!important}",
 "p32": ":root{--nnw-prose-size:32px} body,.articleBody{font-size:32px!important}",
}

def measure(bundles):
    out = {}
    with sync_playwright() as p:
        b = p.chromium.launch(); pg = b.new_page(viewport={"width": 390, "height": 844})
        for bundle in bundles:
            res = {}
            for cond, ov in CONDS.items():
                pg.set_content(build(bundle, ov))
                res[cond] = pg.evaluate("""(sel)=>{const o={};for(const k in sel){const e=document.querySelector(sel[k]);o[k]=e?parseFloat(getComputedStyle(e).fontSize):null}return o}""", SEL)
            out[bundle] = res
        b.close()
    return out



PINNED=["title","byline","dateline","preface_dd","preface_dt","heading","series","series_footer"]
def run_compare(old_root, new_root, names):
    olds=[f"{old_root}/{n}" for n in names]; news=[f"{new_root}/{n}" for n in names]
    mo=measure(olds); mn=measure(news)
    bad_default=[]; bad_pin=[]
    for n,o,w in zip(names,olds,news):
        for k in PINNED:
            a=mo[o]["default"][k]; b=mn[w]["default"][k]
            if a is None and b is None: continue
            if a is None or b is None or abs(a-b)>0.6: bad_default.append((n,k,a,b))
            for c in ("p12","p32"):
                x=mn[w][c][k]
                if x is None: continue
                # pinned parts must not shrink with slider; title/heading may grow past floor
                if k in("title","heading"):
                    if x+0.01<b: bad_pin.append((n,k,c,b,x))
                else:
                    if abs(x-b)>0.01: bad_pin.append((n,k,c,b,x))
    return bad_default,bad_pin
def compare_main(old,new,pat):
    names=sorted(os.path.relpath(p,new) for p in glob.glob(f"{new}/{pat}"))
    bd,bp=run_compare(old,new,names)
    print(len(names),"bundles; default mismatches",len(bd),"; pin violations",len(bp))
    for x in bd[:40]: print("D",x)
    for x in bp[:40]: print("P",x)


if __name__ == "__main__":
    if sys.argv[1:2] == ["compare"]:
        compare_main(*sys.argv[2:5])
    else:
        print(json.dumps(measure(sys.argv[1:]), indent=1))
