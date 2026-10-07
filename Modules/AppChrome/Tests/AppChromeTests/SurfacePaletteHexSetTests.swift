//
//  SurfacePaletteHexSetTests.swift
//  AppChromeTests
//
//  Pure-type coverage of SurfacePalette's HexSets, moved from the app test
//  target. The tests that resolve colors through Assets.Colors and
//  AppDefaults stay in the app (SurfacePaletteAssetsResolutionTests).
//

import Testing
import UIKit
import HexColor
@testable import AppChrome

@Suite struct SurfacePaletteHexSetTests {

	// MARK: - .default

	@Test func defaultSurfacePaletteHasNoHexSetInEitherAppearance() {
		#expect(SurfacePalette.default.lightHexSet == nil)
		#expect(SurfacePalette.default.darkHexSet == nil)
	}

	// MARK: - Every non-default case supplies a complete, valid set

	@Test func everyNonDefaultCaseHasParseableHexForEverySlotInBothAppearances() {
		for surfacePalette in SurfacePalette.allCases where surfacePalette != .default {
			for (appearanceName, hexSet) in [("light", surfacePalette.lightHexSet), ("dark", surfacePalette.darkHexSet)] {
				guard let hexSet else {
					Issue.record("\(surfacePalette) has no \(appearanceName) HexSet")
					continue
				}
				let slots: [String: String] = [
					"barBackground": hexSet.barBackground,
					"fullScreenBackground": hexSet.fullScreenBackground,
					"vibrantText": hexSet.vibrantText,
					"navigationBarBackground": hexSet.navigationBarBackground,
					"navigationBarTint": hexSet.navigationBarTint,
					"settingsBackground": hexSet.settingsBackground,
					"settingsCellBackground": hexSet.settingsCellBackground,
					"listBackground": hexSet.listBackground
				]
				for (slotName, hex) in slots {
					#expect(UIColor(cssHex: hex) != nil, "\(surfacePalette).\(appearanceName).\(slotName) = \(hex) does not parse as a hex color")
				}
			}
		}
	}

	// MARK: - New cases (sepia/forest/berry) are included and distinct

	@Test func newSurfacePaletteCasesAreIncludedInAllCases() {
		for surfacePalette: SurfacePalette in [.sepia, .forest, .berry] {
			#expect(SurfacePalette.allCases.contains(surfacePalette))
		}
	}

	@Test func newSurfacePaletteCasesAreDistinctFromSlateAndFromEachOther() {
		// Guards against a copy-paste error when adding a new palette case
		// reusing Slate's (or another new case's) hex values instead of its
		// own -- listBackground should be unique across every non-default
		// case, in both appearances.
		let lightListBackgrounds = SurfacePalette.allCases.compactMap { $0.lightHexSet?.listBackground }
		#expect(Set(lightListBackgrounds).count == lightListBackgrounds.count, "expected every non-default SurfacePalette case to have a unique light listBackground")

		let darkListBackgrounds = SurfacePalette.allCases.compactMap { $0.darkHexSet?.listBackground }
		#expect(Set(darkListBackgrounds).count == darkListBackgrounds.count, "expected every non-default SurfacePalette case to have a unique dark listBackground")
	}
}
