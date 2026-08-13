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

`ArticleThemeColorExtractor.colors(for:)` resolves the text/background/link
colors a theme's own stylesheet declares, so the webview background, the
notch cover, and the page-counter text can default to what the theme
actually looks like instead of a generic system color. It's a small
regex-based scanner, not a full CSS parser: it understands literal
`#hex`/`rgb()`/`rgba()` colors, a modest set of named CSS colors, and
`var(--custom-property)` resolved against that theme's own `:root`
declarations (scoped separately for light/dark so a dark-mode redefinition
of a variable doesn't leak into the light-mode result). It does not
understand CSS-4 system color keywords (`Canvas`, `CanvasText`, etc. — these
fall through to "not found" like anything else unparseable) or selector
specificity beyond exact-string matching. `@supports (...)` blocks are
excluded from consideration entirely before scanning starts
(`stripBraceBlocks`), on the basis that they carry platform-specific
overrides this scanner isn't equipped to reason about correctly — as of a
later fix, this also covers the `@supports not (...)` form, which the
original regex missed (`stylesheet.css`'s own macOS-only rules block uses
exactly that form).

**Precedence logic now lives in `ArticleResolvedColors.resolved(theme:
isDark:overrideBackgroundColorHex:overrideBackgroundColorDarkHex:)`**
(`Shared/ArticleStyles/ArticleThemeColorExtractor.swift`), not inline in
`WebViewController` — this doc's prose below describing the precedence
order still holds, but treat `ArticleResolvedColors.resolved` as the
single source of truth for it, since that's the actual code path now.
Resolved once per render in `WebViewController.renderPage()`/
`applyResolvedBackgroundColors()` and applied to the webview, scroll view,
and `notchCoverView` together so all three always agree: override
background (`ArticleThemeOverrides.backgroundColorHex`/
`backgroundColorDarkHex`, if set) → the theme's own extracted background →
a black/white fallback if neither is present. The same function is also
the one consumer outside `WebViewController`:
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

**Open investigation, not yet resolved as of this doc:** `WebViewController`
currently carries temporary debug logging (`Self.logger.debug(...)` calls
in the `registerForTraitChanges` handler and in
`applyResolvedBackgroundColors()`, plus a `logCSSColorSchemeAgreement`
helper) checking whether WKWebView's own `prefers-color-scheme` media
query has actually re-evaluated by the time the native trait-change
handler fires, or lags behind it. In-code comments attribute this to
"nectar-theme-background-toolbar-plan.md item 2" — that file is not
present anywhere in the current tree (same dangling-reference pattern as
elsewhere in this doc set; see `refresh-throttling.md` and
`sqlite-transfer.md` for others). Remove the temporary logging once
whichever engineer is running this investigation confirms the fix
on-device, and fold the finding into this doc.
