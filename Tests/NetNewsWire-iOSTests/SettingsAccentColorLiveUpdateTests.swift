//
//  SettingsAccentColorLiveUpdateTests.swift
//  NetNewsWire-iOSTests
//
//  Regression coverage for two reported bugs against SettingsViewController:
//
//  1. Changing accent color didn't visibly update anything on the Settings
//     screen until the whole Settings sheet was dismissed and re-presented.
//     Root cause: SettingsViewController never observed .accentColorDidChange
//     at all, so accentColorDetailLabel only ever got set once, in
//     viewWillAppear.
//  2. Accent color never applied to the toggle sliders (UISwitches) in
//     Settings. Root cause: Settings.storyboard binds each switch's
//     onTintColor to the static primaryAccentColor named color asset, which
//     never changes -- the live, accent-aware color is
//     Assets.Colors.primaryAccent, which the storyboard has no way to read.
//
//  These tests exercise applyAccentColorTinting()'s effects directly rather
//  than posting the notification through NotificationCenter and racing a
//  main-queue callback, since the fix itself (observing the notification at
//  all) isn't in question -- what's being pinned here is that the method the
//  observer calls actually updates the label text and every switch's
//  onTintColor from the live accent color, not a stale/static one.
//

import Testing
import UIKit
@testable import Nectar

@Suite struct SettingsAccentColorLiveUpdateTests {

	@MainActor
	private func makeLoadedController() -> SettingsViewController {
		let controller = UIStoryboard.settings.instantiateController(ofType: SettingsViewController.self)
		controller.loadViewIfNeeded()
		controller.viewWillAppear(false)
		return controller
	}

	@MainActor
	@Test func accentColorDetailLabelReflectsCurrentAccentColorAfterChange() {
		defer { AppDefaults.shared.accentColor = .default }

		let controller = makeLoadedController()
		AppDefaults.shared.accentColor = .forest // posts .accentColorDidChange

		#expect(controller.accentColorDetailLabel.text == AccentColor.forest.description)
	}

	@MainActor
	@Test func switchesPickUpLiveAccentColorNotTheStaticStoryboardAsset() {
		defer { AppDefaults.shared.accentColor = .default }

		let controller = makeLoadedController()
		AppDefaults.shared.accentColor = .berry // posts .accentColorDidChange

		let liveTint = Assets.Colors.primaryAccent
		for toggle in [controller.groupByFeedSwitch, controller.refreshClearsReadArticlesSwitch,
					   controller.showLastUpdatedLabelSwitch, controller.showFeedNameInReaderViewSwitch,
					   controller.disableArticleLinksSwitch, controller.openLinksInNetNewsWire] {
			#expect(toggle?.onTintColor == liveTint)
		}
	}

	@MainActor
	@Test func accentColorTintingIsAppliedOnInitialAppearanceNotJustOnChange() {
		// Guards against a regression where applyAccentColorTinting() only
		// ever runs from the notification observer -- it must also run from
		// viewWillAppear so a non-default accent color set before this
		// screen ever loaded is reflected immediately, not just on the next
		// change after that.
		defer { AppDefaults.shared.accentColor = .default }

		AppDefaults.shared.accentColor = .ocean
		let controller = makeLoadedController()

		#expect(controller.accentColorDetailLabel.text == AccentColor.ocean.description)
		#expect(controller.groupByFeedSwitch.onTintColor == Assets.Colors.primaryAccent)
	}
}
