//
//  ReadingTimeIndicatorDisplayModeTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for AppDefaults.readingTimeIndicatorDisplayMode (Phase 5 of the
//  Reading Stats/Reading Time fix plan): the indicator's own toggle,
//  independent of pageCounterDisplayMode. WebViewController's actual
//  isHidden wiring can't be exercised here -- see
//  WebViewControllerAppearanceToggleTests.swift's header comment for why
//  WebViewController can't be instantiated in this test target -- so this
//  covers the AppDefaults-level contract the settings toggle and
//  WebViewController both read from.
//

import Testing
import Foundation
@testable import Nectar

@MainActor @Suite struct ReadingTimeIndicatorDisplayModeTests {

	@Test func defaultsToPie_preservingExistingAlwaysOnBehavior() {
		let key = AppDefaults.Key.readingTimeIndicatorDisplayMode
		let original = AppDefaults.string(for: key)
		defer { AppDefaults.setString(for: key, original) }
		AppDefaults.setString(for: key, nil)

		#expect(AppDefaults.shared.readingTimeIndicatorDisplayMode == .pie)
	}

	@Test func roundTripsThroughOffAndPie() {
		let key = AppDefaults.Key.readingTimeIndicatorDisplayMode
		let original = AppDefaults.string(for: key)
		defer { AppDefaults.setString(for: key, original) }

		AppDefaults.shared.readingTimeIndicatorDisplayMode = .off
		#expect(AppDefaults.shared.readingTimeIndicatorDisplayMode == .off)

		AppDefaults.shared.readingTimeIndicatorDisplayMode = .pie
		#expect(AppDefaults.shared.readingTimeIndicatorDisplayMode == .pie)
	}

	@Test func isBackupEligible() {
		#expect(AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.readingTimeIndicatorDisplayMode))
	}
}
