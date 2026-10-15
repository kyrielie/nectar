# Theme mockups and mockup-to-bundle conversion

The fixed sample page, review page and title check used to design shape B themes as CSS
mockups, and the two routes by which mockups were converted into `.nnwtheme` bundles. Most of
this describes tooling that is not in this checkout (`buildscripts/theme-mockups/`,
`convert_mockups.py`, `kit.py`), and part of it is conversion history. It was moved out of
`nnwtheme-format.md` so that document stays an authoring reference; to start a theme, read
`creating-a-theme.md` first.

**Note:** the 68px title-clearance rule referenced throughout this file is retired (the app
now keeps the page below the notch cover; see `nnwtheme-format.md`, "Full-screen reading").
The 68px measurements and the "clear" check below are history, not a current requirement.

Quoted section names below that are not headings in this file ("License.md", "Ornaments: where they go", "Styleable blocks") are in `nnwtheme-format.md`.

A mockup is a one-theme CSS preview of a fixed sample page, written against simplified
markup, reviewed on a single page, then converted into a `.nnwtheme`. Every mockup styles
the same sample, so themes compare like for like. The page layout, sample text and shared
CSS are below so none of it has to be regenerated; the tools that build and check the
review page are in `buildscripts/theme-mockups/`:

| File | Purpose |
|---|---|
| `build_mockup_page.py` | Builds the review page from `themes.json`. Holds the sample text and the page shell, so the page is rebuilt without regenerating anything. |
| `themes.json` | The 65 mockups of batches 3 to 8 (`id`, `cat`, `name`, `n`, `css`, `lk`). All 65 now also exist as converted bundles in `gallery-themes/` (matched by name), so this file is the source of the mockups rather than the only copy of the designs. |
| `fonts.html` | The Google Fonts `<link>` tags (91 families) the mockups load. The builder writes them into the page head. Add a family here when a mockup uses a new one, or the preview silently falls back to system fonts. |
| `check_fullscreen_titles.py` | Full-screen title check in headless Chromium (needs Playwright). |

These files are not in the checkout this doc was last revised against: `buildscripts/` there has only `theme-generation/` among the theme tools, so confirm they exist before relying on the commands below.

The built review page (about 220KB) is not committed. `python3 build_mockup_page.py
themes.json out.html` regenerates it, byte for byte identical to the page it was first
built as.

## Page layout (fixed order)

Every mockup and every converted theme lays the page out in this order. Notes never come
after a chapter. Aesthetic ornaments (rules, flourishes, corner marks, borders) may sit
anywhere between these blocks; in a mockup they are CSS only (`::before`/`::after`,
backgrounds, or the `.dv` divider). See "Ornaments: where they go" for the real-markup
slots.

| # | Block | Mockup markup | Converted theme | Notes |
|---|---|---|---|---|
| 1 | NetNewsWire-style header (optional) | `.rh` | `.rh` in `template.html`, outside `.t` | Feed name and date. Counts toward the 68px above the title. |
| 2 | Title / author | `header.hd > h1`, `p.by` | same, from `template.html` | |
| 3 | Preface | `dl.pf` | `#bodyContainer dl.tags` | Rows can carry `.wide`; the series row uses `.ao3SeriesPrefaceEntry`, `.ao3SeriesPrefaceLinks`, `.ao3SeriesNavDisabled`. |
| 4 | Summary | `.sm` (`h3`, `p`) | `.summary.module` (`h3.heading`, `blockquote.userstuff`) | |
| 5 | Notes | `.nt` | `.notes.module` | Before the first chapter heading. |
| 6 | First chapter heading | `span.dv` then `h2` | `h2.heading` / `h3.title` | The divider is inserted by `data-chapter-divider`. |
| 7 | First chapter text | `p.b`, opening words in `span.vc` | prose inside `div.userstuff.module[role="article"]` | Opening words wrapped by `data-versal-target`. |
| 8 | Chapter heading | `span.dv` then `h2` | as 6 | |
| 9 | Chapter text | `p.b` with `span.vc` | as 7 | |
| 10 | End matter (optional) | `div.nt.end` | `.end.notes.module` | The series footer (`#ao3SeriesFooter`) also belongs here in the app. |

Not in the sample: the fetch notice, the series footer, highlights, footnotes and wide
tables. Style those from the "Styleable blocks" table; a mockup does not exercise them.

## Sample content

The one sample every mockup renders. It is a copy of `PF` and `sample_html()` in
`build_mockup_page.py`; change both
together. `__N__` is the theme's number (`.t1`, `.t2`, ...). Only the first paragraph after
each chapter heading is `p.b`; the converter keeps the drop-cap rule for that paragraph
only. The builder emits the preface rows with no whitespace between them.

```html
<div class="stage">
<div class="rh"><a href="#">Archive of Our Own</a><time>Nov 18, 2024</time></div>
<section class="t t__N__"><header class="hd"><h1>The Lantern Keeper's Apprentice</h1><p class="by">by Wren Ashcombe</p></header>
<div class="bd">
<dl class="pf">
<dt>Rating:</dt><dd><a href="#">Teen And Up Audiences</a></dd>
<dt class="wide">Archive Warning:</dt><dd class="wide"><a href="#">Creator Chose Not To Use Archive Warnings</a>, <a href="#">Graphic Depictions Of Violence</a></dd>
<dt>Category:</dt><dd><a href="#">F/M</a>, <a href="#">Gen</a></dd>
<dt class="wide">Fandom:</dt><dd class="wide"><a href="#">Original Work</a>, <a href="#">The Lantern Keeper's Apprentice - Wren Ashcombe</a></dd>
<dt class="wide">Relationships:</dt><dd class="wide"><a href="#">Mara Hale/Tobias Wren</a>, <a href="#">Mara Hale &amp; The Ghost</a>, <a href="#">Mara Hale &amp; Mrs. Pell</a></dd>
<dt class="wide">Characters:</dt><dd class="wide"><a href="#">Mara Hale</a>, <a href="#">Tobias Wren</a>, <a href="#">The Ghost (Elias)</a>, <a href="#">Mrs. Pell</a>, <a href="#">Captain Orrin Vale</a>, <a href="#">The Harbor Cat</a></dd>
<dt class="wide">Additional Tags:</dt><dd class="wide"><a href="#">Slow Burn</a>, <a href="#">Found Family</a>, <a href="#">Gentle Fantasy</a>, <a href="#">Lighthouse Keeper</a>, <a href="#">Ghosts</a>, <a href="#">Hurt/Comfort</a>, <a href="#">Cozy Mystery</a>, <a href="#">Coming of Age</a>, <a href="#">Original Female Character</a>, <a href="#">Soft Ending</a>, <a href="#">Established Friendship</a>, <a href="#">Sea Imagery</a>, <a href="#">Everyone Is Tired</a>, <a href="#">Mild Peril</a>, <a href="#">Weather as Character</a>, <a href="#">Angst with a Happy Ending</a>, <a href="#">Mara Is Competent and Also Panicking</a>, <a href="#">Spooky but Not Scary</a>, <a href="#">Inherited Property</a>, <a href="#">Reluctant Roommates (Living and Dead)</a>, <a href="#">Sundays Updates</a>, <a href="#">Rated for Brooding</a></dd>
<dt>Language:</dt><dd>English</dd>
<dt class="wide">Series:</dt><dd class="wide"><span class="ao3SeriesPrefaceEntry">Part 2 of <a href="#">The Lantern Keeper Cycle</a></span> <span class="ao3SeriesPrefaceLinks"><a href="#">First</a> · <a href="#">Previous</a> · <span class="ao3SeriesNavDisabled">Next</span></span></dd>
<dt class="wide">Collections:</dt><dd class="wide"><a href="#">Lighthouse Fic Exchange 2024</a>, <a href="#">Cozy Autumn Reads</a></dd>
<dt>Published:</dt><dd>2021-03-04</dd>
<dt>Updated:</dt><dd>2024-11-18</dd>
<dt>Words:</dt><dd>42,180</dd>
<dt>Chapters:</dt><dd>12/12</dd>
<dt>Comments:</dt><dd>318</dd>
<dt>Kudos:</dt><dd>2,104</dd>
<dt>Bookmarks:</dt><dd>412</dd>
<dt>Hits:</dt><dd>58,977</dd>
</dl>
<div class="sm"><h3>Summary:</h3><p>Mara inherits a lighthouse she cannot afford and a ghost who will not leave.</p></div>
<div class="nt">Notes: thank you for reading. New chapters on Sundays, see <a href="#">my profile</a>.</div>
<span class="dv"></span><h2>Chapter 1</h2>
<p class="b"><span class="vc">The tide came in</span> earlier than <a href="#">the almanac</a> promised, and Mara counted the stairs twice to be sure the night had not stolen any.</p>
<span class="dv"></span><h2>Chapter 2</h2>
<p class="b"><span class="vc">Mrs. Pell left the kettle</span> on the stove and a note on the table, which said only that the ghost preferred his tea without sugar.</p>
<div class="nt end">End Notes: the harbor cat is based on a real cat. Next part is <a href="#">here</a>.</div></div></section></div>
```

This is the pre-conversion sample. The gallery preview uses a second, smaller sample in
real converted markup (`SAMPLE` and `SUB` in `gallery/index.template.html`; see
`theme-gallery.md`), so a converted bundle is previewed there, not here.

## Shared base CSS

Every theme's `css` field starts with this block (checked: all 65 entries in `themes.json`
do), followed by that theme's own `.tN` rules: palette and fonts as custom properties on
`.tN` (`--bg --ink --a --fh --fb`, plus any extras), dark values on `.dk .tN`, and element
rules such as `.tN .hd`, `.tN h2`, `.tN .sm`, `.tN .dv`. Green Phosphor adds one
`@keyframes` rule after the base.

```css
.t{padding:22px 20px 26px;background:var(--bg);color:var(--ink);font:15px/1.6 var(--fb);position:relative;overflow:hidden}
.t h1,.t h2,.t h3{margin:0;font-family:var(--fh);font-weight:400}
.t h1{font-size:30px;line-height:1.05}.t h2{font-size:21px;margin-bottom:8px}.t h3{font-size:12px}
.hd{position:relative;margin-bottom:16px}.by{margin:8px 0 0;font-size:12px;letter-spacing:.05em}
.pf{display:grid;grid-template-columns:auto 1fr;gap:3px 12px;margin:0 0 14px;font-size:12px}.pf dt{font-weight:700}.pf dd{margin:0}
.sm{margin:0 0 14px;padding:10px 12px}.sm h3{margin-bottom:4px}.sm p,.b{margin:0}
.nt{font-size:13px;opacity:.8;border-left:2px solid var(--a);padding-left:10px;margin-top:12px}
.dv{display:block;margin:18px 0 8px}
.b::first-letter{font-family:var(--fh);float:left;font-size:2.7em;line-height:.85;padding:.05em .1em 0 0;color:var(--a)}
.vc{font-variant:small-caps;letter-spacing:.03em}
```

## Review page

```
python3 buildscripts/theme-mockups/build_mockup_page.py themes.json out.html [old_page.html]
```

`themes.json` is a list of `{"id", "cat", "name", "n", "css", "lk"}`: `n` is the root class
number, `css` is the shared base plus the theme's rules, `lk` is per-theme link styling
(always applied). The optional third argument is an earlier page whose font links are
reused instead of `fonts.html`.

- Each theme renders in its own shadow root, so `.tN` numbers can repeat across batches.
- The builder copies each theme's custom properties from `.tN` and `.dk .tN` onto `.stage`,
  so the header band, which sits outside the section as in a converted theme, uses the same
  palette.
- The header band uses the same rules as `RH_CSS` in the converter (56px minimum height,
  12px below, 20px side padding, which is the iOS `--gx`).
- The page mirrors the converted body rules `word-wrap: break-word` and (iOS)
  `word-break: break-word`; without them a long word runs off the side of the mockup.
- Visible controls: "Preview dark mode" and "Full-screen view", which hatches the top 68px
  the way the app's notch cover hides it. The Approve/Discard buttons, filters and "Copy
  decisions" exist in the markup but are hidden in the final page.

## Full-screen title check

Requirements are the three under "Full-screen reading" above. `check_fullscreen_titles.py`
tests them for every mockup in headless Chromium at 390px wide:

```
python3 buildscripts/theme-mockups/check_fullscreen_titles.py page.html [--dark] [--no-header] [--long-title | --extreme-title] [--shots DIR]
```

- **clear**: top of the first title line to top of the page must be at least 68px.
- **clipped**: the title must be in the hit-test stack at 3 points on each line. If it is
  absent, an ancestor's `overflow` or `clip-path` is cutting it. An element merely drawn
  above the title is reported as a note for a visual check (Tattoo Flash's transparent
  dotted frame is one; it does not hide the title).
- **side**: no title line may pass the left or right edge.
- **css**: no title `line-height` under 1, no `nowrap`/`text-overflow`, no `overflow` on
  the title.
- `--long-title` swaps in a 76 character title, `--extreme-title` a 126 character one,
  `--no-header` hides the band to show what the header contributes, `--shots` writes a PNG
  of the top of each theme with the 68px zone marked.
- Fonts load from Google Fonts. With no network the browser falls back to system fonts, so
  line counts and heights are approximate while clearance (pure layout) is exact.

Results on the 65 mockups, as reported by the engineer who ran the check on 2026-10-07;
they were not reproduced when this doc was written (no browser available there). With the
band, the first title line sits 87px to 155px down (median 101px), in light and dark and
with the 76 character title. Without the band 59 of 65 start under 68px, so the band is
what makes the mockups pass; a design without it has to supply the 68px itself. Fixes made
while checking: `line-height: .95` raised to 1 on the titles of Bullet Journal, Giallo,
Futurism, Underground Comix and VHS Tracking Glitch; `padding-inline: .45em` added to the
skewed titles of Giallo and Futurism so the skew does not push the lower lines off the
left edge. Known remaining: Giallo at 126 characters leaves about 4px of the last lines
past the left edge. Device verification (see "Full-screen reading") has not been done for
the mockups or the converted bundles.

## Making a mockup

1. Pick the theme's `n` (any unused number in its batch) and write its rules against the
   sample markup above: `.tN` for palette and fonts, `.dk .tN` for dark values, then
   element rules. Use only the classes in the layout table.
2. Keep the title safe: `.hd` and `h1` need no `overflow: hidden`, fixed `height`,
   `line-height` under 1 or `nowrap`; ornaments must not take space above the title.
3. A theme with a custom header (negative top margin on `.hd`, large top padding) still sits
   below the band, because the band comes first.
4. Add the theme's object to `themes.json` (and any new font to `fonts.html`), rebuild the
   page, run the title check in light and dark and with `--long-title`, then review.

## Converting mockups into `.nnwtheme` bundles

Status: the two conversion routes below are described from the scripts that produced the
bundles in `gallery-themes/` (`convert_mockups.py`, `notes_lib.py`, `kit.py`, `t_*.py`,
`build_all.py`, `finalize_credits.py`). Those scripts are in the v4 theme set's `tools/`
directory and are not in this repo, so what they do was not re-read here. What the
bundles contain was checked in `gallery-themes/` (Swiss International read in full; the
sections below say what was checked).

**Route A: CSS-mapped themes.** `convert_mockups.py <batch1.html> <batch2.html> <out_dir>`
produced the shape B bundles. Its output is the contract between the mockup and the
bundle:

| Mockup | Bundle |
|---|---|
| `.pf` | `#bodyContainer dl.tags` |
| `.sm` | `.summary.module` |
| `.sm p` | `.summary.module blockquote.userstuff` |
| `h2` | `h2.heading, h3.title` |
| `h3` | `h3.heading` |
| `.vc` | `.versalCap` |
| `.b::first-letter` | `p:has(> .versalCap:first-child)::first-letter` |
| `.nt` | not converted; notes get one of 17 treatments from `notes_lib.py`, chosen per theme and built from the theme's own `--ink --a --bg --fb --r` |
| `.dv` | unchanged; inserted by `data-chapter-divider` with class `dv` and a zero-width character |
| `.tN` custom properties | `:root`; `.dk ` rules go into one `@media (prefers-color-scheme: dark)` block, with dark rules identical to light ones dropped |
| `font-size: Npx` | `calc(var(--u) * N)` (`--u` is 1px on macOS, font size / 15 on iOS, so type follows Dynamic Type) |
| `padding: 22px 20px ...` | `10px var(--gx) ...`; `-20px` becomes `calc(var(--gx) * -1)`, `-22px` becomes `-10px` |

**Page color.** The converted `body` rule should paint the page with `background-color:
var(--nnw-bg)`. The app measures the rendered page, so the `background` shorthand also
works now; `background-color` stays preferred because the legacy scanner fallback (used
until a measurement exists) can only read that property, and it is what the 66 Route A
bundles already use. See `article-color-pipeline.md`. The converter and `kit.py`
are outside this repo.

Other rules that mention `.b` are dropped. A converted title therefore sits 12px higher than
in the mockup for themes with plain top padding, and in the same place for themes with a
negative top margin. Versal is dropped for themes in the converter's `NO_VERSAL` set.

Anatomy of a converted stylesheet, in file order (read in Swiss International; the `.rh`,
`.t` and `@supports` pattern also matches Disco): the Google Fonts `@import`, a `:root`
palette, the structural base (link, preface-reset, blockquote, table, `img` max-width and
text-size rules), the `.rh` running head, the notes treatment, the converted `.t` base, the
theme's own `.tN` rules, the dark `@media` block, then the iOS and macOS `@supports` blocks
that set `--gx` (20px iOS, 48px macOS) and `--u`.

Starting a bundle by hand: copy the structural base, `.rh` block and `@supports` blocks
from an existing shape B bundle, then replace the palette, the notes treatment and the
`.tN` rules. The converter's limits, if it is ever added to the repo: the batch names,
fonts and `NOTES` table are hard-coded (a new theme needs a name, a `NOTES` entry and a
font spec or it raises `KeyError`), `parse_rules` asserts there are no at-rules (Green
Phosphor's `@keyframes` needs hand handling), and it reads the two-file batch format, not
`themes.json`. Converting from the review page needs a small adapter that calls its
`process` and `build` functions per theme; it has not been written.

**Route B: hand-built themes with their own markup** (`kit.py`, `t_*.py`, `build_all.py`).
Each `t_<name>.py` defines `LIGHT`/`DARK` palettes, a `TEMPLATE` and a `CSS` string with
`@@LIGHT@@`, `@@DARK@@`, `@@STRUCT@@` and `@@PLATFORM@@` placeholders, and `build(outdir)`
calling `kit.write`. `kit.py` supplies `STRUCT` (the shared overflow, image, footnote and
preface-reset rules), `platform()`, `PLIST`, `rootvars`, `svg_uri` and `contrast`.
`build_all.py <out>` builds every module, then checks each bundle: `@import` first,
balanced braces, no leftover `@@`, `#bodyContainer` with `articleBody` and `[[body]]`, an
`img` `max-width`, the `[[font-size]]` token, a dark block and the platform split, and it
prints WCAG contrast for the text pairs and marks any under 4.5. In the tree, Heist Night
and Undercity Dusk (shape D) match this route: both are `Version` 2 with homepage
`https://github.com/nectar-app/gallery-themes` and both put a 56px-minimum running head first.

**Info.plist fingerprints, checked across `gallery-themes/` by script:** all shape B
bundles have homepage `https://github.com/kyrielie/nectar` and `CreatorName` `kyrielie`;
113 are `Version` 1 and four are `Version` 2 (why was not determined). Every one has a
`License.md`. How the 65 batch 3 to 8 bundles were converted is not recorded in this
repo; their `License.md` only says "converted to this bundle by script".

**After either route.**

1. `finalize_credits.py <dir>` sets `CreatorName` to just the creator name and moves the
   descriptive text into `License.md` (CC0 unless the bundle already ships another license).
   All shape B bundles have a `License.md`; the mockup conversions carry the placeholder described under "License.md".
   Leave `Version` at 1.
2. Put the bundle in `Themes/` or `gallery-themes/` (see below) and update `BUNDLED` if needed.
3. Run the theme tests named below, which scan both directories.
4. Check full-screen reading on a device, as described above.
