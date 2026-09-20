# .nnwtheme Format

Bundle-file structure and authoring conventions for `.nnwtheme` themes. For
the Swift-side theme system (`ArticleTheme`, `ArticleThemesManager`, color
extraction, rendering integration), see `theme-system.md`.

## `.nnwtheme` Structure

An `.nnwtheme` comprises of three files:
- `Info.plist`
- `template.html`
- `stylesheet.css`

### Info.plist
The `Info.plist` requires the following keys/types:

|Key|Type|Notes|
|---|---|---|
|`ThemeIdentifier`|`String`|Unique identifier for the theme, e.g. using reverse domain name.|
|`Name`|`String`|Theme name|
|`CreatorHomePage`|`String`||
|`CreatorName`|`String`|Also shown as the "Description" in the theme gallery's detail modal (`gallery/build.py`'s `by` field). The gallery grid card itself shows only the theme name -- see `docs/theme-gallery.md`.|
|`Version`|`Integer`||
|`Family`|`String`|Optional. Groups sibling bundles that are the same design with different accents/palettes (e.g. "Rosé Pine"). Omit unless there are genuinely 2+ sibling bundles -- a family of one adds nothing, and isn't how any single-variant theme (including Dracula, reduced to one accent) is set up. Not currently read by the theme gallery (see "Theme families" below).|
|`FamilyVariant`|`String`|Optional. This bundle's variant label within `Family` (e.g. "Moon", "Purple"). Meaningless without `Family` also being set.|

### template.html
This provides a starting point for editing the structure of the page. Theme variables are documented in the header.

### Custom template.html

A theme is not required to reuse the default `template.html` verbatim. Two shipped
themes already don't: `Vintage Letter Green.nnwtheme` (full custom markup — letter-header/
letter-seal/letter-title/etc.) and `Biblioteca.nnwtheme` (renamed header container class).

The one hard constraint: `#bodyContainer` must keep the `articleBody` class, whatever
other classes it also carries (e.g. `class="articleBody letter-body [[text_size_class]]"`).
Two systems key off that exact class name regardless of which theme is active:

- `core.css`'s AO3 preface rules (`#ao3SyntheticPreface`, `#ao3Preface`) are concatenated
  ahead of every theme's CSS and assume no theme overrides them at the markup level.
- `ArticleThemeOverrides.cssOverrideBlock` and `ArticleThemeColorExtractor` both target
  `.articleBody` by class name, not by structural position — a theme that renames or
  drops that class breaks font-size/line-height/color overrides and the live theme-color
  preview for anyone using that theme.

Everything else in a custom `template.html` — header layout, added wrapper elements,
decorative markup, alternate class names on non-`articleBody` elements — is fair game.

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
Dawn palettes) can declare `Family`/`FamilyVariant` in `Info.plist`. This is
presentational metadata only -- it doesn't merge the bundles at runtime, doesn't
change storage or deletion, and each variant is still picked, imported, and deleted
as its own complete theme. Don't add `Family` for a single bundle; it needs at
least one sibling to mean anything. As of this writing, the theme gallery
(`gallery/build.py`, `gallery/index.template.html`) does not read `Family` or
`FamilyVariant` -- it lists every published bundle as its own grid card, with no
family grouping or swatch dots. See `docs/theme-gallery.md`.

Distinguish a genuine family from a single theme with an accent-color setting baked
in: if the bundles differ only in one or two color values with everything else
(background, layout, other colors) identical, consider whether that's better
expressed as a single theme with an override rather than N near-duplicate bundles.
Rosé Pine's three variants differ in background, text, and border colors across the
board -- a genuine multi-palette family, not an accent swap -- which is why they're
grouped rather than merged.

## Add Themes Directly to Nectar with URL Scheme
On iOS and macOS, themes can be opened directly in Nectar using the below URL scheme:

`nectar://theme/add?url={url}`

When using this URL scheme the theme being shared must be zipped.

Parameters:
- `url`: (mandatory, URL-encoded): The theme's location.
