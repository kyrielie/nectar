# Theme gallery

The public static site (`gallery/`) that lists every gallery-only `.nnwtheme`
bundle (see `nnwtheme-format.md` for what "gallery-only" vs. bundled means),
lets a visitor preview each one, and installs it into Nectar with a single
tap. Deployed to GitHub Pages. For the bundle format itself, see
`nnwtheme-format.md`; for the Swift-side theme system, see `theme-system.md`.

## `build.py`

`gallery/build.py` is the only build step; standard library only, no
dependencies to install.

```
python3 gallery/build.py [--out gallery/dist] [--base-url URL] [--src DIR ...]
```

For every `.nnwtheme` bundle under `--src` (default: `Themes/` and
`gallery-themes/`) that isn't in `BUNDLED`, it:

1. Validates the bundle against the constraints in `nnwtheme-format.md`
   (required `Info.plist` keys, `#bodyContainer`/`articleBody` in
   `template.html`, an overflow guard in the CSS) -- a validation failure
   fails the build (`sys.exit(1)`), a missing overflow guard only warns.
2. Writes `dist/zips/<slug>.nnwtheme.zip`, with the bundle's real folder name
   kept as the zip's single top-level directory (the app derives the theme
   name from that folder on import, not from the zip's file name).
3. Writes `dist/index.html` from `index.template.html`, with every theme's
   CSS, imports, and `template.html` inlined into one `__DATA__` JSON blob
   and `Shared/Article Rendering/core.css` inlined as `__CORE__` -- the page
   needs no fetches for its own data and works opened straight from disk.

### `BUNDLED`

`BUNDLED` is the set of bundle names that ship inside the app (everything
physically in `Themes/`) and must never be published to the gallery, because
a person who already has them can't "install" them again in any useful
sense. It also excludes anything whose `ThemeIdentifier` starts with
`com.netnewswire.themes.` (`BUNDLED_ID_PREFIXES`), so a new NetNewsWire
starter theme dropped into `Themes/` is skipped automatically without a
`BUNDLED` edit. Anything in `gallery-themes/` is published unconditionally --
that directory has no other purpose. Moving a theme between `Themes/` and
`gallery-themes/` means updating `BUNDLED` here in the same change (see
`nnwtheme-format.md`'s "Where a theme lives" section).

As of this writing there are 26 gallery-only themes under `gallery-themes/`
and 14 bundled themes under `Themes/` (8 NetNewsWire-origin + 6 Nectar
customs) -- see `theme-system.md` for the itemized lists. This count drifts
as themes are added; don't treat it as load-bearing anywhere outside this
doc.

### Tone classification

Each theme is classified `light`, `dark`, or `both` (`load_theme`'s `tone`
field), driving the gallery's "Light mode"/"Dark mode"/"All" filter chips:

- `both` if the stylesheet has an `@media (prefers-color-scheme: dark)`
  block at all (`has_dark`), regardless of what's inside it.
- Otherwise, `dark` or `light` based on the luminance of the first
  unconditional `body` background-color declaration (`light_luminance`) --
  luminance under 0.4 counts as `dark`. A theme with no `body`
  background-color declaration at all falls through `light_luminance`
  returning `None`, which this check treats as `light` (`lum is not None and
  lum < 0.4` is false when `lum` is `None`).

This is deliberately a much simpler heuristic than
`ArticleThemeColorExtractor.colors(css:)` (`article-color-pipeline.md`) --
it only needs a light/dark bucket for the filter UI, not the actual resolved
colors the app renders, and it works from plain regex rather than the
extractor's brace-block/variable-resolution machinery (which lives in the
app target, not in this standalone Python script).

## `index.template.html`

The template has three parts:

- Static markup and CSS: the page chrome (banner, sticky filter bar, grid,
  detail dialog). See "Page styling notes" below for specifics that have
  changed recently.
- `__DATA__`: replaced at build time with a JSON blob
  `{base, scheme, themes: [...]}` -- `base` is `--base-url`, `scheme` is
  always `"nectar"` (the app's URL scheme, not NetNewsWire's -- see "Install
  link" below), and each theme entry carries everything `build.py` extracted
  (`name`, `slug`, `by`, `tone`, `dark`, `imp`, `css`, `template`, `zip`,
  etc.).
- `__CORE__`: replaced with `core.css`'s contents as a JSON string, so the
  preview iframes can compose `core.css + theme.css` the same way
  `ArticleTheme.init()` does in the app.

### `frameDoc()` / `themeCSS()` / `frameScript` mirroring the app

These three pieces of `index.template.html` reimplement, in JavaScript,
behavior that the real app gets from Swift + WebKit. They must be kept in
sync by hand -- there's no shared source between the two:

- **`themeCSS(t, mode)`** mirrors the `@supports (-webkit-touch-callout:
  none)` / `@supports not (...)` split every bundled theme's CSS uses to
  target iOS vs. macOS (see `nnwtheme-format.md`), and forces
  `prefers-color-scheme` to the requested `mode` regardless of the browser's
  actual system setting, by rewriting all four at-rules to `@media all` /
  `@media not all`. This is what lets each card's own Light/Dark toggle
  (`segHTML`/`setMode`) force a specific mode inside an iframe that has no
  other way to fake `prefers-color-scheme`.
- **`frameDoc(t, mode, scroll)`** builds the full `srcdoc` HTML for a
  preview iframe: theme imports in their own leading `<style>` tag (kept
  separate from the theme CSS itself so they stay valid regardless of where
  the source `.css` file placed them -- see `build.py`'s `split_imports`),
  then a fallback `body{background;color}` block matching
  `ArticleThemeColorExtractor`'s own black-on-white/white-on-black fallback
  (a theme that declares no body background, like Broadsheet, would
  otherwise render as a transparent iframe showing the card's `--plate`
  color instead of what the app actually falls back to), then
  `themeCSS(t, mode)` itself, then the templated HTML body, then
  `frameScript` as an inline `<script>`.
- **`frameScript`** (referenced by name inside `frameDoc`'s template
  literal, defined nearby) reimplements the reader's runtime DOM
  post-processing -- drop-cap `versal()` promotion and chapter-divider
  insertion -- that in the real app happens via `WebViewController`'s JS
  injection. `SAMPLE`/`SUB` fill in the same template placeholders
  (`[[title]]`, `[[byline]]`, etc.) the app substitutes at render time, with
  shorter placeholder text so more of a theme's structure fits inside a
  390×600 thumbnail than the real preview
  (`iOS/Settings/ArticleThemePreviewWebView.swift`) needs to show.

If `WebViewController`'s real substitution logic, `core.css`'s AO3-preface
structure, or the `@supports`/`prefers-color-scheme` rewriting the app
relies on ever changes, update this trio in the same change, or the
gallery's previews silently stop matching what the app actually renders.

### Install link

Each card's Install button and the "Copy link" button both build
`nectar://theme/add?url=<zip URL>` (`deepLink()` in the template's script,
`D.scheme` from `build.py`'s always-`"nectar"` value). See
`nnwtheme-format.md`'s "Add Themes Directly to Nectar with URL Scheme"
section for the scheme itself; it is `nectar://`, not NetNewsWire's original
`netnewswire://.`

### Page styling notes

A few specifics worth flagging because they're easy to miss on a skim and
have changed since the page was first built:

- **No hand-drawn "ink" wobble.** The `#ink`/`#ink-text` SVG filters
  (`feTurbulence`/`feDisplacementMap`) that used to distort the band, the
  install buttons, the preview-frame ring, and the `<h1>` title have been
  removed entirely, filter defs included -- the page currently ships with
  wobble at 0. If a future design pass wants the hand-inked look back at a
  lower intensity, reintroduce the filters rather than assuming they're
  still defined somewhere.
- **`--r` corner radius.** A single `:root` variable (`--r`, currently
  `0.5px`) drives corner rounding on straight-line chrome: preview frames
  (`.pvw::before`, `.pv`), the Install button (`.btn`), each card's
  Light/Dark preview toggle (`.seg`), the detail dialog and its iframe
  (`dialog`, `dialog iframe`), the drop cap (`.lede::first-letter`), and the
  diamond ornament under the title (`.fleuron i`). Change corner softness by
  editing `--r` in one place rather than each selector. The outer preview
  ring is a pseudo-element (`.pvw::before`) rather than the frame's own
  `outline`, specifically because a CSS `outline`'s radius grows with its
  offset -- keeping it a separately-radiused pseudo-element is what keeps
  that ring subtle instead of ballooning outward.
- **No card description.** Cards used to show `CreatorName` (aliased as
  `by` in the theme data) as a byline paragraph under the theme name, with a
  hover tooltip and a click/keyboard handler that opened the detail dialog.
  That paragraph, its CSS, and its handlers are gone -- `CreatorName` now
  surfaces only inside the detail dialog's text. Clicking the preview
  thumbnail is the only way to open the dialog now; there is no separate
  "Details" affordance next to Zip/Copy link.
- **Banner background is transparent.** `.band` (the frieze banner behind
  the title) no longer paints `var(--plate)` behind itself -- it's
  `transparent`, so the page's own paper-grain background (the `body`
  rule's noise-filter SVG data URI) shows through the banner instead of
  sitting behind a flat rectangle. Card preview mounts (`.pvw`, `.pv`) are
  unrelated to this and still use `--plate` as their background.
- **Site-wide Light/Dark button.** The sticky filter bar has a button (next
  to the tone filter chips, `#pagemode` in the template) that sets
  `data-theme="light"|"dark"` on `<html>` and remembers the choice in
  `localStorage` (`nectar-gallery-page-mode`). With no saved choice it
  follows `prefers-color-scheme` as before. This only repaints the gallery
  page's own chrome via the `:root[data-theme=...]` variable blocks; it is
  independent of, and does not change, each card's own per-preview
  Light/Dark toggle or the "Light mode"/"Dark mode" tone filter chips, which
  are controls over the theme previews rather than the page itself.

## `gallery.yml`

`.github/workflows/gallery.yml` runs `gallery/build.py` on every push to
`main` that touches `gallery/**`, `gallery-themes/**`, `Themes/**`, or
`Shared/Article Rendering/core.css`, and publishes the result to the
`gh-pages` branch under `/themes/` (alongside the AltStore `source.json`
that `release.yml` publishes to the same branch under a different path --
the two workflows touch disjoint paths and are deliberately not in the same
concurrency group, so one queuing doesn't cancel the other). It force-syncs
`pages/themes` from the fresh build output on every run rather than diffing,
so a theme removed from `gallery-themes/` also disappears from the published
site on the next push.
