# .nnwtheme Format

Bundle-file structure and authoring conventions for `.nnwtheme` themes. For
the Swift-side theme system (`ArticleTheme`, `ArticleThemesManager`, color
extraction, rendering integration), see `theme-system.md`.

## `.nnwtheme` Structure

An `.nnwtheme` comprises of three required files, plus an optional fourth:
- `Info.plist`
- `template.html`
- `stylesheet.css`
- `License.md` (optional for a wholly original theme; expected for anything ported from, or inspired by, someone else's work -- see "License.md" below)

### Info.plist
The `Info.plist` requires the following keys/types:

|Key|Type|Notes|
|---|---|---|
|`ThemeIdentifier`|`String`|Unique identifier for the theme, e.g. using reverse domain name. Nectar bundles use `com.nectar.themes.<slug>` (plural `themes`; 156 bundles). The slug is usually the lower-cased name, but a few older bundles keep ids from earlier names (Beacon `teenwolf`, Mystery `gravityfalls`, Perseus `percyjackson`, Black & White `blackandwhite`) and were not renamed, since changing an identifier would make an installed copy look like a different theme (inferred; not checked in code). The NetNewsWire-origin bundles keep their upstream ids. The 65 batch 3 to 8 conversions were `com.nectar.theme.<slug>` (singular) and have been changed to match.|
|`Name`|`String`|Theme name|
|`CreatorHomePage`|`String`||
|`CreatorName`|`String`|The creator's name (a person or organization), and nothing else. **Do not put the theme's description, attribution prose, or license status here** -- those go in `License.md` (see below). Migrated: every bundle except the eight NetNewsWire-origin ones (which keep their upstream creators and are left alone) now has `CreatorName` `kyrielie`, and the text that used to sit here is in its `License.md`. `gallery/build.py` still copies this key into its `by` field and does not read `License.md` (confirmed by reading it), so the gallery's detail dialog shows only the creator name for migrated bundles until the build reads `License.md`. `buildscripts/theme-generation/generate_ported_themes.py` now writes `kyrielie` here and puts its `creator=` text in a new `License.md` only when the bundle has none. The gallery grid card shows only the theme name -- see `docs/theme-gallery.md`.|
|`Version`|`Integer`|Leave at `1` while Nectar is in development; do not bump it for edits. Found as-is and left alone: seven gallery bundles at `2`, and two bundles in `Themes/` at `3` and `14`.|
|`Family`|`String`|Optional. Groups sibling bundles that are the same design with different accents/palettes (e.g. "Rosé Pine"). Omit unless there are genuinely 2+ sibling bundles -- a family of one adds nothing, and isn't how any single-variant theme (including Dracula, reduced to one accent) is set up. `gallery/build.py` copies it into each theme's data, but the gallery page does not use it yet (see "Theme families" below).|
|`FamilyVariant`|`String`|Optional. This bundle's variant label within `Family` (e.g. "Moon", "Purple"). Meaningless without `Family` also being set.|

### License.md

Where a theme's **description** lives, along with its attribution and license
status. `CreatorName` is not the place for any of these.

A `License.md` is plain Markdown, a few short paragraphs, in this order:

1. **What the theme is** -- one or two sentences on its visual character
   (palette, type, signature treatments), written for someone choosing between
   themes, e.g. `Themes/Powder Pink.nnwtheme/License.md`'s "Off-white background,
   deep berry text, a saturated pink link accent".
2. **Where it came from** -- the source skin/theme and author, linked, and how
   closely this bundle follows it (direct port vs. inspired by). Say "inspired
   by" and that values were reimplemented, rather than implying a grant, when
   the source has no license or an unclear one. Never state a license you
   haven't checked on the source repo.
3. **Third-party assets** -- font credits and their licenses (e.g. `Set in Cardo
   (David Perry, SIL OFL)`), ornament/dingbat fonts, anything else bundled or
   `@import`ed.

`Themes/*/License.md` already follow this shape informally (Black & White,
Powder Pink and Tumblr Blue each lead with attribution and then describe the
look). Current state: all 150 gallery bundles and 7 of the 14 bundled ones have a
`License.md`; the seven without are NetNewsWire-origin bundles, left unchanged.
When `CreatorName` was migrated, bundles that had no `License.md` got a short one
holding the old text plus `License: not yet decided; set one before publishing.`;
the 65 batch 3 to 8 conversions carry the same line, and their font licenses were
not checked. Where a bundle's `License.md` did not already credit the source, the
old `CreatorName` text was added at its top (Beetlejuice and Constellations).
No code reads `License.md` -- `gallery/build.py` and `ArticleThemePlist` use only
`Info.plist` -- so making the gallery's detail dialog show `License.md` instead of
`CreatorName` is still follow-up work.

### template.html
This provides a starting point for editing the structure of the page. Theme variables are documented in the header.

### Custom template.html

A theme is not required to reuse the default `template.html` verbatim, and most
gallery themes don't. The hard constraint, for every shape:

`#bodyContainer` must keep the `articleBody` class, whatever other classes it
also carries (e.g. `class="articleBody letter-body [[text_size_class]]"`).
Two systems key off that exact class name regardless of which theme is active:

- `core.css`'s AO3 preface rules (`#ao3SyntheticPreface`, `#ao3Preface`) are concatenated
  ahead of every theme's CSS and assume no theme overrides them at the markup level.
- `ArticleThemeOverrides.cssOverrideBlock` and `ArticleThemeColorExtractor` both target
  `.articleBody` by class name, not by structural position -- a theme that renames or
  drops that class breaks font-size/line-height/color overrides and the live theme-color
  preview for anyone using that theme.

Everything else in a custom `template.html` -- header layout, added wrapper elements,
decorative markup, alternate class names on non-`articleBody` elements -- is fair game.

#### Template shapes in `gallery-themes/`

Surveyed by reading every `gallery-themes/*/template.html` (85 bundles at the
time; `Themes/` was not surveyed). The 65 batch 3 to 8 mockup conversions added
since (150 bundles now) were classified by matching `class="rh"` in their
templates, not by reading each one, and are all shape B. Counts drift; the
shapes are what matter.

| Shape | Count | Markup | Examples |
|---|---|---|---|
| A. NetNewsWire header table | 17 | `header.headerContainer > table.headerTable` (feed link and byline left, avatar right), then title, `[[dateline_style]]`, external link, body. Stock NetNewsWire structure. | Beacon, Dracula, Twilight, Rosé Pine (all four variants) |
| B. Compact running head | 117 (52 earlier, 65 mockup conversions) | Converted from mockups (see "Theme mockups"). 8 lines: `div.rh` (feed link left, date right), then `div.t.tNN > header.hd` (title, byline), then body. `tNN` (t1 to t38) is a per-theme variant class, so the design lives in the CSS. No avatar, no `[[dateline_style]]`, no external-link line. | Swiss International, Disco, Bauhaus, Birdsite, Bridge Command |
| C. Custom wrapper | 13 | `div.fontSize` wrapper, external-link line, and `#nnwFooter`. The six older themes (Aldine, Deco Line, Kelmscott, Kennerley, Marigold Press, Rosarivo) keep header bars with feed link and avatar; the seven newer ones (Craft Table, Didone Editorial, Four Nations, Illuminated Codex, Mid-century Jost, Screenplay, Sticker Pop) have no feed link or avatar and open with the title. | Craft Table, Illuminated Codex |
| D. Outliers | 3 | Broadsheet is the stock layout plus a live inline `<script>` (blocked in the real reader). Heist Night and Undercity Dusk are hand-built (Route B in "Converting mockups"), B-like with their own class prefixes (`sc-`, `ar-`). | |

Behavior differs by shape too. A has no versal and no chapter dividers, and
only Pinerose has a `prefers-color-scheme: dark` block, so the other 16 are
single-mode. B opts into the divider mechanism in all 117 (zero-width glyph,
styled through CSS) and into versal in 84. The 33 that skip versal are Birdsite,
Upvote, Watch Later, Galactic Matinee and Matisse Paper Cutouts, plus 28 mockup
conversions whose drop cap and small-caps opening words were removed by decision
(Green Phosphor, 1-Bit Desktop, Night Amber, Cassette Futurism, Catppuccin,
Symmetry Pastel Hotel, Wiener Werkstätte, Futurism, Suprematism, Papel Picado,
Atomic Age Populuxe, Mid-Century Modern, Underground Comix, Nordic Folk, Papercut
Layers, Giallo, Large Print, OLED Black, Gruvbox, Game Boy Green, Commodore 64,
Bento Grid, Park Service Brochure, Library Card Catalog, Tokyo Night, Solarized,
Subway Diagram, E-Ink); their stylesheets keep `.versalCap` and
`::first-letter` rules that can no longer match. Every B theme has a dark block. C is mixed: nine use versal, six of the older ones have no divider
attributes at all, and the newer ones use visible dividers (a diamond, a fleuron,
kanji, `CUT TO:`, `/`). Kelmscott's template mentions an inline script only in a
comment explaining why it was removed; it ships none.

#### Which templates to add, and which to start from

Only shape B is a starter. It is the one pipeline with a documented layout, a mockup
review page, a mockup-to-bundle contract and a title-spacing check ("Theme mockups"), and
its running head clears the 68px rule by arithmetic. Two templates are kept in these docs:

1. **B with the running head (default).** Written out below.
2. **B without the header.** The same file with the `.rh` line deleted and
   `.t{padding-top:68px}` added after the converted `.t` rule. The 68px has to come from
   the theme because nothing else supplies it (59 of the 65 mockups fell under 68px
   without the band). No bundle in the tree does this yet and the padding value is
   inferred, so check it on a device.

```html
<div class="rh"><a class="rh-feed" href="[[feed_link]]">[[feed_link_title]]</a><time class="rh-date" datetime="[[datetime_long]]">[[date_medium]]</time></div>
<div class="t tN">
	<header class="hd">
		<h1 class="articleTitle"><a href="[[preferred_link]]">[[title]]</a></h1>
		<p class="by">[[byline]]</p>
	</header>
	<div id="bodyContainer" class="articleBody bd [[text_size_class]]" data-versal-target data-chapter-divider data-chapter-divider-char="&#8203;" data-chapter-divider-class="dv">[[body]]</div>
</div>
```

(This is Swiss International's `template.html` with its `t16` replaced by `tN`. Checked
across `gallery-themes/`: 83 of the 117 shape B templates are identical to it apart from
that class number, 33 omit `data-versal-target` (the five earlier ones above and 28 converted
mockups), and Bridge Command adds a nav strip and a credit line. Counts were taken by script
over `gallery-themes/`.)
Drop `data-versal-target` for a theme with no drop cap. The layout it renders is the fixed order under "Page layout".

Not added as starters:

- **A (header table).** It is the stock NetNewsWire layout, whose source is
  `Shared/Article Rendering/template.html`. Its avatar never renders, it has no versal or
  divider opt-in, and its header height is unaudited. Use it only for a faithful port.
- **C (custom wrapper).** The older six carry a legacy header bar and avatar. The newer
  seven (Craft Table, Didone Editorial, Four Nations, Illuminated Codex, Mid-century Jost,
  Screenplay, Sticker Pop) are bespoke designs with no header and no checked 68px
  clearance. Read them for a footer or an external-link line; do not copy their top
  spacing.
- **D.** Broadsheet ships a live inline `<script>`, and the other two are one-off hand-built
  designs.
- **Any inline `<script>`**, in any shape (see "Drop caps / versal treatments").

The shape B template has no external-link line. Add `<div class="externalLink">[[external_link_label]] <a href="[[external_link]]">[[external_link_stripped]]</a></div>` after `#bodyContainer` if the design needs it (not tested in a B bundle).

#### Required vs optional

| Item | Status | Enforced by |
|---|---|---|
| `Name`, `ThemeIdentifier`, `CreatorHomePage`, `CreatorName`, `Version` in `Info.plist` | Required | `REQUIRED_KEYS` in `gallery/build.py` (fails the build) |
| `#bodyContainer` with the `articleBody` class | Required | `gallery/build.py` regex (fails the build) |
| `img, ... { max-width: 100% }` rule in the CSS | Required in practice | `build.py` only warns, but `ArticleThemeOverflowSafetyTests` fails on it |
| At least 68px above the title | Required | Documentation only; no test |
| `Family`, `FamilyVariant`, `License.md` | Optional (`License.md` expected for ports) | Nothing |
| `[[avatar_src]]` | Optional | Shape B omits it; `main.js` strips the image anyway |
| `[[dateline_style]]`, `[[datetime_*]]`, `[[date_*]]` | Optional | Shape B uses only `[[date_medium]]` and `[[datetime_long]]` |
| `[[external_link*]]` | Optional | Shape B omits it |
| `[[feed_link]]`, `[[feed_link_title]]` | Optional | Nothing requires them; `removeFeedNameLink` only acts on anchors that exist |
| `[[byline]]`, `[[title]]`, `[[preferred_link]]` | Unverified | All 85 gallery templates include them, so whether omitting is safe was not tested |
| `data-versal-target` | Optional | `applyVersalCaps` no-ops without it |
| `data-chapter-divider*` | Optional, but `-char` and `-class` must be set together | `applyChapterDividers` no-ops if either is missing |
| `#nnwFooter` | Optional | Custom templates only |
| `@media (prefers-color-scheme: dark)` block | Optional | Without one, the gallery classifies the theme by its `body` background luminance |
| `[[text_size_class]]` on `#bodyContainer` | Optional, harmless | Legacy token, never substituted; every shipped template keeps it |

### stylesheet.css
This provides a starting point for editing the style of the page. 

#### Per-theme fonts

A theme that wants a non-system font declares it via a Google Fonts CDN `@import`,
not a base64-embedded `@font-face`. `Hyperlegible.nnwtheme` is the reference pattern:

```css
@import url('https://fonts.googleapis.com/css2?family=Atkinson+Hyperlegible:wght@400;700&display=swap');

:root {
	--font-main: 'Atkinson Hyperlegible', -apple-system, sans-serif;
	--font-body: 'Atkinson Hyperlegible', Georgia, serif;
	--font-code: 'SF Mono', Menlo, monospace;
}
```

- Put the `@import` first in the file, before any other rule.
- Every font stack ends in a system fallback so a network failure (offline reading)
  degrades to something legible rather than breaking layout.
- `--font-main` is for UI chrome text (`.feedlink`, dateline, external-link), never
  the fic prose; `--font-body` is for `.articleBody`; `--font-code` is for `code`/`pre`.
  This is a documented convention for themes that choose to declare fonts as CSS
  custom properties -- it is not yet followed by every bundled theme (confirmed:
  `Hyperlegible.nnwtheme` sets `font-family` directly on each selector with no CSS
  variables at all; `Biblioteca.nnwtheme` uses its own `--font-sans`/`--font-serif`/
  `--font-mono` names). `ArticleThemeOverrides`'s chrome-font override
  (`sansFontFamilyName`) works around this today via a hand-maintained selector
  allowlist rather than this variable convention; retrofitting every bundled theme
  to it and simplifying that override to a two-line `:root` block instead is
  tracked as a separate, larger follow-up.
- Do not lead a font stack with an Apple-only face (`ui-serif`, `ui-sans-serif`,
  `-apple-system`, `-apple-system-body`, `SF Pro Text`, `SF Mono`, `Menlo`,
  `Charter`, `Iowan Old Style`): they resolve only on Apple platforms, so the
  same theme falls through to a browser default on the gallery page in
  Chrome/Firefox. Name a real Google Fonts family first and keep the Apple face
  as a later fallback. The stand-ins in use: Charter -> Source Serif 4, SF Pro ->
  Inter, SF Mono/Menlo -> JetBrains Mono, Iowan Old Style -> Lora, Georgia ->
  Libre Baskerville. Also note `font: ui-serif, ...` is invalid CSS (the `font`
  shorthand requires a size), so use `font-family`. The eight NetNewsWire default
  themes are exempt and keep their upstream stacks.
- Themes must not claim to be free of network dependencies (Duskbloom's header
  comment used to); every custom theme now `@import`s Google Fonts.
- Only reference font families genuinely published on Google Fonts -- confirm on
  fonts.google.com before writing the `@import`, don't guess a family name.

#### AO3 preface styling

The AO3 work preface (`#ao3SyntheticPreface` / `#ao3Preface` in
`Shared/Article Rendering/core.css`, ~line 165) is styled from `core.css`,
not `stylesheet.css` -- see the comment block above that rule for why (it
loads ahead of every theme, bundled or custom, so a theme with no `dl`/`dt`/
`dd` rules of its own still gets a usable grid layout instead of the
browser's default `<dl>` box model). A theme customizes it entirely through
CSS custom properties; there is no other override path.

```css
:root {
	--ao3-preface-border-color: rgba(0, 0, 0, 0.15);
	--ao3-preface-background-color: transparent;
	--ao3-preface-text-color: inherit;
	--ao3-preface-label-color: inherit;
	--ao3-preface-font-size: 0.9em;
}
```

- `--ao3-preface-border-color` and `--ao3-preface-background-color` already
  work today. `--ao3-preface-text-color`, `--ao3-preface-label-color`, and
  `--ao3-preface-font-size` require a small `core.css` change (each hardcoded
  value replaced with `var(--ao3-preface-<x>, <existing hardcoded value>)`)
  before they take effect -- confirm that change has actually landed before
  relying on them in a theme.
- `--ao3-preface-label-color` falls back to `--ao3-preface-text-color` when
  unset, which itself falls back to the theme's normal body text color.
- These must be declared as custom properties in the theme's own
  `stylesheet.css`, in the same `:root` block the theme already uses for any
  other custom property (see the font variables above). Declaring them
  anywhere else, or as plain (non-custom-property) rules targeting
  `#ao3Preface` directly, won't reach `core.css`'s rules -- `core.css` loads
  first, so a theme's own `#ao3Preface` selector can only win a specificity
  fight it shouldn't need to pick.
- Every existing theme's preface renders byte-identical unless it opts in;
  these are additive fallback variables, not a breaking change to the rule
  block.

#### Drop caps / versal treatments

A theme that wants a real drop cap (a large decorative first letter, optionally
followed by small-caps for the rest of the opening sentence -- a "versal") should
**not** ship its own inline `<script>` in `template.html` to do this. The real
article reader (`WebViewController`) loads with
`WKWebpagePreferences.allowsContentJavaScript = false`
(`Shared/Article Rendering/WebViewConfiguration.swift`), which silently blocks any
inline `<script>` a theme's own `template.html` contains -- only `WKUserScript`s
(`main.js`/`main_ios.js`/`newsfoot.js`, injected outside that restriction) run.
The Settings → Theme preview (`ArticleThemePreviewWebView`) uses a plain `WKWebView`
with no such restriction, so a theme carrying its own inline script for this will
render a drop cap correctly there and never in the real reader -- a confusing,
easy-to-miss gap between the two surfaces.

Instead, opt in to the shared, theme-agnostic implementation already in
`main.js` (`applyVersalCaps`):

1. Add `data-versal-target` to the `#bodyContainer` element in `template.html`:
   `<div id="bodyContainer" class="articleBody yourThemeBody [[text_size_class]]" data-versal-target>`.
   Without this attribute the function no-ops immediately, so it's safe for every
   other theme to leave unset.
2. `applyVersalCaps` wraps the opening sentence of the work's first paragraph, and
   of the first paragraph following each chapter heading (`h2.heading`/`h3.title`),
   in `<span class="versalCap">`.
3. Style off that span and its parent paragraph in the theme's own `stylesheet.css`,
   e.g.:
   ```css
   .yourThemeBody p:has(> .versalCap:first-child)::first-letter {
   	font-family: var(--font-main);
   	font-weight: 700;
   	font-size: 3.2em;
   	float: left;
   }
   .versalCap {
   	font-variant: small-caps;
   	letter-spacing: 0.03em;
   }
   ```

`Kelmscott.nnwtheme` is the reference theme for this pattern.

**Two gotchas that broke this in practice, both worth knowing before writing
theme-side selectors/logic against "the opening paragraph":**

1. **Book apparatus can contain an earlier `<p>` than the real prose.**
   `.summary.module`/`.notes.module` (and `.end.notes.module`) wrap their text
   in `<blockquote class="userstuff"><p>...</p></blockquote>`, which sits
   earlier in document order than the work's actual opening paragraph. A naive
   "first `<p>` in the container" search (`container.querySelector("p")`) will
   silently grab the Summary's `<p>` instead. `applyVersalCaps` in `main.js`
   guards against this explicitly (`isApparatus`, checking `.closest(".summary,
   .notes, .preface, #ao3SyntheticPreface, #ao3Preface")`) -- reuse that
   exclusion rather than re-deriving it if you're writing something else that
   needs to find "the real opening paragraph."
2. **Real AO3 chapter prose is never a direct child of `#bodyContainer`.**
   `AO3ChapterHTMLExtractor` always nests it one level deeper, inside
   `div.userstuff.module[role="article"]` (multi-chapter) or
   `div#chapters[role="article"]` (single-chapter). A pure-CSS selector that
   assumes direct-child position (`.articleBody > p:first-of-type`) will never
   match real content -- only the Settings theme preview's sample body, which
   (before this was caught and fixed) didn't reproduce that wrapper and so
   looked correct there while being wrong for every real article. If a
   drop-cap/versal rule needs the paragraph reliably located regardless of
   nesting depth, use the shared `data-versal-target` JS mechanism above
   rather than a positional CSS selector.

#### Chapter dividers / decorative elements before each chapter heading

The same reader-vs-preview split above (inline `<script>` silently not running
in the real article view) applies to any theme-owned script, not just versal
caps. A theme that wants to insert a decorative element ahead of every chapter
heading (`h2.heading`/`h3.title`) -- Vintage Letter Green's flourish divider is
the reference case -- should use the shared, generic `applyChapterDividers()`
in `main.js` instead of its own inline `<script>`:

```html
<div id="bodyContainer" class="articleBody yourThemeBody [[text_size_class]]"
	data-chapter-divider
	data-chapter-divider-char="&#10087;"
	data-chapter-divider-class="yourThemeFlourish yourThemeFlourish--chapter">[[body]]</div>
```

`data-chapter-divider-char` is the divider's text content; `data-chapter-
divider-class` is the class applied to the inserted `<div>`, so the theme's
own CSS can style it however it needs. Both attributes are required -- the
function no-ops if either is missing, so it's safe for every other theme to
leave the `data-chapter-divider*` attributes unset entirely.

`Vintage Letter Green.nnwtheme` is the reference theme for this pattern.


## Styleable blocks

Every block a theme can style, in document order, with where its markup comes
from. "Template" means `template.html` (theme-owned, may be rewritten);
"generated" means Nectar or the fetched work produces it and the theme can only
style it. Verified against `Shared/Article Rendering/template.html`,
`core.css`, `main.js`, `AO3PrefaceRenderer.swift`, and
`AO3ChapterHTMLExtractor.serializedContentHTML`.

| Block | Selector(s) | Source | Notes |
|---|---|---|---|
| Page / body | `body`, `html` | template + `core.css` | `core.css` sets `html { scrollbar-gutter: stable }` and `html, body { overflow-x: hidden }`, so anything wider than the page is clipped, not scrolled. |
| Header (feed name, byline, avatar) | `.headerContainer`, `.headerTable`, `.header`, `.feedlink`, `.avatar img`, `#nnwImageIcon` | template | Default header is a 68px-tall table. `main.js` runs `removeArticleIconAvatar()` at load, which removes every `img` whose `src` starts with `nnwimageicon:` (so the avatar `<img>` in a template never renders), and `removeFeedNameLink()`, which removes any `a[href]` with a non-empty href and empty text (what the feed-name anchor becomes when `showFeedNameInReaderView` is off). Neither depends on theme markup. See "Full-screen reading" below before shrinking or removing it. |
| Title | `.articleTitle`, `.articleTitle h1`, `.articleTitle a` | template | Must stay clear of the notch in full-screen reading. |
| Dateline | `.articleDateline` or `.articleDatelineTitle` | template (`[[dateline_style]]`) | Which class is used depends on whether the article has a title. |
| External link | `.externalLink` | template | |
| Body container | `#bodyContainer.articleBody` | template | Hard constraint: keep the id and the `articleBody` class. Everything below is inside it. |
| Fetch notice | `p.ao3ChapterFetchNotice` | generated (`ArticleRenderer`) | "Full text unavailable: ..." line prepended to the body when `contentHTML` is nil. |
| Preface | `#ao3Preface` (fetched) / `#ao3SyntheticPreface` (pre-fetch), `dl.tags`, `dt`, `dd`, `dt.wide`, `dd.wide` | generated (`AO3PrefaceRenderer`) | Structure and defaults live in `core.css`; themes restyle through the `--ao3-preface-*` variables below. `.wide` rows span the full preface width on their own line. Ambrosia items may carry their own embedded preface markup instead. |
| Preface series row | `.ao3SeriesPrefaceEntry`, `.ao3SeriesPrefaceLinks`, `.ao3SeriesNavDisabled` | generated | One `dt`/`dd` pair per series entry; the First/Previous/Next links sit on a block line under the name. |
| Author work skin | `#workskin`, plus the author's own `<style>` ahead of it | generated | Author markup and rules are left untouched on purpose; do not restyle `#workskin` descendants broadly. |
| Work summary | `.summary.module`, `h3.heading`, `blockquote.userstuff` | generated | Inside the work-level `div.preface.group`. |
| Start / end notes | `.notes.module`, `.end.notes.module`, `h3.heading`, `blockquote.userstuff` | generated | Biblioteca and Kelmscott style `.end.notes.module` explicitly. |
| Chapter heading | `h2.heading` (the extractor rewrites `h3.title` into this) | generated | A direct child of `div.chapter.preface.group`; the table of contents depends on that shape (see `ao3-preface-rendering.md`). |
| Chapter prose | `div.userstuff.module[role="article"]` (multi-chapter) or `div#chapters[role="article"]` (single chapter) | generated | Prose is never a direct child of `#bodyContainer`. |
| Series footer | `#ao3SeriesFooter`, `.ao3SeriesFooterHeading`, `.ao3SeriesFooterEntry`, `.ao3SeriesFooterName`, `.ao3SeriesFooterLinks` | generated | Appended after the work; absent for works with no series. |
| Opt-in versal | `span.versalCap` | generated by `main.js` | Only when the template sets `data-versal-target`. |
| Opt-in chapter divider | the class named by `data-chapter-divider-class` | generated by `main.js` | Only when the template sets the `data-chapter-divider*` attributes. |
| Highlights | `mark.nnw-highlight`, `span.nnw-edit-only` | generated by `annotations.js` | Colors come from `--nnw-highlight-*` variables that `WebViewController` sets; see `annotations.md`. |
| Footnotes | `a.footnote`, `.newsfoot-footnote-popover`, `-arrow`, `-inner` | generated by `newsfoot.js` | |
| Wide content | `.nnw-overflow` | generated by `main.js` | Wrapper that makes tables scroll sideways inside the page. |
| System message | `.systemMessage` | generated | Absolutely positioned in the default stylesheet. |
| Page footer | `#nnwFooter` | template, custom templates only | Not in the default template. All 13 shape C themes (below) add one. |

## Ornaments: where they go

Ornaments (rules, flourishes, corner marks, dingbats, borders) belong in a
small set of slots. Anywhere else risks colliding with generated markup, with
annotations, or with the notch.

| Slot | How to build it |
|---|---|
| Around the title | `::before`/`::after` on `.articleTitle` (Beacon and Twilight do this), or an `aria-hidden` element in `template.html` between the header and the body (Kelmscott's rule element). |
| Between header and body | An `aria-hidden` element in `template.html` or `::after` on the dateline. |
| Before each chapter heading | The shared `data-chapter-divider*` mechanism (see above). Never an inline `<script>`. |
| Edges of the preface, summary and notes blocks | `::before`/`::after` on `#ao3Preface`/`#ao3SyntheticPreface`, `.summary.module`, `.notes.module`, `.end.notes.module`. |
| End of the work | `::before` on `#ao3SeriesFooter`, `::after` on `.end.notes.module`, or `#nnwFooter` in a custom template. |
| Opening letter | The versal mechanism (`data-versal-target`) -- see "Drop caps / versal treatments". |

Rules for any ornament:

1. **Prefer CSS generated content (`content:`) to real text.** `annotations.js`
   builds its text index by walking every text node under `.articleBody`, so
   real characters a theme's markup or script adds inside the body count toward
   stored highlight offsets, where `content:` text does not. The one exception
   is the chapter-divider glyph, which `applyChapterDividers()` inserts as real
   text inside `#bodyContainer` on an element carrying `data-nnw-ornament`.
   Text inside `[data-nnw-ornament]` is excluded from the annotation index,
   range wrapping, selection and find-in-page, so the glyph is free to differ
   between themes. Only `main.js` creates such elements; a theme or shared
   script must not insert any other text under `#bodyContainer`.
2. **Mark decorative elements `aria-hidden="true"`.**
3. **Keep ornaments inside the page width.** `core.css` clips horizontal
   overflow, so an ornament that pokes past the edge is cut off rather than
   scrolled to.
4. **No inline `<script>` for ornaments.** The real reader blocks it (see "Drop
   caps / versal treatments").
5. **Nothing decorative at the very top of the page may reduce the space above
   the title** -- see the next section.
6. **A page frame belongs to the article, not the viewport.** A border that is
   meant to enclose the article must be anchored to a wrapper that scrolls with
   it (Illuminated Codex: `.codexPage` is `position: relative`, and the frame is
   its pseudo-elements and those of `.codexHeader` and `.codexFooter`). A
   `position: fixed` frame floats over the text at the screen edges instead.
   Do not run an SVG filter on a box as tall as the article; filter only short
   edge strips and leave the long edges as plain borders. Verified by reading the
   CSS, not on a device.

## Full-screen reading: space above the title

The default theme's structure leaves room above the title in full-screen
reading; custom templates may not. What the code does (confirmed by reading
`WebViewController`):

- `hideBars()` hides the navigation bar and toolbar and calls
  `updateTopSafeAreaForFullScreen()`, which sets `additionalSafeAreaInsets.top`
  to minus the raw top inset. The web view's content therefore starts at the
  very top edge of the screen instead of below the status bar area.
- `notchCoverView`, as tall as the raw top inset and filled with the article
  background color, covers the notch area when notch hiding is on (it is forced
  on whenever Page Counter is not Off).
- No shared CSS compensates: `env(safe-area-inset-top)` appears in no
  `core.css` or default `stylesheet.css` rule.

What keeps the default theme safe is structure, not a rule: its header table
(`.headerTable { height: 68px }`) sits above the title, so the title starts at
least 68px down the page. A theme whose template puts the title first, or whose
header is shorter than the device's top inset, starts the title inside that
area. That is inferred from the code above, not reproduced on a device.

Requirements for every theme:

1. At least **68px of space above the first line of the title** in the
   theme's own markup and CSS (a header at least that tall, or equivalent
   `padding-top`/`margin-top` on the topmost wrapper), including themes that hide
   or drop the header.
2. Do not rely on `env(safe-area-inset-top)` to supply it.
3. Title elements must not use `overflow: hidden`, a fixed `height`, a
   `line-height` under 1, or `white-space: nowrap` with `text-overflow`.
   Ornaments on the title may not take the space away.

Verify on a device with a notch or Dynamic Island: turn on Page Counter (forces
notch hiding), open a long-titled work, enter full-screen reading, scroll to
the top, and confirm the whole title is visible. Audit status, by template shape (see
"Custom template.html"). Shape B: the mockups were measured in headless Chromium (see
"Theme mockups", "Full-screen title check"), with the first title line 87px to 155px down
with the running head. Conversion moves a title up to 12px (`10px` top padding instead of
`22px`), so the converted bundles should clear 68px by that arithmetic; that is inferred,
and neither the bundles nor the mockups have been checked on a device. Without the `.rh`
band, 59 of the 65 mockups fell under 68px. Shapes A, C and D have not been audited, and no
test enforces this rule for any bundle. Shape A themes do not set a `.headerTable` height
of their own.

## Theme mockups

A mockup is a one-theme CSS preview of a fixed sample page, written against simplified
markup, reviewed on a single page, then converted into a `.nnwtheme`. Every mockup styles
the same sample, so themes compare like for like. The page layout, sample text and shared
CSS are below so none of it has to be regenerated; the tools that build and check the
review page are in `buildscripts/theme-mockups/`:

| File | Purpose |
|---|---|
| `build_mockup_page.py` | Builds the review page from `themes.json`. Holds the sample text and the page shell, so the page is rebuilt without regenerating anything. |
| `themes.json` | The 65 mockups of batches 3 to 8 (`id`, `cat`, `name`, `n`, `css`, `lk`). All 65 now also exist as converted bundles in `gallery-themes/` (matched by name; they were not there when this section was first written), so this file is the source of the mockups rather than the only copy of the designs. |
| `fonts.html` | The Google Fonts `<link>` tags (91 families) the mockups load. The builder writes them into the page head. Add a family here when a mockup uses a new one, or the preview silently falls back to system fonts. |
| `check_fullscreen_titles.py` | Full-screen title check in headless Chromium (needs Playwright). |

These files are not in the checkout this doc was last revised against: `buildscripts/` there has only `theme-generation/` among the theme tools, so confirm they exist before relying on the commands below.

The built review page (about 220KB) is not committed. `python3 build_mockup_page.py
themes.json out.html` regenerates it, byte for byte identical to the page it was first
built as (checked when this section was written).

### Page layout (fixed order)

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

### Sample content

The one sample every mockup renders. It is a copy of `PF` and `sample_html()` in
`build_mockup_page.py` (checked equal when this section was written); change both
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

### Shared base CSS

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

### Review page

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

### Full-screen title check

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

### Making a mockup

1. Pick the theme's `n` (any unused number in its batch) and write its rules against the
   sample markup above: `.tN` for palette and fonts, `.dk .tN` for dark values, then
   element rules. Use only the classes in the layout table.
2. Keep the title safe: `.hd` and `h1` need no `overflow: hidden`, fixed `height`,
   `line-height` under 1 or `nowrap`; ornaments must not take space above the title.
3. A theme with a custom header (negative top margin on `.hd`, large top padding) still sits
   below the band, because the band comes first.
4. Add the theme's object to `themes.json` (and any new font to `fonts.html`), rebuild the
   page, run the title check in light and dark and with `--long-title`, then review.

### Converting mockups into `.nnwtheme` bundles

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

**Info.plist fingerprints, checked across `gallery-themes/` by script:** all 117 shape B
bundles have homepage `https://github.com/kyrielie/nectar` and `CreatorName` `kyrielie`;
113 are `Version` 1 and four are `Version` 2 (why was not determined). Every one has a
`License.md`. How the 65 batch 3 to 8 bundles were converted is not recorded in this
repo; their `License.md` only says "converted to this bundle by script".

**After either route.**

1. `finalize_credits.py <dir>` sets `CreatorName` to just the creator name and moves the
   descriptive text into `License.md` (CC0 unless the bundle already ships another license).
   All 117 shape B bundles have a `License.md`; the 65 mockup conversions carry the placeholder described under "License.md".
   Leave `Version` at 1.
2. Put the bundle in `Themes/` or `gallery-themes/` (see below) and update `BUNDLED` if needed.
3. Run the theme tests named below, which scan both directories.
4. Check full-screen reading on a device, as described above.

## Where a theme lives: `Themes/` vs `gallery-themes/`

- `Themes/` is bundled into the app (`project.yml` adds it as a resources
  folder). It holds the eight NetNewsWire-origin themes (Appanoose, Biblioteca,
  Hyperlegible, NewsFax, Promenade, Sepia, Tiqoe Dark, Verdana Revival) and the
  six Nectar customs that still ship (Black & White, Duskbloom, Ember, Powder
  Pink, Tumblr Blue, Vintage Letter Green). Promenade cannot move: it is the
  fresh-install default (`AppDefaults.swift`, `Key.currentThemeName`).
- `gallery-themes/` holds every other authored theme. These are not in the app;
  they are built into the public gallery and installed from there.
- `gallery/build.py` publishes every bundle from both directories that is not in
  its `BUNDLED` set. `BUNDLED` must list exactly the bundles that live in
  `Themes/`. Moving a theme between the directories means updating `BUNDLED`
  (and `SHIPPED` in `buildscripts/theme-generation/generate_ported_themes.py`
  for generated themes) in the same change.
- Tests (`ArticleThemeOverflowSafetyTests`, `ArticleThemePlistFamilyTests`,
  `ArticleThemeColorExtractorTests`) scan both directories, so a theme keeps full
  test coverage wherever it lives.

## Theme families

Two or more `.nnwtheme` bundles that are the same design with different accents or
palettes (Dracula's hue variants before the reduction to one; Rosé Pine's Main/Moon/
Dawn palettes, plus Pinerose, whose `FamilyVariant` is "Pinerose (adaptive)") can declare `Family`/`FamilyVariant` in `Info.plist`. This is
presentational metadata only -- it doesn't merge the bundles at runtime, doesn't
change storage or deletion, and each variant is still picked, imported, and deleted
as its own complete theme. Don't add `Family` for a single bundle; it needs at
least one sibling to mean anything. As of this writing, the theme gallery
(`gallery/build.py`, `gallery/index.template.html`) does not use `Family` or
`FamilyVariant` (`build.py` copies them into the theme data, but the template ignores them) -- it lists every published bundle as its own grid card, with no
family grouping or swatch dots. See `docs/theme-gallery.md`.

Distinguish a genuine family from a single theme with an accent-color setting baked
in: if the bundles differ only in one or two color values with everything else
(background, layout, other colors) identical, consider whether that's better
expressed as a single theme with an override rather than N near-duplicate bundles.
Rosé Pine's Main/Moon/Dawn variants differ in background, text, and border colors across the
board -- a genuine multi-palette family, not an accent swap -- which is why they're
grouped rather than merged.

## Add Themes Directly to Nectar with URL Scheme
On iOS and macOS, themes can be opened directly in Nectar using the below URL scheme:

`nectar://theme/add?url={url}`

When using this URL scheme the theme being shared must be zipped.

Parameters:
- `url`: (mandatory, URL-encoded): The theme's location.
