//
//  ArticleResolvedColors+Current.swift
//  Nectar
//
//  Copyright © 2026 Ranchero Software, LLC. All rights reserved.
//
//  ArticleResolvedColors.resolved(...) (the pure, parameterized computation)
//  lives in Modules/ArticleTheming. This app-target extension supplies
//  `current(isDark:)`, the convenience wrapper that reads the live globals
//  (current theme via ArticleThemesManager, current overrides via
//  AppDefaults) -- it can't live in the package because AppDefaults stays
//  in the app target (Modularization Stage 0b).
//

import UIKit
import ArticleTheming

extension ArticleResolvedColors {

	/// Convenience over `resolved(theme:isDark:overrideBackgroundColorHex:overrideBackgroundColorDarkHex:)`
	/// that reads the live globals (current theme, current overrides) itself,
	/// rather than requiring every caller to look those up. Originally a
	/// private wrapper local to `WebViewController`
	/// (`resolvedArticleColors(isDark:)`); promoted to a shared definition
	/// once `SurfacePaletteNavigationBarAware`'s `.blend` toolbar style needed
	/// the exact same computation -- one shared definition rather than a
	/// second copy that can drift out of sync with the webview/notch-cover
	/// pipeline (see `article-color-pipeline.md`). Callers should pass
	/// `traitCollection.userInterfaceStyle == .dark` from their own real
	/// view's trait collection, not `UITraitCollection.current` -- see
	/// `app-chrome-palette.md`'s note on that distinction.
	static func current(isDark: Bool) -> (background: UIColor, text: UIColor) {
		let theme = ArticleThemesManager.shared.currentTheme
		let overrides = AppDefaults.shared.articleThemeOverrides
		return resolved(theme: theme, isDark: isDark, overrideBackgroundColorHex: overrides.backgroundColorHex, overrideBackgroundColorDarkHex: overrides.backgroundColorDarkHex)
	}
}
