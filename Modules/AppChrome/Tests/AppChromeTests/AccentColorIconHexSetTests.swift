//
//  AccentColorIconHexSetTests.swift
//  AppChromeTests
//
//  Pure-type coverage of AccentColor.IconHexSet, moved from the app test
//  target so it runs in the package's own test target. The tests that
//  resolve colors through Assets.Colors and AppDefaults stay in the app
//  (AccentColorAssetsResolutionTests).
//

import Testing
import UIKit
import HexColor
@testable import AppChrome

@Suite struct AccentColorIconHexSetTests {

	// MARK: - .default

	@Test func defaultAccentColorHasNoIconHexSet() {
		#expect(AccentColor.default.iconHexSet == nil)
	}

	// MARK: - Every non-default case supplies a complete, valid set

	@Test func everyNonDefaultCaseHasParseableHexForEverySlot() {
		for accentColor in AccentColor.allCases where accentColor != .default {
			guard let hexSet = accentColor.iconHexSet else {
				Issue.record("\(accentColor) has no IconHexSet")
				continue
			}
			let slots: [String: String] = [
				"folder": hexSet.folder,
				"unreadFeed": hexSet.unreadFeed,
				"readFeed": hexSet.readFeed,
				"lastOpenedFeed": hexSet.lastOpenedFeed,
				"unreadCellIndicator": hexSet.unreadCellIndicator,
				"star": hexSet.star,
				"today": hexSet.today,
				"loved": hexSet.loved
			]
			for (slotName, hex) in slots {
				#expect(UIColor(cssHex: hex) != nil, "\(accentColor).\(slotName) = \(hex) does not parse as a hex color")
			}
		}
	}

	// MARK: - iconHexSet is a pure computed property (not cached across calls)

	@Test func iconHexSetIsStableAcrossRepeatedReads() {
		// Guards against a future change accidentally introducing
		// once-only caching (the exact bug IconHexSet's fields exist to
		// avoid at the Assets.Images call-site level -- see
		// the doc comment on AccentColor in Palettes.swift).
		let first = AccentColor.rosePine.iconHexSet
		let second = AccentColor.rosePine.iconHexSet
		#expect(first?.folder == second?.folder)
		#expect(first?.unreadFeed == second?.unreadFeed)
	}

	// MARK: - New theme cases (ocean/sunset/lavender/graphite)

	@Test func newThemeCasesAreDistinctFromEachOtherAndFromExistingCases() {
		// Guards against a copy-paste error when adding a new theme
		// case reusing an existing case's hex values instead of its
		// own -- each case's primaryHex should be unique across the
		// whole enum.
		let allHexes = AccentColor.allCases.compactMap { $0.primaryHex }
		#expect(Set(allHexes).count == allHexes.count, "expected every non-default AccentColor case to have a unique primaryHex")
	}

	@Test func newThemeCasesAreIncludedInAllCases() {
		for accentColor: AccentColor in [.ocean, .sunset, .lavender, .graphite] {
			#expect(AccentColor.allCases.contains(accentColor))
		}
	}
}
