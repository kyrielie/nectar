# Article Theme System

Nectar renders every article/fic chapter through a themeable HTML template.
A theme is a `.nnwtheme` bundle (a directory, not a flat file) containing a
template, a stylesheet, and metadata. The system layers four independent
pieces on top of that bundle format: theme discovery/selection, third-party
theme import, a small CSS pre-processor, and a user-facing override layer
that sits on top of whichever theme is active.

## The `.nnwtheme` bundle format

Each bundle under `Themes/<Name>.nnwtheme/` (shipped; `gallery-themes/` bundles are gallery-only and never in the app) or in the user's
Application Support Themes folder (imported) contains:

- `template.html` — the article HTML template, using `[[token]]` placeholders
  (see `Shared/Article Rendering/template.html` for the full token list:
  `title`, `preferred_link`, `byline`, `avatar_src`, `dateline_style`,
  `datetime_long/medium/short`, `external_link*`, `feed_link*`, `body`, and
  a legacy always-literal `text_size_class` token that's inherited from
  upstream NetNewsWire and never substituted).
- `stylesheet.css` — the theme's CSS. May start with one or more `@import`
  statements (e.g. a Google Fonts `@import url(...)`), which are handled
  specially (see below).
- `Info.plist` — theme metadata, decoded into `ArticleThemePlist`. Every key is
  optional at import (see "Two tiers"); the table is what authors should supply:

  | Key | Type | Notes |
  |---|---|---|
  | `Name` | String | |
  | `ThemeIdentifier` | String | reverse-DNS-style identifier |
  | `CreatorHomePage` | String | |
  | `CreatorName` | String | the creator's name only; description, attribution and license text go in `License.md` (see `nnwtheme-format.md`) |
  | `Version` | Int | |
  | `Family` | String? | optional; groups sibling bundles that are the same design with different palettes (e.g. "Rosé Pine" has Main/Moon/Dawn variants) for gallery display. Omitted for the large majority of themes. |
  | `FamilyVariant` | String? | this bundle's label within `Family`; meaningless without `Family`. |

- An optional `License.md`: the theme's description, its attribution, and its
  license status (e.g. NewsFax, Ember). Nothing in Swift reads it; format and
  expected contents are in `nnwtheme-format.md`.

Nectar ships these themes in `Themes/`: the eight NetNewsWire-origin themes
(Appanoose, Biblioteca, Hyperlegible, NewsFax, Promenade, Sepia, Tiqoe Dark,
Verdana Revival) plus six Nectar customs (Black & White, Duskbloom, Ember,
Powder Pink, Tumblr Blue, Vintage Letter Green). Only `Themes/` is copied into
the app bundle (`project.yml`). Every other authored theme lives in
`gallery-themes/`, is not in the app, and is published only on the theme
gallery (`gallery/build.py`), from which a person installs them via the
`nectar://theme/add` URL scheme. See `nnwtheme-format.md` for the
directory rules and `docs/theme-gallery.md` for the gallery page itself.
Only a minority of themes are **generated** now. The single generator,
`buildscripts/theme-generation/generate_ported_themes.py`, fills a shared
structural CSS/HTML template with per-theme palette and font data. Its theme
table covers 13 entries (the Rosé Pine Moon/Dawn ports, the ZerafinaCSS "neos"
recolors Black & White, Charcoal Rose, Dusky Purple, Midnight Teal, Powder Pink
and Tumblr Blue, Constellations, Dracula, Moonlit Wisteria, Pastel Whimsy and
Poudre et Plume), and only three of those are in `SHIPPED` (so written to
`Themes/`); the rest go to `gallery-themes/`. Everything it emits uses the
NetNewsWire header-table template shape ("shape A" in `nnwtheme-format.md`).
Beacon, Beetlejuice, Mystery, Perseus, Pinerose, Rosé Pine, and Twilight use that
same shape but are not in the generator's table; where they came from was not
determined.

The "shape B" themes (compact running head, `nnwtheme-format.md`) were converted from CSS
mockups by a separate script (`convert_mockups.py`, "Route A" in `theme-mockups.md`). That
script is not in this repo (it lives in the v4 theme set's `tools/` directory), so a
structural fix has to be applied to each bundle, not regenerated. The mockup tooling
(`buildscripts/theme-mockups/`) is not in this checkout either; `theme-mockups.md`
describes it. `buildscripts/theme-generation/theme_inventory.py` prints the current bundle
and shape counts, which this document no longer states.

Horizontal overflow (an oversized fic image forcing the whole article page
to scroll sideways) is guarded at two layers: every theme is expected to
carry the generator's `img, figure, video, div, object { max-width: 100% }`
rule (or an equivalent) so oversized content actually fits its column, and
`core.css` additionally sets `html, body { overflow-x: hidden }` as a
structural backstop that applies regardless of what any individual theme
does. The six themes that predate the generator (Aldine, Deco Line,
Kelmscott, Kennerley, Marigold Press, Rosarivo) originally shipped without
the media-sizing rule; it's since been added directly to each one.
`Tests/NetNewsWire-iOSTests/ArticleThemeOverflowSafetyTests.swift` guards
both layers so a future hand-written theme that forgets the rule fails the
build instead of shipping a silent regression.

## `ArticleTheme`

`Modules/ArticleTheming`'s `ArticleTheme.swift` is the runtime value type
(`Equatable`, `Sendable`, a plain `struct`) representing a loaded theme:

```swift
struct ArticleTheme {
    let url: URL?          // nil for the built-in default theme
    let template: String?
    let importCSS: String? // extracted @import statements, if any
    let css: String?       // core.css + the theme's own stylesheet minus @imports
    let isAppTheme: Bool   // bundled with the app vs. user-imported
    var name: String { ... }         // derived from filename, sans .nnwtheme suffix
    var creatorHomePage, creatorName, version: String
    var family, familyVariant: String?
}
```

Two initializers:

- `init()` — the built-in default theme. No `Info.plist`; builds a synthetic
  `ArticleThemePlist` in code, loads `core.css` and `stylesheet.css` and
  `template.html` from the app bundle directly (not from a `Themes/` bundle).
- `init(url:isAppTheme:) throws` — loads a real `.nnwtheme` bundle: reads
  `stylesheet.css` (if present) and `template.html` from the bundle,
  decodes `Info.plist` into `ArticleThemePlist` via `PropertyListDecoder`,
  and always prepends the app's own `core.css` to whatever the theme
  supplies. `core.css` is not overridable per-theme — every theme rides on
  the same structural base.

Every theme's CSS is composed as `core.css + "\n" + <theme's own CSS with
@imports removed>`. The `@import` statements are extracted separately (see
`CSSImportExtractor` below) rather than left inline, because they need to be
emitted as a separate `<style>` block ahead of the main stylesheet in the
rendered page (see `ArticleRenderer.importStyle`).

`url.startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`
bracket the load, since imported theme URLs can be security-scoped (e.g. from
a document picker).

## `ArticleThemesManager`

`Modules/ArticleTheming`'s `ArticleThemesManager.swift` is the singleton
(`ArticleThemesManager.shared`) that owns theme discovery, selection, import,
and deletion. It is an `NSFilePresenter` on the Themes folder
(`Platform.dataSubfolder(..., "Themes")`, under Application Support), so
external changes to that folder (e.g. a Finder drag) trigger
`presentedSubitemDidChange(at:)`, which re-scans and prewarms the changed
theme's measured colors. Making a resolved theme current goes through a gate
that can wait for a color measurement first; see the "Theme gate" section of
`article-color-pipeline.md`.

State is kept in an `OSAllocatedUnfairLock`-protected `State` struct
(`currentTheme`, `themeNames`) rather than plain stored properties, since the
manager is touched from multiple threads/actors. Mutating `currentTheme` or
`themeNames` posts `.CurrentArticleThemeDidChangeNotification` /
`.ArticleThemeNamesDidChangeNotification` on the main thread.

Theme discovery (`updateThemeNames()`) unions two sources:
1. Bundled `.nnwtheme` files under the app bundle's `Themes/` resource
   directory.
2. Installed (user-imported) `.nnwtheme` directories under the Themes data
   folder.

Both are reduced to bare theme names (bundle filename minus the `.nnwtheme`
suffix) and sorted case-insensitively. `currentThemeName` is persisted via
`AppDefaults`; if the persisted name no longer resolves to an existing theme
(e.g. it was deleted), selection silently falls back to `AppDefaults.defaultThemeName`.

`articleThemeWithThemeName(_:)` resolves a theme by name: checks the app
bundle first, then the installed-themes folder, and returns `nil` (silently,
without posting any failure notification) if neither has it or the bundle
fails to parse — this is deliberate, since this lookup can be called
repeatedly during SwiftUI re-renders (e.g. by the theme picker's row labels)
and a failure notification per broken theme per render would spam the user.
Callers doing a user-initiated import report their own failures instead.

`importTheme(filename:)` first runs `ArticleThemeBundleValidator.validate(directory:)`
on the source (safety checks only, see "Two tiers" below), builds a clean copy
containing just the kept files in a temporary folder, then replaces the
installed bundle of the same name with it. Both steps run before the existing
copy is removed, so a rejected bundle, or a copy that fails halfway, never
replaces or deletes an installed theme. `ArticleThemeImporter.importTheme` also
validates before it reads the bundle for the install alert, and offers "Show
Website" only when `CreatorHomePage` is an http or https address.
`deleteTheme(themeName:)` removes an installed bundle by resolved path.

## Third-party theme download and import

The `nectar://theme/add?url=` handler in `iOS/SceneDelegate.swift` checks that
the URL scheme is `http` or `https` (`ArticleThemeDownloader.validateDownloadURL`),
starts a `URLSessionDownloadTask`, and requires an `HTTPURLResponse` with a 2xx
status (`validateDownloadResponse`). Every failure, including a transport
error, posts `.didFailToImportThemeWithError`; nothing is dropped silently.

`Modules/ArticleTheming`'s `ArticleThemeDownloader.swift` then handles the
downloaded `.zip`-wrapped theme:

1. `moveDownloadedTheme(from:)` rejects a file over 10,000,000 bytes
   (`ArticleThemeDownloaderError.tooLarge`), then relocates it into
   `Application Support/NetNewsWire/Downloads`, renaming `.tmp` → `.zip`. This
   must stay synchronous inside the download completion handler.
2. `finishImportingTheme(at:)` calls `unzipFile(at:)`, which extracts into a
   fresh `Downloads/<UUID>` directory through `unzipTheme(at:to:)` and always
   deletes the zip afterwards.
3. `unzipTheme(at:to:)` runs `ArticleThemeArchiveValidator.validate(zipURL:)`
   first. That reads only the ZIP central directory, so no byte is extracted
   from an archive that breaks a safety rule. It also picks the bundle folder
   (see below). After extraction it runs `ArticleThemeBundleValidator.validate(directory:)`
   (an `lstat`-based second safety check) on that folder, rebuilds it with
   `copyInstallableFiles(from:to:)` into a uniquely named staging folder, deletes
   everything else in the extraction directory, and moves the clean bundle
   into place under a name ending in exactly `.nnwtheme`. On any failure the
   destination directory is deleted.
4. Posts `.didEndDownloadingTheme` with the `.nnwtheme` URL in
   `userInfo["url"]`.

### Two tiers: safety rejects, layout never does

Themes are community work and should load even when imperfect, so the import
path separates two kinds of rule. This follows upstream NetNewsWire, which does
no layout validation at all: it extracts, then takes the first `.nnwtheme` it
finds anywhere. The stricter layout rules Nectar used to enforce (exactly one
top-level folder, only the three theme files plus `LICENSE*`/`NOTICE*`, no
subfolders, all three files present) came from the `nnw-theme` authoring
linter. That linter is a publishing gate for authors; it is still what
`gallery/upstream_compat.py` runs for bundles Nectar ships as upstream-portable,
and `gallery/build.py` still requires the five `Info.plist` keys for gallery
entries. Neither applies to a reader importing a theme.

**Safety rules (reject).** Limits: 10,000,000 bytes compressed, 50 MiB declared
expanded (sum of every entry, junk included, overflow-safe). Rejected:
symlink or other non-regular Unix entries, absolute paths (including drive
letters), any `.` or `..` component, empty components, control characters
(including NUL), names that are not UTF-8, duplicate paths after NFC and case
folding, ZIP64 (EOCD sentinels, locator, extra field 0x0001), multi-part
archives, encrypted entries, compression methods other than stored or deflate,
and local headers that disagree with the central directory. On disk, a link or
special file at the top level of the bundle, or kept files over the size cap.
`\` is normalized to `/` before every check, because `Zip` does the same when it
extracts. Checks are component-wise, never a string-prefix test.

**Layout rules (never reject).**

- Bundle choice: any path component ending in `.nnwtheme` (any case, non-empty
  stem) that is a folder is a candidate, at any depth. Preference order: a
  folder that directly holds one of the three theme files, then the
  shallowest, then name (NFC, case folded), so the result does not depend on
  archive order. No candidate is the one layout failure
  (`ArticleThemeDownloaderError.noThemeFile`, the same error upstream raises).
- Kept: `Info.plist`, `template.html`, `stylesheet.css` (matched case-insensitively and
  stored under those exact names) and `LICENSE*` / `NOTICE*`. Everything else
  (screenshots, READMEs, fonts, scripts, subfolders, other bundles,
  `__MACOSX`, `.DS_Store`, `._*`) is dropped, never copied. Nothing reads
  it: the renderer only takes the three theme files, and upstream's
  validator documents that bundle-local resource references do not work.
- Missing files are fine. A missing `template.html` or `stylesheet.css` makes
  the theme use the app default for that part (`ArticleTheme.template` /
  `.css` are nil and `ArticleRenderer` falls back).
- `Info.plist` is decoded leniently (`ArticleThemePlist.init(from:)`): every
  key is optional, wrong types read as empty, `Version` also accepts a numeric
  string or real number. A missing, unreadable or non-dictionary plist gives
  no metadata; the name comes from the folder and the creator reads "Unknown".
  Every plist upstream accepts decodes to the same values as before. The
  theme's identity is its folder name, not `ThemeIdentifier`.
- Not checked at import, on purpose: `Name` matching the folder, placeholder
  metadata, `CSS @import`, remote or bundle-local `url()`, macros in comments.
  These stay in the authoring checklist (`creating-a-theme.md`).

Dependency note: `Zip` is pinned to `bca30f6d6c7d37cbc4aa8f6b0002e281dcc36195`
in `Modules/ArticleTheming/Package.swift`, `Modules/BackupRestore/Package.swift`
and `project.yml`. All three must name the same revision or SwiftPM cannot
resolve the graph. That revision adds a containment check to extraction, but it
is a string-prefix test, so the validator above is the real guard. The repo has
no committed `Package.resolved` that records `Zip`.

`cleanUp()` removes all downloaded theme folders from the Downloads
directory (called opportunistically, not automatically after each import).

Notification names for the whole download → import flow live in
`ArticleTheme+Notifications.swift`: `.didBeginDownloadingTheme`,
`.didEndDownloadingTheme`, `.didFailToImportThemeWithError`.

## `CSSImportExtractor`

A small hand-rolled scanner (`Modules/ArticleTheming`'s `CSSImportExtractor.swift`),
not a regex, that walks a CSS string character-by-character from the start
and peels off any leading run of whitespace, comments (`/* ... */`), and
`@import` statements, stopping at the first token that's none of those three.
It correctly treats semicolons inside quoted strings (tracking a `quote`
character and escaping via a trailing backslash check) as not terminating
the `@import` statement. Returns `CSSImportExtraction { importCSS,
remainingCSS }` — an empty `importCSS` if no leading imports were found.

This exists because `@import` rules are only valid at the very top of a
stylesheet, and browsers/WebKit will silently ignore any that appear after
non-import content — so imports have to be lifted out and placed in their
own `<style>` block ahead of everything else once `core.css` gets prepended
to a theme's stylesheet (which would otherwise push a theme's own leading
`@import` past the start of the combined string, invalidating it).

## Color measurement: probe, store, composer

Native colors (webview background, notch cover, Blend toolbars, page counter,
override-picker defaults) are measured, not scanned. `ArticlePageComposer` builds
the page the reader would build (real `page.html`, same six keys) from a theme
and `ArticleThemeSampleContent`; `ArticleThemeColorProbe` renders it in a hidden
`WKWebView`, light then dark, and reads back computed colors;
`ArticleThemeColorStore` caches the result (memory, `ThemeColors.json`, the
bundled `ThemeColorTable.json`) and serves it through `colors(for:)`;
`ArticleThemesManager.updateCurrentTheme()` holds back an unmeasured theme until
it has colors. The Settings preview uses the same composer and sample. All of
this, including the cache key, the gate and the cold-start exception, is
described in `article-color-pipeline.md`; testing and table regeneration are in
`theme-testing.md`.

## `ArticleThemeColorExtractor` (scanner fallback)

`Modules/ArticleTheming`'s `ArticleThemeColorExtractor.swift` is the legacy, small,
deliberately non-general CSS color scanner (regex-based, not a real CSS
parser) that reads a theme's *effective* text/background/link colors — both
light- and dark-mode — directly out of its compiled `css` string. This is
used so the app's own chrome (webview background, the iOS notch/status-bar
fill) and the theme-override UI can default to what a given theme actually
looks like, rather than a generic system color. Callers do not use it
directly: they go through `ArticleThemeColorStore.colors(for:)`, and this scanner
is only the store's fallback when a theme has no measurement (see
`article-color-pipeline.md`). Theme authors do not need to write CSS the scanner
can read.

What it understands:
- Literal `#hex`, `rgb()`/`rgba()`, and a modest hand-maintained table of
  named CSS colors actually seen in shipped themes (not the full CSS
  keyword list).
- `var(--custom-property)`, resolved against that theme's own `:root`-style
  declarations — light and dark variable scopes are tracked and resolved
  separately, so a dark-mode redefinition of a variable can't leak into the
  light-mode result.
- A single `@media (prefers-color-scheme: dark)` block. `colors(css:)` still
  reports its presence in the composed CSS as `hasDarkModeVariant`, but that is
  always true once `core.css` is prepended; callers go through
  `ArticleThemeColorStore.colors(for:)`, which recomputes it from
  `ArticleTheme.ownStylesheet` via `declaresDarkBlock(_:)` (presence only, not
  whether every color differs). See `article-color-pipeline.md`.

What it deliberately ignores: nested `@supports` conditional blocks (stripped
out entirely via brace-depth matching in `stripBraceBlocks` before any
scanning happens, since at least one shipped theme uses `@supports` to carry
a CSS-4 system-color override this scanner can't resolve), CSS-4 system
color keywords (`Canvas`, `CanvasText`, etc. — fall through as "not found"),
and selector specificity beyond exact-string selector matching (`body`,
`.articleBody`, `a`, `.articleBody a`).

Falls back independently per-channel to black-on-white (light) /
white-on-black (dark) when a color can't be resolved — never fails outright.

## `ArticleThemeOverrides`

`Modules/ArticleTheming`'s `ArticleThemeOverrides.swift` is a `Codable`,
`Sendable` struct of entirely optional fields — font family (split into
`serifFontFamilyName` for article prose and `sansFontFamilyName` for UI
chrome text), font size, line height, paragraph spacing/indent, horizontal/
top margins, justify/hyphenate toggles, and text/background/link colors
(each with an independent `*DarkHex` variant, falling back to the light
value when unset). This is a user-configurable layer applied *on top of*
whichever theme (bundled or imported) is currently active, persisted via
`AppDefaults.shared.articleThemeOverrides`.

`cssOverrideBlock` compiles the non-nil fields into a CSS string, appended
*after* the active theme's own stylesheet so it can win regardless of the
theme's own specificity/declaration order — every declaration is
`!important`. Notable details:

- Font/size/color rules target both `body` and `.articleBody` (the actual
  content div every theme renders text into), because a directly-declared
  property on `.articleBody` (which every bundled theme sets `line-height`
  on) always wins over an inherited `body` rule regardless of `!important` —
  targeting only `body` would silently fail to override `line-height`
  specifically while still working for font/color.
- Chrome-text font overrides use a **hand-maintained allowlist** of
  selectors (`chromeSelectors`) rather than a generic mechanism, because
  chrome class names aren't standardized across bundled themes (the default
  theme uses `.feedlink`/`.articleDateline`/etc.; Vintage Letter Green uses
  its own `.letter-*` classes). This is a known-fragile part of the design;
  a shared `--font-main`/`--font-body` CSS variable convention across all
  themes would remove the need for it, but doesn't exist yet.
- `justifyText`/`hyphenate` explicit-`false` states are real "off" states
  (emitting `text-align: left` / `hyphens: none`), not just "don't add" —
  needed because some themes justify or hyphenate natively and an override
  has to be able to turn that back off.
- Dark-mode colors are emitted inside a `@media (prefers-color-scheme: dark)`
  block layered after the light rules, so they react live to system
  appearance changes with no Swift-side trait-collection plumbing.
- `marginTop` targets `#bodyContainer`'s padding-top, chosen because
  `.articleContent`/`.barContent` (which an earlier draft of this feature
  assumed existed) don't actually exist anywhere in
  `Shared/Article Rendering/template.html`. `marginHorizontal` depends on the
  theme: if the theme CSS declares `--gx` (matched by `--gx\s*:`), the override
  sets `--gx` in `:root`; otherwise it pads `body` as before.
- **Signature.** `cssOverrideBlock(themeCSS:)` takes the active theme's CSS
  (`ArticleRenderer.styleString()` passes the theme CSS or the default
  stylesheet; `ArticleThemeListView.previewCSS` passes the preview's
  `themeCSS`). The `cssOverrideBlock` property is `cssOverrideBlock(themeCSS: nil)`.
- **Variables.** Before the legacy rules, a `:root` block sets
  `--nnw-prose-size` (font size, not `!important`), `--nnw-bg`, `--nnw-ink`,
  `--nnw-link`, `--nnw-font-chrome` (all `!important`) and, for `--gx` themes,
  `--gx`. The dark `@media` block repeats `--nnw-bg`/`--nnw-ink`/`--nnw-link`
  in its own `:root` rule before its `body, .articleBody` rule, because a
  theme's dark `:root` would otherwise lose to the light `!important` values.
  The legacy `body, .articleBody` rules stay so untokenized themes still work.
- **Links.** The link color applies to `.articleBody a`, `:link` and
  `:visited`, excluding `#ao3Preface a`, `#ao3SyntheticPreface a` and
  `#ao3SeriesFooter a`, and strips background, border and shadows and
  underlines (a plain colored link). There is no bare `a` selector, so title,
  header, preface and series links are never recolored. The dark rule sets only
  `color`.
- **Chrome font.** `chromeSelectors` stays for the NetNewsWire-origin bundles
  and Vintage Letter Green; tokenized themes read `--nnw-font-chrome` themselves.

## Page composer and sample content

`ArticlePageComposer` (`Modules/ArticleTheming`) renders `page.html` through
`MacroProcessor` with exactly the six keys the reader uses (`title`,
`importStyle`, `style`, `baseURL`, `body`, `lang`). The package cannot see the
app's `page.html`, so callers pass its text in (`ArticleRenderer.page.html`).
`ArticlePageComposer.defaultLang` is the reader's language expression
(`WebViewController.renderPage` uses it). `ArticlePageComposerTests` renders a
theme through the reader's own path and through the composer and asserts the
HTML is identical, so the two cannot drift.

`ArticleThemeSampleContent` holds the sample article (preface, summary, notes,
chapter heading, two chapter paragraphs with a prose `<a>` inside `.articleBody`),
the fallback template and the sample macro values. The Settings preview
(`ArticleThemePreviewWebView`) renders through the composer and
`ArticleRenderer.page.html`, so its canvas, viewport and margins match the
reader; it no longer adds its own `body { margin; padding }` rule. It still uses
a default `WKWebViewConfiguration` (JavaScript on) and appends its own inline
helper scripts, and it loads with the fixed base URL
`https://example.invalid/`. `ArticleThemePreviewWebView.sampleBodyForTesting`
remains as an alias of `ArticleThemeSampleContent.sampleBody`.

Unknown `[[macro]]` tokens are left untouched by `MacroProcessor`, so a template
macro the sample does not supply (the default template's `[[text_size_class]]`)
stays literal in the preview, as it does in the reader.

## Rendering integration

`ArticleRenderer` (`Shared/Article Rendering/ArticleRenderer.swift`) is where
all of the above comes together for a given article:

- `template()` uses `articleTheme.template`, falling back to the app's own
  default `template.html` if the theme didn't supply one.
- `styleString()` uses `articleTheme.css` (falling back to
  `ArticleRenderer.defaultStyleSheet`), and appends
  `AppDefaults.shared.articleThemeOverrides.cssOverrideBlock` when overrides
  are non-empty.
- `importStyle` wraps `articleTheme.importCSS` (the extracted `@import`
  statements) in its own `<style>` block, kept separate from the main
  style tag. The wrapping lives in `ArticlePageComposer.importStyle(importCSS:)`
  and `ArticleRenderer` calls it.
- `articleCSS` runs the composed style string through `MacroProcessor` with
  `styleSubstitutions()` to fill in any remaining CSS-side template tokens
  (currently only `font-size`). There is a static `ArticleRenderer.styleSubstitutions()`
  so callers without a renderer instance can build the same dictionary.
- `ArticleRenderer.stripFakeParagraphIndents` removes leading `&nbsp;`
  sequences and literal-space "fake indents" from the start of `<p>` tag
  content, without disturbing the tag's own attributes or the rest of the
  paragraph's text/whitespace. Some AO3/Ambrosia source HTML hand-indents
  paragraphs this way instead of using CSS `text-indent`; left alone, it
  double-indents under themes that already apply their own paragraph
  indent via CSS. See
  `Tests/NetNewsWire-iOSTests/ArticleRendererStripFakeParagraphIndentsTests.swift`
  for the exact cases covered.

## Notifications summary

| Notification | Posted when |
|---|---|
| `.ArticleThemeNamesDidChangeNotification` | the set of available theme names changes (import/delete/external folder change) |
| `.CurrentArticleThemeDidChangeNotification` | the active theme changes |
| `.didBeginDownloadingTheme` / `.didEndDownloadingTheme` | web-downloaded `.zip` theme handling starts/finishes |
| `.didFailToImportThemeWithError` | an import attempt fails |

## Authoring new themes

`docs/creating-a-theme.md` is the short end-to-end walk-through, with the exact names a
bundle must use; the skills below carry the detailed workflow.

`.claude/skills/nnwtheme-porter/SKILL.md`,
`.claude/skills/nnwtheme-header-design/SKILL.md`, and
`.claude/skills/nnwtheme-builder/SKILL.md` document the workflow for
porting a new theme (typically from an AO3 workskin) into a `.nnwtheme`
bundle, including the generator script's per-theme dict schema, palette
contrast requirements, font-sourcing rules, verified AO3 markup this app
actually renders, and the constraints imposed by
`ArticleThemeColorExtractor`/`ArticleThemeOverrides`/`core.css` on every
theme (e.g. don't invent selectors that don't exist in the shared template;
prefer reusing an existing muted color over inventing a new one). See also
`docs/nnwtheme-format.md` for the theme-family convention.
