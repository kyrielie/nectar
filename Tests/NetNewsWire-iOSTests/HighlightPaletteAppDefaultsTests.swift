//
//  HighlightPaletteAppDefaultsTests.swift
//  NetNewsWire-iOSTests
//
//  App-side coverage for HighlightPalette (docs/annotations.md, "Color
//  palette" and docs/app-chrome-palette.md, "Highlight Palette"): the parts
//  that need the app target, namely AppDefaults.shared.highlightPalette and
//  its change notification, and Annotation.Color.uiColor(palette:isDark:).
//  The pure HexSet tests live in
//  Modules/AppChrome/Tests/AppChromeTests/HighlightPaletteHexSetTests.swift.
//

import Testing
import UIKit
import Articles
@testable import Nectar
@testable import HexColor
import AppChrome

@Suite struct HighlightPaletteAppDefaultsTests {

	// MARK: - Annotation.Color.uiColor(palette:isDark:) resolves against the given palette

	@Test func annotationColorUIColorResolvesAgainstTheGivenPaletteAndAppearance() {
		for palette in HighlightPalette.allCases {
			for isDark in [false, true] {
				for color in Annotation.Color.allCases {
					let expectedHex = palette.hexSet(isDark: isDark)[color]
					let resolved = color.uiColor(palette: palette, isDark: isDark)
					let expected = UIColor(cssHex: expectedHex)!
					#expect(resolved.cssHexString == expected.cssHexString, "\(color) under \(palette)/isDark=\(isDark) should resolve to \(expectedHex)")
				}
			}
		}
	}

	@MainActor
	@Test func highlightPaletteDefaultsToDefaultAndPostsNotificationOnChange() async {
		// AppDefaults.store is the real, shared UserDefaults.standard, which
		// persists across test runs (and even CI invocations on the same
		// simulator) -- don't assume it's still at its registered default
		// just because nothing *in this test* has touched it yet.
		AppDefaults.shared.highlightPalette = .default
		defer { AppDefaults.shared.highlightPalette = .default }

		#expect(AppDefaults.shared.highlightPalette == .default)

		await confirmation { confirmed in
			let observer = NotificationCenter.default.addObserver(forName: .highlightPaletteDidChange, object: nil, queue: nil) { _ in
				confirmed()
			}
			defer { NotificationCenter.default.removeObserver(observer) }
			AppDefaults.shared.highlightPalette = .vivid
		}

		#expect(AppDefaults.shared.highlightPalette == .vivid)
	}
}
