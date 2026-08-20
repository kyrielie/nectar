//
//  FullScreenReadingAccentColorLiveUpdateTests.swift
//  NetNewsWire-iOSTests
//
//  Regression coverage, mirroring SettingsAccentColorLiveUpdateTests, for
//  the switches that moved from SettingsViewController onto
//  FullScreenReadingViewController: accent color must still tint them
//  live, both on initial appearance and on subsequent change, now that
//  they're owned by a different controller.
//

import Testing
import UIKit
@testable import Nectar

@Suite struct FullScreenReadingAccentColorLiveUpdateTests {

	@MainActor
	private func makeLoadedController() -> FullScreenReadingViewController {
		let controller = UIStoryboard.settings.instantiateController(ofType: FullScreenReadingViewController.self)
		controller.loadViewIfNeeded()
		controller.viewWillAppear(false)
		return controller
	}

	@MainActor
	@Test func switchesPickUpLiveAccentColorNotTheStaticStoryboardAsset() {
		defer { AppDefaults.shared.accentColor = .default }

		let controller = makeLoadedController()
		AppDefaults.shared.accentColor = .berry // posts .accentColorDidChange

		let liveTint = Assets.Colors.primaryAccent
		for toggle in [controller.showFullscreenArticlesSwitch, controller.backSwipeEnabledSwitch,
					   controller.pagingSwipeEnabledSwitch] {
			#expect(toggle?.onTintColor == liveTint)
		}
	}

	@MainActor
	@Test func accentColorTintingIsAppliedOnInitialAppearanceNotJustOnChange() {
		defer { AppDefaults.shared.accentColor = .default }

		AppDefaults.shared.accentColor = .ocean
		let controller = makeLoadedController()

		#expect(controller.showFullscreenArticlesSwitch.onTintColor == Assets.Colors.primaryAccent)
	}

	// hideNotchInFullScreenSwitch is deliberately excluded from the two
	// tests above: when Page Counter forces it disabled,
	// updateHideNotchAvailability() runs after applyAccentColorTinting()
	// in viewWillAppear, but disabling a switch doesn't affect its
	// onTintColor, so this isn't a gap -- it's covered together with the
	// disabled-state assertions in FullScreenReadingHideNotchTests instead
	// of being duplicated here.
}
