//
//  HighlightPaletteHexSetTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for HighlightPalette (docs/annotations.md, "Color palette" and
//  docs/app-chrome-palette.md, "Highlight Palette"), mirroring
//  SurfacePaletteHexSetTests' shape with one deliberate difference:
//  HighlightPalette.default is NOT nil in either appearance (unlike
//  SurfacePalette.default) -- there's no pre-existing asset-catalog
//  colorset for highlight colors to fall back to, so .default's own
//  HexSets carry real values. See HighlightPalette's own doc comment in
//  AppDefaults.swift.
//

import Testing
import UIKit
import Articles
@testable import Nectar

@Suite struct HighlightPaletteHexSetTests {

	// MARK: - .default has real values in both appearances, unlike SurfacePalette.default

	@Test func defaultHighlightPaletteHasParseableHexInBothAppearances() {
		for color in Annotation.Color.allCases {
			#expect(UIColor(cssHex: HighlightPalette.default.lightHexSet[color]) != nil)
			#expect(UIColor(cssHex: HighlightPalette.default.darkHexSet[color]) != nil)
		}
	}

	@Test func defaultHighlightPaletteDarkSetKeepsTheLegacyHueButClearsWCAGContrast() {
		// The five hex values core.css/HighlightColorPopover used to
		// hardcode as their single, appearance-independent fallback were
		// Apple's dark-mode system colors -- kept as-is through the
		// light-mode fix (see module history), but measured contrast
		// showed every one of those five failed 4.5:1 against white
		// (yellow's ratio was ~1.41), so the WCAG contrast fix deepened
		// them further rather than leaving them frozen. Each dark value
		// below keeps its predecessor's hue, just darkened -- this test
		// guards that relationship (same hue family, not an arbitrary
		// new palette) rather than pinning exact legacy hex values, since
		// those are exactly what the contrast fix needed to change. See
		// everyDarkHexSetColorMeetsWCAGAAContrastForWhiteText for the
		// contrast guarantee itself.
		let dark = HighlightPalette.default.darkHexSet
		#expect(dark.yellow == "#8B7300")
		#expect(dark.red == "#EA0D00")
		#expect(dark.green == "#1E8738")
		#expect(dark.blue == "#0072E6")
		#expect(dark.purple == "#B033EF")
	}

	// MARK: - Every case supplies a complete, valid set for every Annotation.Color

	@Test func everyCaseHasParseableHexForEveryAnnotationColorInBothAppearances() {
		for palette in HighlightPalette.allCases {
			for (appearanceName, hexSet) in [("light", palette.lightHexSet), ("dark", palette.darkHexSet)] {
				for color in Annotation.Color.allCases {
					let hex = hexSet[color]
					#expect(UIColor(cssHex: hex) != nil, "\(palette).\(appearanceName)[\(color.rawValue)] = \(hex) does not parse as a hex color")
				}
			}
		}
	}

	// MARK: - byColorKey covers exactly Annotation.Color's five keys

	@Test func byColorKeyCoversExactlyAnnotationColorRawValues() {
		let expectedKeys = Set(Annotation.Color.allCases.map(\.rawValue))
		for palette in HighlightPalette.allCases {
			#expect(Set(palette.lightHexSet.byColorKey.keys) == expectedKeys)
			#expect(Set(palette.darkHexSet.byColorKey.keys) == expectedKeys)
		}
	}

	// MARK: - Every case (including the plan's five "fun" palettes) is included and distinct

	@Test func newHighlightPaletteCasesAreIncludedInAllCases() {
		let expectedCases: [HighlightPalette] = [.default, .muted, .vivid, .sepia, .mint, .flourescent, .refresh, .warm, .neutral]
		#expect(Set(HighlightPalette.allCases) == Set(expectedCases))
	}

	@Test func everyCaseIsDistinctFromEveryOtherCase() {
		// Guards against a copy-paste error reusing another case's values --
		// yellow's light hex should be unique across every case, since a
		// palette that's an exact duplicate of another provides no reason
		// to exist as a separate case.
		let lightYellows = HighlightPalette.allCases.map { $0.lightHexSet.yellow }
		#expect(Set(lightYellows).count == lightYellows.count, "expected every HighlightPalette case to have a unique light yellow")
	}

	// MARK: - Every case, including the five "fun" palettes, tunes dark mode separately

	@Test func everyCaseHasDistinctLightAndDarkHexSets() {
		// White article text against several of the "fun" palettes'
		// original light-mode pastels measured under 3:1 contrast --
		// well below WCAG AA's 4.5:1 for body text -- so every case
		// (not just .default/.muted/.vivid/.sepia) now supplies its own
		// deepened dark-mode values rather than reusing lightHexSet.
		for palette in HighlightPalette.allCases {
			let allSame = Annotation.Color.allCases.allSatisfy { palette.lightHexSet[$0] == palette.darkHexSet[$0] }
			#expect(!allSame, "\(palette) is expected to have at least one color differ between light and dark")
		}
	}

	@Test func everyDarkHexSetColorMeetsWCAGAAContrastForWhiteText() {
		// The concrete bug this guards against: a highlight rendered in
		// dark mode uses the reader's foreground color (near-white) for
		// text, so a highlight background that's still a light-mode-style
		// pastel makes that text nearly unreadable. 4.5:1 is WCAG AA for
		// normal-size body text.
		for palette in HighlightPalette.allCases {
			for color in Annotation.Color.allCases {
				let hex = palette.darkHexSet[color]
				guard let bg = UIColor(cssHex: hex) else {
					Issue.record("\(palette).darkHexSet[\(color.rawValue)] = \(hex) does not parse")
					continue
				}
				let ratio = bg.contrastRatio(against: .white)
				#expect(ratio >= 4.5, "\(palette).darkHexSet[\(color.rawValue)] = \(hex) has white-text contrast \(ratio), below WCAG AA's 4.5")
			}
		}
	}

	// MARK: - hexSet(isDark:) dispatches correctly

	@Test func hexSetIsDarkDispatchesToTheCorrectAppearance() {
		for palette in HighlightPalette.allCases {
			#expect(palette.hexSet(isDark: false).yellow == palette.lightHexSet.yellow)
			#expect(palette.hexSet(isDark: true).yellow == palette.darkHexSet.yellow)
		}
	}

	// MARK: - Live property + notification

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
