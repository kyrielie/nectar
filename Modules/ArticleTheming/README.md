# ArticleTheming

`.nnwtheme` bundle loading, the theme registry (`ArticleThemesManager`),
per-reader font/color overrides (`ArticleThemeOverrides`), and CSS color
extraction (`ArticleThemeColorExtractor` / `ArticleResolvedColors`).
Extracted from `Shared/ArticleStyles/` (Modularization Stage 0b).

`ArticleThemesManager` needs one piece of app-target state -- the
persisted current theme name -- which it can't own itself (that's
`AppDefaults`, which stays app-target-only). See `ArticleThemeNameStoring`
for the seam: `AppDefaults` conforms to it, and `AppDelegate.swift`
injects `AppDefaults.shared` into `ArticleThemesManager.nameStorage`
before calling `start()`.

`ArticleResolvedColors.current(isDark:)` (the version that reads live
AppDefaults/ArticleThemesManager globals) lives in the app target for
the same reason -- see `iOS/Article/ArticleResolvedColors+Current.swift`.
This package only owns the pure `resolved(theme:isDark:overrideBackgroundColorHex:overrideBackgroundColorDarkHex:)`
computation.

Depends on `RSCore` (`Platform.dataSubfolder`, `postOnMainThread`),
`HexColor` (`UIColor(cssHex:)` etc.), and `Zip` (unzipping downloaded
theme archives).
