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
   fails the build (`sys.exit(1)`), a missing overflow guard only warns. A leftover full-screen clearance rule (`Full-screen clearance` comment or
   `html{padding-top:Npx}`) also only warns; see `theme-fullscreen-audit.md`.
2. Writes `dist/zips/<BundleStem>.nnwtheme.zip` (`<BundleStem>` is the bundle
   folder name without `.nnwtheme`, e.g. `Ink and Mist.nnwtheme.zip`). The zip
   contains exactly one top-level `<BundleStem>.nnwtheme` folder holding the
   bundle's files; `.`-prefixed files are left out. The app derives the theme
   name from that folder on import, and the shape matches the upstream
   marketplace's release-asset rules. `slugify` still produces each theme's
   `slug` field in the data blob, but the zip is named from the folder stem, not the slug. Because stems
   contain spaces, `&` and non-ASCII characters, the `zip` field in the data
   blob is the percent-encoded file name (`zip_url_path`); `index.template.html`
   appends it to `base` unchanged, so both the Zip link and the install deep link
   (which wraps the whole URL in `encodeURIComponent`) stay valid.
3. Writes `dist/index.html` from `index.template.html`, with every theme's
   CSS, imports, and `template.html` inlined into one `__DATA__` JSON blob
   and `Shared/Article Rendering/core.css` inlined as `__CORE__` -- the page
   needs no fetches for its own data and works opened straight from disk.

### Bundle checks

Every bundle under `--src` is checked, including the ones in `BUNDLED` that are
not published. Each failure prints `ERROR <bundle>: <reason>` and fails the
build (exit 1) after all bundles have been reported:

- **Macro inside an HTML comment** in `template.html`
  (`\[\[[A-Za-z0-9_-]+\]\]` within `<!--...-->`). Macros are substituted
  inside comments too, and the substituted text can end the comment early.
  Same rule as the upstream validator.
- **Non-leading `@import`** in `stylesheet.css`. `build.py` ports
  `CSSImportExtractor`'s notion of a leading block (whitespace, comments and
  terminated `@import` rules only) and is quote-aware, because Google Fonts
  URLs contain `;` inside quotes. An `@import` anywhere after other content
  (matched case-insensitively, ignoring comments and strings) is an error,
  because the app lifts only the leading block and an `@import` left in the
  body is ignored once `core.css` is prepended.
- **Unterminated `@import`**: no closing `;`, or an unquoted `{` or `}` before
  one (a missing `;` would otherwise let the statement swallow the next rule).
- **Duplicate `ThemeIdentifier`** across all bundles in `--src`, bundled and
  published together.
- **`Version`** that is not an integer or is less than 1 (booleans and
  numeric strings are rejected).

The existing required-keys, `#bodyContainer` and overflow-guard checks are
unchanged. The checks are covered by `gallery/test_build.py`
(`python3 -m unittest discover -s gallery`), which also builds the shipped
corpus and asserts every zip has a single top-level `<BundleStem>.nnwtheme`.

### Discoverability

A zip of this shape, attached as a release asset to a GitHub repository that
carries the `netnewswire-theme` topic, is discoverable by the upstream
NetNewsWire theme marketplace. The same URL installs into Nectar with
`nectar://theme/add?url=<zip URL>`; the app validates the archive before
extracting it (`theme-system.md`, "Archive rules"), so a malformed zip fails
with an error instead of writing files.

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

Bundle counts for `gallery-themes/` and `Themes/` come from
`buildscripts/theme-generation/theme_inventory.py`; see `theme-system.md` for the
itemized lists. This document does not state counts.

### Family metadata

`load_theme` copies `Family` and `FamilyVariant` from `Info.plist` into each
theme's data blob (`family`, `variant`). `index.template.html` does not use
either field, so the page still shows every bundle as its own card with no
grouping.

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

The app only follows `http` and `https` zip URLs, requires a 2xx response,
caps the download at 10,000,000 bytes, and validates the archive layout before
extracting anything; the rules are in `theme-system.md`'s "Archive rules".
A gallery zip that breaks them cannot be installed through this link.

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
  surfaces only inside the detail dialog's text. Under the convention in
  `nnwtheme-format.md`, a theme's description belongs in `License.md`, not
  `CreatorName`; `gallery/build.py` does not read `License.md` yet (confirmed),
  so the dialog shows only `CreatorName`, which is now just the creator name
  (`kyrielie`) for every bundle except the NetNewsWire-origin ones. Clicking the preview
  thumbnail is the only way to open the dialog now; there is no separate
  "Details" affordance next to Zip/Copy link.
- **Banner background is transparent.** `.band` (the frieze banner behind
  the title) does not paint `var(--plate)` behind itself -- it's
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
- **Starred themes.** Each card has a star toggle at the right of its title, and the
  detail dialog has one beside the theme name. Stars are a JSON array of theme slugs in
  `localStorage` under `nectar-gallery-starred`, so they are per browser and per origin
  and never leave the device. The sticky bar's "Starred (n)" button shows only starred
  themes and combines with the tone chips (a starred Dark theme must pass both). The
  count in the button covers only slugs that still exist; a slug whose theme was removed
  or renamed stays in storage but matches nothing, because slugs come from the bundle
  name (see `slugify` in `build.py`), so renaming a bundle drops its star. Unreadable or
  malformed stored data is treated as no stars, a blocked `localStorage` leaves stars
  working for the visit only, and a `storage` listener keeps open tabs in step.
  `applyVisibility()` handles show/hide and the count; `applyFilter()` adds the tone
  chips' preview-mode switch on top, so starring never reloads a preview.

### Release identity check

```
python3 gallery/build.py --check-release-identity <base-ref> [--src DIR ...]
```

Builds nothing. Compares the working tree with the merge-base of `<base-ref>` and
`HEAD` (so changes that landed on the base branch after a branch was cut are not
blamed on the branch) and exits 1 with `ERROR <bundle>: <reason>` lines when:

- a bundle's `ThemeIdentifier` differs from its base copy;
- a bundle's name changed: a bundle with no base copy under its name but whose
  `ThemeIdentifier` matches a base bundle under another name is a rename. The
  name is the bundle folder name, compared after NFC normalization and matched
  across `--src` directories, so moving a bundle between `Themes/` and
  `gallery-themes/`, or re-encoding a folder name to NFC, is not a rename.
  `Info.plist`'s `Name` is not compared (upstream requires it to equal the
  folder name; the folder name is the identity the app looks themes up by);
- `stylesheet.css` or `template.html` differ from the base copy and `Version` is
  not strictly greater (or either `Version` is not an integer).

New and deleted bundles are not checked, and a change confined to `Info.plist`
metadata or `License.md` needs no bump. A missing or unresolvable base ref is
reported as an error rather than skipped. If there is no merge-base (a shallow
clone), the ref itself is the base and a note is printed.

## `ci.yml`: `theme-gallery` job

Runs as part of the release gate (see `release-pipeline.md`, "Test gate"), or by
hand via `workflow_dispatch`; `ci.yml` has no pull request or push trigger:
`python3 -m unittest discover -s gallery` and a build into the runner's temp
directory (so the bundle checks above gate a release, not only the publish run on
`main`).

`--check-release-identity` no longer runs in CI. It compares against a base branch
and the job used to run it only on pull requests. Run it by hand when a bundle's
`stylesheet.css` or `template.html` changes, from a clone with the base branch
fetched: `python3 gallery/build.py --check-release-identity origin/main`.

## Upstream-compatibility gate

`gallery/upstream-compatible.txt` lists, one bundle name per line (blank lines and
`#` comments are ignored), the bundles that are meant to stay portable to upstream
NetNewsWire. It is a checked-in list, not an `Info.plist` key. Currently:
Biblioteca, NewsFax, Promenade, Sepia, Tiqoe Dark, Verdana Revival, the six that
pass the upstream validator; the `upstream-compat` CI job is the source of truth. A bundle belongs on it only while it
also keeps the upstream rules Nectar does not otherwise enforce: no `@import`
(`@import` stays a supported Nectar capability, so themes that use it are
Nectar-only), `Name` equal to the bundle name, no bundle-local `url()`.

`gallery/upstream_compat.py` runs `nnw-theme check --no-open` on every listed
bundle. `nnw-theme` expects exactly one `*.nnwtheme` at the root of the directory
it runs in and writes `build/` there, so the script copies each bundle into its own
temporary directory and runs the check there; one failing bundle does not stop the
rest, and the exit status is 1 if any failed, a name is not found in `Themes/` or
`gallery-themes/`, or the list is empty or has a duplicate. `--report-dir` keeps each
bundle's `build/check-report.txt`; `--dry-run` only validates the list.

The `upstream-compat` job in `.github/workflows/ci.yml` runs it as part of the
release gate (or on a manual `ci.yml` run). It pins Node 24 (nnw-theme's minimum), pins
`nnw-theme` to an exact version (`NNW_THEME_VERSION`, currently 2.0.2, kept in step
with `DEFAULT_VERSION` in `upstream_compat.py` by a test), caches `~/.npm` and
`~/.cache/ms-playwright`, installs WebKit with `nnw-theme setup --with-deps`, and
uploads the reports. It runs on `ubuntu-26.04`, the runner label nnw-theme's own
reusable workflow uses for the same commands. To adopt a newer `nnw-theme`, change
both version strings in one commit.

Three bundles are deliberately not listed: Craft Table, Illuminated Codex and
Nectar. The upstream validator reports their `url(#...)` references to inline SVG
filters as bundle-local CSS resources. That is a false positive for inline SVG
filter references and the CSS is left as it is; each also begins with an `@import`,
so they are Nectar-only regardless.

## Upstream pin test

`gallery/test_upstream_pins.py` pins the eight NetNewsWire-origin bundles in `gallery-themes/`
(Appanoose, Biblioteca, Hyperlegible, NewsFax, Promenade, Sepia, Tiqoe Dark, Verdana
Revival) to upstream, file by file. `UPSTREAM` holds the SHA-256 of all 25 files at one
upstream commit (`UPSTREAM_COMMIT`, path `Resources/Themes/` in
`Ranchero-Software/NetNewsWire`). Every file must equal its upstream hash unless it is
listed in `INTENTIONAL_DELTAS`, where it must equal the recorded Nectar hash instead.
The suite fails on an unlisted edit, on a listed file edited without re-pinning, on a
listed file that has become identical to upstream, and on a file added to or missing
from a bundle. It runs with the rest of `python3 -m unittest discover -s gallery`, needs
no network and no Xcode.

Each delta carries a reason. Permanent ones: Appanoose's `ThemeIdentifier` (upstream's
`starter` is rejected by `test_no_placeholder_metadata`) and its removed
`[[time_short]]` line (the renderer strips the time only from `datetime_*`), and
Biblioteca's appended AO3 CSS and its `#bodyContainer`/`articleBody` container (the
color probe loads no `main.js`, so a runtime fix would leave the probe without
`.articleBody`), and the removal of the dead avatar markup (the `nnwImageIcon` cell or
`[[avatar_src]]` image, and in Sepia and Tiqoe Dark the two CSS rules that only styled it)
in all seven upstream-origin bundles that had it, with the `Version` bump that
`--check-release-identity` requires on each (`main.js` strips the image unless it carries
`data-nnw-keep`). Entries marked `PENDING REVERT` are scanner-driven or redundant edits
waiting on the probe check described in `theme-testing.md`.

After an intentional bundle change, run `python3 gallery/test_upstream_pins.py --print`
and paste the output over `INTENTIONAL_DELTAS`. Moving the upstream pin means
regenerating `UPSTREAM` from the new commit by hand; the test does not fetch anything.
Editing any of these bundles' CSS or template also requires regenerating
`ThemeColorTable.json` (see `theme-testing.md`).

## `gallery.yml`

`.github/workflows/gallery.yml` runs `gallery/build.py` (without waiting for
`ci.yml`, which no longer runs on pushes) on every push to
`main` that touches `gallery/**`, `gallery-themes/**`, `Themes/**`, or
`Shared/Article Rendering/core.css`, and publishes the result to the
`gh-pages` branch under `/themes/` (alongside the AltStore `source.json`
that `release.yml` publishes to the same branch under a different path --
the two workflows touch disjoint paths and are deliberately not in the same
concurrency group, so one queuing doesn't cancel the other). It force-syncs
`pages/themes` from the fresh build output on every run rather than diffing,
so a theme removed from `gallery-themes/` also disappears from the published
site on the next push.
