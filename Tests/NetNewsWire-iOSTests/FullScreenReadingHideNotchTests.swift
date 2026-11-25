//
//  FullScreenReadingHideNotchTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for FullScreenReadingModel's hide-notch availability:
//  WebViewController forces notch-hiding whenever Page Counter is anything
//  other than Off, independent of Hide Notch's own stored AppDefaults value.
//

import Testing
@testable import Nectar

@Suite struct FullScreenReadingHideNotchTests {

	@MainActor
	@Test func hideNotchSwitchIsDisabledAndOnWhenPageCounterIsActive() {
		defer {
			AppDefaults.shared.pageCounterDisplayMode = .off
			AppDefaults.shared.hideNotchInFullScreen = false
		}

		AppDefaults.shared.hideNotchInFullScreen = false
		AppDefaults.shared.pageCounterDisplayMode = .percentage
		let model = FullScreenReadingModel()

		#expect(model.isHideNotchDisabled)
		#expect(model.effectiveHideNotch)
	}

	@MainActor
	@Test func hideNotchSwitchReflectsStoredValueWhenPageCounterIsOff() {
		defer {
			AppDefaults.shared.pageCounterDisplayMode = .off
			AppDefaults.shared.hideNotchInFullScreen = false
		}

		AppDefaults.shared.pageCounterDisplayMode = .off
		AppDefaults.shared.hideNotchInFullScreen = true
		let model = FullScreenReadingModel()

		#expect(!model.isHideNotchDisabled)
		#expect(model.effectiveHideNotch)

		model.hideNotchInFullScreen = false
		#expect(!model.effectiveHideNotch)
	}

	@MainActor
	@Test func hideNotchAvailabilityUpdatesLiveWhenPageCounterChanges() {
		defer {
			AppDefaults.shared.pageCounterDisplayMode = .off
			AppDefaults.shared.hideNotchInFullScreen = false
		}

		AppDefaults.shared.pageCounterDisplayMode = .off
		AppDefaults.shared.hideNotchInFullScreen = false
		let model = FullScreenReadingModel()
		#expect(!model.isHideNotchDisabled)

		model.pageCounterDisplayMode = .pageCount

		#expect(model.isHideNotchDisabled)
		#expect(model.effectiveHideNotch)
		#expect(AppDefaults.shared.hideNotchInFullScreen == false)
	}
}
