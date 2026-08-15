//
//  BadgeColorTableTests.swift
//  NetNewsWire-iOSTests
//
//  See docs/app-chrome-palette.md ("Badge Colors"): coverage for BadgeColorTable's
//  restructuring from three BadgeColorPalette cases (neutral/default/
//  semantic) to five (monochrome/default/semantic/transparent/accent).
//  Specifically guards: (1) .monochrome's rename from .neutral is a
//  behavior-preserving no-op, (2) .transparent always returns a clear
//  background, (3) .accent's colors change when AccentColor changes and
//  differ across ratings/categories/warnings, and (4) fandom badges stay
//  neutral in every palette, unchanged.
//

import Testing
import UIKit
@testable import Nectar

@Suite struct BadgeColorTableTests {

	// MARK: - .monochrome (renamed from .neutral)

	@Test func monochromeReturnsTertiarySystemFillAndSecondaryLabel() {
		let colors = BadgeColorTable.colors(for: "Explicit", category: .rating, palette: .monochrome)
		#expect(colors.background == .tertiarySystemFill)
		#expect(colors.text == .secondaryLabel)
	}

	@Test func monochromeIgnoresCategoryValue() {
		// .monochrome must return the same pair regardless of category,
		// confirming the early guard in colors(for:category:palette:)
		// still short-circuits before any lookup table is consulted.
		let rating = BadgeColorTable.colors(for: "Mature", category: .rating, palette: .monochrome)
		let warning = BadgeColorTable.colors(for: "Underage", category: .warning, palette: .monochrome)
		#expect(rating.background == warning.background)
		#expect(rating.text == warning.text)
	}

	// MARK: - fandom stays neutral in every palette

	@Test func fandomIsAlwaysNeutralRegardlessOfPalette() {
		for palette in BadgeColorPalette.allCases {
			let colors = BadgeColorTable.colors(for: "Some Fandom", category: .fandom, palette: palette)
			#expect(colors.background == .tertiarySystemFill, "palette \(palette) did not stay neutral for .fandom")
			#expect(colors.text == .secondaryLabel, "palette \(palette) did not stay neutral for .fandom")
		}
	}

	@Test func nilCategoryIsAlwaysNeutralRegardlessOfPalette() {
		for palette in BadgeColorPalette.allCases {
			let colors = BadgeColorTable.colors(for: "anything", category: nil, palette: palette)
			#expect(colors.background == .tertiarySystemFill)
			#expect(colors.text == .secondaryLabel)
		}
	}

	// MARK: - .default / .semantic unchanged shape

	@Test func defaultRatingRecognizesKnownValue() {
		let colors = BadgeColorTable.colors(for: "Explicit", category: .rating, palette: .default)
		#expect(colors.background.cssHexString == UIColor(cssHex: "#eb6f92")!.cssHexString)
	}

	@Test func unrecognizedValueFallsBackToNeutralHex() {
		let colors = BadgeColorTable.colors(for: "Not Rated", category: .rating, palette: .default)
		#expect(colors.background.cssHexString == UIColor(cssHex: "#8E8E93")!.cssHexString)
	}

	// MARK: - .transparent

	@Test func transparentAlwaysHasClearBackground() {
		for category: BadgeCategory in [.rating, .category, .warning] {
			let colors = BadgeColorTable.colors(for: "Explicit", category: category, palette: .transparent)
			#expect(colors.background == .clear)
		}
	}

	@Test func transparentTextColorIsNotSecondaryLabelForRecognizedValue() {
		// Recognized values should get a real hue-derived text color, not
		// the neutral .secondaryLabel fallback -- distinguishes "found in
		// the lookup table" from "fell through to the unmatched case."
		let colors = BadgeColorTable.colors(for: "Explicit", category: .rating, palette: .transparent)
		#expect(colors.text != .secondaryLabel)
		#expect(colors.background == .clear)
	}

	@Test func transparentUnrecognizedValueFallsBackToNeutralHexText() {
		let colors = BadgeColorTable.colors(for: "Not Rated", category: .rating, palette: .transparent)
		#expect(colors.background == .clear)
		#expect(colors.text.cssHexString == UIColor(cssHex: "#8E8E93")!.cssHexString)
	}

	// MARK: - .accent

	@Test func accentRatingValuesAreDistinctFromOneAnother() {
		// Confirms the hue-offset table actually produces distinct colors
		// per rating rather than collapsing to one hue.
		let general = BadgeColorTable.colors(for: "General Audiences", category: .rating, palette: .accent)
		let teen = BadgeColorTable.colors(for: "Teen And Up Audiences", category: .rating, palette: .accent)
		let mature = BadgeColorTable.colors(for: "Mature", category: .rating, palette: .accent)
		let explicit = BadgeColorTable.colors(for: "Explicit", category: .rating, palette: .accent)

		let hexes = Set([general, teen, mature, explicit].map { $0.background.cssHexString })
		#expect(hexes.count == 4, "expected four distinct accent-derived rating colors, got \(hexes)")
	}

	@Test func accentBackgroundIsNotClearOrNeutralFallback() {
		// .accent should always resolve a real derived hue for recognized
		// values, not silently fall through to .transparent's .clear or
		// .monochrome's .tertiarySystemFill shape.
		let colors = BadgeColorTable.colors(for: "Explicit", category: .rating, palette: .accent)
		#expect(colors.background != .clear)
		#expect(colors.background != .tertiarySystemFill)
	}

	@Test func accentColorsAreConsistentAcrossCategoriesOfTheSameAccentColor() {
		// Not a strict equality check (categories intentionally use
		// different hue offsets than ratings/warnings) -- this just
		// guards that .accent resolves without crashing or returning the
		// neutral fallback for every one of the three lookup kinds.
		let rating = BadgeColorTable.colors(for: "Mature", category: .rating, palette: .accent)
		let category = BadgeColorTable.colors(for: "Gen", category: .category, palette: .accent)
		let warning = BadgeColorTable.colors(for: "Underage", category: .warning, palette: .accent)
		for colors in [rating, category, warning] {
			#expect(colors.background != .tertiarySystemFill)
		}
	}

	@Test func accentUnrecognizedValueFallsBackToNeutralHex() {
		let colors = BadgeColorTable.colors(for: "Not Rated", category: .rating, palette: .accent)
		#expect(colors.background.cssHexString == UIColor(cssHex: "#8E8E93")!.cssHexString)
	}

	// MARK: - .accent tracks live AppDefaults.shared.accentColor

	@MainActor
	@Test func accentBadgeColorsChangeWhenAccentColorChanges() {
		// The whole point of .accent: no separate badge-specific color
		// setting to keep in sync with AccentColor. This is the
		// regression test for that -- .accent's rendered rating color
		// must differ between two different AccentColor selections.
		defer { AppDefaults.shared.accentColor = .default }

		AppDefaults.shared.accentColor = .forest
		let forestColors = BadgeColorTable.colors(for: "Mature", category: .rating, palette: .accent)

		AppDefaults.shared.accentColor = .berry
		let berryColors = BadgeColorTable.colors(for: "Mature", category: .rating, palette: .accent)

		#expect(forestColors.background.cssHexString != berryColors.background.cssHexString)
	}
}
