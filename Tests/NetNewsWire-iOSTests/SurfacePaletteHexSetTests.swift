//
//  SurfacePaletteHexSetTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for SurfacePalette after growing from a single alternative
//  (.slate) to four (.slate/.sepia/.forest/.berry), mirroring the shape of
//  AccentColorIconHexSetTests: (1) .default must have no HexSet in either
//  appearance, (2) every non-default case must supply a complete,
//  parseable HexSet for every slot in both light and dark, and (3) the new
//  cases must actually be distinct from Slate and from each other, not a
//  copy-paste of an existing case's values.
//

import Testing
import UIKit
@testable import Nectar

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

	// MARK: - Assets.Colors accessors resolve the new cases live

	@MainActor
	@Test func listBackgroundAccessorResolvesSepiaLiveWithoutRestart() {
		defer { AppDefaults.shared.surfaceTint = .default }

		AppDefaults.shared.surfaceTint = .sepia
		let lightTraits = UITraitCollection(userInterfaceStyle: .light)
		let resolved = Assets.Colors.listBackground(for: lightTraits)
		let expected = UIColor(cssHex: SurfacePalette.sepia.lightHexSet!.listBackground)!
		#expect(resolved.cssHexString == expected.cssHexString)
	}

	@MainActor
	@Test func settingsCellBackgroundAccessorDiffersBetweenForestAndBerry() {
		defer { AppDefaults.shared.surfaceTint = .default }
		let lightTraits = UITraitCollection(userInterfaceStyle: .light)

		AppDefaults.shared.surfaceTint = .forest
		let forestBackground = Assets.Colors.settingsCellBackground(for: lightTraits)

		AppDefaults.shared.surfaceTint = .berry
		let berryBackground = Assets.Colors.settingsCellBackground(for: lightTraits)

		#expect(forestBackground.cssHexString != berryBackground.cssHexString)
	}
}
