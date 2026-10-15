"""Designs 1 to 10 from clean-room-theme-specs.md (Part A, wovenstarlight themes 1 to 10)."""
from spec_common import mods, emph, dropcap

SANS = "-apple-system,BlinkMacSystemFont,'Segoe UI',system-ui,sans-serif"
SERIF = "Georgia,'Times New Roman',serif"
CREDIT = "Inspired by *{src}* by *{who}* (a Tumblr theme)."


def credit(src, who="wovenstarlight"):
    return f"Inspired by *{src}* by *{who}*."


THEMES = []

# 1 Discord -> chat-app shell
THEMES.append(dict(
    name="Late Night Lounge", slug="late-night-lounge", cls="t401", credit=credit("Discord"),
    desc="A chat-room page: the title sits in a channel bar with a round hash badge that squares off on touch, the chapters read as one message column, and chapter breaks are the punched date dividers of a chat log. Teal accent; soft grey panels in light mode, charcoal in dark.",
    fonts=["Inter:wght@400;600;700"], font_credits=["Inter, David Hall and Rasmus Andersson, SIL OFL 1.1"],
    fh=f"'Inter',{SANS}", fb=f"'Inter',{SANS}", divchar="&#183;&#183;&#183;",
    light=dict(bg="#ffffff", ink="#2e3338", link="#0b6f9e", a="#1f8a7a", s="#f2f3f5", b="#dcdee2", m="#5b6470"),
    dark=dict(bg="#2b2d31", ink="#dcdde0", link="#5cc8e6", a="#4cc3b0", s="#232428", b="#3a3c42", m="#a0a4ac"),
    css="""
.t401 .hd{display:grid;grid-template-columns:auto 1fr;column-gap:14px;align-items:center;padding:14px 16px;background:var(--s);border:1px solid var(--b);border-radius:12px;border-bottom:3px solid var(--a)}
.t401 .hd::before{content:"#";grid-row:1 / span 2;display:flex;align-items:center;justify-content:center;width:2.4em;height:2.4em;border-radius:50%;background:var(--a);color:#fff;font:700 calc(var(--u) * 20)/1 var(--fh);transition:border-radius .2s}
.t401 .hd:hover::before,.t401 .hd:active::before{border-radius:32%}
.t401 h1{font-weight:700;font-size:max(calc(var(--u) * 23 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.35));letter-spacing:-.01em}
.t401 .by{margin:2px 0 0}
.t401 .bd{padding:0 2px}
.t401 h2.heading,.t401 h3.title{display:flex;gap:.45em;align-items:baseline;font-weight:700}
.t401 h2.heading::before,.t401 h3.title::before{content:"#";color:var(--m);font-weight:400}
.t401 .dv{display:flex;align-items:center;gap:.8em;margin:24px 0 14px;color:var(--m);font-size:calc(var(--u) * 13)}
.t401 .dv::before,.t401 .dv::after{content:"";flex:1;border-top:1px solid var(--b)}
.t401 .articleBody blockquote{background:var(--s);border-left:4px solid var(--a);border-radius:0 8px 8px 0;padding:.5em 1em}
""" + mods("t401", "8px"),
))

# 2 Paint Job -> banner and paper tags
THEMES.append(dict(
    name="Pinned Tags", slug="pinned-tags", cls="t402", credit=credit("Paint Job"),
    desc="A painted banner runs behind the page and the title hangs across its seam on a paper tag with a punched hole; the story sits on a sheet that straddles the same seam. Bold and italic text carry their own colors. Mossy green by day, warm brown by night.",
    fonts=["Abel"], font_credits=["Abel, Matthew Desmond, SIL OFL 1.1"],
    fh=f"'Abel',{SANS}", fb=f"'Abel',{SANS}", divchar="&#10022;",
    light=dict(bg="#a6c9ae", ink="#1f1f1f", link="#005d06", a="#375600", s="#dde2de", b="#b3beb6", m="#4a4f4b", pg="#f3f4f3", bold="#005f51", ital="#7a3b00"),
    dark=dict(bg="#252a28", ink="#ece6df", link="#ffb04d", a="#c98a5a", s="#4b5a37", b="#6b5a45", m="#cdbfae", pg="#3b2e24", bold="#ff9781", ital="#fff382"),
    css="""
html{background-color:var(--pg)}
body{background-image:linear-gradient(to bottom,transparent 200px,var(--pg) 200px)}
.t402 .hd{margin:0 -4px 26px;padding:14px 46px 16px 18px;background:var(--s);color:var(--nnw-ink);border-radius:10px;box-shadow:0 3px 0 rgba(0,0,0,.25)}
.t402 .hd::before{content:"";position:absolute;top:12px;right:16px;width:14px;height:14px;border-radius:50%;background:var(--nnw-bg);box-shadow:inset 0 2px 3px rgba(0,0,0,.45)}
.t402 h1{font-weight:700;letter-spacing:.01em}
.t402 .bd{background:var(--pg);border-radius:10px;padding:18px 18px 8px;box-shadow:0 2px 0 rgba(0,0,0,.2)}
.t402 h2.heading,.t402 h3.title{display:inline-block;padding:2px 14px;background:var(--s);border-radius:99px;font-weight:700}
.t402 .dv{margin:20px 0 10px;text-align:center;color:var(--a)}
.t402 .articleBody a{font-weight:700;text-decoration:none;border-bottom:2px solid color-mix(in srgb,var(--nnw-link) 35%,transparent)}
""" + emph("t402", "var(--bold)", "var(--ital)") + mods("t402", "8px", bg="var(--s)"),
))

# 3 Newsprint -> broadsheet with stamp
THEMES.append(dict(
    name="Penny Gazette", slug="penny-gazette", cls="t403", credit=credit("Newsprint"),
    desc="A typeset broadsheet drawn with rules and type alone: a thick-thin masthead, a boxed byline between thin rules, a perforated postage stamp built from one radial gradient, a drop cap, and photos that warm from sepia on touch. Kraft paper and ink red; lamplit charcoal in dark.",
    fonts=["IM+Fell+English+SC", "Zen+Old+Mincho:wght@400;700"], font_credits=["IM FELL English SC, Igino Marini, SIL OFL 1.1", "Zen Old Mincho, Yoshimichi Ohira, SIL OFL 1.1"],
    fh=f"'IM Fell English SC',{SERIF}", fb=f"'Zen Old Mincho',{SERIF}", divchar="&#10086;",
    light=dict(bg="#d0cdba", ink="#2b2b2b", link="#663a04", a="#524000", s="#f1f0eb", b="#524000", m="#5a5340", bold="#840606", ital="#8b4f00"),
    dark=dict(bg="#21201f", ink="#d2ceb8", link="#ff915c", a="#ffcfb7", s="#2f2d2a", b="#9b8f78", m="#aaa28c", bold="#ffc29d", ital="#f7ff99"),
    css="""
.t403 .hd{padding:.5em 4.4em .5em 0;border-top:.25rem solid var(--a);border-bottom:.25rem solid var(--a);text-align:center;margin-bottom:22px}
.t403 .hd::before{content:"";display:block;border-top:.1em solid var(--a);margin:.15em 0 .6em}
.t403 h1{text-transform:uppercase;letter-spacing:.04em;font-size:max(calc(var(--u) * 25 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.35));line-height:1.08}
.t403 .by{margin:.7em 0 0;padding:.25em;border-block:.1em solid var(--a);font-style:italic;color:var(--nnw-ink)}
.t403 .hd::after{content:"\\2605";position:absolute;right:0;top:.7em;display:flex;align-items:center;justify-content:center;box-sizing:border-box;width:3.6em;height:3.6em;color:var(--a);font-size:1.1em;background:linear-gradient(var(--s),var(--s)) center/calc(100% - 1em) calc(100% - 1em) no-repeat,radial-gradient(transparent 0,transparent .25em,var(--s) .25em) -.3em -.3em/1.2em 1.2em;filter:drop-shadow(0 0 .2em color-mix(in srgb,var(--nnw-ink) 45%,transparent))}
.t403 .bd img{filter:sepia(.75) contrast(.95);transition:filter .3s}
.t403 .bd img:hover,.t403 .bd img:active{filter:none}
.t403 h2.heading,.t403 h3.title{display:block;text-align:center;border-block:3px double var(--a);padding:.2em 0;text-transform:uppercase;letter-spacing:.06em}
.t403 .dv{text-align:center;color:var(--a);margin:20px 0 10px}
.t403 .articleBody blockquote{border-left:0;border-block:.1em solid var(--a);text-align:center;font-style:italic;padding:.6em 1.5em}
""" + dropcap("t403", "var(--bold)", size="3.1em") + emph("t403", "var(--bold)", "var(--ital)") + mods("t403", "0", border="3px double var(--a)", bg="var(--s)"),
))

# 4 Sans Comic -> webcomic panels
THEMES.append(dict(
    name="Four Panel", slug="four-panel", cls="t404", credit=credit("Sans Comic", "wovenstarlight, concept by kernelbastard"),
    desc="A webcomic page: a bordered title frame, the story in a framed panel, and chapter breaks as gutters between panels. Every frame shares one teal border; headings are marigold on deep teal in dark mode and ochre on paper in light.",
    fonts=["Nunito:wght@400;700;800"], font_credits=["Nunito, Vernon Adams and contributors, SIL OFL 1.1"],
    fh=f"'Nunito',{SANS}", fb=f"'Nunito',{SANS}", divchar="&#8203;",
    light=dict(bg="#f6f1e4", ink="#1c1f24", link="#0b5f73", a="#2b8094", s="#e3f1f3", b="#2b8094", m="#3c5560", hl="#7a4f00", bold="#00696f", ital="#2c4f7c"),
    dark=dict(bg="#020017", ink="#eeeeee", link="#7fd4e6", a="#5fb4c8", s="#00333d", b="#2b8094", m="#a9c4cc", hl="#ffcc52", bold="#bbefe6", ital="#b8d4f2"),
    css="""
.t404 .hd{display:flex;flex-direction:column;justify-content:center;min-height:4rem;padding:.7rem 1rem;border:.3rem solid var(--b);background:var(--s);border-radius:.7rem;text-align:center}
.t404 h1{color:var(--hl);font-weight:800}
.t404 .by{color:var(--nnw-ink)}
.t404 .bd{border:.3rem solid var(--b);background:var(--s);border-radius:.7rem;padding:14px 16px 4px}
.t404 .dv{height:16px;margin:18px -16px;background:var(--nnw-bg);border-block:.3rem solid var(--b)}
.t404 h2.heading,.t404 h3.title{display:inline-block;padding:2px 12px;background:var(--b);color:var(--nnw-bg);border-radius:.4rem;font-weight:800}
.t404 .articleBody blockquote{border:2px solid var(--b);border-radius:.5rem;padding:.4em 1em;background:var(--nnw-bg)}
""" + emph("t404", "var(--bold)", "var(--ital)") + mods("t404", ".5rem", border="2px solid var(--b)", bg="var(--nnw-bg)"),
))

# 5 Jupiter -> observatory log
THEMES.append(dict(
    name="Observatory Log", slug="observatory-log", cls="t405", credit=credit("Jupiter"),
    desc="A star-chart notebook drawn with hairlines: a crosshair marker on the title frame, L-shaped viewfinder brackets around the story, and a small planet with a tilted ring as the chapter divider. One amber accent; every tint derives from it.",
    fonts=["Space+Grotesk:wght@400;600", "Source+Serif+4:ital,wght@0,400;0,600;1,400"], font_credits=["Space Grotesk, Florian Karsten, SIL OFL 1.1", "Source Serif 4, Adobe, SIL OFL 1.1"],
    fh=f"'Space Grotesk',{SANS}", fb=f"'Source Serif 4',{SERIF}", divchar="&#8203;",
    light=dict(bg="#fbf3e4", ink="#2a1a12", link="#8a3b00", a="#b87500", s="#f2e3c4", b="#c79a3a", m="#6a5846", hl="#8a5a00", bold="#9b2a86", ital="#a02a68"),
    dark=dict(bg="#170903", ink="#dddddd", link="#ffc436", a="#ffbf00", s="#3c1916", b="#7f5a12", m="#b9a98f", hl="#ffc436", bold="#ff8cf7", ital="#ff5fba"),
    css="""
.t405 .hd{padding:16px 54px 16px 16px;border:1px solid var(--b);background:var(--s)}
.t405 .hd::before{content:"";position:absolute;right:12px;top:12px;width:30px;height:30px;border:1px solid var(--a);border-radius:50%;background:linear-gradient(var(--a),var(--a)) center/1px 100% no-repeat,linear-gradient(var(--a),var(--a)) center/100% 1px no-repeat}
.t405 h1{color:var(--hl);font-weight:600;letter-spacing:.02em}
.t405 .bd{position:relative;padding:20px 16px 6px;border:1px solid color-mix(in srgb,var(--a) 25%,transparent)}
.t405 .bd::before,.t405 .bd::after{content:"";position:absolute;width:1.5em;height:1.5em;border:0 solid var(--a)}
.t405 .bd::before{left:-1px;top:-1px;border-top-width:.15em;border-left-width:.15em}
.t405 .bd::after{right:-1px;bottom:-1px;border-bottom-width:.15em;border-right-width:.15em}
.t405 .dv{position:relative;height:28px;margin:20px 0}
.t405 .dv::before{content:"";position:absolute;left:50%;top:50%;width:12px;height:12px;border-radius:50%;background:var(--a);transform:translate(-50%,-50%)}
.t405 .dv::after{content:"";position:absolute;left:50%;top:50%;width:46px;height:14px;border:1.5px solid var(--a);border-radius:50%;transform:translate(-50%,-50%) rotate(-18deg)}
.t405 h2.heading,.t405 h3.title{color:var(--hl);font-weight:600;border-bottom:1px solid var(--b);padding-bottom:3px}
""" + emph("t405", "var(--bold)", "var(--ital)") + mods("t405", "0", border="1px solid var(--b)", bg="transparent"),
))

# 6 Horizon -> highlighter links
THEMES.append(dict(
    name="Marker Sweep", slug="marker-sweep", cls="t406", credit=credit("Horizon"),
    desc="Two color pairs and a highlighter pen: links carry a marker stripe that thickens on touch, quotes are threads with a square terminal dot, and the title sits in a wash-tinted hero panel. Wine and lavender at night; navy and crimson by day.",
    fonts=["DM+Sans:ital,wght@0,400;0,700;1,400"], font_credits=["DM Sans, Colophon Foundry and Indian Type Foundry, SIL OFL 1.1"],
    fh=f"'DM Sans',{SANS}", fb=f"'DM Sans',{SANS}", divchar="&#9679;",
    light=dict(bg="#f7ffff", ink="#000945", link="#b6002b", a="#616993", s="#00001e", b="#9aa3c4", m="#3d4570", t2="#e7faff", hlc="rgba(182,0,43,.22)"),
    dark=dict(bg="#100001", ink="#f1ebe4", link="#c68ffc", a="#864d8e", s="#540f19", b="#7a3a48", m="#d3b8c4", t2="#ffaed8", hlc="rgba(198,143,252,.28)"),
    css="""
.t406 .hd{padding:22px 18px;border-radius:.6rem;color:var(--t2);background:linear-gradient(color-mix(in srgb,var(--s) 80%,transparent),color-mix(in srgb,var(--s) 80%,transparent)),var(--a)}
.t406 .by{color:var(--t2);opacity:.85}
.t406 h1{font-weight:700;letter-spacing:-.01em}
.t406 .articleBody a{color:var(--nnw-link);text-decoration:none;background:linear-gradient(var(--hlc),var(--hlc)) 0 100%/100% .22em no-repeat;transition:background-size .35s ease}
.t406 .articleBody a:hover,.t406 .articleBody a:active{background-size:100% 100%}
.t406 .articleBody blockquote{position:relative;border-left:4px solid var(--a);padding-left:1em;margin:1em 0 1.4em 4px}
.t406 .articleBody blockquote::after{content:"";position:absolute;left:-7px;bottom:-5px;width:10px;height:10px;background:var(--a)}
.t406 h2.heading,.t406 h3.title{padding:3px 12px;background:var(--s);color:var(--t2);border-radius:.4rem;display:inline-block}
.t406 .dv{text-align:center;margin:20px 0 10px;color:var(--a);letter-spacing:.6em}
""" + mods("t406", ".5rem", bg="color-mix(in srgb,var(--a) 14%,transparent)", border="1px solid color-mix(in srgb,var(--a) 40%,transparent)"),
))

# 7 Unite -> soft widget card
THEMES.append(dict(
    name="Lilac Card", slug="lilac-card", cls="t407", credit=credit("Unite", "wovenstarlight, an homage to the Tumblr blog view"),
    desc="A soft app card built from three colors: the page is a 20 percent accent tint, the story sits on a bordered card with a corner notch, and an overlapping round badge crosses the header edge. Lilac by day, magenta-on-black at night.",
    fonts=["Nunito:ital,wght@0,400;0,700;1,400"], font_credits=["Nunito, Vernon Adams and contributors, SIL OFL 1.1"],
    fh=f"'Nunito',{SANS}", fb=f"'Nunito',{SANS}", divchar="&#10022;",
    light=dict(bg="#e8d7ee", ink="#1d0023", link="#7a3ea3", a="#8b5ab6", s="#fff7fd", b="#c9b1d6", m="#5b3a6b", card="#fff7fd"),
    dark=dict(bg="#290d2f", ink="#e3d2f7", link="#e077f5", a="#cf43ed", s="#000000", b="#5a2766", m="#b79ad4", card="#000000"),
    css="""
.t407 .hd{margin-top:30px;padding:44px 18px 16px;background:var(--card);border:1px solid color-mix(in srgb,var(--a) 28%,transparent);border-radius:.5rem}
.t407 .hd::before{content:"";position:absolute;left:18px;top:-30px;width:58px;height:58px;border-radius:50%;border:3px solid var(--card);background:radial-gradient(circle at 32% 30%,#fff,var(--a) 70%)}
.t407 .bd{position:relative;overflow:hidden;background:var(--card);border:1px solid color-mix(in srgb,var(--a) 28%,transparent);border-radius:.5rem;padding:16px 18px 6px}
.t407 .bd::after{content:"";position:absolute;top:0;right:0;border-style:solid;border-width:0 26px 26px 0;border-color:transparent var(--a) transparent transparent}
.t407 .articleBody blockquote{position:relative;margin:14px 0 22px;padding:10px 14px;border:0;border-radius:.5rem;background:color-mix(in srgb,var(--a) 14%,var(--card))}
.t407 .articleBody blockquote::after{content:"";position:absolute;left:18px;bottom:-9px;border-style:solid;border-width:9px 9px 0 0;border-color:color-mix(in srgb,var(--a) 14%,var(--card)) transparent transparent transparent}
.t407 h2.heading,.t407 h3.title{padding-bottom:4px;border-bottom:1px solid color-mix(in srgb,var(--a) 28%,transparent);font-weight:700}
.t407 .dv{text-align:center;color:var(--a);margin:20px 0 10px}
""" + mods("t407", ".5rem", bg="color-mix(in srgb,var(--a) 10%,var(--card))", border="1px solid color-mix(in srgb,var(--a) 28%,transparent)"),
))

# 8 Washi 1 -> vertical-tape journal
THEMES.append(dict(
    name="Tape Strips", slug="tape-strips", cls="t408", credit=credit("Washi 1"),
    desc="A scrapbook journal where headings, tags and quotes are strips of patterned tape: three tape colors cycle down the page, the title tape ends in a pointed tip, and a faint woven print (drawn with gradients, no images) lies over each strip. Green, pink, cream and sky tape on a pale page; plum and amber at night.",
    fonts=["Quicksand:wght@500;700", "Lora:ital,wght@0,400;0,600;1,400"], font_credits=["Quicksand, Andrew Paglinawan, SIL OFL 1.1", "Lora, Cyreal, SIL OFL 1.1"],
    fh=f"'Quicksand',{SANS}", fb=f"'Lora',{SERIF}", divchar="&#10047;",
    light=dict(bg="#e9e7db", ink="#0c2801", link="#176a00", a="#43880c", s="#f2ffd8", b="#b7c9a0", m="#43522f", tt="#43880c", tx="#f2ffd8", t1="#ebc5d9", x1="#88003a", t2="#f0e4c1", x2="#5d2809", t3="#bfdfe9", x3="#004150"),
    dark=dict(bg="#3c0e3c", ink="#ddd9ba", link="#ffa532", a="#ffcd8e", s="#280029", b="#7a4a70", m="#c9bf9f", tt="#280029", tx="#ffcd8e", t1="#72003b", x1="#eba4a4", t2="#63085d", x2="#e3af80", t3="#1e4a5c", x3="#bfe9f5"),
    css="""
.t408 .hd{padding:18px 20px 30px;color:var(--tx);background:var(--tt);clip-path:polygon(0 0,100% 0,100% calc(100% - 16px),50% 100%,0 calc(100% - 16px));margin-bottom:22px}
.t408 .hd::before{content:"";position:absolute;inset:0;background:repeating-linear-gradient(45deg,rgba(255,255,255,.2) 0 2px,transparent 2px 9px),repeating-linear-gradient(-45deg,rgba(255,255,255,.12) 0 2px,transparent 2px 9px);pointer-events:none}
.t408 .by{color:var(--tx);opacity:.9}
.t408 h1{font-weight:700;text-transform:lowercase}
.t408 h2.heading,.t408 h3.title{position:relative;display:inline-block;padding:3px 16px;font-weight:700;letter-spacing:.04em;text-transform:lowercase}
.t408 h2.heading:nth-of-type(3n+1),.t408 h3.title:nth-of-type(3n+1){background:var(--t1);color:var(--x1)}
.t408 h2.heading:nth-of-type(3n+2),.t408 h3.title:nth-of-type(3n+2){background:var(--t2);color:var(--x2)}
.t408 h2.heading:nth-of-type(3n),.t408 h3.title:nth-of-type(3n){background:var(--t3);color:var(--x3)}
.t408 .articleBody blockquote{border:0;padding:.5em 1em;background:var(--t2);color:var(--x2)}
.t408 .articleBody blockquote:nth-of-type(3n+1){background:var(--t1);color:var(--x1)}
.t408 .articleBody blockquote:nth-of-type(3n){background:var(--t3);color:var(--x3)}
.t408 .dv{height:12px;margin:20px 0 10px;background:var(--t1);transform:rotate(-1deg)}
.t408 #bodyContainer dl.tags dd{padding:0 10px;background:var(--t3);color:var(--x3);border-radius:2px;justify-self:start}
""" + mods("t408", "2px", bg="color-mix(in srgb,var(--t2) 55%,transparent)", border="0"),
))

# 9 Washi 2 -> horizontal title tapes
THEMES.append(dict(
    name="Tape Crossing", slug="tape-crossing", cls="t409", credit=credit("Washi 2"),
    desc="Washi tape laid across the page like a desk: the title runs on one wide horizontal strip and the byline on a second, shorter one, a tape runs down the story's right edge, and a marbled L-shaped corner piece caps the top. Plum and lilac in light mode, forest and lime at night.",
    fonts=["Josefin+Sans:wght@400;700", "Lora:ital,wght@0,400;0,600;1,400"], font_credits=["Josefin Sans, Santiago Orozco, SIL OFL 1.1", "Lora, Cyreal, SIL OFL 1.1"],
    fh=f"'Josefin Sans',{SANS}", fb=f"'Lora',{SERIF}", divchar="&#10047;",
    light=dict(bg="#f0eaf0", ink="#1c0128", link="#6d00c8", a="#6e0f76", s="#e6d8ee", b="#b99fcb", m="#523a63", t1="#6e0f76", x1="#f4e4ff", t2="#974dc0", x2="#fff4fb", t3="#201b24", x3="#fbf4ff", ta="#6a636b", xa="#ffffff"),
    dark=dict(bg="#16230e", ink="#f6fff5", link="#8aec39", a="#8aec39", s="#1f3314", b="#4a6a38", m="#c5d9b8", t1="#2b2f2a", x1="#f6fff1", t2="#d3d9cd", x2="#335305", t3="#114f04", x3="#fbffe7", ta="#2d6904", xa="#fcfff1"),
    css="""
.t409 .hd{margin-bottom:26px}
.t409 h1{margin:0 calc(var(--gx) * -1) 0 0;padding:.35em var(--gx) .35em 1em;text-align:right;color:var(--x1);background:var(--t1);font-weight:700;letter-spacing:.02em}
.t409 .by{display:block;margin:6px calc(var(--gx) * -1) 0 24%;padding:.3em var(--gx) .3em 1em;text-align:right;color:var(--x2);background:var(--t2);font-weight:700}
.t409 .bd{position:relative;padding-right:22px}
.t409 .bd::before{content:"";position:absolute;top:0;right:0;bottom:0;width:14px;background:var(--t3);background-image:repeating-linear-gradient(0deg,rgba(255,255,255,.18) 0 2px,transparent 2px 8px)}
.t409 h2.heading,.t409 h3.title{display:inline-block;padding:2px 14px;color:var(--xa);background:var(--ta);font-weight:700}
.t409 .articleBody blockquote{border:0;padding:.5em 1em;background:var(--t2);color:var(--x2)}
.t409 .dv{height:10px;margin:20px 0 10px;background:var(--t3);transform:rotate(1deg)}
.t409 .t409-corner{display:none}
""" + mods("t409", "2px", bg="color-mix(in srgb,var(--t2) 22%,transparent)", border="0"),
))

# 10 Washi 3 -> leaning tape
THEMES.append(dict(
    name="Leaning Tape", slug="leaning-tape", cls="t410", credit=credit("Washi 3"),
    desc="Tape strips lean against a calm, straight story column: the title tape tilts up and to the left, chapter tabs lean the other way and slide on touch, and the body stays level. Rust, orange and magenta on wine at night; teal and sky tape on sea-glass by day.",
    fonts=["Rubik:wght@400;600;700", "Lora:ital,wght@0,400;0,600;1,400"], font_credits=["Rubik, Hubert and Fischer, SIL OFL 1.1", "Lora, Cyreal, SIL OFL 1.1"],
    fh=f"'Rubik',{SANS}", fb=f"'Lora',{SERIF}", divchar="&#10047;",
    light=dict(bg="#dde7e4", ink="#002b11", link="#006b3b", a="#119175", s="#c9ddd6", b="#8fb6a8", m="#2f5a48", t1="#119175", x1="#e5faf8", t2="#72cdaf", x2="#015a22", t3="#73bddd", x3="#0a3e55", ta="#344f77", xa="#ddf0f3"),
    dark=dict(bg="#4e081c", ink="#eddae0", link="#ff7aa3", a="#ce641b", s="#5e1428", b="#8a3a50", m="#d9b9c4", t1="#bb3200", x1="#ffeee8", t2="#ce641b", x2="#fff3eb", t3="#bf3084", x3="#ffe8f6", ta="#8e0054", xa="#ffebf7"),
    css="""
.t410 .hd{margin:22px 0 28px}
.t410 h1{display:inline-block;max-width:100%;box-sizing:border-box;padding:.4em .9em;color:var(--x1);background:var(--t1);font-weight:700;transform:rotate(-2deg);transform-origin:left bottom}
.t410 .by{display:inline-block;margin:10px 0 0 6px;padding:.25em .8em;color:var(--xa);background:var(--ta);transform:rotate(2deg);transform-origin:left bottom;font-weight:600}
.t410 h2.heading,.t410 h3.title{display:inline-block;padding:3px 14px;font-weight:600;transform:rotate(2deg);transform-origin:left bottom;transition:margin-left .2s}
.t410 h2.heading:hover,.t410 h3.title:hover{margin-left:.5em}
.t410 h2.heading:nth-of-type(odd),.t410 h3.title:nth-of-type(odd){background:var(--t2);color:var(--x2)}
.t410 h2.heading:nth-of-type(even),.t410 h3.title:nth-of-type(even){background:var(--t3);color:var(--x3)}
.t410 .articleBody blockquote{border:0;padding:.5em 1em;background:var(--ta);color:var(--xa)}
.t410 .dv{height:10px;margin:20px 0 10px;background:var(--t2);transform:rotate(-2deg)}
""" + mods("t410", "2px", bg="color-mix(in srgb,var(--t3) 28%,transparent)", border="0"),
))
