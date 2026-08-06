# Themes

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
|`CreatorName`|`String`||
|`Version`|`Integer`||
|`Family`|`String`|Optional. Groups sibling bundles that are the same design with different accents/palettes (e.g. "Rosé Pine") for display in the theme gallery. Omit unless there are genuinely 2+ sibling bundles -- a family of one just adds gallery nesting for nothing, and isn't how any single-variant theme (including Dracula, reduced to one accent) is set up.|
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
- Only reference font families genuinely published on Google Fonts -- confirm on
  fonts.google.com before writing the `@import`, don't guess a family name.

## Theme families

Two or more `.nnwtheme` bundles that are the same design with different accents or
palettes (Dracula's hue variants before the reduction to one; Rosé Pine's Main/Moon/
Dawn palettes) can declare `Family`/`FamilyVariant` in `Info.plist` to be grouped
together in the theme gallery, with one thumbnail and per-variant swatch dots rather
than N separate grid cells. This is presentational only -- it doesn't merge the
bundles at runtime, doesn't change storage or deletion, and each variant is still
picked, imported, and deleted as its own complete theme. Don't add `Family` for a
single bundle; it needs at least one sibling to mean anything.

Distinguish a genuine family from a single theme with an accent-color setting baked
in: if the bundles differ only in one or two color values with everything else
(background, layout, other colors) identical, consider whether that's better
expressed as a single theme with an override rather than N near-duplicate bundles.
Rosé Pine's three variants differ in background, text, and border colors across the
board -- a genuine multi-palette family, not an accent swap -- which is why they're
grouped rather than merged.

## Add Themes Directly to NetNewsWire with URL Scheme
On iOS and macOS, themes can be opened directly in NetNewsWire using the below URL scheme:

`netnewswire://theme/add?url={url}`

When using this URL scheme the theme being shared must be zipped.

Parameters:
- `url`: (mandatory, URL-encoded): The theme's location.
