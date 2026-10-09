#!/usr/bin/env python3
"""Verify a migrated bundle against its pre-migration copy (WP5, plan section 6.2).

For each named bundle, renders the sample article from OLD_ROOT and NEW_ROOT in headless
Chromium (html at 17px, iOS block on, light and dark) and checks:

1. At the default prose size every element's computed font size matches the old tree.
2. At the default prose size every element's computed color and background color matches.
3. In the new tree, with the override CSS for a 12px and a 32px prose size, nothing outside
   the prose, summary and notes changes size: the page chrome, the preface and the series
   footer stay fixed, and the title and chapter headings never shrink (they may grow once
   the prose passes their floor).

Usage: verify_theme_contract_sizes.py OLD_ROOT NEW_ROOT NAME...
where NAME is a bundle directory relative to the roots, e.g. gallery-themes/Aldine.nnwtheme.
"""
import os
import sys

import measure_theme_sizes as M
from playwright.sync_api import sync_playwright

JS = """()=>{
 const TITLE='h1,.articleTitle,.kelmscottTitle,.ar-title,.sc-title,.letter-title';
 const out=[];
 for(const e of document.body.querySelectorAll('*')){
  if(e.closest('svg')||e.tagName==='SCRIPT') continue;
  const cs=getComputedStyle(e);
  let kind='chrome';
  if(e.closest('#ao3Preface,#ao3SyntheticPreface,#ao3SeriesFooter')) kind='pinned';
  else if(e.closest('h2.heading,h3.title')) kind='grows';
  else if(e.closest('#bodyContainer')) kind='prose';
  else if(e.closest(TITLE)) kind='grows';
  const label=e.tagName.toLowerCase()+(e.id?'#'+e.id:'')+(e.classList.length?'.'+[...e.classList].join('.'):'');
  out.push({label,kind,size:parseFloat(cs.fontSize),color:cs.color,bg:cs.backgroundColor});
 }
 return out;}"""


def render(page, bundle, override=""):
    page.set_content(M.build(bundle, override))
    return page.evaluate(JS)


def main(old, new, names):
    problems = 0
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        for name in names:
            for scheme in ("light", "dark"):
                page = browser.new_page(viewport={"width": 390, "height": 844}, color_scheme=scheme)
                a = render(page, os.path.join(old, name))
                b = render(page, os.path.join(new, name))
                p12 = render(page, os.path.join(new, name), M.CONDS["p12"])
                p32 = render(page, os.path.join(new, name), M.CONDS["p32"])
                page.close()
                if len(a) != len(b):
                    print("%s [%s]: element count differs (%d vs %d)" % (name, scheme, len(a), len(b)))
                    problems += 1
                    continue
                for i, (x, y) in enumerate(zip(a, b)):
                    if abs(x["size"] - y["size"]) > 0.6:
                        print("%s [%s] SIZE %s: %.2f -> %.2f" % (name, scheme, x["label"], x["size"], y["size"]))
                        problems += 1
                    if x["color"] != y["color"] or x["bg"] != y["bg"]:
                        print("%s [%s] COLOR %s: %s/%s -> %s/%s" % (name, scheme, x["label"], x["color"], x["bg"], y["color"], y["bg"]))
                        problems += 1
                    d = b[i]["size"]
                    for tag, other in (("p12", p12[i]), ("p32", p32[i])):
                        kind, s = b[i]["kind"], other["size"]
                        if kind in ("chrome", "pinned") and abs(s - d) > 0.01:
                            print("%s [%s] %s %s %s %s: %.2f -> %.2f (should be fixed)" % (name, scheme, tag, kind, "", b[i]["label"], d, s))
                            problems += 1
                        elif kind == "grows" and s + 0.01 < d:
                            print("%s [%s] %s %s shrank: %.2f -> %.2f" % (name, scheme, tag, b[i]["label"], d, s))
                            problems += 1
            print("%s: checked" % name)
        browser.close()
    print("problems: %d" % problems)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3:]))
