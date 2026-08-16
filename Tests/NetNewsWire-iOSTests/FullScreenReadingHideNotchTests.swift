//
//  FullScreenReadingHideNotchTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for updateHideNotchAvailability(): WebViewController forces
//  notch-hiding whenever Page Counter is anything other than Off,
//  independent of Hide Notch's own stored AppDefaults value. These tests
//  pin that the Settings switch stops silently disagreeing with that --
//  it disables itself and shows on, rather than displaying whatever
//  hideNotchInFullScreen happens to be stored as.
//

import Testing
import UIKit
@testable import Nectar

@Suite struct FullScreenReadingHideNotchTests {

	@MainActor
	private func makeLoadedController() -> FullScreenReadingViewController {
		let controller = UIStoryboard.settings.instantiateController(ofType: FullScreenReadingViewController.self)
		controller.loadViewIfNeeded()
		controller.viewWillAppear(false)
		return controller
	}

	@MainActor
	@Test func hideNotchSwitchIsDisabledAndOnWhenPageCounterIsActive() {
		defer {
			AppDefaults.shared.pageCounterDisplayMode = .off
			AppDefaults.shared.hideNotchInFullScreen = false
		}

		AppDefaults.shared.hideNotchInFullScreen = false
		AppDefaults.shared.pageCounterDisplayMode = .percentage
		let controller = makeLoadedController()

		#expect(controller.hideNotchInFullScreenSwitch.isEnabled == false)
		#expect(controller.hideNotchInFullScreenSwitch.isOn)
	}

	@MainActor
	@Test func hideNotchSwitchReflectsStoredValueWhenPageCounterIsOff() {
		defer {
			AppDefaults.shared.pageCounterDisplayMode = .off
			AppDefaults.shared.hideNotchInFullScreen = false
		}

		AppDefaults.shared.pageCounterDisplayMode = .off
		AppDefaults.shared.hideNotchInFullScreen = true
		let controller = makeLoadedController()

		#expect(controller.hideNotchInFullScreenSwitch.isEnabled)
		#expect(controller.hideNotchInFullScreenSwitch.isOn)

		AppDefaults.shared.hideNotchInFullScreen = false
		controller.updateHideNotchAvailability()

		#expect(controller.hideNotchInFullScreenSwitch.isOn == false)
	}

	@MainActor
	@Test func hideNotchAvailabilityUpdatesLiveWhenPageCounterChangesFromThisScreen() {
		defer {
			AppDefaults.shared.pageCounterDisplayMode = .off
			AppDefaults.shared.hideNotchInFullScreen = false
		}

		AppDefaults.shared.pageCounterDisplayMode = .off
		AppDefaults.shared.hideNotchInFullScreen = false
		let controller = makeLoadedController()
		#expect(controller.hideNotchInFullScreenSwitch.isEnabled)

		// Simulates presentPageCounterDisplayModePicker's action handler,
		// which calls updateHideNotchAvailability() right after writing
		// the new mode -- pinned here without presenting a real
		// UIAlertController.
		AppDefaults.shared.pageCounterDisplayMode = .pageCount
		controller.updateHideNotchAvailability()

		#expect(controller.hideNotchInFullScreenSwitch.isEnabled == false)
		#expect(controller.hideNotchInFullScreenSwitch.isOn)
	}
}
