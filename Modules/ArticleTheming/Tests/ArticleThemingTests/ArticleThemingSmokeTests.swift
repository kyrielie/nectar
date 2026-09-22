//
//  ArticleThemingSmokeTests.swift
//  ArticleThemingTests
//
//  Copyright © 2026 Ranchero Software, LLC. All rights reserved.
//
//  A small package-level smoke test guarding the package boundary itself
//  (public API is usable from outside the package), independent of the
//  much larger app-level regression suite this code already has
//  (ArticleThemeColorExtractorTests, ArticleThemeOverflowSafetyTests,
//  ArticleThemePlistFamilyTests, ArticleThemeSelectorCoverageTests,
//  CSSImportExtractorTests, ArticleRendererSeriesNavigationTests,
//  WebViewControllerAppearanceToggleTests). Deliberately avoids
//  ArticleTheme.defaultTheme / ArticleTheme() -- both need a `core.css`
//  resource from Bundle.main that isn't available in a pure SPM test
//  target (same reason ArticleThemeColorExtractorTests exercises
//  colors(css:) directly rather than through a real ArticleTheme).
//

import Testing
import Foundation
@testable import ArticleTheming

struct ArticleThemingSmokeTests {

	@Test func cssImportExtractorSeparatesImportFromRemainingCSS() {
		let css = "@import url(\"fonts.css\");\nbody { color: red; }"
		let result = CSSImportExtractor.extract(from: css)
		#expect(result.importCSS.contains("@import"))
		#expect(result.remainingCSS.contains("body"))
		#expect(!result.remainingCSS.contains("@import"))
	}

	@Test func articleThemeOverridesCssOverrideBlockIsEmptyWhenNoOverridesSet() {
		let overrides = ArticleThemeOverrides()
		#expect(overrides.isEmpty)
		#expect(overrides.cssOverrideBlock.isEmpty)
	}

	@Test func articleThemeOverridesCssOverrideBlockReflectsASetOverride() {
		let overrides = ArticleThemeOverrides(fontSize: 18)
		#expect(!overrides.isEmpty)
		#expect(overrides.cssOverrideBlock.contains("font-size: 18.0px"))
	}

	@Test func defaultThemeNameIsStable() {
		// This is the non-localized persistence key AppDefaults matches
		// theme selections against -- see ArticleThemesManager.swift's
		// header comment on why it's distinct from ArticleTheme's own
		// (localized) defaultThemeName display fallback.
		#expect(ArticleThemesManager.defaultThemeName == "Default")
	}

	@Test func articleThemePlistRoundTripsFamilyFields() throws {
		let plist = ArticleThemePlist(name: "Test", themeIdentifier: "com.example.test", creatorHomePage: "https://example.com", creatorName: "Example", version: 1, family: "Dracula", familyVariant: "Purple")
		let data = try PropertyListEncoder().encode(plist)
		let decoded = try PropertyListDecoder().decode(ArticleThemePlist.self, from: data)
		#expect(decoded.family == "Dracula")
		#expect(decoded.familyVariant == "Purple")
	}
}
