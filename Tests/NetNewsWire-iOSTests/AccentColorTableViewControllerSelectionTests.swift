//
//  AccentColorTableViewControllerSelectionTests.swift
//  NetNewsWire-iOSTests
//
//  Regression coverage for AccentColorSettingsModel selection and external
//  notification synchronization.
//

import Testing
@testable import Nectar
import AppChrome

@Suite struct AccentColorTableViewControllerSelectionTests {

	@MainActor
	@Test func selectingAnAccentColorUpdatesAppDefaults() {
		defer { AppDefaults.shared.accentColor = .default }

		let model = AccentColorSettingsModel()
		model.accentColor = .forest

		#expect(AppDefaults.shared.accentColor == .forest)
	}

	@MainActor
	@Test func selectingASecondAccentColorLandsOnTheNewSelectionNotThePrevious() {
		defer { AppDefaults.shared.accentColor = .default }

		let model = AccentColorSettingsModel()

		model.accentColor = .ocean
		#expect(AppDefaults.shared.accentColor == .ocean)
		#expect(model.accentColor == .ocean)

		model.accentColor = .berry
		#expect(AppDefaults.shared.accentColor == .berry)
		#expect(model.accentColor == .berry)
	}

	@MainActor
	@Test func externalAccentColorNotificationUpdatesModel() {
		defer { AppDefaults.shared.accentColor = .default }

		let model = AccentColorSettingsModel()
		AppDefaults.shared.accentColor = .sunset

		#expect(model.accentColor == .sunset)
	}
}
