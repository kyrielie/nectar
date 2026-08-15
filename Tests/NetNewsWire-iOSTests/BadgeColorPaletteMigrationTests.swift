//
//  BadgeColorPaletteMigrationTests.swift
//  NetNewsWire-iOSTests
//
//  See docs/app-chrome-palette.md ("Badge Colors"): BadgeColorPalette.neutral was
//  renamed to .monochrome, and the case set grew from three to five.
//  This guards the "no UserDefaults migration needed" claim in
//  BadgeColorPalette's doc comment directly, at the raw-value level
//  rather than trusting the comment -- a future edit that changes
//  .monochrome's raw value would silently change what a person with a
//  previously-saved `badgeColorMode == 1` sees, with no crash to catch it.
//

import Testing
@testable import Nectar

@Suite struct BadgeColorPaletteMigrationTests {

	@Test func monochromeKeepsRawValueOneForNoMigrationReason() {
		#expect(BadgeColorPalette.monochrome.rawValue == 1)
	}

	@Test func defaultKeepsRawValueTwo() {
		#expect(BadgeColorPalette.default.rawValue == 2)
	}

	@Test func semanticKeepsRawValueThree() {
		#expect(BadgeColorPalette.semantic.rawValue == 3)
	}

	@Test func transparentAndAccentTakeTheNextFreeRawValues() {
		#expect(BadgeColorPalette.transparent.rawValue == 4)
		#expect(BadgeColorPalette.accent.rawValue == 5)
	}

	@Test func rawValueOneStillResolvesToACase() {
		// Direct stand-in for "a device with badgeColorMode already
		// persisted as 1 loads correctly post-update."
		#expect(BadgeColorPalette(rawValue: 1) == .monochrome)
	}

	@Test func allCasesOrderMatchesSettingsRowOrder() {
		// AccentColorTableViewController's badgePalette section builds its
		// rows from BadgeColorPalette.allCases, in declaration order, and
		// (after the off-by-one fix alongside this change) maps a
		// selected row straight back via allCases[indexPath.row] rather
		// than treating the row index as a raw value. This test pins that
		// declaration order so a future case reorder doesn't silently
		// scramble which row selects which palette without any test
		// catching it.
		#expect(BadgeColorPalette.allCases == [.monochrome, .default, .semantic, .transparent, .accent])
	}
}
