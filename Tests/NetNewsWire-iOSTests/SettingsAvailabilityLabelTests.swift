//
//  SettingsAvailabilityLabelTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for the reason-label and disabled-control behavior added to
//  Settings: Group by Feed and Clear Read Articles on Refresh show a
//  reason instead of silently no-op'ing when their gating condition isn't
//  met, and the SQLite/JSON feed transfer picker's detail label stays in
//  sync with the underlying preference. Hide Notch's forced-disable
//  behavior is covered in FullScreenReadingHideNotchTests, since that
//  switch now lives on FullScreenReadingViewController.
//
//  updateClearReadArticlesReasonLabel() isn't covered here:
//  it reads presentingParentController as? RootSplitViewController, and
//  RootSplitViewController's real SceneCoordinator can only be
//  constructed from a fully wired Main.storyboard flow (primary/
//  supplementary/secondary columns already populated) -- disproportionate
//  scaffolding for one label's text. presentingParentController is nil in
//  a directly-instantiated controller, so the method's nil-coalescing
//  fallback (filterOnNow = false, reason shown) is exercised implicitly
//  by every other test in this file that loads a controller without
//  setting that property; the live, filter-on case needs manual/
//  on-device verification instead.
//

import Testing
import UIKit
import Account
@testable import Nectar

@Suite struct SettingsAvailabilityLabelTests {

	@MainActor
	private func makeLoadedController() -> SettingsViewController {
		let controller = UIStoryboard.settings.instantiateController(ofType: SettingsViewController.self)
		controller.loadViewIfNeeded()
		controller.viewWillAppear(false)
		return controller
	}

	@MainActor
	@Test func groupByFeedSwitchIsDisabledWithReasonWhenNotSortedByDate() {
		defer {
			AppDefaults.shared.timelineSortField = .date
		}

		AppDefaults.shared.timelineSortField = .title
		let controller = makeLoadedController()

		#expect(controller.groupByFeedSwitch.isEnabled == false)
		#expect(controller.groupByFeedReasonLabel.isHidden == false)
		#expect(controller.groupByFeedReasonLabel.text != nil)
	}

	@MainActor
	@Test func groupByFeedSwitchIsEnabledWithNoReasonWhenSortedByDate() {
		defer {
			AppDefaults.shared.timelineSortField = .date
		}

		AppDefaults.shared.timelineSortField = .date
		let controller = makeLoadedController()

		#expect(controller.groupByFeedSwitch.isEnabled)
		#expect(controller.groupByFeedReasonLabel.isHidden)
	}

	@MainActor
	@Test func feedTransferFormatLabelReflectsCurrentPreference() {
		defer { AmbrosiaTransferFormatPreference.current = .json }

		AmbrosiaTransferFormatPreference.current = .sqlite
		let controller = makeLoadedController()

		#expect(controller.feedTransferFormatDetailLabel.text == "SQLite")

		AmbrosiaTransferFormatPreference.current = .json
		controller.updateFeedTransferFormatLabel()

		#expect(controller.feedTransferFormatDetailLabel.text == "JSON")
	}

	@MainActor
	@Test func clearReadArticlesReasonLabelShowsReasonWhenNoParentControllerIsSet() {
		// presentingParentController is nil here (never set outside the
		// real presentation flow), so updateClearReadArticlesReasonLabel()
		// takes its nil-coalescing fallback (filterOnNow = false) rather
		// than reading a live SceneCoordinator.
		let controller = makeLoadedController()

		#expect(controller.clearReadArticlesReasonLabel.isHidden == false)
		#expect(controller.clearReadArticlesReasonLabel.text != nil)
	}
}
