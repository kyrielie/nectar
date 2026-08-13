# Article Theme System

Nectar renders every article/fic chapter through a themeable HTML template.
A theme is a `.nnwtheme` bundle (a directory, not a flat file) containing a
template, a stylesheet, and metadata. The system layers four independent
pieces on top of that bundle format: theme discovery/selection, third-party
theme import, a small CSS pre-processor, and a user-facing override layer
that sits on top of whichever theme is active.

## The `.nnwtheme` bundle format

Each bundle under `Themes/<Name>.nnwtheme/` (shipped) or in the user's
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
- `Info.plist` — theme metadata, decoded into `ArticleThemePlist`:

  | Key | Type | Notes |
  |---|---|---|
  | `Name` | String | |
  | `ThemeIdentifier` | String | reverse-DNS-style identifier |
  | `CreatorHomePage` | String | |
  | `CreatorName` | String | |
  | `Version` | Int | |
  | `Family` | String? | optional; groups sibling bundles that are the same design with different palettes (e.g. "Rosé Pine" has Main/Moon/Dawn variants) for gallery display. Omitted for the large majority of themes. |
  | `FamilyVariant` | String? | this bundle's label within `Family`; meaningless without `Family`. |

- An optional `License.md` for themes ported from a licensed source (e.g.
  NewsFax, Ember).

Nectar ships ~30 bundled themes in `Themes/`. Most are **generated**: produced
from a single Python script, `buildscripts/theme-generation/generate_ported_themes.py`,
which fills a shared structural CSS/HTML template with per-theme palette and
font data so that structural rules (header table, footnote popovers, table
borders, overflow handling) stay byte-identical across themes and can be
batch-audited. A minority are **hand-written**, used only when a source
theme's structure can't be expressed as a recolor of the shared template.

## `ArticleTheme`

`Shared/ArticleStyles/ArticleTheme.swift` is the runtime value type
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

`Shared/ArticleStyles/ArticleThemesManager.swift` is the singleton
(`ArticleThemesManager.shared`) that owns theme discovery, selection, import,
and deletion. It is an `NSFilePresenter` on the Themes folder
(`Platform.dataSubfolder(..., "Themes")`, under Application Support), so
external changes to that folder (e.g. a Finder drag) trigger
`presentedSubitemDidChange(at:)`, which re-scans.

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

`importTheme(filename:)` copies a `.nnwtheme` directory into the Themes data
folder (overwriting any existing bundle with the same name).
`deleteTheme(themeName:)` removes an installed bundle by resolved path.

## Third-party theme download and import

`Shared/ArticleStyles/ArticleThemeDownloader.swift` handles the case of a
person downloading a `.zip`-wrapped theme from the web (e.g. from a browser
"Open in Nectar" flow):

1. `handleFile(at:)` is given the downloaded file's temporary location.
2. `moveTheme(from:)` relocates it into `Application Support/NetNewsWire/Downloads`,
   renaming `.tmp` → `.zip`.
3. `unzipFile(at:)` unzips using the `Zip` package, then deep-searches the
   unzipped contents (via `FileManager.enumerator`) for a `.nnwtheme`
   directory, explicitly skipping anything under a `__MACOSX/` path (a
   macOS zip artifact). Throws `ArticleThemeDownloaderError.noThemeFile` if
   none is found.
4. Posts `.didEndDownloadingTheme` with the resolved `.nnwtheme` URL in
   `userInfo["url"]`.

`cleanUp()` removes all downloaded theme folders from the Downloads
directory (called opportunistically, not automatically after each import).

Notification names for the whole download → import flow live in
`ArticleTheme+Notifications.swift`: `.didBeginDownloadingTheme`,
`.didEndDownloadingTheme`, `.didFailToImportThemeWithError`.

## `CSSImportExtractor`

A small hand-rolled scanner (`Shared/ArticleStyles/CSSImportExtractor.swift`),
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

## `ArticleThemeColorExtractor`

`Shared/ArticleStyles/ArticleThemeColorExtractor.swift` is a small,
deliberately non-general CSS color scanner (regex-based, not a real CSS
parser) that reads a theme's *effective* text/background/link colors — both
light- and dark-mode — directly out of its compiled `css` string. This is
used so the app's own chrome (webview background, the iOS notch/status-bar
fill) and the theme-override UI can default to what a given theme actually
looks like, rather than a generic system color.

What it understands:
- Literal `#hex`, `rgb()`/`rgba()`, and a modest hand-maintained table of
  named CSS colors actually seen in shipped themes (not the full CSS
  keyword list).
- `var(--custom-property)`, resolved against that theme's own `:root`-style
  declarations — light and dark variable scopes are tracked and resolved
  separately, so a dark-mode redefinition of a variable can't leak into the
  light-mode result.
- A single `@media (prefers-color-scheme: dark)` block, whose presence alone
  sets `hasDarkModeVariant` — this reflects presence, not whether every
  color actually differs inside it.

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

`Shared/ArticleStyles/ArticleThemeOverrides.swift` is a `Codable`,
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
- `marginHorizontal`/`marginTop` target `body`'s padding and
  `#bodyContainer`'s padding-top respectively — chosen because
  `.articleContent`/`.barContent` (which an earlier draft of this feature
  assumed existed) don't actually exist anywhere in
  `Shared/Article Rendering/template.html`.

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
  style tag.
- `articleCSS` runs the composed style string through `MacroProcessor` with
  `styleSubstitutions()` to fill in any remaining CSS-side template tokens.

## Notifications summary

| Notification | Posted when |
|---|---|
| `.ArticleThemeNamesDidChangeNotification` | the set of available theme names changes (import/delete/external folder change) |
| `.CurrentArticleThemeDidChangeNotification` | the active theme changes |
| `.didBeginDownloadingTheme` / `.didEndDownloadingTheme` | web-downloaded `.zip` theme handling starts/finishes |
| `.didFailToImportThemeWithError` | an import attempt fails |

## Authoring new themes

`.claude/skills/nnwtheme-porter/SKILL.md` and
`.claude/skills/nnwtheme-header-design/SKILL.md` document the workflow for
porting a new theme (typically from an AO3 workskin) into a `.nnwtheme`
bundle, including the generator script's per-theme dict schema, palette
contrast requirements, font-sourcing rules, and the constraints imposed by
`ArticleThemeColorExtractor`/`ArticleThemeOverrides`/`core.css` on every
theme (e.g. don't invent selectors that don't exist in the shared template;
prefer reusing an existing muted color over inventing a new one). See also
`docs/nnwtheme-format.md` for the theme-family convention.
