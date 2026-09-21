#!/usr/bin/env python3
"""Builds the Nectar landing page into a single self-contained index.html.

    python3 landing/build.py [--out landing/dist] [--config landing/site.json]

Inputs
  landing/template.html   the page; {{tokens}} and <!--?key-->...<!--/?key--> blocks
  landing/site.json       editable facts and optional content
  landing/frieze.html     the flower band, shared look with the theme gallery
  landing/texture.txt     the paper-grain background url()
  appstore/source.template.json
                          screenshot URLs and icon URL are read from here, so the
                          page always matches what the AltStore source ships.

Optional sections (demo video, testimonials, community links, tip link, changelog,
install screenshots, press contact, min iOS FAQ entry) are removed from the page
whenever their config value is empty. Nothing is invented: a section shows only
when site.json has content for it.
"""

import argparse
import html
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

LINK = re.compile(r"\[([^\]]+)\]\((https://[^)\s]+)\)")


def esc(value):
    return html.escape(str(value), quote=True)


def inline(text):
    """Escape text, turning [label](https://url) into links. Nothing else is markup."""
    out, pos = [], 0
    for m in LINK.finditer(text):
        out.append(esc(text[pos:m.start()]))
        out.append(f'<a href="{esc(m.group(2))}">{esc(m.group(1))}</a>')
        pos = m.end()
    out.append(esc(text[pos:]))
    return "".join(out)


class Fmt(dict):
    def __missing__(self, key):
        return ""


def fail(msg):
    sys.exit(f"landing/build.py: {msg}")


def need_https(label, url):
    if not isinstance(url, str) or not url.startswith("https://"):
        fail(f"{label} must be an https:// URL, got {url!r}")
    return url


def load_config(path):
    cfg = json.loads(Path(path).read_text(encoding="utf-8"))
    for key in ("site_url", "repo_url", "source_url", "themes_url"):
        need_https(key, cfg.get(key, ""))
    for key in ("demo_video", "demo_poster", "og_image", "tip_url"):
        if cfg.get(key):
            need_https(key, cfg[key])
    for item in cfg.get("community", []):
        need_https("community url", item.get("url", ""))
        if not item.get("name"):
            fail("every community entry needs a name")
    for item in cfg.get("testimonials", []):
        if not item.get("quote") or not item.get("name"):
            fail("every testimonial needs a quote and a name")
        if item.get("url"):
            need_https("testimonial url", item["url"])
    for item in cfg.get("install_step_images", []):
        need_https("install_step_images src", item.get("src", ""))
        if not item.get("alt"):
            fail("every install_step_images entry needs alt text")
    for item in cfg.get("changelog", []):
        if not item.get("version") or not isinstance(item.get("notes"), list):
            fail("every changelog entry needs a version and a notes list")
    if cfg.get("press_contact") and "@" not in cfg["press_contact"]:
        fail("press_contact must be an email address")
    return cfg


def load_store():
    src = json.loads((ROOT / "appstore" / "source.template.json").read_text(encoding="utf-8"))
    app = src["apps"][0]
    shots = app["screenshots"]
    if not shots:
        fail("source.template.json lists no screenshots")
    return app["iconURL"], shots


def conditionals(text, flags):
    pat = re.compile(r"<!--\?(\w+)-->(.*?)<!--/\?\1-->", re.S)
    for key in set(re.findall(r"<!--\?(\w+)-->", text)):
        if key not in flags:
            fail(f"template uses unknown conditional {key!r}")
    while True:
        new = pat.sub(lambda m: m.group(2) if flags[m.group(1)] else "", text)
        if new == text:
            return text
        text = new


def build(cfg):
    icon, shots = load_store()
    repo = cfg["repo_url"].rstrip("/")
    slug = repo.split("github.com/", 1)[1] if "github.com/" in repo else ""
    if not slug:
        fail("repo_url must be a github.com URL")
    alt_url = "https://altdirect.app/?url=" + cfg["source_url"]
    site = cfg["site_url"]

    # FAQ, skipping entries whose required config value is empty
    fmt = Fmt({k: v for k, v in cfg.items() if isinstance(v, str)})
    faq = []
    for item in cfg.get("faq", []):
        req = item.get("requires")
        if req and not cfg.get(req):
            continue
        answer = item["a"].format_map(fmt).strip()
        faq.append(
            f'<details><summary>{esc(item["q"])}</summary><div class="a">{inline(answer)}</div></details>\n'
        )

    reel = "".join(
        f'<figure class="shot"><img src="{esc(u)}" alt="Nectar app screenshot {i} of {len(shots)}" '
        f'width="250" loading="lazy" decoding="async"></figure>\n'
        for i, u in enumerate(shots[1:], 2)
    )
    install_reel = "".join(
        '<figure class="shot"><img src="%s" alt="%s" width="250" loading="lazy" decoding="async">%s</figure>\n'
        % (esc(i["src"]), esc(i["alt"]), f'<figcaption>{esc(i["caption"])}</figcaption>' if i.get("caption") else "")
        for i in cfg.get("install_step_images", [])
    )

    testimonials = ""
    for t in cfg.get("testimonials", []):
        who = esc(t["name"])
        if t.get("url"):
            who = f'<a href="{esc(t["url"])}">{who}</a>'
        testimonials += f'<blockquote><p>\u201c{esc(t["quote"])}\u201d</p><cite>{who}</cite></blockquote>\n'

    community = ""
    if cfg.get("community"):
        community = "<ul>" + "".join(
            f'<li><a href="{esc(c["url"])}">{esc(c["name"])}</a></li>' for c in cfg["community"]
        ) + "</ul>"

    changelog = ""
    for e in cfg.get("changelog", []):
        when = f" <small>{esc(e['date'])}</small>" if e.get("date") else ""
        items = "".join(f"<li>{inline(n)}</li>" for n in e["notes"])
        changelog += f"<h4>{esc(e['version'])}{when}</h4><ul>{items}</ul>\n"

    press = ", ".join(
        [f'<a href="{esc(icon)}">icon</a>']
        + [f'<a href="{esc(u)}">screenshot {i}</a>' for i, u in enumerate(shots, 1)]
    )

    fine = "Free and open source. Beta software. Not on the App Store: you sideload it."
    if cfg.get("min_ios"):
        fine += f" Requires {cfg['min_ios']}."
    install_sub = "Nectar is sideloaded. AltStore is the way I test."
    if cfg.get("install_time"):
        install_sub += f" Allow about {cfg['install_time']}."

    og_image = cfg.get("og_image") or icon
    ld = {
        "@context": "https://schema.org",
        "@type": "MobileApplication",
        "name": "Nectar",
        "description": cfg["description"],
        "url": site,
        "operatingSystem": "iOS",
        "applicationCategory": "Entertainment",
        "isAccessibleForFree": True,
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
    }

    nav_items = []
    if cfg.get("demo_video"):
        nav_items.append(("demo", "Watch"))
    nav_items += [("features", "Features"), ("themes", "Themes"), ("faq", "Questions"),
                  ("install", "Install"), ("support", "Help")]
    nav = "".join(f'<a href="#{i}">{l}</a>' for i, l in nav_items) + f'<a href="{esc(repo)}">GitHub</a>'

    flags = {
        "demo_video": bool(cfg.get("demo_video")),
        "demo_poster": bool(cfg.get("demo_poster")),
        "testimonials": bool(cfg.get("testimonials")),
        "community": bool(cfg.get("community")),
        "tip_url": bool(cfg.get("tip_url")),
        "press_contact": bool(cfg.get("press_contact")),
        "changelog": bool(cfg.get("changelog")),
        "install_step_images": bool(cfg.get("install_step_images")),
    }

    vals = {
        "description": esc(cfg["description"]),
        "site_url": esc(site),
        "og_image": esc(og_image),
        "og_image_alt": "Nectar" + (" app icon" if og_image == icon else ""),
        "twitter_card": "summary_large_image" if cfg.get("og_image") else "summary",
        "icon_url": esc(icon),
        "jsonld": json.dumps(ld, ensure_ascii=False).replace("</", "<\\/"),
        "texture": (HERE / "texture.txt").read_text(encoding="utf-8").strip(),
        "frieze": (HERE / "frieze.html").read_text(encoding="utf-8").strip(),
        "nav": nav,
        "alt_url": esc(alt_url),
        "repo_url": esc(repo),
        "repo_slug": esc(slug),
        "source_url": esc(cfg["source_url"]),
        "themes_url": esc(cfg["themes_url"]),
        "hero_fine": esc(fine),
        "shot1": esc(shots[0]),
        "shot_count": str(len(shots)),
        "reel": reel,
        "install_reel": install_reel,
        "install_sub": esc(install_sub),
        "faq": "".join(faq),
        "testimonials": testimonials,
        "community": community,
        "changelog": changelog,
        "press": press,
        "demo_video": esc(cfg.get("demo_video", "")),
        "demo_poster": esc(cfg.get("demo_poster", "")),
        "demo_caption": esc(cfg.get("demo_caption", "")),
        "tip_url": esc(cfg.get("tip_url", "")),
        "tip_label": esc(cfg.get("tip_label") or "Support development"),
        "press_contact": esc(cfg.get("press_contact", "")),
    }

    page = conditionals((HERE / "template.html").read_text(encoding="utf-8"), flags)
    missing = sorted(set(re.findall(r"\{\{(\w+)\}\}", page)) - set(vals))
    if missing:
        fail(f"template uses unknown tokens: {missing}")
    # Substitute in one pass so values containing {{...}} are never re-expanded.
    return re.sub(r"\{\{(\w+)\}\}", lambda m: vals[m.group(1)], page)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=str(HERE / "dist"))
    ap.add_argument("--config", default=str(HERE / "site.json"))
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    page = build(load_config(args.config))
    (out / "index.html").write_text(page, encoding="utf-8")
    print(f"built landing page -> {out / 'index.html'} ({len(page) // 1024} KB)")


if __name__ == "__main__":
    main()
