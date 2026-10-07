//
//  SurfacePaletteAssetsResolutionTests.swift
//  NetNewsWire-iOSTests
//
//  App-side coverage for SurfacePalette: the Assets.Colors accessors that
//  resolve a palette's HexSet live through AppDefaults.shared.surfaceTint.
//  The pure HexSet tests (.default has no set, every non-default case is
//  complete and parseable, new cases are distinct) live in
//  Modules/AppChrome/Tests/AppChromeTests/SurfacePaletteHexSetTests.swift.
//

import Testing
import UIKit
@testable import Nectar
@testable import HexColor
import AppChrome

@Suite struct SurfacePaletteAssetsResolutionTests {

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
