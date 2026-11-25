//
//  ToolbarStylePickerSelectionTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for ColorPaletteSettingsModel toolbarStyle and surfaceTint selection.
//

import Testing
@testable import Nectar

@Suite struct ToolbarStylePickerSelectionTests {

	@MainActor
	@Test func selectingARowUpdatesAppDefaults() {
		defer { AppDefaults.shared.toolbarStyle = .system }

		let model = ColorPaletteSettingsModel()
		model.toolbarStyle = .blend

		#expect(AppDefaults.shared.toolbarStyle == .blend)
		#expect(model.toolbarStyle == .blend)
	}

	@MainActor
	@Test func selectingASecondRowLandsOnTheNewSelectionNotThePrevious() {
		defer { AppDefaults.shared.toolbarStyle = .system }

		let model = ColorPaletteSettingsModel()

		model.toolbarStyle = .tinted
		#expect(AppDefaults.shared.toolbarStyle == .tinted)
		#expect(model.toolbarStyle == .tinted)

		model.toolbarStyle = .blend
		#expect(AppDefaults.shared.toolbarStyle == .blend)
		#expect(model.toolbarStyle == .blend)
	}
}
