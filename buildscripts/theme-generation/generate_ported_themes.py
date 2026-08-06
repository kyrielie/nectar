# Generates the 9 palette-ported .nnwtheme bundles listed in
# nectar-personalization-plan.md's theme table (Rosé Pine Moon/Dawn, Black &
# White, Charcoal Rose, Dusky Purple, Midnight Teal, Powder Pink, Tumblr
# Blue, Constellations). Run from the repo root: `python3
# buildscripts/theme-generation/generate_ported_themes.py`. Re-running
# overwrites the generated bundles in place -- Beetlejuice and Vintage
# Letter Green are hand-written, not generated, and this script doesn't
# touch them.
import os

BASE_DIR = "Themes"

STYLESHEET_TEMPLATE = """/* {name} -- {credit_comment}
   Palette:
     body background   <- {bg}
     body text          <- {text}
     link                <- {link}
     header border        <- {header_border}
     table/rule border     <- {table_border}
   {differentiation_comment}
   Structure follows the bundled Sepia.nnwtheme (same selectors, same
   iOS/macOS @supports split); shared iOS/macOS structural rules (max-width,
   hyphens, footnote popover, table borders, etc.) are the same base every
   bundled theme needs so embeds/footnotes/tables don't fall back to
   unstyled defaults. */

body {{
\tmargin-left: auto;
\tmargin-right: auto;
\tword-wrap: break-word;
\tmax-width: 44em;
\tbackground-color: {bg};
\tcolor: {text};
}}

[href] {{
{link_underline_css}
}}
[href]:hover {{
{link_hover_css}
}}

#nnwImageIcon {{
\twidth: 32px;
\theight: 32px;
\tmargin-right: 0.2em;
}}

.systemMessage {{
\tposition: absolute;
\ttop: 45%;
\tleft: 50%;
\ttransform: translateX(-55%) translateY(-50%);
\t-webkit-user-select: none;
\tcursor: default;
}}

:root {{
\t--header-table-border-color: {header_border};
\t--header-color: {header_text};
\t--body-code-color: {code_color};
\t--system-message-color: {header_text};
\t--feedlink-color: {text};
\t--article-title-color: {text};
\t--article-date-color: {header_text};
\t--table-cell-border-color: {table_border};
\t--primary-accent-color: {link};
\t--secondary-accent-color: {link};
\t--block-quote-border-color: {blockquote_border};
\t--link-underline-color: {link_underline_color};
\t--link-underline-special: {link_underline_special};
\t/* Consumed by core.css's #ao3SyntheticPreface/#ao3Preface rules. */
\t--ao3-preface-border-color: {preface_border};
}}

/* Exact-selector fallback for ArticleThemeColorExtractor -- additive only,
   higher-specificity 'body a' below still wins the cascade. See the fix
   applied to Ember/Sepia/Tiqoe Dark/Rose Pine for why this is needed. */
a {{
\tcolor: {link};
}}

body a,
body a:visited,
body a * {{
\tcolor: {link};
}}

body > header {{
\tborder-bottom: 1px solid var(--header-table-border-color);
\tpadding-bottom: 0.5rem;
}}

body > header a,
body > header a:link,
body > header a:visited {{
\tcolor: var(--header-color);
}}
body > header .headerTable {{
\twidth: 100%;
}}
body > header .headerTable td,
body > header .headerTable th {{
\tcolor: var(--header-color);
\tpadding: 0.2em;
\tborder: none;
\tfont-family: {header_font};
\tfont-size: 0.9rem;
{header_extra}}}
body > header .headerTable td.avatar {{
\twidth: 33%;
}}

body code,
body pre {{
\tcolor: var(--body-code-color);
}}

body > .systemMessage {{
\tcolor: var(--system-message-color);
}}

.headerContainer a[href] {{
\ttext-decoration-color: var(--link-underline-special);
\tcolor: var(--feedlink-color);
}}

.avatar img {{
\tborder-radius: {avatar_radius};
}}

.feedIcon {{
\tborder-radius: {avatar_radius};
}}

.rightAlign {{
\ttext-align: end;
}}

.leftAlign {{
\ttext-align: start;
}}

.articleTitle [href] {{
\ttext-decoration-color: transparent;
\tcolor: var(--article-title-color);
\tmargin-top: 26px;
{title_extra}}}

.articleDateline {{
\tmargin-bottom: 5px;
\tfont-weight: bold;
{dateline_extra}}}

.articleDateline [href] {{
\ttext-decoration-color: var(--link-underline-special);
\tcolor: var(--article-date-color);
}}

.articleDatelineTitle {{
\tmargin-bottom: 5px;
\tfont-weight: bold;
}}

.articleDatelineTitle [href] {{
\tcolor: var(--article-title-color);
}}

.externalLink {{
\tmargin-bottom: 5px;
\tfont-style: italic;
\twidth: 100%;
\twhite-space: nowrap;
\toverflow: hidden;
\ttext-overflow: ellipsis;
}}

.articleBody {{
\tmargin-top: 20px;
\tline-height: 1.6em;
}}

h1 {{
\tline-height: 1.15em;
\tfont-weight: bold;
\tpadding-bottom: 0;
\tmargin-bottom: 5px;
}}

pre {{
\tmax-width: 100%;
\tmargin: 0;
\toverflow: auto;
\toverflow-y: hidden;
\tword-wrap: normal;
\tword-break: normal;
\tline-height: 1.4286em;
}}

code,
pre {{
\tfont-family: {code_font};
\tfont-size: 0.85rem;
\tletter-spacing: -0.027em;
\t-webkit-hyphens: none;
}}

.nnw-overflow {{
\toverflow-x: auto;
}}

.nnw-overflow table {{
\tmargin-bottom: 1px;
\tborder-spacing: 0;
\tborder: 1px solid var(--table-cell-border-color);
\tfont-size: inherit;
{table_extra}}}

.nnw-overflow table table {{
\tmargin-bottom: 0;
\tborder: none;
}}

.nnw-overflow td,
.nnw-overflow th {{
\t-webkit-hyphens: none;
\tword-break: normal;
\tborder: 1px solid var(--table-cell-border-color);
\tborder-top: none;
\tborder-left: none;
\tpadding: 5px;
}}

.nnw-overflow tr :matches(td, th):last-child {{
\tborder-right: none;
}}

.nnw-overflow
\t:matches(thead, tbody, tfoot):last-child
\t> tr:last-child
\t:matches(td, th) {{
\tborder-bottom: none;
}}

.nnw-overflow td pre {{
\tborder: none;
\tpadding: 0;
}}

.nnw-overflow table[border="0"] {{
\tborder-width: 0;
}}

img,
figure,
video,
div,
object {{
\tmax-width: 100%;
\theight: auto !important;
\tmargin: 0 auto;
}}

iframe {{
\tmax-width: 100%;
\tmargin: 0 auto;
}}

iframe.nnw-constrained {{
\tmax-height: 50vw;
}}

figure {{
\tmargin-bottom: 1em;
\tmargin-top: 1em;
}}

figcaption {{
\tfont-size: 14px;
\tline-height: 1.3em;
\tcolor: var(--header-color);
}}

sup {{
\tvertical-align: top;
\tposition: relative;
\tbottom: 0.2rem;
}}

sub {{
\tvertical-align: bottom;
\tposition: relative;
\ttop: 0.2rem;
}}

hr {{
{hr_style}}}

.iframeWrap {{
\tposition: relative;
\tdisplay: block;
\tpadding-top: 56.25%;
}}

.iframeWrap iframe {{
\tposition: absolute;
\ttop: 0;
\tleft: 0;
\theight: 100% !important;
\twidth: 100% !important;
}}

blockquote {{
\tmargin-inline-start: 0;
\tmargin-inline-end: 0;
\tpadding-inline-start: 15px;
\tborder-inline-start: {blockquote_width} {blockquote_style} var(--block-quote-border-color);
{blockquote_extra}}}

/* Feed Specific */

.feedbin--article-wrap {{
\tborder-top: 1px solid var(--header-table-border-color);
}}

/* Twitter */

.twitterAvatar {{
\tvertical-align: middle;
\tborder-radius: 4px;
\theight: 1.7em;
\twidth: 1.7em;
}}

.twitterUsername {{
\tline-height: 1.2;
\tmargin-left: 4px;
\tdisplay: inline-block;
\tvertical-align: middle;
}}

.twitterScreenName {{
\tfont-size: 66%;
}}

.twitterTimestamp {{
\tfont-size: 66%;
}}

/* Newsfoot theme */
.newsfoot-footnote-popover {{
\tbackground: {popover_bg};
\tbox-shadow: {popover_shadow};
\tcolor: {text};
\tpadding: 1px;
{popover_extra}}}

.newsfoot-footnote-popover-arrow {{
\tbackground: {popover_arrow_bg};
\tborder: 1px solid var(--table-cell-border-color);
}}

.newsfoot-footnote-popover-inner {{
\tbackground: {popover_arrow_bg};
{popover_extra}}}

body a.footnote,
body a.footnote:visited,
.newsfoot-footnote-popover + a.footnote:hover {{
\tbackground: var(--table-cell-border-color);
\tcolor: {text};
\ttransition: background-color 200ms ease-out;
}}

a.footnote:hover,
.newsfoot-footnote-popover + a.footnote {{
\tbackground: {link};
\tcolor: {bg};
\ttransition: background-color 200ms ease-out;
}}

/* AO3 direct-reading preface (#ao3SyntheticPreface/#ao3Preface structural
   rules live in core.css -- this theme only supplies appearance). */
#ao3SyntheticPreface,
#ao3Preface {{
{preface_extra}}}
#ao3SyntheticPreface dt,
#ao3Preface dt {{
{preface_dt_extra}}}

.ao3ChapterFetchNotice {{
\tmargin: 0 0 1em 0;
\tpadding: 0.6em 0.8em;
{notice_extra}\tfont-size: 0.9em;
\tfont-style: italic;
\tcolor: var(--header-color);
}}

/* iOS Specific */
@supports (-webkit-touch-callout: none) {{
\tbody {{
\t\tmargin-top: 3px;
\t\tmargin-bottom: 20px;
\t\tpadding-left: 20px;
\t\tpadding-right: 20px;

\t\tword-break: break-word;
\t\t-webkit-hyphens: auto;
\t\t-webkit-text-size-adjust: none;
\t\tfont-family: {body_font};
\t\tfont-size: [[font-size]]px;
{ios_title_transform}\t}}

\t.articleTitle h1 {{
\t\tfont-size: 1.5em;
\t}}

\tpre {{
\t\tborder: 1px solid var(--table-cell-border-color);
\t\tpadding: 5px;
\t}}

\t.nnw-overflow table {{
\t\tborder: 1px solid var(--table-cell-border-color);
\t}}
}}

/* macOS Specific */
@supports not (-webkit-touch-callout: none) {{
\tbody {{
\t\tmargin-top: 20px;
\t\tmargin-bottom: 64px;
\t\tpadding-left: 48px;
\t\tpadding-right: 48px;
\t\tfont-family: {body_font};
\t}}

\t.smallText {{
\t\tfont-size: 14px;
\t}}

\t.mediumText {{
\t\tfont-size: 16px;
\t}}

\t.largeText {{
\t\tfont-size: 18px;
\t}}

\t.xlargeText {{
\t\tfont-size: 20px;
\t}}

\t.xxlargeText {{
\t\tfont-size: 22px;
\t}}

\tpre {{
\t\tborder: 1px solid {link};
\t\tpadding: 10px;
\t}}

\t.nnw-overflow table {{
\t\tborder: 1px solid {link};
\t}}
}}
"""

PLIST_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>Name</key>
\t<string>{name}</string>
\t<key>ThemeIdentifier</key>
\t<string>com.nectar.themes.{identifier}</string>
\t<key>CreatorHomePage</key>
\t<string>{homepage}</string>
\t<key>CreatorName</key>
\t<string>{creator}</string>
\t<key>Version</key>
\t<integer>1</integer>
</dict>
</plist>
"""

themes = [
    dict(
        name="Rosé Pine Moon",
        identifier="rosepinemoon",
        homepage="https://github.com/Wolfbatcat/ao3-rose-pine",
        creator='Ported from the "Rosé Pine Moon" variant of BlackBatCat\'s AO3 workskin "Rosé Pine — Closer to Home" (MIT licensed)',
        credit_comment="ported from the Rosé Pine Moon variant of the ao3-rose-pine workskin (BlackBatCat, MIT). Same family as the bundled Rosé Pine theme, one step darker/more saturated -- its own standalone theme rather than a dark-mode variant of Rosé Pine, matching how the source skin ships it.",
        differentiation_comment="Differentiation from Rosé Pine: dotted (not solid) link underline, and italicized article titles -- Moon leans slightly more literary/nocturnal than the base theme.",
        bg="#232136", text="#e0def4", link="#eb6f92",
        header_border="#36324e", table_border="#36324e", header_text="#908caa",
        code_color="#ebbcba", preface_border="rgba(224, 222, 244, 0.15)",
        link_underline_color="color-mix(in hsl, currentColor, transparent 40%)",
        link_underline_special="color-mix(in hsl, currentColor, transparent 80%)",
        blockquote_border="#36324e", blockquote_width="3px", blockquote_style="solid", blockquote_extra="",
        header_font="sans-serif", header_extra="", avatar_radius="4px",
        title_extra="\tfont-style: italic;\n", dateline_extra="",
        code_font='"SF Mono", Menlo, "Courier New", Courier, monospace',
        table_extra="", hr_style="\tborder: 1.5px solid var(--table-cell-border-color);\n",
        popover_bg="#26233a", popover_shadow="0 2px 4px rgba(0, 0, 0, 0.5), 0 3px 6px rgba(0, 0, 0, 0.25)",
        popover_arrow_bg="#1f1d2e", popover_extra="",
        preface_extra="\tborder-bottom-style: dotted;\n", preface_dt_extra="",
        notice_extra="\tborder-left: 3px solid rgba(0, 0, 0, 0.3);\n\tbackground: rgba(0, 0, 0, 0.15);\n",
        body_font="Charter, Georgia, sans-serif", ios_title_transform="",
        link_underline_css="\ttext-decoration-line: underline;\n\ttext-decoration-style: dotted;\n\ttext-decoration-color: var(--link-underline-color);\n\ttext-decoration-thickness: 1px;\n\ttext-underline-offset: 0.15em;",
        link_hover_css="\ttext-shadow: 0 1px rgba(0, 0, 0, 0.4);\n\topacity: 0.85;\n\tcolor: color-mix(in hsl, var(--link-underline-color), white 20%);",
    ),
    dict(
        name="Rosé Pine Dawn",
        identifier="rosepinedawn",
        homepage="https://github.com/Wolfbatcat/ao3-rose-pine",
        creator='Ported from the "Rosé Pine Dawn" variant of BlackBatCat\'s AO3 workskin "Rosé Pine — Closer to Home" (MIT licensed)',
        credit_comment="ported from the Rosé Pine Dawn (light) variant of the ao3-rose-pine workskin (BlackBatCat, MIT). Same link hue as the other two Rosé Pine themes on a warm cream background instead of ink.",
        differentiation_comment="Differentiation: solid underline (not dotted) since it's a light theme where dotted underlines read as weaker against cream than they do against ink; slightly heavier preface card treatment (light background tint + rounded corners) rather than a bare rule.",
        bg="#faf4ed", text="#575279", link="#eb6f92",
        header_border="#e7d3cb", table_border="#e7d3cb", header_text="#797593",
        code_color="#d7827e", preface_border="rgba(87, 82, 121, 0.15)",
        link_underline_color="color-mix(in hsl, currentColor, transparent 40%)",
        link_underline_special="color-mix(in hsl, currentColor, transparent 80%)",
        blockquote_border="#e7d3cb", blockquote_width="3px", blockquote_style="solid", blockquote_extra="",
        header_font="sans-serif", header_extra="", avatar_radius="4px",
        title_extra="", dateline_extra="",
        code_font='"SF Mono", Menlo, "Courier New", Courier, monospace',
        table_extra="", hr_style="\tborder: 1.5px solid var(--table-cell-border-color);\n",
        popover_bg="#fffaf3", popover_shadow="0 2px 4px rgba(87, 82, 121, 0.15), 0 3px 6px rgba(87, 82, 121, 0.08)",
        popover_arrow_bg="#f2e9e1", popover_extra="",
        preface_extra="\tborder: 1px solid var(--ao3-preface-border-color);\n\tborder-radius: 8px;\n\tpadding: 0.8em 1em 1em 1em;\n\tbackground: rgba(87, 82, 121, 0.03);\n",
        preface_dt_extra="",
        notice_extra="\tborder-left: 3px solid rgba(87, 82, 121, 0.3);\n\tbackground: rgba(87, 82, 121, 0.06);\n",
        body_font="Charter, Georgia, sans-serif", ios_title_transform="",
        link_underline_css="\ttext-decoration-line: underline;\n\ttext-decoration-style: solid;\n\ttext-decoration-color: var(--link-underline-color);\n\ttext-decoration-thickness: 1px;\n\ttext-underline-offset: 0.15em;",
        link_hover_css="\topacity: 0.75;\n\tcolor: color-mix(in hsl, var(--link-underline-color), black 15%);",
    ),
    dict(
        name="Black & White",
        identifier="blackandwhite",
        homepage="https://github.com/ZerafinaCSS/neos",
        creator='Ported from the "Black & White" variant of ZerafinaCSS\'s "neos" AO3 workskin family (MIT licensed)',
        credit_comment="ported from the Black & White variant of the neos AO3 workskin family (ZerafinaCSS, MIT). Pure monochrome, no accent hue -- link color is body text color, distinguished by underline weight and small-caps instead.",
        differentiation_comment="Real structural differentiation, not just recolor: monospaced/typewriter body font (Menlo/Courier) instead of the serif every other bundled theme uses, uppercase small-caps dateline and preface labels, thick 2px borders throughout, square (not rounded) avatar corners -- reads like a printed manuscript rather than a magazine page.",
        bg="#FFFFFF", text="#000000", link="#000000",
        header_border="#000000", table_border="#D6D6D6", header_text="#000000",
        code_color="#000000", preface_border="rgba(0, 0, 0, 0.3)",
        link_underline_color="currentColor",
        link_underline_special="currentColor",
        blockquote_border="#000000", blockquote_width="2px", blockquote_style="solid", blockquote_extra="",
        header_font="Menlo, \"Courier New\", Courier, monospace", header_extra="\ttext-transform: uppercase;\n\tletter-spacing: 0.04em;\n",
        avatar_radius="0px",
        title_extra="\ttext-transform: uppercase;\n\tletter-spacing: 0.02em;\n", dateline_extra="\tfont-variant: small-caps;\n\tletter-spacing: 0.04em;\n",
        code_font='Menlo, "Courier New", Courier, monospace',
        table_extra="\tborder-width: 2px;\n", hr_style="\tborder: 2px solid #000000;\n",
        popover_bg="#FFFFFF", popover_shadow="0 0 0 2px #000000",
        popover_arrow_bg="#FFFFFF", popover_extra="\tborder: 2px solid #000000;\n",
        preface_extra="\tborder-bottom-width: 2px;\n", preface_dt_extra="\tfont-variant: small-caps;\n\tletter-spacing: 0.04em;\n",
        notice_extra="\tborder-left: 3px solid #000000;\n\tbackground: #F5F5F5;\n",
        body_font='Menlo, "Courier New", Courier, monospace', ios_title_transform="",
        link_underline_css="\ttext-decoration-line: underline;\n\ttext-decoration-style: solid;\n\ttext-decoration-color: currentColor;\n\ttext-decoration-thickness: 2px;\n\ttext-underline-offset: 0.15em;",
        link_hover_css="\ttext-decoration-thickness: 3px;",
    ),
    dict(
        name="Charcoal Rose",
        identifier="charcoalrose",
        homepage="https://github.com/ZerafinaCSS/neos",
        creator='Ported from the "Charcoal Rose" variant of ZerafinaCSS\'s "neos" AO3 workskin family (MIT licensed)',
        credit_comment="ported from the Charcoal Rose variant of the neos AO3 workskin family (ZerafinaCSS, MIT). Warm charcoal background with dusty rose text and a brighter pink link accent.",
        differentiation_comment="Differentiation: italic serif titles and a soft rose glow on link hover (text-shadow), dashed rose preface border with generous padding -- softer and more romantic than Rosé Pine's crisper look despite a similar dark-plus-pink family.",
        bg="#1D1D1D", text="#D3C5C8", link="#F59DB3",
        header_border="#2B2B2B", table_border="#434343", header_text="#A38F93",
        code_color="#F59DB3", preface_border="rgba(211, 197, 200, 0.2)",
        link_underline_color="color-mix(in hsl, currentColor, transparent 35%)",
        link_underline_special="color-mix(in hsl, currentColor, transparent 75%)",
        blockquote_border="#434343", blockquote_width="3px", blockquote_style="solid", blockquote_extra="",
        header_font="sans-serif", header_extra="", avatar_radius="6px",
        title_extra="\tfont-style: italic;\n", dateline_extra="",
        code_font='"SF Mono", Menlo, "Courier New", Courier, monospace',
        table_extra="", hr_style="\tborder: 1.5px solid var(--table-cell-border-color);\n",
        popover_bg="#2B2B2B", popover_shadow="0 2px 4px rgba(0, 0, 0, 0.5), 0 3px 6px rgba(0, 0, 0, 0.25)",
        popover_arrow_bg="#1D1D1D", popover_extra="",
        preface_extra="\tborder-bottom-style: dashed;\n\tpadding-bottom: 1.4em;\n",
        preface_dt_extra="\tcolor: var(--primary-accent-color);\n",
        notice_extra="\tborder-left: 3px solid rgba(245, 157, 179, 0.4);\n\tbackground: rgba(245, 157, 179, 0.06);\n",
        body_font="Charter, Georgia, sans-serif", ios_title_transform="",
        link_underline_css="\ttext-decoration-line: underline;\n\ttext-decoration-style: solid;\n\ttext-decoration-color: var(--link-underline-color);\n\ttext-decoration-thickness: 1px;\n\ttext-underline-offset: 0.15em;",
        link_hover_css="\ttext-shadow: 0 0 6px rgba(245, 157, 179, 0.5);\n\tcolor: color-mix(in hsl, var(--link-underline-color), white 15%);",
    ),
    dict(
        name="Dusky Purple",
        identifier="duskypurple",
        homepage="https://github.com/ZerafinaCSS/neos",
        creator='Ported from the "Dusky Purple" (dusky-dark-purple) variant of ZerafinaCSS\'s "neos" AO3 workskin family (MIT licensed)',
        credit_comment="ported from the dusky-dark-purple variant of the neos AO3 workskin family (ZerafinaCSS, MIT). Deep plum background with a muted mauve text color and a saturated magenta-purple link accent.",
        differentiation_comment="Differentiation: dotted plum link underline, moody wide-letter-spaced small-caps dateline, rounded preface card in a deeper plum tint than the page background -- reads more gothic/velvet than Rosé Pine's cooler jewel tones.",
        bg="#262029", text="#BD8A96", link="#AD396F",
        header_border="#302433", table_border="#472E44", header_text="#8E6B76",
        code_color="#D3789A", preface_border="rgba(189, 138, 150, 0.2)",
        link_underline_color="color-mix(in hsl, currentColor, transparent 40%)",
        link_underline_special="color-mix(in hsl, currentColor, transparent 80%)",
        blockquote_border="#472E44", blockquote_width="3px", blockquote_style="solid", blockquote_extra="",
        header_font="sans-serif", header_extra="", avatar_radius="8px",
        title_extra="", dateline_extra="\tfont-variant: small-caps;\n\tletter-spacing: 0.06em;\n",
        code_font='"SF Mono", Menlo, "Courier New", Courier, monospace',
        table_extra="", hr_style="\tborder: 1.5px solid var(--table-cell-border-color);\n",
        popover_bg="#302433", popover_shadow="0 2px 4px rgba(0, 0, 0, 0.5), 0 3px 6px rgba(0, 0, 0, 0.25)",
        popover_arrow_bg="#262029", popover_extra="",
        preface_extra="\tborder: 1px solid var(--ao3-preface-border-color);\n\tborder-radius: 10px;\n\tpadding: 0.8em 1em 1em 1em;\n\tbackground: #302433;\n",
        preface_dt_extra="\tfont-variant: small-caps;\n\tletter-spacing: 0.03em;\n",
        notice_extra="\tborder-left: 3px solid rgba(173, 57, 111, 0.4);\n\tbackground: rgba(173, 57, 111, 0.08);\n",
        body_font="Charter, Georgia, sans-serif", ios_title_transform="",
        link_underline_css="\ttext-decoration-line: underline;\n\ttext-decoration-style: dotted;\n\ttext-decoration-color: var(--link-underline-color);\n\ttext-decoration-thickness: 1px;\n\ttext-underline-offset: 0.15em;",
        link_hover_css="\topacity: 0.85;\n\tcolor: color-mix(in hsl, var(--link-underline-color), white 20%);",
    ),
    dict(
        name="Midnight Teal",
        identifier="midnightteal",
        homepage="https://github.com/ZerafinaCSS/neos",
        creator='Ported from the "Midnight Teal" (midnight-black) variant of ZerafinaCSS\'s "neos" AO3 workskin family (MIT licensed)',
        credit_comment="ported from the midnight-black variant of the neos AO3 workskin family (ZerafinaCSS, MIT). True-black background, pale teal-gray text, a bright cyan-teal link accent.",
        differentiation_comment="Differentiation: geometric sans-serif body font (not the serif every other bundled theme defaults to) for a cleaner, more modern-editorial feel, no link underline at all -- links are bold and colored only, like a UI rather than a printed page -- and a left-accent-bar preface treatment instead of a bottom rule.",
        bg="#000000", text="#DAE6E1", link="#00A8AD",
        header_border="#111515", table_border="#333B3B", header_text="#7A8C89",
        code_color="#4DD9DD", preface_border="#00A8AD",
        link_underline_color="transparent",
        link_underline_special="transparent",
        blockquote_border="#333B3B", blockquote_width="3px", blockquote_style="solid", blockquote_extra="",
        header_font="-apple-system, sans-serif", header_extra="", avatar_radius="4px",
        title_extra="", dateline_extra="",
        code_font='"SF Mono", Menlo, "Courier New", Courier, monospace',
        table_extra="", hr_style="\tborder: 1.5px solid var(--table-cell-border-color);\n",
        popover_bg="#111515", popover_shadow="0 2px 4px rgba(0, 0, 0, 0.6), 0 3px 6px rgba(0, 0, 0, 0.35)",
        popover_arrow_bg="#000000", popover_extra="",
        preface_extra="\tborder-bottom: none;\n\tborder-left: 3px solid var(--ao3-preface-border-color);\n\tpadding-left: 1em;\n",
        preface_dt_extra="\tcolor: var(--primary-accent-color);\n",
        notice_extra="\tborder-left: 3px solid #00A8AD;\n\tbackground: rgba(0, 168, 173, 0.08);\n",
        body_font="-apple-system, \"SF Pro Text\", sans-serif", ios_title_transform="",
        link_underline_css="\ttext-decoration-line: none;\n\tfont-weight: 600;",
        link_hover_css="\ttext-decoration-line: underline;\n\ttext-decoration-thickness: 1px;",
    ),
    dict(
        name="Powder Pink",
        identifier="powderpink",
        homepage="https://github.com/ZerafinaCSS/neos",
        creator='Ported from the "Powder Pink" variant of ZerafinaCSS\'s "neos" AO3 workskin family (MIT licensed)',
        credit_comment="ported from the Powder Pink variant of the neos AO3 workskin family (ZerafinaCSS, MIT). Off-white background, deep berry text, a saturated pink link accent -- higher-contrast than the pastel-on-pastel look the name might suggest.",
        differentiation_comment="Differentiation: rounded sans-serif body font and fully rounded corners throughout (avatar, preface card, table, popover) for a softer, friendlier feel than the serif-and-square treatment most other bundled themes share; link underline is a thicker pink line rather than the thin 1px default.",
        bg="#F7F6F5", text="#6C2D52", link="#D44E8B",
        header_border="#FCFCFC", table_border="#D8D2D2", header_text="#9C5C7E",
        code_color="#B23D6E", preface_border="rgba(108, 45, 82, 0.15)",
        link_underline_color="color-mix(in hsl, currentColor, transparent 20%)",
        link_underline_special="color-mix(in hsl, currentColor, transparent 70%)",
        blockquote_border="#D8D2D2", blockquote_width="3px", blockquote_style="solid", blockquote_extra="",
        header_font="-apple-system, sans-serif", header_extra="", avatar_radius="50%",
        title_extra="", dateline_extra="",
        code_font='"SF Mono", Menlo, "Courier New", Courier, monospace',
        table_extra="\tborder-radius: 8px;\n", hr_style="\tborder: none;\n\tborder-top: 1px solid var(--table-cell-border-color);\n",
        popover_bg="#FFFFFF", popover_shadow="0 2px 4px rgba(108, 45, 82, 0.12), 0 3px 6px rgba(108, 45, 82, 0.06)",
        popover_arrow_bg="#FCFCFC", popover_extra="\tborder-radius: 8px;\n",
        preface_extra="\tborder: 1px solid var(--ao3-preface-border-color);\n\tborder-radius: 12px;\n\tpadding: 0.8em 1em 1em 1em;\n\tbackground: #FFFFFF;\n",
        preface_dt_extra="\tcolor: var(--primary-accent-color);\n",
        notice_extra="\tborder-left: 3px solid rgba(212, 78, 139, 0.4);\n\tbackground: rgba(212, 78, 139, 0.06);\n",
        body_font="-apple-system, \"SF Pro Text\", sans-serif", ios_title_transform="",
        link_underline_css="\ttext-decoration-line: underline;\n\ttext-decoration-style: solid;\n\ttext-decoration-color: var(--link-underline-color);\n\ttext-decoration-thickness: 2px;\n\ttext-underline-offset: 0.15em;",
        link_hover_css="\topacity: 0.8;",
    ),
    dict(
        name="Tumblr Blue",
        identifier="tumblrblue",
        homepage="https://github.com/ZerafinaCSS/neos",
        creator='Ported from the "Tumblr Blue" variant of ZerafinaCSS\'s "neos" AO3 workskin family (MIT licensed)',
        credit_comment="ported from the tumblr-blue variant of the neos AO3 workskin family (ZerafinaCSS, MIT). Deep navy background, light gray body text, classic Tumblr-blue link accent.",
        differentiation_comment="Differentiation: bold, no-underline links (Tumblr's own dashboard convention) with an underline only on hover, flat sans-serif throughout instead of a serif body face, and a semi-transparent white preface card echoing the source skin's translucent-panel-on-navy look.",
        bg="#1A2735", text="#B3B3B3", link="#529ECC",
        header_border="transparent", table_border="rgba(255, 255, 255, 0.13)", header_text="#7A8A99",
        code_color="#7EC0E8", preface_border="rgba(255, 255, 255, 0.13)",
        link_underline_color="transparent",
        link_underline_special="transparent",
        blockquote_border="rgba(255, 255, 255, 0.13)", blockquote_width="3px", blockquote_style="solid", blockquote_extra="",
        header_font="-apple-system, sans-serif", header_extra="", avatar_radius="4px",
        title_extra="", dateline_extra="",
        code_font='"SF Mono", Menlo, "Courier New", Courier, monospace',
        table_extra="", hr_style="\tborder: none;\n\tborder-top: 1px solid rgba(255, 255, 255, 0.13);\n",
        popover_bg="#233043", popover_shadow="0 2px 4px rgba(0, 0, 0, 0.5), 0 3px 6px rgba(0, 0, 0, 0.25)",
        popover_arrow_bg="#1A2735", popover_extra="",
        preface_extra="\tborder: 1px solid var(--ao3-preface-border-color);\n\tborder-radius: 6px;\n\tpadding: 0.8em 1em 1em 1em;\n\tbackground: rgba(255, 255, 255, 0.04);\n",
        preface_dt_extra="\tcolor: var(--primary-accent-color);\n",
        notice_extra="\tborder-left: 3px solid rgba(82, 158, 204, 0.4);\n\tbackground: rgba(82, 158, 204, 0.08);\n",
        body_font="-apple-system, \"SF Pro Text\", sans-serif", ios_title_transform="",
        link_underline_css="\ttext-decoration-line: none;\n\tfont-weight: 700;",
        link_hover_css="\ttext-decoration-line: underline;\n\ttext-decoration-thickness: 1px;\n\ttext-underline-offset: 0.15em;",
    ),
    dict(
        name="Constellations",
        identifier="constellations",
        homepage="https://github.com/lolisleepy/constellations-ao3-skin",
        creator='Palette inspired by lolisleepy\'s "Constellations" AO3 workskin (unlicensed -- values reimplemented independently, not copied verbatim; credited by name/link rather than relying on a license grant)',
        credit_comment="palette *inspired by* the constellations-ao3-skin workskin (lolisleepy) -- that source is unlicensed, so this reimplements the visual character (deep indigo-black sky, warm amber \"starlight\" accent) from scratch rather than copying any of its CSS.",
        differentiation_comment="Differentiation: dotted star-like link underline with a soft amber glow on hover, letter-spaced small-caps dateline standing in for a constellation label, and a faint dotted-star pattern feel via a dashed (not solid) preface border -- distinct from every other dark bundled theme's link treatment.",
        bg="#0d0e1f", text="#76859b", link="#f3bc70",
        header_border="#151726", table_border="#424c5e", header_text="#4c5870",
        code_color="#f3bc70", preface_border="rgba(118, 133, 155, 0.2)",
        link_underline_color="color-mix(in hsl, currentColor, transparent 30%)",
        link_underline_special="color-mix(in hsl, currentColor, transparent 75%)",
        blockquote_border="#424c5e", blockquote_width="3px", blockquote_style="solid", blockquote_extra="",
        header_font="sans-serif", header_extra="", avatar_radius="50%",
        title_extra="", dateline_extra="\tfont-variant: small-caps;\n\tletter-spacing: 0.08em;\n",
        code_font='"SF Mono", Menlo, "Courier New", Courier, monospace',
        table_extra="", hr_style="\tborder: 1.5px solid var(--table-cell-border-color);\n",
        popover_bg="#151726", popover_shadow="0 2px 4px rgba(0, 0, 0, 0.6), 0 3px 6px rgba(0, 0, 0, 0.35)",
        popover_arrow_bg="#0d0e1f", popover_extra="",
        preface_extra="\tborder-bottom-style: dashed;\n",
        preface_dt_extra="\tfont-variant: small-caps;\n\tletter-spacing: 0.04em;\n\tcolor: var(--primary-accent-color);\n",
        notice_extra="\tborder-left: 3px solid rgba(243, 188, 112, 0.4);\n\tbackground: rgba(243, 188, 112, 0.06);\n",
        body_font="Charter, Georgia, sans-serif", ios_title_transform="",
        link_underline_css="\ttext-decoration-line: underline;\n\ttext-decoration-style: dotted;\n\ttext-decoration-color: var(--link-underline-color);\n\ttext-decoration-thickness: 1px;\n\ttext-underline-offset: 0.2em;",
        link_hover_css="\ttext-shadow: 0 0 6px rgba(243, 188, 112, 0.6);\n\tcolor: color-mix(in hsl, var(--link-underline-color), white 25%);",
    ),
]

# §7 additions (nnwtheme-porter skill, Round 3 plan): Dracula's 7 hue variants and
# the three site-skin ports (Moonlit Wisteria, Pastel Whimsy, Poudre et Plume). All
# palette/font values below were read directly from the source repos in the AO3-skins
# repomix dump, not guessed -- see .claude/skills/nnwtheme-porter/SKILL.md for the
# extraction method.
DRACULA_HUES = [
    ("Cyan", "cyan", "#8be9fd"),
    ("Green", "green", "#50fa7b"),
    ("Orange", "orange", "#ffb86c"),
    ("Pink", "pink", "#ff79c6"),
    ("Purple", "purple", "#bd93f9"),
    ("Red", "red", "#ff5555"),
    ("Yellow", "yellow", "#f1fa8c"),
]

for hue_name, hue_slug, accent in DRACULA_HUES:
    themes.append(dict(
        name=f"Dracula {hue_name}",
        identifier=f"dracula{hue_slug}",
        homepage="https://github.com/dracula/ao3",
        creator=f'Ported from the {hue_name} variant of the official Dracula Theme AO3 port (MIT licensed, Dracula Theme)',
        credit_comment=f"ported from dracula_{hue_slug}_ao3.css in the official Dracula Theme AO3 repo (MIT). Standard Dracula dark palette (#282a36 background, #f8f8f2 foreground) with the {hue_name.lower()} accent ({accent}) used for links, code, and the preface border. The muted #6272a4 \"Comment\" tone is Dracula's own published palette value (draculatheme.com), not read from this particular AO3 port, which doesn't need a distinct muted color.",
        differentiation_comment=f"Differentiation: monospace header-chrome font (this is a developer-tool-derived palette; the header table/dateline read like a terminal even though the article body itself stays serif for readability), square-ish 4px avatar corners, and the {hue_name.lower()} accent distinguishing this variant from the other six Dracula hues -- same structure, only the accent hex changes.",
        bg="#282a36", text="#f8f8f2", link=accent,
        header_border="#44475a", table_border="#44475a", header_text="#6272a4",
        code_color=accent, preface_border=accent,
        link_underline_color="color-mix(in hsl, currentColor, transparent 40%)",
        link_underline_special="color-mix(in hsl, currentColor, transparent 80%)",
        blockquote_border="#44475a", blockquote_width="3px", blockquote_style="solid", blockquote_extra="",
        header_font='"SF Mono", Menlo, "Courier New", Courier, monospace', header_extra="", avatar_radius="4px",
        title_extra="", dateline_extra="",
        code_font='"SF Mono", Menlo, "Courier New", Courier, monospace',
        table_extra="", hr_style="\tborder: 1.5px solid var(--table-cell-border-color);\n",
        popover_bg="#21222c", popover_shadow="0 2px 4px rgba(0, 0, 0, 0.6), 0 3px 6px rgba(0, 0, 0, 0.35)",
        popover_arrow_bg="#191a21", popover_extra="",
        preface_extra="\tborder-bottom: none;\n\tborder-left: 3px solid var(--ao3-preface-border-color);\n\tpadding-left: 1em;\n",
        preface_dt_extra="\tcolor: var(--primary-accent-color);\n",
        notice_extra=f"\tborder-left: 3px solid {accent};\n\tbackground: rgba(0, 0, 0, 0.15);\n",
        body_font="Charter, Georgia, sans-serif", ios_title_transform="",
        link_underline_css="\ttext-decoration-line: underline;\n\ttext-decoration-style: solid;\n\ttext-decoration-color: var(--link-underline-color);\n\ttext-decoration-thickness: 1px;\n\ttext-underline-offset: 0.15em;",
        link_hover_css="\topacity: 0.85;",
    ))

themes.append(dict(
    name="Moonlit Wisteria",
    identifier="moonlitwisteria",
    homepage="https://github.com/intothisshadow",
    creator="Palette inspired by intothisshadow's \"Moonlit Wisteria\" AO3 site skin (no LICENSE file in source repo -- values reimplemented independently from the published :root palette, not copied verbatim; credited by name/author page rather than relying on a license grant)",
    credit_comment="palette *inspired by* intothisshadow's Moonlit Wisteria AO3 skin (so-obsessed.com) -- that source has no explicit license, so this reimplements the documented :root palette (Starlight Cream background, Ink Stem text, the skin's own \"a11y replacement\" Deep Violet for links) from scratch. The skin's decorative display font (\"Admiration Pains\") isn't on Google Fonts, so it's dropped rather than substituted; only the skin's own body serif (Lora, confirmed on Google Fonts) is carried over.",
    differentiation_comment="Differentiation: warm cream-and-violet pastel palette (the only bundled theme in this hue family besides Rosé Pine, and lighter/warmer than it), a soft dotted link underline in the skin's own lavender-soft tone, and fully rounded (50%) avatar corners matching the skin's floral, soft-edged visual language.",
    bg="#F5EDE8", text="#5C4F6B", link="#6B5A90",
    header_border="#F2C4BE", table_border="#C9BFD8", header_text="#A89EC0",
    code_color="#8B7AA8", preface_border="#C9BFD8",
    link_underline_color="color-mix(in hsl, currentColor, transparent 40%)",
    link_underline_special="color-mix(in hsl, currentColor, transparent 80%)",
    blockquote_border="#C9BFD8", blockquote_width="3px", blockquote_style="solid", blockquote_extra="",
    header_font="-apple-system, sans-serif", header_extra="", avatar_radius="50%",
    title_extra="", dateline_extra="\tfont-variant: small-caps;\n\tletter-spacing: 0.04em;\n",
    code_font='"SF Mono", Menlo, "Courier New", Courier, monospace',
    table_extra="\tborder-radius: 8px;\n", hr_style="\tborder: none;\n\tborder-top: 1px solid var(--table-cell-border-color);\n",
    popover_bg="#FFFAF8", popover_shadow="0 2px 4px rgba(107, 90, 144, 0.15), 0 3px 6px rgba(107, 90, 144, 0.08)",
    popover_arrow_bg="#FAF5F2", popover_extra="\tborder-radius: 8px;\n",
    preface_extra="\tborder: 1px solid var(--ao3-preface-border-color);\n\tborder-radius: 12px;\n\tpadding: 0.8em 1em 1em 1em;\n\tbackground: #FAF5F2;\n",
    preface_dt_extra="\tcolor: var(--primary-accent-color);\n",
    notice_extra="\tborder-left: 3px solid rgba(107, 90, 144, 0.4);\n\tbackground: rgba(107, 90, 144, 0.06);\n",
    body_font="'Lora', Georgia, serif", ios_title_transform="",
    link_underline_css="\ttext-decoration-line: underline;\n\ttext-decoration-style: dotted;\n\ttext-decoration-color: var(--link-underline-color);\n\ttext-decoration-thickness: 1px;\n\ttext-underline-offset: 0.15em;",
    link_hover_css="\topacity: 0.8;",
))

themes.append(dict(
    name="Pastel Whimsy",
    identifier="pastelwhimsy",
    homepage="https://github.com/intothisshadow",
    creator="Palette inspired by intothisshadow's \"Pastel Whimsy\" AO3 site skin (no LICENSE file in source repo -- values reimplemented independently from the published :root palette, not copied verbatim; credited by name/author page rather than relying on a license grant)",
    credit_comment="palette *inspired by* intothisshadow's Pastel Whimsy AO3 skin -- reimplemented from the documented :root palette (pale pink/lavender background, deep purple ink, saturated purple link accent) rather than copied. This is the cleanest test of the three-font-role convention: the source skin itself already splits Lora (body) / Playfair Display (headings) / JetBrains Mono (code), all three confirmed on Google Fonts.",
    differentiation_comment="Differentiation: the only bundled theme with all three font roles genuinely distinct (serif body, display-serif headings, monospace code) rather than one face doing double duty, plus a thick solid link underline in the skin's own accent lavender -- visually the most maximalist of the bundled pastel themes.",
    bg="#fff7fb", text="#3f3747", link="#7b5fa3",
    header_border="#e1d7f2", table_border="#e6dbf5", header_text="#5a4a78",
    code_color="#3a2d5c", preface_border="#d9cdee",
    link_underline_color="color-mix(in hsl, currentColor, transparent 20%)",
    link_underline_special="color-mix(in hsl, currentColor, transparent 70%)",
    blockquote_border="#e6dbf5", blockquote_width="3px", blockquote_style="solid", blockquote_extra="",
    header_font="'Playfair Display', Georgia, serif", header_extra="", avatar_radius="50%",
    title_extra="", dateline_extra="",
    code_font='"JetBrains Mono", "SF Mono", Menlo, monospace',
    table_extra="\tborder-radius: 8px;\n", hr_style="\tborder: none;\n\tborder-top: 1px solid var(--table-cell-border-color);\n",
    popover_bg="#faf7ff", popover_shadow="0 2px 4px rgba(90, 60, 130, 0.12), 0 3px 6px rgba(90, 60, 130, 0.06)",
    popover_arrow_bg="#f3ecff", popover_extra="\tborder-radius: 8px;\n",
    preface_extra="\tborder: 1px solid var(--ao3-preface-border-color);\n\tborder-radius: 12px;\n\tpadding: 0.8em 1em 1em 1em;\n\tbackground: #faf7ff;\n",
    preface_dt_extra="\tfont-family: 'Playfair Display', Georgia, serif;\n\tcolor: var(--primary-accent-color);\n",
    notice_extra="\tborder-left: 3px solid rgba(123, 95, 163, 0.4);\n\tbackground: rgba(123, 95, 163, 0.06);\n",
    body_font="'Lora', Georgia, serif", ios_title_transform="",
    link_underline_css="\ttext-decoration-line: underline;\n\ttext-decoration-style: solid;\n\ttext-decoration-color: var(--link-underline-color);\n\ttext-decoration-thickness: 2px;\n\ttext-underline-offset: 0.15em;",
    link_hover_css="\topacity: 0.8;",
))

themes.append(dict(
    name="Poudre et Plume",
    identifier="poudreetplume",
    homepage="https://github.com/intothisshadow/AO3-SiteSkin_PeacockFlare",
    creator="Palette inspired by intothisshadow's \"Poudre et Plume\" recolor of their Peacock Flare AO3 site skin (no LICENSE file in source repo -- values reimplemented independently from the published :root palette, not copied verbatim; credited by name/repo rather than relying on a license grant)",
    credit_comment="palette *inspired by* intothisshadow's Poudre et Plume AO3 skin, itself a recolor of their own Peacock Flare skin -- reimplemented from the documented :root palette (antique ivory background, warm umber ink, faded-indigo link accent) rather than copied. Fonts (EB Garamond body, Cormorant Garamond headings) confirmed on Google Fonts from the source's own header-comment credits. Link color is the source's --clr-teal-deep (#6A8FAA) darkened to #4d6c85 -- the source value is only 3.3:1 against this background, below WCAG AA (4.5:1) for body text; the darkened value keeps the same hue at 5.3:1.",
    differentiation_comment="Differentiation: warm antique-paper palette (ivory/umber/dusty-rose, no other bundled theme shares this warmth), Cormorant Garamond small-caps preface labels for a letterpress feel, and 8px rounded corners throughout -- softer than Vintage Letter Green's sharp letter framing but in the same antique-correspondence spirit.",
    bg="#fdfaf6", text="#3a2a22", link="#4d6c85",
    header_border="#D7979F", table_border="#BAC2C0", header_text="#8A8AA8",
    code_color="#4a3830", preface_border="#D87884",
    link_underline_color="color-mix(in hsl, currentColor, transparent 30%)",
    link_underline_special="color-mix(in hsl, currentColor, transparent 75%)",
    blockquote_border="#BAC2C0", blockquote_width="3px", blockquote_style="solid", blockquote_extra="",
    header_font="'Cormorant Garamond', Georgia, serif", header_extra="", avatar_radius="8px",
    title_extra="", dateline_extra="\tfont-variant: small-caps;\n\tletter-spacing: 0.05em;\n",
    code_font='"Source Code Pro", "SF Mono", Menlo, monospace',
    table_extra="\tborder-radius: 6px;\n", hr_style="\tborder: none;\n\tborder-top: 1px solid var(--table-cell-border-color);\n",
    popover_bg="#F3E1D6", popover_shadow="0 2px 4px rgba(58, 42, 34, 0.15), 0 3px 6px rgba(58, 42, 34, 0.08)",
    popover_arrow_bg="#EDD8CC", popover_extra="\tborder-radius: 6px;\n",
    preface_extra="\tborder: 1px solid var(--ao3-preface-border-color);\n\tborder-radius: 10px;\n\tpadding: 0.8em 1em 1em 1em;\n\tbackground: #F3E1D6;\n",
    preface_dt_extra="\tfont-family: 'Cormorant Garamond', Georgia, serif;\n\tfont-variant: small-caps;\n\tletter-spacing: 0.03em;\n\tcolor: var(--primary-accent-color);\n",
    notice_extra="\tborder-left: 3px solid rgba(106, 143, 170, 0.4);\n\tbackground: rgba(106, 143, 170, 0.08);\n",
    body_font="'EB Garamond', Georgia, serif", ios_title_transform="",
    link_underline_css="\ttext-decoration-line: underline;\n\ttext-decoration-style: dotted;\n\ttext-decoration-color: var(--link-underline-color);\n\ttext-decoration-thickness: 1px;\n\ttext-underline-offset: 0.15em;",
    link_hover_css="\topacity: 0.85;",
))

# Font-carrying themes among the above get a Google Fonts CDN @import prepended to
# their generated stylesheet.css after generation (see the font_imports loop below --
# not a template field, since only these four of the full theme list need one and
# every other dict in `themes` would otherwise need an empty font_import="" added).
FONT_IMPORTS = {
    "Moonlit Wisteria": "@import url('https://fonts.googleapis.com/css2?family=Lora:ital,wght@0,400..700;1,400..700&display=swap');\n",
    "Pastel Whimsy": "@import url('https://fonts.googleapis.com/css2?family=Lora:ital,wght@0,400..700;1,400..700&family=Playfair+Display:ital,wght@0,400..700;1,400..700&family=JetBrains+Mono:wght@400;700&display=swap');\n",
    "Poudre et Plume": "@import url('https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400..700;1,400..700&family=Cormorant+Garamond:ital,wght@0,400;0,700;1,400;1,700&family=Source+Code+Pro:wght@400;700&display=swap');\n",
}


for t in themes:
    dirname = os.path.join(BASE_DIR, f"{t['name']}.nnwtheme")
    os.makedirs(dirname, exist_ok=True)

    def xml_escape(s):
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    plist = PLIST_TEMPLATE.format(
        name=xml_escape(t["name"]), identifier=t["identifier"],
        homepage=xml_escape(t["homepage"]), creator=xml_escape(t["creator"])
    )
    with open(os.path.join(dirname, "Info.plist"), "w") as f:
        f.write(plist)

    css = STYLESHEET_TEMPLATE.format(**t)
    if t["name"] in FONT_IMPORTS:
        css = FONT_IMPORTS[t["name"]] + css
    with open(os.path.join(dirname, "stylesheet.css"), "w") as f:
        f.write(css)

    # All nine reuse Sepia's template.html verbatim -- CSS-only
    # differentiation, same pattern as Beetlejuice. None of these needed a
    # structural rework the way Vintage Letter Green's letter framing did.
    import shutil
    shutil.copyfile(os.path.join(BASE_DIR, "Sepia.nnwtheme", "template.html"), os.path.join(dirname, "template.html"))

    print("wrote", dirname)
