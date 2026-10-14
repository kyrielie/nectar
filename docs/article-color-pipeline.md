# Article background/notch color pipeline

How the webview background, notch cover, and page-counter text derive
their color from the active article theme, and how that stays live across
appearance changes. This is `WebViewController`'s own per-theme color
pipeline — distinct from the app-wide `app-chrome-palette.md` (Accent
Color / Surface Palette), which is contrasted directly against this one
below since Nectar's per-theme colors can't use the dynamic-system-color
shortcut that pipeline relies on. Also unrelated to, but in the same file
as, the article scrollbar-visibility setting and the reading-progress
scroll tracking in `reading-progress.md`.

Every native consumer reads theme colors through
`ArticleThemeColorStore.colors(for:)` (the seam; see "Color store" below). The
colors come from **measuring the rendered theme**, not from reading its CSS:
`ArticleThemeColorProbe` renders the theme in a hidden web view and reads back
computed colors (see "Color probe" below). A theme written the way community
themes are written (colors on `html`, the `background` shorthand,
`light-dark()`, `oklch()`, space-separated `rgb()`) therefore gets correct
native colors. There is no required token, selector or property spelling for
the native surfaces any more.

What is still true of theme CSS:

- `--nnw-bg`, `--nnw-ink` and `--nnw-link` are an optional authoring
  convenience. The user override block still sets them (with `!important`) next
  to direct `body, .articleBody` color and background rules, so a recolor
  reaches the page whether or not a theme uses the tokens. Themes may keep them
  literal and on the exact selectors the old scanner read; nothing requires it.
- The page color the probe records is `background-color` on `body`, then
  `html`. A page painted only by a gradient or image counts as unpainted and
  gets the legacy white/black fallback, so a theme with a gradient page should
  also set a `background-color` close to the gradient's top edge so the notch
  cover blends in.
- `--nnw-highlight-*`, `--nnw-line-height`, `--nnw-prose-size`,
  `--nnw-font-chrome` and `--gx` are app-to-theme inputs and are unchanged.

**The scanner is only a fallback.** `ArticleThemeColorExtractor.colors(for:)` is a
small regex scanner, not a CSS parser. It reads literal `#hex`/`rgb()`/`rgba()`
and a modest set of named colors, resolves `var()` one level against the
theme's own `:root` (light and dark scoped separately), excludes `@supports`
blocks, and reads only `color`/`background-color` on `body` and `.articleBody`
and `color` on `a` and `.articleBody a`. It is consulted when no measurement
exists yet (first launch of a non-bundled theme, a failed measurement, the
probe disabled). Because it cannot see the `background` shorthand, a
shorthand-only body falls back to white (light) or black (dark) while it is in
use; that is the accepted cost of the fallback and is corrected once the
measurement lands. Themes are not required to write `background-color`: the
scanner is a fallback only, and no check enforces a particular background
declaration form. The scanner suites `BackgroundInversionExposure` and
`ComposedThemeDarkBlockCollision` stay while the scanner exists. Reading a stylesheet in a test: production strips
`@import` lines with `CSSImportExtractor` before extraction, so a test that reads
the raw file must do the same, or the import text is glued onto the first rule's
selector.

**Precedence logic now lives in `ArticleResolvedColors.resolved(theme:
isDark:overrideBackgroundColorHex:overrideBackgroundColorDarkHex:)`**
(`Modules/ArticleTheming`'s `ArticleThemeColorExtractor.swift`), not inline in
`WebViewController` — this doc's prose below describing the precedence
order still holds, but treat `ArticleResolvedColors.resolved` as the
single source of truth for it, since that's the actual code path now.
Resolved once per render in `WebViewController.renderPage()`/
`applyResolvedBackgroundColors()` and applied to the webview, scroll view,
and `notchCoverView` together so all three always agree: override
background (`ArticleThemeOverrides.backgroundColorHex`/
`backgroundColorDarkHex`, if set) → the theme's own extracted background →
a black/white fallback if neither is present. `ArticleResolvedColors.current(isDark:)`
is a convenience wrapper over `resolved(...)` that reads the live globals
(current theme, current overrides) itself — originally a `private static`
helper local to `WebViewController` (`resolvedArticleColors(isDark:)`,
still present there as a thin wrapper over `.current(isDark:)`), promoted
onto `ArticleResolvedColors` once `app-chrome-palette.md`'s `ToolbarStyle`
`.blend` state needed the exact same computation for the article reader's
top nav bar and bottom toolbar. This means `ArticleResolvedColors.resolved(...)`'s
output now feeds two independent consumers — the webview/notch-cover
pipeline described in this doc, and `.blend`-mode toolbar color — so a
future change to this function's precedence order (override → theme →
fallback) needs both in mind, not just the webview. The function is also
the one other consumer outside `WebViewController`:
`iOS/Settings/ArticleThemePreviewWebView.swift` (a SwiftUI-facing live
theme preview, used somewhere in the theme-editing/picker Settings flow —
not yet investigated in detail here) calls it directly to resolve preview
colors for the theme currently being looked at, rather than duplicating
the precedence logic a second time.

`applyResolvedBackgroundColors()` also re-runs on its own, without a full
page reload, from a `registerForTraitChanges` handler installed in
`WebViewController.viewDidLoad` (the deployment target is iOS 17+, so this
uses the non-deprecated API rather than overriding
`traitCollectionDidChange`). This is the fix for a "notch cover / webview
background go stale on live appearance change" bug: the webview's own CSS
already updates live via `@media prefers-color-scheme` when the app's
Appearance setting changes or the system trait changes, but
`webView.backgroundColor` and the notch/page-counter colors were previously
resolved only once per `renderPage()` call, off a snapshot of
`webView.traitCollection.userInterfaceStyle` — they stayed wrong until the
next full render (theme change, article change, and so on). Upstream
NetNewsWire doesn't have this problem because it assigns the dynamic system
color `.systemBackground` via storyboard, which tracks trait changes for
free; Nectar's per-theme colors can't be expressed that way, since custom
themes need their own light/dark colors, so this pipeline needs its own
live-invalidation hook that the dynamic-color approach got automatically.

**Cold-launch state-restoration fix:** a related but distinct problem from the
live-toggle question below -- `WebViewController.viewDidLoad`'s own initial
`initialColors` read and the first `applyResolvedBackgroundColors()` call (from
`renderPage()`) both resolve against whatever `traitCollection.userInterfaceStyle`
reads as at the moment they run. During state restoration,
`SceneCoordinator.restoreSelectedSidebarItemAndArticle` pushes the restored
article before the first frame is ever drawn, and that whole path runs from
`SceneDelegate.scene(_:willConnectTo:options:)` -- before the window is
key/visible -- so that initial read can land against a not-yet-settled trait
environment while WKWebView's own CSS engine (driven independently by the real
system `prefers-color-scheme`) resolves correctly. Nothing previously corrected
this afterward, since `registerForTraitChanges` only fires on a *change* event,
not on "the initial read was wrong." Most visible on themes with no
`body`/`.articleBody` `color`/`background-color` declared at all (e.g.
Broadsheet) while the scanner fallback is in use, since its fallback for those is a
genuine light/dark opposite (`.black`-on-`.white` vs `.white`-on-`.black`) --
themes that declare an explicit, appearance-invariant background/color (no
dark media block; e.g. Black & White) resolve to the same color either way and
aren't affected. Fixed by adding `WebViewController.viewDidAppear(_:)`, which
re-runs `applyResolvedBackgroundColors()` once the view is guaranteed to
actually be on screen in a real, key window -- the first lifecycle point whose
timing doesn't depend on `SceneCoordinator`'s own restore-path scheduling. See
`ArticleThemeColorExtractorTests.BackgroundInversionExposure` for the
Broadsheet/Black & White divergence this depends on.

**Color probe.**
`ArticleThemeColorProbe` (`Modules/ArticleTheming`) measures what a theme paints
instead of scanning its CSS. It renders the theme through the reader's real
`page.html` in a hidden `WKWebView` (composed by `ArticlePageComposer`, sample
article from `ArticleThemeSampleContent`), once in light and once in dark, and
reads back computed colors with a `WKUserScript` that posts to a message
handler. Content JavaScript stays off (the page preferences come from
`WebViewConfiguration.makeReaderWebpagePreferences()`), so a theme's own
scripts cannot change the result. Page color is `background-color` only: body
over html over the legacy white/black fallback, and a page painted only by a
gradient or image counts as unpainted. Ink is `.articleBody`'s `color`, link is
the first `.articleBody a`, each normalized to opaque sRGB through a 2D canvas
(so `oklch()`, `light-dark()` and space-separated `rgb()` work); translucent
text is composited onto the page color. A pass whose `matchMedia` dark flag
does not match the requested appearance, an unparsable color, ink equal to the
page, or ink or link under 1.5 WCAG contrast against the page makes the whole
measurement nil. The app builds the probe's inputs with
`ArticleThemeProbeEnvironment.reader()` (`iOS/Article/`). The store drives
the probe through `ensureMeasured` (see "Theme gate" below); the bundled table is
described under "Bundled table" below. If the hidden window turns out not to flip `prefers-color-scheme`,
`ArticleThemeColorProbe.useVisibleHostFallback` is the pre-decided switch. It is now
`true`: the first CI run of the probe suites got no read-back from the hidden-window
host. Re-run the probe suites to confirm the visible host fixes it.
Tests: `ArticleThemeColorProbeTests` (rendering, written without being run in
Xcode) and the package's `ArticleThemeColorProbeLogicTests` (pure logic).

**Color store.** `ArticleThemeColorStore`
(`Modules/ArticleTheming`) is where measurements live. `colors(for:)` never
blocks and looks in session memory, then the persisted
`ThemeColorCache/ThemeColors.json`, then the bundled `ThemeColorTable.json` (written by
`ThemeColorTableGeneratorTests`; see `theme-testing.md`), then the legacy scanner. For the scanner fallback,
`hasDarkModeVariant` now comes from `ArticleThemeColorExtractor.declaresDarkBlock`
run on `ArticleTheme.ownStylesheet` (the theme's own CSS after `@import`
extraction, before `core.css`), because `core.css` carries a dark block of its
own and made the composed-CSS answer true for every theme. The cache key,
`ArticleTheme.colorCacheKey`, is SHA-256 over the length-prefixed raw
`stylesheet.css`, raw `template.html` and `ArticleThemeColorProbe.version`; it
excludes `core.css` and identity fields. The persisted file records the probe
version and `core.css` hash it was written under; `remeasureIfStale(_:)`
re-measures installed themes when either differs, keeps old entries in use
meanwhile, and returns the keys whose values changed. `ensureMeasured(_:)`
coalesces concurrent callers per theme and allows two attempts per launch;
failures are never persisted. `ArticleThemeColorStore.measurer` is the test hook.
The environment is supplied by `configure(_:)`, which `AppDelegate` calls with
`.reader()` just before `ArticleThemesManager.shared.start()`.

The seam: `ArticleResolvedColors.resolved` and `ArticleThemeListView` (the
appearance footer, the dark-mode preview toggle's availability, the override
picker's initial values and "Reset to Theme Defaults") all call
`ArticleThemeColorStore.colors(for:)`; the only remaining direct calls to
`ArticleThemeColorExtractor.colors(for:)` are the store's own fallback and the
probe agreement test. `hasDarkModeVariant` is true only when the theme's
own stylesheet declares a dark block (or, once measured, when page, ink or link
differs between light and dark), so the single-palette branches in
`ArticleThemeListView` (footer wording, disabled preview toggle) are reachable.

**Bundled table.** `iOS/Resources/ThemeColorTable.json` holds a measurement
for every theme that ships in the app (each `Themes/*.nnwtheme` plus Default) so
a cold start needs no measuring and no correction. It is generated by
`ThemeColorTableGeneratorTests` and kept honest by `ThemeColorTableGuardTests`,
which fail when `core.css`, a bundled theme or the probe version changes without
regenerating it. Procedure and bump rules are in `theme-testing.md`. State of this
checkout: the generator and guard are written, but the JSON itself has to be
produced by running the generator in Xcode (it needs a simulator web view) and
committed; until then the guard fails and the store falls back to the scanner as
before.

**Theme gate.** `ArticleThemesManager.updateCurrentTheme` decides when a
newly resolved theme becomes `currentTheme`, so native surfaces never paint
scanner colors and then visibly correct them where that can be avoided. A theme
that has a measurement (memory, persisted cache, bundled table) is
assigned synchronously. At launch the stored current theme is
assigned at once with scanner colors and measured in the background; if the
measurement differs from the scanner colors, the manager reposts
`CurrentArticleThemeDidChangeNotification` once. Any other unmeasured theme is
measured first and assigned afterwards (also when the measurement fails), unless
`currentThemeName` changed meanwhile, in which case the result is dropped.
Measurements are coalesced per theme by the store. `importTheme` and
`presentedSubitemDidChange(at:)` prewarm the affected theme (deduplicated by
name, so repeated file-presenter callbacks start nothing new). After `start()`,
if the persisted cache was written under another probe version or `core.css`,
installed themes are re-measured at utility priority and the notification is
reposted if the current theme's values changed. `ArticleThemeColorProbe.isEnabled`
(a constant, true) is the rollback: when false the store neither measures nor
serves measurements and the gate assigns synchronously with scanner colors.
`ArticleThemeListView` keeps a `pendingSelection` so the picker shows a choice
immediately while the gate waits; the current-theme notification clears it. The
only first-paint exception is a non-bundled current theme whose cache file is
missing at launch. Tests: `ArticleThemesManagerGateTests`.
Tests: the package's `ArticleThemeColorStoreTests` and the app's
`ArticleThemeColorStoreAppTests` (written without being run in Xcode).

**Open investigation:** whether WKWebView's `prefers-color-scheme` media query has
re-evaluated by the time the native trait-change handler fires is tracked in
`docs/investigate-later.md`; read it before re-investigating.
