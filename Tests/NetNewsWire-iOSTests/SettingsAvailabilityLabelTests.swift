//
//  SettingsAvailabilityLabelTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for SettingsModel's reason-label, disabled-control gating,
//  and feed transfer format preference synchronization.
//

import Testing
import Account
@testable import Nectar

@Suite struct SettingsAvailabilityLabelTests {

	@MainActor
	@Test func groupByFeedIsDisabledWithReasonWhenNotSortedByDate() {
		defer { AppDefaults.shared.timelineSortField = .date }

		AppDefaults.shared.timelineSortField = .title
		let model = SettingsModel()

		#expect(model.isGroupByFeedEnabled == false)
		#expect(model.groupByFeedDisabledReason != nil)
	}

	@MainActor
	@Test func groupByFeedIsEnabledWithNoReasonWhenSortedByDate() {
		defer { AppDefaults.shared.timelineSortField = .date }

		AppDefaults.shared.timelineSortField = .date
		let model = SettingsModel()

		#expect(model.isGroupByFeedEnabled)
		#expect(model.groupByFeedDisabledReason == nil)
	}

	@MainActor
	@Test func feedTransferFormatTextReflectsCurrentPreference() {
		defer { AmbrosiaTransferFormatPreference.current = .json }

		AmbrosiaTransferFormatPreference.current = .sqlite
		let model = SettingsModel()

		#expect(model.feedTransferFormatText == "SQLite")

		AmbrosiaTransferFormatPreference.current = .json
		model.refresh()

		#expect(model.feedTransferFormatText == "JSON")
	}

	@MainActor
	@Test func clearReadArticlesReasonShowsWhenNoParentControllerIsSet() {
		let model = SettingsModel()
		#expect(model.clearReadArticlesReason != nil)
	}
}
