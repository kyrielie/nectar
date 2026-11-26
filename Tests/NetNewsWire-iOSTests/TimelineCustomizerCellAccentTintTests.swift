//
//  TimelineCustomizerCellAccentTintTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for TimelineCustomizerModel preferences (numberOfLines,
//  tagDisplayMode, statsVisible).
//

import Testing
@testable import Nectar

@Suite struct TimelineCustomizerCellAccentTintTests {

	@MainActor
	@Test func updatingTimelineCustomizerModelPersistsToAppDefaults() {
		let originalLines = AppDefaults.shared.timelineNumberOfLines
		let originalTagMode = AppDefaults.shared.timelineTagDisplayMode
		let originalStats = AppDefaults.shared.statsVisible
		defer {
			AppDefaults.shared.timelineNumberOfLines = originalLines
			AppDefaults.shared.timelineTagDisplayMode = originalTagMode
			AppDefaults.shared.statsVisible = originalStats
		}

		let model = TimelineCustomizerModel()
		model.numberOfLines = 4
		model.tagDisplayMode = .badges
		model.statsVisible = false

		#expect(AppDefaults.shared.timelineNumberOfLines == 4)
		#expect(AppDefaults.shared.timelineTagDisplayMode == .badges)
		#expect(AppDefaults.shared.statsVisible == false)
	}
}
