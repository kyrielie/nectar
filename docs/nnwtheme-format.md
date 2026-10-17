# .nnwtheme Format

Bundle-file structure and authoring conventions for `.nnwtheme` themes. For
the Swift-side theme system (`ArticleTheme`, `ArticleThemesManager`, color
extraction, rendering integration), see `theme-system.md`.

Starting a new theme? Read `creating-a-theme.md` first: it is the short, spec-only
walk-through, and this document is the reference behind it. Mockups and the
mockup-to-bundle conversion history are in `theme-mockups.md`.

## Theme contract

One table for every rule a theme is held to. "Required" alone is ambiguous, so each row names
who enforces it. The sections below hold the detail; the rows link to them. Two visual
versions open in a browser: `theme-contract.html` (this table, filterable by enforcement level)
and `theme-anatomy.html` (a mock rendered article page with every block numbered and
annotated: what the template supplies, what Nectar generates, what is opt-in).

Enforcement levels, strongest first:

| Level | Meaning | What happens if you break it |
|---|---|---|
| **App** | The Swift loader needs it | The theme falls back to the default, or does not load |
| **Build** | `gallery/build.py` checks it | The gallery build fails |
| **Test** | A unit test checks it | CI fails |
| **Release** | `--check-release-identity` compares with the base branch | The release check fails |
| **Docs only** | Written down, checked by nothing | Nothing fails; the theme may still render badly |

A person importing a theme is held only to the App level (`theme-system.md`, "Two tiers").
Bundles shipped in `Themes/` or the gallery are held to every level.

| Item | Status | Enforced at | Detail |
|---|---|---|---|
| Folder `<Name>.nnwtheme` | Required | App (the folder name is the identity) | `.nnwtheme` Structure |
| `Info.plist` present | Required | App (without it nothing identifies the theme) | `Info.plist` |
| `Name`, `ThemeIdentifier`, `CreatorHomePage`, `CreatorName`, `Version` | Required for shipped bundles | Build (`REQUIRED_KEYS`). Import is lenient: a missing key decodes to `""` or `0` | `Info.plist` |
| `Version` is an integer of 1 or more | Required | Build (`version_problems`) | `Info.plist` |
| `Version` raised when `stylesheet.css` or `template.html` changed | Required for existing bundles | Release (`--check-release-identity`) | `theme-gallery.md` |
| `ThemeIdentifier` and folder name unchanged once published | Required | Release | `theme-gallery.md` |
| `Family`, `FamilyVariant` | Optional | Test (`ArticleThemePlistFamilyTests`, when set) | `Theme families` |
| `template.html` present | Required for shipped bundles | Build and tests. App falls back to the default if missing | `template.html` |
| `#bodyContainer` carrying class `articleBody` | Required | Build (regex). The override and color systems also key off it | Custom template.html |
| `[[body]]` token | Required | Docs only | Custom template.html |
| `[[title]]`, `[[preferred_link]]`, `[[byline]]` | Unverified | Nothing; omitting was never tested | Required vs optional |
| Header, running head, feed link, date, avatar, external link, `[[dateline_style]]` | Optional | Nothing | Custom template.html |
| `data-versal-target` | Optional | Nothing (no-ops if absent) | Drop caps / versal treatments |
| `data-chapter-divider` with `-char` and `-class` | Optional, all three together | Nothing (no-ops if either is missing) | Chapter dividers |
| `#nnwFooter` | Optional, custom templates only | Nothing | Styleable blocks |
| Inline `<script>` | Forbidden | The real reader blocks it | Drop caps / versal treatments |
| Space above the title for the notch | Not needed (the app keeps the page below the notch cover) | Nothing | Full-screen reading |
| `stylesheet.css` present | Required for shipped bundles | Build and tests. App falls back to the default if missing | `stylesheet.css` |
| `img, figure, video, div, object { max-width: 100% }` | Required in practice | Test (`ArticleThemeOverflowSafetyTests`); build only warns | `stylesheet.css` |
| `--nnw-bg`, `--nnw-ink`, `--nnw-link` as literals in `:root` and the dark `:root`; page color as `background-color` on `body` | Required for shipped bundles | Docs only | Color tokens and the page color |
| `--ao3-preface-*` variables | Optional | Nothing (`core.css` supplies fallbacks) | Styleable blocks |
| `@media (prefers-color-scheme: dark)` block | Optional | Nothing. Without it the gallery classifies by `body` background luminance | Color tokens and the page color |
| `--gx`, `--u`, `--font-*`, the iOS and macOS `@supports` split | Convention | Nothing | `stylesheet.css` |
| `License.md` | Optional; expected for ports | Nothing (no code reads it) | `License.md` |

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
|`ThemeIdentifier`|`String`|Unique identifier for the theme, e.g. using reverse domain name. Nectar bundles use `com.nectar.themes.<slug>` (plural `themes`). The slug is usually the lower-cased name, but a few older bundles keep ids from earlier names (Beacon `teenwolf`, Mystery `gravityfalls`, Perseus `percyjackson`, Black & White `blackandwhite`) and were not renamed, since changing an identifier would make an installed copy look like a different theme (inferred; not checked in code). The NetNewsWire-origin bundles keep their upstream ids. The 65 batch 3 to 8 conversions were `com.nectar.theme.<slug>` (singular) and have been changed to match.|
|`Name`|`String`|Theme name|
|`CreatorHomePage`|`String`||
|`CreatorName`|`String`|The creator's name (a person or organization), and nothing else. **Do not put the theme's description, attribution prose, or license status here** -- those go in `License.md` (see below). Migrated: every bundle except the eight NetNewsWire-origin ones (which keep their upstream creators and are left alone) now has `CreatorName` `kyrielie`, and the text that used to sit here is in its `License.md`. `gallery/build.py` still copies this key into its `by` field and does not read `License.md` (confirmed by reading it), so the gallery's detail dialog shows only the creator name for migrated bundles until the build reads `License.md`. `buildscripts/theme-generation/generate_ported_themes.py` now writes `kyrielie` here and puts its `creator=` text in a new `License.md` only when the bundle has none. The gallery grid card shows only the theme name -- see `docs/theme-gallery.md`.|
|`Version`|`Integer`|Start at `1`. An integer of 1 or more (build check). Raise it whenever `stylesheet.css` or `template.html` changes in a bundle that already exists on the base branch: `--check-release-identity` fails otherwise (`theme-gallery.md`). An edit confined to `Info.plist` or `License.md` needs no bump. Older text said not to bump it during development; the release check supersedes that. Existing values vary (gallery bundles at 1 to 3, two bundles in `Themes/` at 3 and 14).|
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
look). Current state: every bundle has a `License.md` except some of the NetNewsWire-origin
ones, which are left unchanged (`buildscripts/theme-generation/theme_inventory.py
--details` lists them).
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
- `ArticleThemeOverrides.cssOverrideBlock` and the legacy `ArticleThemeColorExtractor`
  fallback both target `.articleBody` by class name, not by structural position -- a
  theme that renames or drops that class breaks font-size/line-height/color overrides and
  the live theme-color preview for anyone using that theme. The color probe also reads
  `.articleBody`'s computed `color`, falling back to `body`.

Everything else in a custom `template.html` -- header layout, added wrapper elements,
decorative markup, alternate class names on non-`articleBody` elements -- is fair game.

**Header elements are optional.** The running head (`div.rh` with the feed link and
date), the byline, the title link and every other header placeholder are design
choices, not requirements. Do not add a running head, feed link, date or byline to a
new theme unless the design calls for one. A theme may open with its own ornament
(Nectar opens with a full-width frieze) or with the title alone. The only header-related
requirement is that the title is not clipped (see "Full-screen reading"); the app supplies the
notch clearance, so a theme with no running head needs no extra top padding.

#### Template shapes in `gallery-themes/`

Surveyed by reading `gallery-themes/*/template.html` (`Themes/` was not surveyed); later
additions were classified by matching `class="rh"` in their templates, not by reading each
one. `buildscripts/theme-generation/theme_inventory.py` detects shape B the same way and
prints the current counts. None are kept in this document, because they drifted and
disagreed with each other across docs.

| Shape | Markup | Examples |
|---|---|---|
| A. NetNewsWire header table | `header.headerContainer > table.headerTable` (feed link and byline left; upstream's stock template also has an avatar cell on the right, which Nectar's built-in template and every shipped and gallery theme have dropped), then title, `[[dateline_style]]`, external link, body. Stock NetNewsWire structure. | Beacon, Dracula, Twilight, Rosé Pine (all four variants) |
| B. Compact running head | Converted from mockups (see `theme-mockups.md`). 8 lines: `div.rh` (feed link left, date right), then `div.t.tNN > header.hd` (title, byline), then body. `tNN` (t1 to t38) is a per-theme variant class, so the design lives in the CSS. No `[[dateline_style]]`, no external-link line. No avatar, except Birdsite and Watch Later, which draw the feed image as a profile picture over a CSS placeholder disc (`<img class="av" src="[[avatar_src]]" data-nnw-keep>`). | Swiss International, Disco, Bauhaus, Birdsite, Watch Later, Bridge Command |
| C. Custom wrapper | `div.fontSize` wrapper, external-link line, and `#nnwFooter`. The six older themes (Aldine, Deco Line, Kelmscott, Kennerley, Marigold Press, Rosarivo) keep header bars with the feed link (their avatar was removed); the seven newer ones (Craft Table, Didone Editorial, Four Nations, Illuminated Codex, Mid-century Jost, Screenplay, Sticker Pop) have no feed link or avatar and open with the title. | Craft Table, Illuminated Codex |
| D. Outliers | Broadsheet is the stock layout plus a live inline `<script>` (blocked in the real reader). Heist Night and Undercity Dusk are hand-built (Route B in `theme-mockups.md`), B-like with their own class prefixes (`sc-`, `ar-`). | |

A shape is a label for markup that already exists, not a category the app knows. Reading
`main.js`, `core.css`, `gallery/build.py` and the Swift sources found nothing that reads a
theme's shape; the only code that does is `theme_inventory.py`, which classifies by substring
match (`class="rh"`, `headerTable`), and `generate_ported_themes.py`, which emits shape A
markup. Every opt-in in "Required vs optional" below (`data-versal-target`,
`data-chapter-divider*`, dark block, `[[...]]` tokens) works on any shape, because each one
keys off `#bodyContainer` or the CSS, not off the header.

What the existing bundles do differs by shape. None of the 23 `gallery-themes/` templates that
contain `headerTable` used `data-versal-target` or `data-chapter-divider*` before Beacon opted
into chapter dividers, and only Pinerose and Hyperlegible have a `prefers-color-scheme: dark`
block, so the other header-table themes are single-mode. Those are habits of the generator's
output and of a stock layout, not limits of the format. B opts into the divider mechanism and, unless its design drops the drop cap, into versal;
every B theme has a dark block. A B template that omits `data-versal-target` chose no drop
cap or small-caps opening words, and its stylesheet may keep `.versalCap` and
`::first-letter` rules that can no longer match (`theme_inventory.py --details` lists the
templates without `data-versal-target`). C is mixed: some use versal, the six older ones
have no divider attributes at all, and the newer ones use visible dividers (a diamond, a
fleuron, kanji, `CUT TO:`, `/`). Kelmscott's template mentions an inline script only in a
comment explaining why it was removed; it ships none.

#### Which templates to add, and which to start from

Only shape B is the recommended starter. It is the one pipeline with a documented layout, a mockup
review page, a mockup-to-bundle contract and a title-spacing check (see `theme-mockups.md`). Two
templates are kept in these docs, and neither is the default: pick by what the design
needs, and leave the running head out unless the design uses it.

1. **B with the running head.** Written out below. Its running head is a design choice,
   not a spacer.
2. **B without the header.** The same file with the `.rh` line deleted. The app supplies the notch clearance, so the theme adds no top spacing for it (older bundles
   that carry 66 to 76px of it are leftovers). The mockup measurements below date from when
   the theme had to supply 68px. Nectar is the example: its full-width frieze opens the page, `.t` has
   18px of top padding, and the title measured 108px down in headless Chromium. That was
   measured in a browser, not on a device, so check it on a device.

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

(This is Swiss International's `template.html` with its `t16` replaced by `tN`. Most shape
B templates are identical to it apart from that class number; the ones without
`data-versal-target` chose no drop cap, and Bridge Command adds a nav strip and a credit
line.)
Drop `data-versal-target` for a theme with no drop cap. The layout it renders is the fixed order under "Page layout" in `theme-mockups.md`.

Not added as starters:

- **A (header table).** It is the stock NetNewsWire layout, whose source is
  `Shared/Article Rendering/template.html`. It is not a starter because no mockup pipeline
  or title check exists for it, not because it cannot carry a design. Its avatar is stripped
  unless the `<img>` carries `data-nnw-keep` (see the avatar row below), and its header height is unaudited, but the stock template sets no versal or divider
  attributes only because it was not written to; add them to `#bodyContainer` as in
  "Chapter dividers" if the design wants them (Beacon does). Use A for a faithful port, or
  for an original design that wants the header table as its masthead; for the latter, check
  the top of the page on a device.
- **C (custom wrapper).** The older six carry a legacy header bar. The newer
  seven (Craft Table, Didone Editorial, Four Nations, Illuminated Codex, Mid-century Jost,
  Screenplay, Sticker Pop) are bespoke designs with no header and no running head. Read them for a footer or an external-link line; do not copy their top
  spacing.
- **D.** Broadsheet ships a live inline `<script>`, and the other two are one-off hand-built
  designs.
- **Any inline `<script>`**, in any shape (see "Drop caps / versal treatments").

The shape B template has no external-link line. Add `<div class="externalLink">[[external_link_label]] <a href="[[external_link]]">[[external_link_stripped]]</a></div>` after `#bodyContainer` if the design needs it (not tested in a B bundle).

#### Required vs optional

This table is the bar for bundles that ship with Nectar or in the gallery. It is an
authoring standard, not an import rule: a theme a person imports loads even if it
breaks every row here (see `theme-system.md`, "Two tiers").

| Item | Status | Enforced by |
|---|---|---|
| `Name`, `ThemeIdentifier`, `CreatorHomePage`, `CreatorName`, `Version` in `Info.plist` | Required | `REQUIRED_KEYS` in `gallery/build.py` (fails the build) |
| `#bodyContainer` with the `articleBody` class | Required | `gallery/build.py` regex (fails the build) |
| `img, ... { max-width: 100% }` rule in the CSS | Required in practice | `build.py` only warns, but `ArticleThemeOverflowSafetyTests` fails on it |
| Space above the title for the notch | Not needed | Nothing |
| `Family`, `FamilyVariant`, `License.md` | Optional (`License.md` expected for ports) | Nothing |
| `[[avatar_src]]` | Optional | Shape B omits it; `main.js` strips the image unless the `<img>` carries `data-nnw-keep`. Neither the built-in template nor any bundled or gallery template renders it except Birdsite and Watch Later; keep it out of new themes unless the design has a profile-picture slot |
| `[[dateline_style]]`, `[[datetime_*]]`, `[[date_*]]` | Optional | Shape B uses only `[[date_medium]]` and `[[datetime_long]]` |
| `[[external_link*]]` | Optional | Shape B omits it |
| The running head (`div.rh`), `[[feed_link]]`, `[[feed_link_title]]`, `[[date_medium]]`, `[[datetime_long]]` | Optional; leave out unless the design uses them | Nothing requires them; `removeFeedNameLink` only acts on anchors that exist |
| `[[byline]]`, `[[title]]`, `[[preferred_link]]` | Unverified | Every gallery template includes them, so whether omitting is safe was not tested |
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

#### Color tokens and the page color

The app measures a theme's page, ink and link colors by rendering it
(`ArticleThemeColorProbe`) for the webview background, the full-screen notch cover, the
page-counter text and the Blend nav bar. Tokens and selectors are therefore optional;
the code path is in `article-color-pipeline.md`.

- Write colors the way you like: on `html` or `body`, with the `background` shorthand,
  `light-dark()`, `oklch()`, space-separated `rgb()`, or a `color-scheme` with no explicit
  colors. The probe reads computed values.
- `--nnw-bg`, `--nnw-ink` and `--nnw-link` are an optional convenience. Themes that use
  them still get the user color override applied through the same variables. If you use
  them, keep them literal and in the single dark `:root` block as before, which also keeps
  the legacy scanner fallback accurate.
- The page color is `background-color` on `body`, else `html`. A gradient or image alone
  counts as unpainted, so also set a `background-color` near the gradient's top edge.
- Ink must contrast with the page (WCAG 1.5 or more for ink and for links) and must not
  equal it, or the measurement is rejected and the scanner fallback is used.
- Content JavaScript never runs in the reader, so a script that recolors the page has no
  effect on the measurement.
- Upstream-compatible subset: no `@import`, no scripts, `Name` equals the bundle name, no
  bundle-local `url()` (see `theme-gallery.md`). Every bundle in `Themes/` and
  `gallery-themes/` keeps `Info.plist` `Name` equal to the folder name, both in NFC
  (`gallery/test_build.py` enforces this and the absence of placeholder metadata such as
  `starter` or `example.com` in `ThemeIdentifier`, `Name`, `CreatorHomePage`,
  `CreatorName`). A folder name typed on macOS can be NFD; rename it to NFC rather than
  changing `Name`. The app looks themes up by folder name, not by `ThemeIdentifier`, so
  correcting an identifier does not affect existing selections.
- Known divergence from upstream `core.css`: Nectar's lacks `.articleBody, .article-body
  { position: relative }`, `pre, code { tab-size: 4 }`, the twemoji layout rules, and the
  hiding rules for `img[src*="/img/social/"]`, `.social_items` and `.mcnFollowBlock`; it
  adds `html, body { overflow-x: hidden }`, paragraph spacing and indent, the AO3 preface
  rules and the highlight rules. This is documented, not synced.

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

- `core.css` reads all five variables (`border-color`, `background-color`, `text-color`,
  `label-color`, `font-size`), each with a fallback, so a theme can set any of them.
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

`Vintage Letter Green.nnwtheme` is the reference theme for this pattern. It is
shape-independent: `applyChapterDividers()` only reads `#bodyContainer`, and inserts the
divider as a sibling directly before each heading, so it works in a shape A template too.
`Beacon.nnwtheme` (shape A) is the example. It sets the character to a zero-width space
(`&#8203;`) and draws the ornament as a CSS mask on `::before` of the inserted class. The
mask is needed because the shared `div { height: auto !important }` rule would override a
height set on the divider div itself, so the size has to live on the pseudo-element.


#### Glass themes (`backdrop-filter`)

Liquid Glass Clear and Liquid Glass Aurora (`gallery-themes/`, family "Liquid Glass", shape B, `t308`/`t310`) are the reference for translucent themes. What the CSS was written against (not yet run on a device):

- **Background on `body`, not `.t`.** The glass is blurred background, so the gradient has to sit behind the panels. It is set as `background-image` on `body` next to `background-color: var(--nnw-bg)`; the probe records `background-color` for the webview and notch cover and ignores `background-image`. Prefer `background-image` over the `background` shorthand on that selector so the flat color stays declared. `.t` is `background: none`.
- **`--nnw-bg` should match the top of the gradient**, so the notch cover blends into the page. A user background override recolors only the flat color underneath, not the gradient (inferred from the override description in `article-color-pipeline.md`).
- **Tile the background.** An article can be tens of thousands of words tall; a single percent-positioned gradient would stretch across all of it. Both themes use `background-size: 100% <tile>px; background-repeat: repeat-y` with a tile that has no seam (Clear is a palindrome; Aurora keeps every blob clear of the tile edges). `background-attachment: fixed` is not used; its behavior in WKWebView was not checked.
- **`body` spans the full width** (`max-width: none`, side padding of `max(0px, (100% - 44em) / 2)`) so its background reaches the edges on iPad/macOS. The macOS block uses body padding instead of margins for the same reason.
- **Custom properties.** `cssCustomProperties` collects every `--name: value;` in the non-dark CSS regardless of selector and lets later declarations win, so never redeclare `--nnw-*` outside `:root` and the dark block. Palette, glass and gradient variables are all in `:root` with dark overrides in the one dark media block.
- **Blur and saturate only.** SVG filters inside `backdrop-filter` render in Chromium only, so none are used. Keep blur at 6px or more (Clear uses 6px, the rest 18px or more); Apple's Regular/Clear guidance and later user feedback both favor more opacity under text, so every glass theme carries a scrim or dim layer under the body text.
- **One blurred layer per surface.** Only `.hd`, `.bd` and the two running-head capsules use `backdrop-filter`; the preface, summary, notes and chapter pills are flat tints.
- **Unverified on device:** whether `backdrop-filter` in the real reader samples the `body` background correctly, the cost of a full-article-height `backdrop-filter` box, and how the glass layout looks with the notch cover now that the page starts below it.
- **Running head as capsules.** `.rh-feed` and `.rh-date` are separate glass pills (34px tall, centered in the 56px band); the feed pill ellipsizes long names.

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
| Header (feed name, byline, avatar) | `.headerContainer`, `.headerTable`, `.header`, `.feedlink`, `.avatar img`, `#nnwImageIcon` | template | Default header is a 68px-tall table. `main.js` runs `removeArticleIconAvatar()` at load, which removes every `img` whose `src` starts with `nnwimageicon:` unless it carries `data-nnw-keep` (a theme opts in per element; a kept avatar that fails to load is removed too, so no broken-image glyph shows), and `removeFeedNameLink()`, which removes any `a[href]` with a non-empty href and empty text (what the feed-name anchor becomes when `showFeedNameInReaderView` is off). Neither depends on theme markup. A kept avatar is drawn by `ArticleIconSchemeHandler` at 192 points square and aspect-fit, so size it with CSS or `width`/`height`; it is a single author's cached avatar if there is one, else the bundled AO3 mark when the article's own link is an AO3 host (including Ambrosia items), else the regular article icon, and a transparent image when none exists. Timeline and feed-row icons are unchanged. See "Full-screen reading" below before shrinking or removing it. |
| Title | `.articleTitle`, `.articleTitle h1`, `.articleTitle a` | template | Not clipped by overflow or fixed height; the app keeps the page below the notch cover. |
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
| AO3 series module | `#series.series.module`, `h3.heading`, `ul > li > span.series`, `a.previous`, `span.position`, `a.next` | generated by AO3 (shipped inside `#workskin`) | Not shown when `#ao3SeriesFooter` exists: `main.js` `removeAO3SeriesModule` removes it, and an `.afterword` it leaves empty. Works stored before the footer existed keep it. Previous/next order is previous, position, next. |
| Works inspired by this one | `#children.children.module`, `h3.heading`, `ul > li` | generated by AO3 (shipped inside `#workskin`) | Last block in `.afterword`, after the end notes and series module. Nectar builds nothing for it; links open in the browser. Each `li` is `Work by author`, or the restricted or unrevealed variant (see `theme-anatomy.html`, note 13). |
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
| Before each chapter heading | The shared `data-chapter-divider*` mechanism (see above), in any template shape (Vintage Letter Green, Beacon). Never an inline `<script>`. |
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

Themes need no top clearance for full-screen reading. What the code does (confirmed by
reading `WebViewController`):

- `hideBars()` hides the navigation bar and toolbar and sets `additionalSafeAreaInsets.top`
  to 0. The top safe-area inset (the notch or Dynamic Island footprint) is deliberately left
  in place, as in upstream NetNewsWire, so the page starts directly below the notch area at
  scroll position 0 and scrolls up past it as usual.
- `notchCoverView`, as tall as the top safe-area inset and filled with the article
  background color, covers the notch area when notch hiding is on (it is forced
  on whenever Page Counter is not Off). Content scrolling up passes under it.
- The cover's color is the theme's measured page color (`ArticleThemeColorStore`),
  which is `background-color` on `body`, else `html`; see `article-color-pipeline.md`.
- No shared CSS compensates and none is needed: `env(safe-area-inset-top)` appears in no
  `core.css` or default `stylesheet.css` rule, and `page.html` has no `viewport-fit=cover`.

History: earlier builds cancelled the top inset (`updateTopSafeAreaForFullScreen()`), which put
page y=0 under the cover and forced every theme to add about 68px above the title. That
function is gone. Bundles written under the old rule may still carry a trailing
`html{padding-top:Npx}` "Full-screen clearance" rule, a `.t` or wrapper `padding-top` of 66 to
76px, or a running head that was only there to supply the space; those are leftovers that now
add blank space at the top of the page. Do not add them to a new theme. See
`theme-fullscreen-audit.md` for the status of the cleanup.

Requirements for every theme:

1. Title elements must not use `overflow: hidden`, a fixed `height`, a `line-height` under 1,
   or `white-space: nowrap` with `text-overflow`. Ornaments on the title may not take the
   space away.
2. Do not rely on `env(safe-area-inset-top)`; it is 0 in the reader.

Verify on a device with a notch or Dynamic Island: turn on Page Counter (forces notch
hiding), open a long-titled work, enter full-screen reading, scroll to the top, and confirm
the whole title is visible and sits just below the cover. This was changed by reading code and
has not yet been confirmed on a device.

## Theme mockups and mockup-to-bundle conversion

Moved to `theme-mockups.md`: the fixed sample page and layout order, the shared base CSS,
the review page and full-screen title check, how to make a mockup, and the two conversion
routes that produced the shape B bundles (with the mockup-to-bundle contract table). That
material describes tooling that is not in this repo and part of it is history, so it no
longer sits in the authoring reference. The old 68px
title-clearance rule it fed is retired; see "Full-screen reading: space above the title" above.

## Where a theme lives: `Themes/` vs `gallery-themes/`

- `Themes/` is bundled into the app (`project.yml` adds it as a resources
  folder). It holds ten themes: System, Reversi, Duskbloom, Midnight Blue, OLED
  Black, Night Amber, Solarized, Dark Academia, Nectar and High Contrast. The
  eight NetNewsWire-origin themes are gallery-only now. The fresh-install theme is
  the built-in `Default` (`ArticleThemesManager.defaultThemeName`). A theme with a
  bundled name cannot be imported (`theme-system.md`, "Built-in names are reserved").
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
least one sibling to mean anything. The theme gallery
(`gallery/build.py`, `gallery/index.template.html`) does not use `Family` or
`FamilyVariant` (`build.py` copies them into the theme data, but the template ignores them) -- it lists every published bundle as its own grid card, with no
family grouping or swatch dots. See `docs/theme-gallery.md`.

Liquid Glass Clear and Liquid Glass Aurora (family "Liquid Glass", variants "Clear" and "Aurora") are a two-bundle family added after the counts and shape tables above were taken; those counts were not refreshed.

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

When using this URL scheme the theme being shared must be zipped, and the zip must
contain a `<Name>.nnwtheme` folder. Anything else in the archive is ignored: extra
files and subfolders are dropped, missing theme files fall back to the app default,
and a missing or malformed `Info.plist` just means the creator shows as "Unknown". The
URL must be `http` or `https` and the file at most 10,000,000 bytes. Archives that fail
a safety rule (path escapes, links, size caps, unsupported zip features) are still
rejected; see `theme-system.md` ("Two tiers") for the full list.

Parameters:
- `url`: (mandatory, URL-encoded): The theme's location.
