//
//  UIColorCSSHexTests.swift
//  HexColorTests
//
//  Copyright © 2026 Ranchero Software, LLC. All rights reserved.
//
//  A small package-level smoke test, independent of the app-level
//  regression coverage this extraction already has (AccentColorIconHexSetTests,
//  ArticleThemeColorExtractorTests, BadgeColorTableTests,
//  HighlightPaletteHexSetTests, SurfacePaletteHexSetTests,
//  WebViewControllerAppearanceToggleTests) -- this guards the package
//  boundary itself (public API is actually usable from outside the
//  package) rather than duplicating that coverage.
//

import Testing
import UIKit
@testable import HexColor

struct UIColorCSSHexTests {

	@Test func sixDigitHexRoundTrips() {
		let color = UIColor(cssHex: "#FF8800")
		#expect(color != nil)
		#expect(color?.cssHexString == "#FF8800")
	}

	@Test func threeDigitHexExpands() {
		let color = UIColor(cssHex: "#F80")
		#expect(color?.cssHexString == "#FF8800")
	}

	@Test func invalidHexReturnsNil() {
		#expect(UIColor(cssHex: "not-a-color") == nil)
	}

	@Test func contrastRatioIsSymmetric() {
		let black = UIColor(cssHex: "#000000")!
		let white = UIColor(cssHex: "#FFFFFF")!
		#expect(black.contrastRatio(against: white) == white.contrastRatio(against: black))
	}

	@Test func blackAgainstWhiteIsMaximumContrast() {
		let black = UIColor(cssHex: "#000000")!
		let white = UIColor(cssHex: "#FFFFFF")!
		// WCAG's maximum possible ratio, (1.0+0.05)/(0.0+0.05).
		#expect(abs(black.contrastRatio(against: white) - 21.0) < 0.01)
	}
}
