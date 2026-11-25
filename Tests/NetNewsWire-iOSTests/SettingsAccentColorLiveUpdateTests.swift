//
//  SettingsAccentColorLiveUpdateTests.swift
//  NetNewsWire-iOSTests
//
//  Regression coverage for SettingsModel's live accent color tracking.
//

import Testing
@testable import Nectar
import AppChrome

@Suite struct SettingsAccentColorLiveUpdateTests {

	@MainActor
	@Test func accentColorDescriptionReflectsCurrentAccentColorAfterChange() {
		defer { AppDefaults.shared.accentColor = .default }

		let model = SettingsModel()
		AppDefaults.shared.accentColor = .forest

		#expect(model.accentColorDescription == AccentColor.forest.description)
	}

	@MainActor
	@Test func accentColorDescriptionIsPopulatedOnInitialAppearanceNotJustOnChange() {
		defer { AppDefaults.shared.accentColor = .default }

		AppDefaults.shared.accentColor = .ocean
		let model = SettingsModel()

		#expect(model.accentColorDescription == AccentColor.ocean.description)
	}
}
