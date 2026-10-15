"""Designs 21 to 29 from clean-room-theme-specs.md (themes 21 to 28 by egg.design and octomoosey, 29 by wovenstarlight)."""
from spec_common import mods, emph, dropcap
from spec_themes_a import SANS, SERIF, credit

THEMES = []

# 21 fiddle of gold -> monochrome window with roman numerals
THEMES.append(dict(
    name="Numeral Window", slug="numeral-window", cls="t421", credit=credit("fiddle of gold", "egg.design"),
    desc="A monochrome window: a solid title strip, a one-pixel frame, photos in greyscale until touched (a slow 0.9 second fade), and chapter headings numbered in roman numerals by a CSS counter. Black and white with one crimson accent; inverted at night.",
    fonts=["Lato:ital,wght@0,300;0,400;0,700;1,300"], font_credits=["Lato, Lukasz Dziedzic, SIL OFL 1.1"],
    fh=f"'Lato',{SANS}", fb=f"'Lato',{SANS}", divchar="&#8203;",
    light=dict(bg="#ffffff", ink="#1b1919", link="#a50000", a="#a50000", s="#000000", b="#000000", m="#555555", si="#ffffff"),
    dark=dict(bg="#111111", ink="#e8e6e6", link="#ff6b6b", a="#ff6b6b", s="#e8e6e6", b="#e8e6e6", m="#b5b5b5", si="#111111"),
    css=r"""
#bodyContainer{counter-reset:t421ch}
.t421 .hd{padding:14px 16px;background:var(--s);color:var(--si)}
.t421 h1{font-weight:300;letter-spacing:.06em;text-transform:uppercase;font-size:max(calc(var(--u) * 24 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.35))}
.t421 .by{color:var(--si);opacity:.8}
.t421 .bd{margin-top:-1px;padding:16px 16px 4px;border:1px solid var(--b)}
.t421 .bd img{filter:grayscale(1);transition:filter .9s ease}
.t421 .bd img:hover,.t421 .bd img:active{filter:none}
.t421 h2.heading,.t421 h3.title{font-weight:300;letter-spacing:.08em;text-transform:uppercase;border-bottom:1px solid var(--b);padding-bottom:3px}
.t421 h2.heading::before{counter-increment:t421ch;content:counter(t421ch,upper-roman) ".\00a0";color:var(--a)}
.t421 .dv{display:block;height:1px;margin:22px 0;background:var(--b)}
.t421 .articleBody a{text-decoration:none;border-bottom:1px solid var(--a)}
.t421 .articleBody blockquote{border-left:1px solid var(--b);padding-left:1em}
""" + mods("t421", "0", bg="transparent", border="1px solid var(--b)"),
))

# 22 baby -> picture frame, hanging headings
THEMES.append(dict(
    name="Hung Dates", slug="hung-dates", cls="t422", credit=credit("baby", "octomoosey"),
    desc="A picture-framed page: a solid mat frame is drawn around the screen edge, the story is a narrow column with a hairline down its left side, chapter headings hang out into the margin in small lowercase, and notes are dark sidebar boxes with orange accents. Charcoal and orange on grey; the inverse at night.",
    fonts=["Work+Sans:ital,wght@0,300;0,400;0,600;1,400"], font_credits=["Work Sans, Wei Huang, SIL OFL 1.1"],
    fh=f"'Work Sans',{SANS}", fb=f"'Work Sans',{SANS}", divchar="&#8203;",
    light=dict(bg="#d4d4d4", ink="#363636", link="#8a4a00", a="#fb9d28", s="#363636", b="#363636", m="#4a4a4a", fr="#363636", side="#363636", sidet="#d4d4d4"),
    dark=dict(bg="#2b2b2b", ink="#d4d4d4", link="#fb9d28", a="#fb9d28", s="#1c1c1c", b="#8a8a8a", m="#bdbdbd", fr="#121212", side="#1c1c1c", sidet="#d4d4d4"),
    css=r"""
.t422::before{content:"";position:fixed;inset:0;border:12px solid var(--fr);pointer-events:none;z-index:8}
.t422 .hd{margin-left:6px}
.t422 h1{font-weight:300;letter-spacing:.02em;font-size:max(calc(var(--u) * 26 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.35))}
.t422 .by{text-transform:lowercase;font-size:calc(var(--u) * 11)}
.t422 .bd{margin-left:6px;padding:4px 4px 4px 18px;border-left:1px solid var(--b)}
.t422 h2.heading,.t422 h3.title{position:relative;margin-left:-14px;text-transform:lowercase;font-size:calc(var(--u) * 14);font-weight:600;letter-spacing:.04em;color:var(--a);padding-bottom:2px}
.t422 .articleBody b,.t422 .articleBody strong,.t422 .articleBody i,.t422 .articleBody em{color:var(--link)}
.t422 .dv{display:block;height:1px;margin:24px 0;background:var(--b)}
.t422 .articleBody blockquote{border-left:1px solid var(--b);padding-left:10px;margin:15px 0 10px;text-align:justify}
.t422 .summary.module,.t422 .notes.module,.t422 .end.notes.module,.t422 #bodyContainer dl.tags{background:var(--side);color:var(--sidet);border:0;border-radius:0;padding:14px 16px}
.t422 .notes.module,.t422 .end.notes.module{margin:14px 0 0;font-size:calc(var(--u) * 13)}
.t422 .summary.module h3.heading,.t422 .notes.module h3.heading,.t422 .end.notes.module h3.heading,.t422 #bodyContainer dl.tags dt{color:var(--a)}
.t422 .summary.module a,.t422 .notes.module a,.t422 #bodyContainer dl.tags a{color:var(--sidet);border-bottom:1px solid var(--a);text-decoration:none}
""",
))

# 23 cat in a box -> gradient-bordered floating cards
THEMES.append(dict(
    name="Gradient Stage", slug="gradient-stage", cls="t423", credit=credit("cat in a box", "octomoosey"),
    desc="Floating cards on a calm stage: every panel has a 3px two-stop gradient border and a deep offset shadow, and the title carries a cascade of three shrinking portrait discs. Rosewood and slate on neutral grey; the same gradient on charcoal at night.",
    fonts=["Yanone+Kaffeesatz:wght@400;600", "Roboto:ital,wght@0,400;0,700;1,400"], font_credits=["Yanone Kaffeesatz, Yanone, SIL OFL 1.1", "Roboto, Christian Robertson, Apache 2.0"],
    fh=f"'Yanone Kaffeesatz','Arial Narrow',{SANS}", fb=f"'Roboto',{SANS}", divchar="&#9679;",
    light=dict(bg="#d9d9d9", ink="#333333", link="#8a4a52", a="#a76a71", s="#f0f0f0", b="#a76a71", m="#555555", g1="#a76a71", g2="#6d7a9b"),
    dark=dict(bg="#3a3a3a", ink="#e6e6e6", link="#e0a6ad", a="#c98a92", s="#4a4a4a", b="#a76a71", m="#bdbdbd", g1="#a76a71", g2="#5b6b94"),
    css=r"""
.t423 .hd,.t423 .bd{border:3px solid transparent;border-radius:6px;background:linear-gradient(var(--s),var(--s)) padding-box,linear-gradient(135deg,var(--g1),var(--g2)) border-box;box-shadow:5px 5px 10px 2px rgba(0,0,0,.35)}
.t423 .hd{display:flex;align-items:center;gap:18px;padding:16px 18px 16px 50px;margin-left:8px}
.t423 .hd::before{content:"";position:absolute;left:-8px;top:50%;width:34px;height:34px;margin-top:-17px;border-radius:50%;background:linear-gradient(135deg,var(--g1),var(--g2));box-shadow:-14px 8px 0 -6px var(--g2),-26px 12px 0 -11px var(--g1)}
.t423 .hd h1,.t423 .hd .by{margin:0}
.t423 .hd{flex-wrap:wrap}
.t423 h1{font-weight:600;letter-spacing:.02em;font-size:max(calc(var(--u) * 30 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.4))}
.t423 .by{flex:1 0 100%}
.t423 .bd{margin-top:22px;padding:14px 16px 4px}
.t423 h2.heading,.t423 h3.title{font-weight:600;letter-spacing:.04em;color:var(--a)}
.t423 .dv{text-align:center;margin:18px 0 8px;color:var(--a)}
.t423 .articleBody blockquote{border-left:3px solid var(--a);padding-left:1em}
""" + mods("t423", "6px", border="2px solid color-mix(in srgb,var(--g1) 60%,transparent)", bg="color-mix(in srgb,var(--g1) 8%,transparent)"),
))

# 24 trash -> dim square, wakes on hover
THEMES.append(dict(
    name="Wake Square", slug="wake-square", cls="t424", credit=credit("trash", "octomoosey"),
    desc="A 600px square that wakes up: the black title container sits at half brightness with a pointer and comes to full brightness on hover (always full on touch screens), the story is a pale port, and chapter headings are charcoal cards with a single orange accent. Black and grey; the same inverted at night.",
    fonts=["Barlow+Condensed:wght@400;600;700", "Barlow:ital,wght@0,400;0,600;1,400"], font_credits=["Barlow, Jeremy Tribby, SIL OFL 1.1"],
    fh=f"'Barlow Condensed','Arial Narrow',{SANS}", fb=f"'Barlow',{SANS}", divchar="&#8203;",
    light=dict(bg="#ffffff", ink="#1a1a1a", link="#b84a00", a="#f26a1b", s="#dddddd", b="#333333", m="#4a4a4a", card="#333333", cardt="#ffffff", cn="#000000", cnt="#ffffff"),
    dark=dict(bg="#101010", ink="#eeeeee", link="#ff9a5a", a="#ff8a3d", s="#1e1e1e", b="#555555", m="#b5b5b5", card="#3a3a3a", cardt="#ffffff", cn="#000000", cnt="#ffffff"),
    css=r"""
.t424{max-width:600px;margin:0 auto}
.t424 .hd{padding:18px 18px 14px;background:var(--cn);color:var(--cnt);border:1px solid #333}
@media (hover:hover){.t424 .hd{opacity:.55;transition:opacity .35s}.t424:hover .hd,.t424 .hd:hover{opacity:1}}
.t424 h1{text-transform:uppercase;letter-spacing:.04em;font-weight:700;font-size:max(calc(var(--u) * 30 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.4))}
.t424 .by{color:var(--cnt);opacity:.8;text-transform:uppercase;letter-spacing:.12em}
.t424 .hd::after{content:"";position:absolute;left:18px;bottom:0;width:48px;height:3px;background:var(--a)}
.t424 .bd{margin-top:14px;padding:14px 16px 4px;background:var(--s);border:1px solid var(--b)}
.t424 h2.heading,.t424 h3.title{display:inline-block;padding:3px 14px;color:var(--cardt);background:var(--card);text-transform:uppercase;letter-spacing:.08em;font-weight:600;font-size:calc(var(--u) * 17)}
.t424 .dv{display:block;height:3px;margin:22px 0;background:var(--a);width:48px}
.t424 .articleBody blockquote{border-left:4px solid var(--card);padding-left:1em}
""" + mods("t424", "0", bg="transparent", border="1px solid var(--b)"),
))

# 25 myst -> translucent tiles, tracked caps
THEMES.append(dict(
    name="Tracked Mist", slug="tracked-mist", cls="t425", credit=credit("myst", "egg.design"),
    desc="Soft translucent tiles drifting over a misty gradient sky: the title is set in light, very widely tracked capitals that open up further on touch. Dusk blue and violet at night; pearl and blue by day.",
    fonts=["Raleway:ital,wght@0,200;0,300;0,400;0,600;1,300"], font_credits=["Raleway, Matt McInerney, Pablo Impallari and Rodrigo Fuenzalida, SIL OFL 1.1"],
    fh=f"'Raleway',{SANS}", fb=f"'Raleway',{SANS}", divchar="&#8203;",
    light=dict(bg="#dfe6ee", ink="#1d2733", link="#2b5f95", a="#4a7fb5", s="rgba(255,255,255,.55)", b="rgba(255,255,255,.8)", m="#46556a"),
    dark=dict(bg="#14202e", ink="#f2f6fa", link="#8fc3f0", a="#6fa8dc", s="rgba(255,255,255,.07)", b="rgba(255,255,255,.2)", m="#b7c6d6"),
    css=r"""
body{background-image:radial-gradient(ellipse 70% 30% at 20% 0%,rgba(111,168,220,.5),transparent),radial-gradient(ellipse 60% 35% at 95% 25%,rgba(190,140,220,.35),transparent)}
.t425 .hd{padding:6px 0 18px}
.t425 h1{text-transform:uppercase;letter-spacing:.3em;font-weight:300;overflow-wrap:anywhere;font-size:max(calc(var(--u) * 22 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.3));transition:letter-spacing .5s}
.t425 .hd:hover h1,.t425 .hd:active h1{letter-spacing:.4em}
.t425 .by{letter-spacing:.2em;text-transform:uppercase;font-weight:300}
.t425 .bd{padding:16px 18px 4px;background:var(--s);border:1px solid var(--b);border-radius:10px;-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px)}
.t425 h2.heading,.t425 h3.title{text-transform:uppercase;letter-spacing:.22em;font-weight:300;font-size:calc(var(--u) * 16)}
.t425 .dv{display:block;height:1px;margin:24px 20%;background:linear-gradient(90deg,transparent,var(--a),transparent)}
.t425 .articleBody a{text-decoration:none;border-bottom:1px solid color-mix(in srgb,var(--nnw-link) 55%,transparent)}
.t425 .articleBody blockquote{border-left:1px solid var(--a);font-weight:300;font-style:italic}
""" + mods("t425", "8px", bg="var(--s)", border="1px solid var(--b)"),
))

# 26 gothica -> book spread with ribbon tabs
THEMES.append(dict(
    name="Ribbon Spread", slug="ribbon-spread", cls="t426", credit=credit("gothica", "egg.design"),
    desc="A bound book: the story page has a rounded outer edge and a thick spine rule, the title is set in blackletter on a cover-colored plate with an asymmetric leaf corner, and chapter headings are ribbon markers with a swallowtail end. Terracotta and parchment by day; terracotta on near-black at night.",
    fonts=["UnifrakturCook:wght@700", "EB+Garamond:ital,wght@0,400;0,600;1,400"], font_credits=["UnifrakturCook, j. 'mach' wust, SIL OFL 1.1", "EB Garamond, Georg Duffner and Octavio Pardo, SIL OFL 1.1"],
    fh=f"'UnifrakturCook','Old English Text MT',{SERIF}", fb=f"'EB Garamond',{SERIF}", divchar="&#10086;",
    light=dict(bg="#f3ebe4", ink="#33241f", link="#8a3b2a", a="#a16456", s="#e8d3cb", b="#a16456", m="#6a524b"),
    dark=dict(bg="#1d1d1d", ink="#efefef", link="#f0b3a4", a="#c0806f", s="#3a2a27", b="#a16456", m="#cbbab4"),
    css=r"""
.t426 .hd{padding:22px 22px 18px;background:var(--a);color:#fff;border-radius:5px 5px 5px 30px;box-shadow:0 0 23px 2px rgba(0,0,0,.28)}
.t426 h1{font-weight:700;letter-spacing:.01em;text-shadow:2px 2px 2px rgba(0,0,0,.35);font-size:max(calc(var(--u) * 34 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.5));line-height:1.05}
.t426 .by{color:#fff;opacity:.88;font-style:italic}
.t426 .bd{margin-top:22px;padding:18px 18px 6px 22px;border-left:10px solid var(--a);border-radius:40px 4px 4px 40px;background:var(--s);box-shadow:0 0 23px 2px rgba(0,0,0,.22);text-align:justify;hyphens:auto}
.t426 h2.heading,.t426 h3.title{display:inline-block;margin-left:-32px;padding:3px 26px 3px 16px;color:#fff;background:var(--a);clip-path:polygon(0 0,100% 0,calc(100% - 12px) 50%,100% 100%,0 100%);font-weight:400;font-size:calc(var(--u) * 21)}
.t426 .dv{text-align:center;color:var(--a);margin:20px 0 10px}
.t426 .articleBody blockquote{border-left:3px solid var(--a);padding-left:1em;font-style:italic}
""" + dropcap("t426", "var(--a)", size="3.4em") + mods("t426", "5px 5px 5px 20px", bg="color-mix(in srgb,var(--a) 14%,transparent)", border="1px solid color-mix(in srgb,var(--a) 50%,transparent)"),
))

# 27 daemonia -> vermilion pill cap, stepped bars
THEMES.append(dict(
    name="Vermilion Cap", slug="vermilion-cap", cls="t427", credit=credit("daemonia", "egg.design"),
    desc="A stage with an orange pill cap: the title plate is a full-bleed vermilion pill with a small ringed circle, three stepped bars (30, 20, 10 pixels wide) step down the story's right edge, and quotes open with a giant curly mark. Vermilion on light grey; vermilion on near-black at night.",
    fonts=["Oswald:wght@400;600;700", "Mukta:wght@400;600;800"], font_credits=["Oswald, Vernon Adams and contributors, SIL OFL 1.1", "Mukta, Ek Type, SIL OFL 1.1"],
    fh=f"'Oswald','Arial Narrow',{SANS}", fb=f"'Mukta',{SANS}", divchar="&#8203;",
    light=dict(bg="#eaeaea", ink="#101010", link="#b8350f", a="#f75222", s="#ffffff", b="#c4c4c4", m="#555555"),
    dark=dict(bg="#1b1b1b", ink="#eaeaea", link="#ff7a52", a="#f75222", s="#101010", b="#444444", m="#b5b5b5"),
    css=r"""
.t427 .hd{margin:20px 0 26px calc(var(--gx) * -1);padding:16px 44px 16px var(--gx);color:#fff;background:var(--a);border-radius:0 100px 100px 0;box-shadow:2px 2px 4px rgba(0,0,0,.4)}
.t427 .hd::before{content:"";position:absolute;right:10px;top:-14px;width:34px;height:34px;box-sizing:border-box;border:3px solid var(--a);border-radius:50%;background:var(--s)}
.t427 h1{font-weight:700;text-transform:uppercase;letter-spacing:.03em;font-size:max(calc(var(--u) * 26 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.35))}
.t427 .by{color:#fff;opacity:.9;font-style:italic;letter-spacing:.1em}
.t427 .bd{position:relative;padding:14px 58px 4px 16px;background:var(--s)}
.t427 .bd::after{content:"";position:absolute;top:0;bottom:0;right:0;width:46px;background:linear-gradient(var(--a),var(--a)) 100% 0/10px 100% no-repeat,linear-gradient(var(--a),var(--a)) calc(100% - 14px) 0/20px 100% no-repeat,linear-gradient(var(--a),var(--a)) calc(100% - 38px) 0/30px 100% no-repeat;opacity:.9;clip-path:inset(0 0 0 0)}
.t427 h2.heading,.t427 h3.title{text-transform:uppercase;letter-spacing:.06em;font-weight:700;color:var(--a);border-bottom:1px solid var(--a);padding-bottom:2px}
.t427 .articleBody blockquote{border:0;margin:.8em 0;padding:0 0 0 1.6em;font-style:italic}
.t427 .articleBody blockquote::before{content:"\201C";float:left;margin:.12em .12em 0 -.5em;font-size:3.2em;line-height:.5;font-weight:700;color:var(--a)}
.t427 .dv{display:block;height:3px;width:60px;margin:22px 0;background:var(--a)}
""" + mods("t427", "0", bg="color-mix(in srgb,var(--b) 40%,transparent)", border="0"),
))

# 28 Gummy Shark -> graph-paper desk
THEMES.append(dict(
    name="Graph Desk", slug="graph-desk", cls="t428", credit=credit("Gummy Shark", "egg.design"),
    desc="A graph-paper desk: the page is a blue grid, the title is a slightly tilted notepaper card held by a strip of translucent tape, and chapter headings are colored index tabs. Teal and sky on pale grid paper; deep teal at night.",
    fonts=["Poppins:ital,wght@0,400;0,600;1,400", "Caveat:wght@500;700"], font_credits=["Poppins, Indian Type Foundry, SIL OFL 1.1", "Caveat, Impallari Type, SIL OFL 1.1"],
    fh=f"'Caveat','Comic Sans MS',cursive", fb=f"'Poppins',{SANS}", divchar="&#9679;",
    light=dict(bg="#f1f6f8", ink="#0d1d24", link="#075277", a="#178cbb", s="#e5f1f4", b="#9cc6d6", m="#34505c", grid="rgba(23,140,187,.22)", tape="#028a98", tab1="#87ceeb", tab2="#beefed"),
    dark=dict(bg="#14222a", ink="#e8f4f7", link="#7fd0ec", a="#4fb4d6", s="#1d3440", b="#3a6c80", m="#a8c8d4", grid="rgba(79,180,214,.18)", tape="#1b9aa8", tab1="#2a6f8a", tab2="#2c7a6c"),
    css=r"""
body{background-image:linear-gradient(var(--grid) 1px,transparent 1px),linear-gradient(90deg,var(--grid) 1px,transparent 1px);background-size:22px 22px}
.t428 .hd{margin:10px 0 28px;padding:20px 20px 16px;background:var(--s);border:1px solid var(--b);transform:rotate(-1deg);box-shadow:0 2px 0 rgba(0,0,0,.12)}
.t428 .hd::before{content:"";position:absolute;top:-10px;left:50%;width:84px;height:22px;transform:translateX(-50%) rotate(-2deg);background:color-mix(in srgb,var(--tape) 55%,transparent);box-shadow:0 1px 0 rgba(0,0,0,.1)}
.t428 h1{font-weight:700;font-size:max(calc(var(--u) * 34 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.5));line-height:1}
.t428 .bd{padding:16px 16px 4px;background:color-mix(in srgb,var(--nnw-bg) 88%,transparent);border:1px solid var(--b);border-radius:4px}
.t428 h2.heading,.t428 h3.title{display:inline-block;padding:2px 16px;border-radius:6px 6px 0 0;font-weight:700;font-size:calc(var(--u) * 24)}
.t428 h2.heading:nth-of-type(odd),.t428 h3.title:nth-of-type(odd){background:var(--tab1);color:#0d1d24}
.t428 h2.heading:nth-of-type(even),.t428 h3.title:nth-of-type(even){background:var(--tab2);color:#0d1d24}
.t428 .articleBody a{text-decoration:underline dashed;text-decoration-thickness:2.4px;text-underline-offset:3px}
.t428 .dv{text-align:center;margin:20px 0 8px;color:var(--a)}
.t428 .articleBody blockquote{border-left:4px solid var(--tape);padding-left:1em}
""" + mods("t428", "4px", bg="var(--s)", border="1px solid var(--b)"),
))

# 29 Starlight FAQ -> question and answer cards
THEMES.append(dict(
    name="Dusk Cards", slug="dusk-cards", cls="t429", credit=credit("Starlight FAQ", "wovenstarlight"),
    desc="Question-and-answer cards at twilight: the title is a lavender question card with a star badge notched out of its corner, chapter headings are peach-to-gold answer cards, and quotes are salmon panels with a soft border. The page stays plain so the cards carry the color. Indigo at night; pale lavender by day.",
    fonts=["Lato:ital,wght@0,400;0,700;1,400"], font_credits=["Lato, Lukasz Dziedzic, SIL OFL 1.1"],
    fh=f"'Lato',{SANS}", fb=f"'Lato',{SANS}", divchar="&#10022;",
    light=dict(bg="#f6f0ff", ink="#201b33", link="#8a2f66", a="#7a56c4", s="#efe6fb", b="#cbb2ed", m="#4f4570", q1="#cbb2ed", q2="#e3d3fa", a1="#fbab97", a2="#f9c98e"),
    dark=dict(bg="#201b33", ink="#f1e9ff", link="#ffb99f", a="#cbb2ed", s="#2c2646", b="#4a3f72", m="#c2b8dc", q1="#cbb2ed", q2="#e3d3fa", a1="#fbab97", a2="#f9c98e"),
    css=r"""
.t429 .hd{margin:12px 0 26px;padding:18px 22px;color:#1a1230;background:linear-gradient(135deg,var(--q1),var(--q2));border-radius:16px;box-shadow:0 4px 0 rgba(0,0,0,.18)}
.t429 .hd::after{content:"\2605";position:absolute;right:-6px;top:-10px;display:flex;align-items:center;justify-content:center;width:34px;height:34px;border-radius:50%;color:#1a1230;background:var(--a2);box-shadow:0 0 0 4px var(--nnw-bg)}
.t429 h1{font-weight:700;color:#1a1230;font-size:max(calc(var(--u) * 24 * var(--nnw-detail-scale, 1)), calc(var(--nnw-prose-size, calc(var(--u) * 15)) * 1.35))}
.t429 .by{color:#3b2f5e}
.t429 h2.heading,.t429 h3.title{display:block;padding:8px 16px;color:#2a1608;background:linear-gradient(135deg,var(--a1),var(--a2));border-radius:14px;font-weight:700;font-size:calc(var(--u) * 17);margin:6px 0 12px}
.t429 .dv{text-align:center;color:var(--a);margin:20px 0 8px}
.t429 .articleBody blockquote{border:1px solid #b86c53;border-left-width:1px;border-radius:12px;background:color-mix(in srgb,var(--a1) 22%,transparent);padding:.5em 1em}
.t429 .articleBody a{font-weight:700;text-decoration:underline;text-underline-offset:.18em}
""" + mods("t429", "14px", bg="color-mix(in srgb,var(--q1) 25%,transparent)", border="1px solid color-mix(in srgb,var(--q1) 70%,transparent)"),
))
