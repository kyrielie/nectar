"""Designs 11 to 20 from clean-room-theme-specs.md (themes 11 to 15 by wovenstarlight, 16 to 19 by palemomos, 20 by octomoosey)."""
from spec_common import mods, emph, dropcap
from spec_themes_a import SANS, SERIF, credit

PALEMOMOS = "The source's published terms forbid copying its code or recreating it elsewhere, so this is a different design: it shares no markup, names, code or art, and only uses general techniques."
THEMES = []

# 11 Archive Of Your Own -> catalogue records
THEMES.append(dict(
    name="Catalogue Bevel", slug="catalogue-bevel", cls="t411", credit=credit("Archive Of Your Own", "wovenstarlight, an homage to a fan-fiction library site"),
    desc="A library-catalogue record: a glossy accent bar with a 2 by 2 cluster of square type icons carries the title, chapter headings are beveled buttons, tags are dotted-underlined, and the story sits in a bordered record. Deep red on white; blue on charcoal at night.",
    fonts=["Libre+Baskerville:ital,wght@0,400;0,700;1,400", "Noto+Sans:ital,wght@0,400;0,700;1,400"], font_credits=["Libre Baskerville, Impallari Type, SIL OFL 1.1", "Noto Sans, Google, SIL OFL 1.1"],
    fh=f"'Libre Baskerville',{SERIF}", fb=f"'Noto Sans',{SANS}", divchar="&#9632;",
    light=dict(bg="#ffffff", ink="#2a2a2a", link="#990000", a="#990000", s="#f2f2f2", b="#d6d6d6", m="#555555", on="#ffffff"),
    dark=dict(bg="#333333", ink="#eeeeee", link="#7fb4e6", a="#5998d6", s="#1e1e1e", b="#4a4a4a", m="#b8b8b8", on="#0b1b2b"),
    css=r"""
.t411 .hd{display:grid;grid-template-columns:auto 1fr;column-gap:14px;align-items:center;padding:14px 16px;color:var(--on);background:linear-gradient(color-mix(in srgb,var(--a) 80%,#fff),var(--a) 55%,color-mix(in srgb,var(--a) 82%,#000));border:1px solid color-mix(in srgb,var(--a) 70%,#000);border-radius:6px;box-shadow:inset 0 1px 0 rgba(255,255,255,.35)}
.t411 .hd::before{content:"";grid-row:1 / span 2;width:34px;height:34px;background:linear-gradient(var(--on),var(--on)) 0 0/15px 15px no-repeat,linear-gradient(var(--on),var(--on)) 100% 0/15px 15px no-repeat,linear-gradient(var(--on),var(--on)) 0 100%/15px 15px no-repeat,linear-gradient(var(--on),var(--on)) 100% 100%/15px 15px no-repeat;opacity:.9}
.t411 h1{font-weight:700;font-size:max(calc(var(--u) * 22 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.35))}
.t411 .by{color:var(--on);margin:2px 0 0;opacity:.9}
.t411 .bd{margin-top:14px;padding:6px 14px 4px;border:1px solid var(--b);border-radius:4px}
.t411 h2.heading,.t411 h3.title{display:inline-block;padding:3px 14px;font-weight:700;font-size:calc(var(--u) * 15);color:var(--ink,var(--nnw-ink));background:linear-gradient(var(--nnw-bg),var(--b));border:1px solid var(--m);border-radius:4px;box-shadow:inset 0 1px 0 rgba(255,255,255,.5),0 1px 1px rgba(0,0,0,.2)}
.t411 .articleBody a{text-decoration:none;border-bottom:1px solid currentColor}
.t411 #bodyContainer dl.tags dd{border-bottom:1px dotted var(--m)}
.t411 .articleBody blockquote{border-left:0;margin:.8em 0 .8em 1.6em;padding:0}
.t411 .dv{text-align:center;color:var(--a);margin:20px 0 10px;font-size:calc(var(--u) * 10)}
""" + mods("t411", "4px", bg="var(--s)"),
))

# 12 Subzero -> winter layout
THEMES.append(dict(
    name="Frostline", slug="frostline", cls="t412", credit=credit("Subzero"),
    desc="A winter page: wide-tracked small capitals, a single accent rule under the title, and a header photo-glow that melts into the page color. Orange on deep navy at night; steel blue on pale ice by day.",
    fonts=["Jost:wght@300;400;600"], font_credits=["Jost, Owen Earl, SIL OFL 1.1"],
    fh=f"'Jost',{SANS}", fb=f"'Jost',{SANS}", divchar="&#10052;",
    light=dict(bg="#cde1ed", ink="#004b68", link="#005f87", a="#0090c8", s="#dcecf5", b="#8fbdd6", m="#2b6a85", pg="#e6f2fa"),
    dark=dict(bg="#172a44", ink="#fff8e2", link="#ffa347", a="#ff8c2a", s="#1c3452", b="#2d4a70", m="#b8c7da", pg="#101e33"),
    css=r"""
html{background-color:var(--pg)}
body{background-image:linear-gradient(to bottom,transparent 140px,var(--pg) 360px)}
.t412 .hd{padding:0 0 16px;border-bottom:.1em solid var(--a)}
.t412 h1{text-transform:uppercase;letter-spacing:.1em;font-weight:300;font-size:max(calc(var(--u) * 24 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.3))}
.t412 .by{text-transform:uppercase;letter-spacing:.18em;color:var(--a)}
.t412 h2.heading,.t412 h3.title{text-transform:uppercase;letter-spacing:.1em;font-weight:600;font-size:calc(var(--u) * 15);padding-bottom:4px;border-bottom:.1em solid var(--a)}
.t412 .articleBody a{text-decoration:underline;text-underline-offset:.2em}
.t412 .dv{display:flex;align-items:center;gap:.8em;color:var(--a);margin:22px 0 12px}
.t412 .dv::before,.t412 .dv::after{content:"";flex:1;border-top:.1em solid var(--a)}
.t412 .articleBody blockquote{border-left:.1em solid var(--a);padding-left:1em;letter-spacing:.02em}
""" + mods("t412", "2px", bg="color-mix(in srgb,var(--s) 80%,transparent)", border=".1em solid var(--b)"),
))

# 13 Document -> word-processor sheet
THEMES.append(dict(
    name="Draft Sheet", slug="draft-sheet", cls="t413", credit=credit("Document", "wovenstarlight, an homage to a web word processor"),
    desc="A word-processor page: the story is a white paper sheet with a hairline outline and a soft lift, headings carry an outline dash, chapter breaks are dashed page breaks, and every tint is a low-alpha mix of one text color and one accent. Blue accent; paper on grey in light, charcoal in dark.",
    fonts=["Roboto:ital,wght@0,400;0,500;0,700;1,400"], font_credits=["Roboto, Christian Robertson, Apache 2.0"],
    fh=f"'Roboto',{SANS}", fb=f"'Roboto',{SANS}", divchar="&#8203;",
    light=dict(bg="#f9fbfd", ink="#1f1f1f", link="#1967d2", a="#1967d2", s="#ffffff", b="#dadce0", m="#5f6368"),
    dark=dict(bg="#202124", ink="#e8eaed", link="#8ab4f8", a="#8ab4f8", s="#303134", b="#5f6368", m="#bdc1c6"),
    css=r"""
.t413 .hd{padding:0 4px 18px;display:flex;align-items:center;gap:12px;flex-wrap:wrap}
.t413 .hd::before{content:"";flex:none;width:22px;height:28px;border:2px solid var(--a);border-radius:2px;background:linear-gradient(var(--a),var(--a)) 5px 8px/10px 2px no-repeat,linear-gradient(var(--a),var(--a)) 5px 13px/10px 2px no-repeat,linear-gradient(var(--a),var(--a)) 5px 18px/6px 2px no-repeat}
.t413 h1{flex:1 1 12em;font-weight:500;font-size:max(calc(var(--u) * 24 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.35))}
.t413 .by{flex:1 0 100%;margin:0}
.t413 .bd{background:var(--s);outline:1px solid var(--b);box-shadow:0 1px 3px rgba(60,64,67,.3),0 4px 8px 3px rgba(60,64,67,.15);padding:26px 20px 14px;border-radius:2px}
.t413 h2.heading,.t413 h3.title{font-weight:500}
.t413 h2.heading::before,.t413 h3.title::before{content:"\2013\00a0";color:var(--a)}
.t413 .dv{display:block;height:0;margin:28px -20px;border-top:1px dashed var(--b)}
.t413 .articleBody blockquote{border-left:3px solid color-mix(in srgb,var(--a) 40%,transparent);margin-left:1.4em}
""" + mods("t413", "4px", bg="color-mix(in srgb,var(--a) 7%,transparent)", border="1px solid color-mix(in srgb,var(--a) 22%,transparent)"),
))

# 14 Rhythmic -> card hub
THEMES.append(dict(
    name="Hand of Cards", slug="hand-of-cards", cls="t414", credit=credit("Rhythmic", "wovenstarlight, an homage to a rhythm-game profile screen"),
    desc="A game profile hub: the title is a collectible card with a gold badge, the story sits on a rounded panel with card-tab chapter headings, and the page ends in a frosted-glass pager strip. Light-blue accent on navy in dark; the same on pale sky in light.",
    fonts=["Exo+2:ital,wght@0,400;0,600;0,700;1,400"], font_credits=["Exo 2, Natanael Gama, SIL OFL 1.1"],
    fh=f"'Exo 2',{SANS}", fb=f"'Exo 2',{SANS}", divchar="&#9670;",
    light=dict(bg="#e9f3ff", ink="#0d1a32", link="#015e97", a="#0179f9", s="#ffffff", b="#9cc4e8", m="#3d5675", on="#ffffff", card="#481f19", gold="#fee822"),
    dark=dict(bg="#0d1a32", ink="#f2f3f3", link="#38b4fe", a="#38b4fe", s="#172039", b="#363650", m="#a5a6a7", on="#0d1a32", card="#481f19", gold="#fee822"),
    css=r"""
.t414 .hd{padding:20px 60px 18px 18px;color:#f2f3f3;background:var(--card);border:2px solid var(--a);border-radius:14px;box-shadow:0 8px 0 -3px var(--b);transform:rotate(-.8deg)}
.t414 .hd::before{content:"\2605";position:absolute;right:14px;top:14px;display:flex;align-items:center;justify-content:center;width:34px;height:34px;border-radius:50%;color:var(--card);background:var(--gold);box-shadow:0 0 0 3px rgba(255,255,255,.4)}
.t414 .by{color:#f2f3f3;opacity:.85}
.t414 h1{font-weight:700;color:#fff}
.t414 .bd{margin-top:22px;padding:18px 18px 0;background:var(--s);border:1px solid var(--b);border-radius:14px;overflow:hidden}
.t414 .bd::after{content:"\25C0\2003\2022 \2022 \2022\2003\25B6";display:block;margin:18px -18px 0;padding:12px;text-align:center;letter-spacing:.3em;color:var(--m);background:color-mix(in srgb,var(--nnw-bg) 70%,transparent);-webkit-backdrop-filter:blur(8px);backdrop-filter:blur(8px)}
.t414 h2.heading,.t414 h3.title{display:inline-block;padding:4px 14px;color:var(--on);background:var(--a);border-radius:8px 8px 0 0;font-weight:700}
.t414 .dv{text-align:center;color:var(--a);margin:20px 0 10px}
.t414 .articleBody blockquote{border-left:4px solid var(--a);background:color-mix(in srgb,var(--a) 10%,transparent);border-radius:0 8px 8px 0;padding:.4em 1em}
""" + mods("t414", "10px", bg="color-mix(in srgb,var(--a) 9%,transparent)", border="1px solid var(--b)"),
))

# 15 Haunted -> two-colour notebook
THEMES.append(dict(
    name="Pixel Notebook", slug="pixel-notebook", cls="t415", credit=credit("Haunted", "wovenstarlight, design by Bwob"),
    desc="A two-color notebook: everything is ink on paper with chunky borders, hover and tap swap ink and paper, notes get triple double-lines, and the story sits on ruled paper with a spiral binding punched down the left edge. Sepia ink on cocoa by night; brown ink on parchment by day.",
    fonts=["Pixelify+Sans:wght@400;700", "Courier+Prime:ital,wght@0,400;0,700;1,400"], font_credits=["Pixelify Sans, Stefie Justprince, SIL OFL 1.1", "Courier Prime, Alan Dague-Greene, SIL OFL 1.1"],
    fh=f"'Pixelify Sans','Courier New',monospace", fb=f"'Courier Prime','Courier New',Courier,monospace", divchar="&#9670; &#9670; &#9670;",
    light=dict(bg="#f3ead3", ink="#4a3010", link="#7a4a12", a="#2b1a05", s="#ece0c2", b="#6a4a22", m="#6a5236"),
    dark=dict(bg="#311a05", ink="#dcae75", link="#ffe3b8", a="#ffffff", s="#3d2309", b="#a97844", m="#b88d5a"),
    css=r"""
:root{--bw:.21875rem}
.t415 .hd{padding:12px 14px;border:var(--bw) solid var(--b);transition:background .2s,color .2s}
.t415 .hd:hover,.t415 .hd:active{background:var(--b);color:var(--nnw-bg)}
.t415 h1{font-weight:700;font-size:max(calc(var(--u) * 24 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.35));line-height:1.15}
.t415 .by{color:inherit;letter-spacing:.08em}
.t415 .bd{position:relative;margin-top:16px;padding:2px 8px 2px 30px;line-height:1.65;background-image:repeating-linear-gradient(transparent 0,transparent calc(1.65em - 1px),color-mix(in srgb,var(--b) 20%,transparent) calc(1.65em - 1px),color-mix(in srgb,var(--b) 20%,transparent) 1.65em);background-attachment:local;border:var(--bw) solid var(--b)}
.t415 .bd::before{content:"";position:absolute;left:3px;top:0;bottom:0;width:20px;background:radial-gradient(circle at 10px 50%,var(--nnw-bg) 4px,var(--b) 4.5px,var(--b) 6px,transparent 6.5px) 0 0/20px 30px repeat-y}
.t415 h2.heading,.t415 h3.title{display:inline-block;padding:2px 12px;border:var(--bw) solid var(--b);font-weight:700;background:var(--nnw-bg)}
.t415 .dv{text-align:center;margin:18px 0 6px;letter-spacing:.2em;color:var(--b)}
.t415 .articleBody blockquote{border:calc(var(--bw) * 3) double var(--b);margin:.8em 0;padding:.4em .8em;background:var(--nnw-bg)}
.t415 .articleBody a{text-decoration:none;border-bottom:var(--bw) solid var(--b)}
""" + mods("t415", "0", border="calc(var(--bw) * 3) double var(--b)", bg="var(--nnw-bg)"),
))

# 16 Glazed -> frosted cards over wallpaper
THEMES.append(dict(
    name="Frosted Wallpaper", slug="frosted-wallpaper", cls="t416", credit=credit("Glazed", "palemomos (Themes by Pale)"), extra=PALEMOMOS,
    desc="Frosted-glass panels over a soft gradient wallpaper: panels blur a little more and flood with accent when touched, and the title is a pink-to-blue text gradient. Pastel pink and blue by day; charcoal glass at night.",
    fonts=["Nanum+Gothic+Coding:wght@400;700"], font_credits=["Nanum Gothic Coding, Sandoll Communication, SIL OFL 1.1"],
    fh=f"'Nanum Gothic Coding',{SANS}", fb=f"'Nanum Gothic Coding',{SANS}", divchar="&#10022;",
    light=dict(bg="#f1e3f0", ink="#3c3c3c", link="#b5174f", a="#ff66a3", s="rgba(255,255,255,.55)", b="rgba(255,255,255,.9)", m="#5a5a5a", a2="#6f9bff"),
    dark=dict(bg="#1f1b24", ink="#f4f4fb", link="#ff8fbc", a="#ff66a3", s="rgba(40,40,40,.55)", b="rgba(255,255,255,.14)", m="#c9c4d0", a2="#7aa7ff"),
    css=r"""
body{background-image:radial-gradient(ellipse 60% 40% at 15% 8%,rgba(255,150,200,.55),transparent),radial-gradient(ellipse 55% 40% at 90% 30%,rgba(120,160,255,.45),transparent),radial-gradient(ellipse 60% 45% at 30% 90%,rgba(255,200,150,.4),transparent);background-attachment:scroll}
.t416 .hd,.t416 .bd{background:var(--s);border:1px solid var(--b);border-radius:18px;-webkit-backdrop-filter:blur(8px);backdrop-filter:blur(8px);transition:box-shadow .4s,backdrop-filter .4s}
.t416 .hd{padding:18px 20px}
.t416 .bd{padding:16px 18px 6px}
.t416 .hd:hover,.t416 .bd:hover{-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);box-shadow:inset 0 0 0 100px color-mix(in srgb,var(--a) 10%,transparent)}
.t416 h1{font-weight:700;background:linear-gradient(90deg,var(--link-g1,#d81b6a),var(--link-g2,#3d6de0));-webkit-background-clip:text;background-clip:text;color:transparent;-webkit-text-fill-color:transparent}
.t416 h2.heading,.t416 h3.title{display:inline-block;padding:2px 16px;border-radius:99px;background:color-mix(in srgb,var(--a) 22%,transparent);font-weight:700}
.t416 .dv{text-align:center;color:var(--a);margin:20px 0 10px}
.t416 .articleBody blockquote{border-left:4px solid var(--a);border-radius:0 12px 12px 0;background:color-mix(in srgb,var(--a) 10%,transparent)}
""" + mods("t416", "14px", bg="color-mix(in srgb,var(--a) 10%,transparent)", border="1px solid var(--b)"),
    dark_css=r"""
.t416 h1{background:linear-gradient(90deg,#ff8fbc,#8fb4ff);-webkit-background-clip:text;background-clip:text;color:transparent}
body{background-image:radial-gradient(ellipse 60% 40% at 15% 8%,rgba(255,102,163,.28),transparent),radial-gradient(ellipse 55% 40% at 90% 30%,rgba(90,130,255,.25),transparent),radial-gradient(ellipse 60% 45% at 30% 90%,rgba(255,170,120,.16),transparent)}
""",
))

# 17 Social Media -> profile and square wall
THEMES.append(dict(
    name="Square Wall", slug="square-wall", cls="t417", credit=credit("Social Media", "palemomos (Themes by Pale)"), extra=PALEMOMOS,
    desc="A photo-profile page: the title is a profile card with a round two-tone avatar, pictures sit as rounded squares, chapter headings are outlined buttons that sweep to a solid fill on touch, and chapter breaks are three small squares. Pink and blue accents; ghost white or charcoal.",
    fonts=["Nunito+Sans:ital,wght@0,400;0,700;1,400"], font_credits=["Nunito Sans, Vernon Adams and Jacques Le Bailly, SIL OFL 1.1"],
    fh=f"'Nunito Sans',{SANS}", fb=f"'Nunito Sans',{SANS}", divchar="&#8203;",
    light=dict(bg="#f4f4fb", ink="#333333", link="#2f5fd0", a="#e0457b", s="#ffffff", b="#dedde8", m="#6b6b7a", a2="#3b82f6", on="#ffffff"),
    dark=dict(bg="#282828", ink="#f4f4fb", link="#8db6ff", a="#ff7aa8", s="#333333", b="#4a4a4a", m="#b4b4c2", a2="#6aa0ff", on="#1c1c1c"),
    css=r"""
.t417 .hd{display:grid;grid-template-columns:auto 1fr;column-gap:16px;align-items:center;padding:16px 18px;background:var(--s);border:1px solid var(--b);border-radius:16px}
.t417 .hd::before{content:"";grid-row:1 / span 2;width:64px;height:64px;border-radius:50%;background:linear-gradient(135deg,var(--a),var(--a2));box-shadow:0 0 0 4px var(--s),0 0 0 6px var(--b)}
.t417 h1{font-weight:700;font-size:max(calc(var(--u) * 22 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.35))}
.t417 .by{margin:2px 0 0}
.t417 .bd{margin-top:16px;padding:6px 2px 0}
.t417 .bd img{border-radius:6px}
.t417 h2.heading,.t417 h3.title{display:inline-block;padding:3px 16px;border:2px solid var(--a);border-radius:99px;font-weight:700;background:linear-gradient(var(--a),var(--a)) 0 0/0 100% no-repeat;transition:background-size .4s,color .4s}
.t417 h2.heading:hover,.t417 h3.title:hover,.t417 h2.heading:active,.t417 h3.title:active{background-size:100% 100%;color:var(--on)}
.t417 .dv{height:12px;margin:22px 0 12px}
.t417 .dv::before{content:"";display:block;width:10px;height:10px;margin:0 auto;background:var(--a);box-shadow:-20px 0 0 var(--a2),20px 0 0 var(--a)}
.t417 .articleBody blockquote{border:1px solid var(--b);border-radius:12px;background:var(--s);padding:.5em 1em}
""" + mods("t417", "12px", bg="var(--s)", border="1px solid var(--b)"),
))

# 18 Doodling 3x1 -> pen-drawn frames
THEMES.append(dict(
    name="Pen Margins", slug="pen-margins", cls="t418", credit=credit("Doodling 3x1", "palemomos (Themes by Pale)"), extra=PALEMOMOS,
    desc="A pencil-and-notebook page: every frame is a 2px line drawn with elliptical corner radii so each side bows like a pen stroke, headings are handwriting, and links carry a hand-drawn underline. Pink accent; ghost white or charcoal paper.",
    fonts=["Caveat:wght@500;700", "Patrick+Hand"], font_credits=["Caveat, Impallari Type, SIL OFL 1.1", "Patrick Hand, Patrick Wagesreiter, SIL OFL 1.1"],
    fh=f"'Caveat','Comic Sans MS',cursive", fb=f"'Patrick Hand','Comic Sans MS',{SANS}", divchar="&#10047;",
    light=dict(bg="#f8f8ff", ink="#333333", link="#c2255c", a="#ff66a3", s="#f8f8ff", b="#333333", m="#666666"),
    dark=dict(bg="#282828", ink="#f8f8ff", link="#ff8fb8", a="#ff66a3", s="#282828", b="#f8f8ff", m="#bdbdc9"),
    css=r"""
.t418 .hd,.t418 .bd,.t418 .summary.module,.t418 .notes.module,.t418 .end.notes.module,.t418 #bodyContainer dl.tags{border:2px solid var(--b);border-top-left-radius:55px 20px;border-top-right-radius:2000px 50px;border-bottom-right-radius:2250px 14px;border-bottom-left-radius:1500px 50px;background:var(--s)}
.t418 .hd{padding:16px 22px 14px}
.t418 .bd{margin-top:20px;padding:14px 20px 4px}
.t418 h1{font-weight:700;font-size:max(calc(var(--u) * 34 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.5));line-height:1}
.t418 .t h2.heading,.t418 h2.heading,.t418 h3.title{font-weight:700;font-size:calc(var(--u) * 26)}
.t418 .by{color:var(--m)}
.t418 .articleBody a{text-decoration:none;background:linear-gradient(var(--a),var(--a)) 0 100%/100% 2px no-repeat;padding-bottom:1px}
.t418 .dv{text-align:center;margin:18px 0 8px;color:var(--a)}
.t418 .articleBody blockquote{margin:.8em 0;padding:.4em 1em;border:2px solid var(--b);border-width:2px 0 0;border-top-left-radius:555px 20px;border-top-right-radius:2000px 20px}
.t418 .summary.module,.t418 .notes.module,.t418 .end.notes.module,.t418 #bodyContainer dl.tags{padding:10px 16px}
.t418 .notes.module,.t418 .end.notes.module{margin:14px 0 0;font-size:calc(var(--u) * 13)}
.t418 .summary.module h3.heading,.t418 .notes.module h3.heading,.t418 .end.notes.module h3.heading,.t418 #bodyContainer dl.tags dt{color:var(--link)}
""",
))

# 19 See The Stars With Me -> RPG dialogue window
THEMES.append(dict(
    name="Sky Dialogue", slug="sky-dialogue", cls="t419", credit=credit("See The Stars With Me", "palemomos (Themes by Pale)"), extra=PALEMOMOS,
    desc="A role-playing dialogue window under a tiled pixel sky: double-line borders, a blinking block cursor after the byline, and star-speckled backgrounds drawn with gradients. Retro purple at night; pastel lilac by day.",
    fonts=["Pixelify+Sans:wght@400;700"], font_credits=["Pixelify Sans, Stefie Justprince, SIL OFL 1.1"],
    fh=f"'Pixelify Sans','Courier New',monospace", fb=f"'Pixelify Sans','Courier New',monospace", divchar="&#9733; &#9733; &#9733;",
    light=dict(bg="#c9b9e6", ink="#2b1a45", link="#5b2ca0", a="#8e5acd", s="#f1e6fa", b="#4a2a80", m="#4a3a63"),
    dark=dict(bg="#3a1058", ink="#f2f2f2", link="#ffd6f5", a="#b78aef", s="#5f1b7c", b="#f2f2f2", m="#e1d0f2"),
    css=r"""
body{background-image:radial-gradient(1px 1px at 20px 30px,#fff,transparent),radial-gradient(1.5px 1.5px at 90px 70px,#fff,transparent),radial-gradient(1px 1px at 160px 120px,#fff,transparent),radial-gradient(1.5px 1.5px at 60px 160px,#fff,transparent),linear-gradient(180deg,color-mix(in srgb,var(--a) 35%,var(--nnw-bg)),var(--nnw-bg) 480px);background-size:200px 200px,200px 200px,200px 200px,200px 200px,100% 100%;background-repeat:repeat,repeat,repeat,repeat,no-repeat}
.t419 .hd,.t419 .bd{background:var(--s);border:6px double var(--b)}
.t419 .hd{padding:14px 16px}
.t419 .bd{margin-top:20px;padding:12px 16px 2px}
.t419 h1{font-weight:700;letter-spacing:.02em}
.t419 .by::after{content:"\258C";margin-left:.3em;animation:t419blink 1s steps(1) infinite}
@keyframes t419blink{50%{opacity:0}}
.t419 h2.heading,.t419 h3.title{font-weight:700;border-bottom:4px double var(--b);padding-bottom:2px}
.t419 .dv{text-align:center;margin:18px 0 8px;color:var(--a);letter-spacing:.3em}
.t419 .articleBody blockquote{border:4px double var(--b);margin:.8em 0;padding:.4em .8em}
.t419 .articleBody b,.t419 .articleBody strong{letter-spacing:2px}
""" + mods("t419", "0", border="4px double var(--b)", bg="color-mix(in srgb,var(--a) 20%,transparent)"),
))

# 20 your bones -> inverted strips
THEMES.append(dict(
    name="Strip Credits", slug="strip-credits", cls="t420", credit=credit("your bones", "octomoosey"),
    desc="A credits-page look: a narrow column with hard color inversion, so every heading is a full-width strip in the opposite color, split rows put the label left and the value right, and links fade slowly. White on charcoal at night; charcoal on white by day, mustard accent.",
    fonts=["Oswald:wght@300;400;600", "Yanone+Kaffeesatz:wght@400;600"], font_credits=["Oswald, Vernon Adams and contributors, SIL OFL 1.1", "Yanone Kaffeesatz, Yanone, SIL OFL 1.1"],
    fh=f"'Yanone Kaffeesatz','Arial Narrow',{SANS}", fb=f"'Oswald','Arial Narrow',{SANS}", divchar="&#8203;",
    light=dict(bg="#ffffff", ink="#333333", link="#8a5d00", a="#eda600", s="#333333", b="#d8d8d8", m="#555555", si="#ffffff"),
    dark=dict(bg="#333333", ink="#ffffff", link="#eda600", a="#eda600", s="#ffffff", b="#555555", m="#d0d0d0", si="#333333"),
    css=r"""
.t420{max-width:520px;margin:0 auto}
.t420 .hd{margin-bottom:6px}
.t420 h1{text-transform:uppercase;letter-spacing:3px;font-weight:600;font-size:max(calc(var(--u) * 30 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.5));line-height:1.05}
.t420 .by{text-align:right;text-transform:uppercase;letter-spacing:2px}
.t420 h2.heading,.t420 h3.title{display:block;margin:20px calc(var(--gx) * -1) 10px;padding:8px var(--gx);text-align:right;color:var(--si);background:var(--s);font-size:calc(var(--u) * 20)}
.t420 .articleBody a{transition:all .7s ease;text-decoration:none;border-bottom:1px solid var(--a)}
.t420 #bodyContainer dl.tags{display:block}
.t420 #bodyContainer dl.tags dt{float:left;clear:left}
.t420 #bodyContainer dl.tags dd{text-align:right;margin:0 0 4px}
.t420 .dv{height:3px;margin:24px calc(var(--gx) * -1);background:var(--a)}
.t420 .articleBody blockquote{border-left:2px solid var(--a);letter-spacing:.5px}
""" + mods("t420", "0", bg="transparent", border="1px solid var(--b)"),
))
