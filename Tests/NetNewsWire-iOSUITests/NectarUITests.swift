//
//  NectarUITests.swift
//  Nectar-iOSUITests
//
//  UI test target that drives fastlane's `snapshot()` calls. This target
//  did not exist before; without a UI test target actually launching the
//  app and calling `snapshot(...)`, `fastlane snapshot` has nothing to
//  photograph, so it builds and runs successfully but produces no images.
//
//  Each of fastlane's 6 style-combination launches runs this same test,
//  which seeds deterministic offline demo data (-UITestSeedDemoData, see
//  iOS/UITestDemoData/UITestDemoData.swift and docs/ui-test-demo-data.md)
//  and walks Main -> Timeline -> Article, capturing a screenshot at each
//  step.
//

import XCTest

// setUp/tearDown predate Swift concurrency and stay nonisolated even in a
// @MainActor class (see https://github.com/swiftlang/swift/issues/75815),
// so they can't call the @MainActor XCUIApplication APIs directly. The
// async throws overrides are MainActor-isolated and don't have that
// problem. The class is @MainActor-isolated, which already implies
// Sendable, so no explicit conformance is needed here.
@MainActor
final class NectarUITests: XCTestCase {

	// Names/titles from iOS/UITestDemoData's seeded fixtures. Kept here
	// rather than shared with the app target since this test target can't
	// import app-target code -- see docs/ui-test-demo-data.md.
	private static let timelineFeedName = "Star Trek: The Original Series (demo)"
	private static let libraryFeedName = "My Library (demo)"
	private static let timelineFeedSeededArticleCount = 7
	private static let focusArticleTitle = "A Quiet Kind of Orbit"

	override func setUp() async throws {
		try await super.setUp()
		continueAfterFailure = false

		let app = XCUIApplication()
		setupSnapshot(app)
		app.launch()
	}

	func testTakeScreenshots() throws {
		let app = XCUIApplication()

		// Give the initial view controller hierarchy -- and, when
		// -UITestSeedDemoData is set, the offline OPML import that
		// populates the sidebar -- a moment to settle before the first
		// capture.
		_ = app.wait(for: .runningForeground, timeout: 10)
		XCTAssertTrue(waitForCell(labeled: Self.timelineFeedName, in: app, timeout: 20),
					  "Seeded feed \"\(Self.timelineFeedName)\" never appeared in the sidebar.")

		snapshot("01MainFeed")

		// Main -> Timeline: open one of the seeded AO3-style feeds, which
		// carries a full, varied 7-entry timeline (ratings/warnings/
		// categories badge variety), for the Timeline screenshot.
		app.staticTexts[Self.timelineFeedName].firstMatch.tap()
		XCTAssertTrue(waitForCellCount(atLeast: Self.timelineFeedSeededArticleCount, in: app, timeout: 20),
					  "Timeline never reached the expected seeded article count.")

		snapshot("02Timeline")

		// Timeline -> Article: this feed's items are AO3-metadata-only (no
		// chapter body -- see docs/ui-test-demo-data.md on why), so back
		// out to the sidebar and into the single-item Ambrosia "My
		// Library" feed instead, which carries the one item with real,
		// fully offline chapter content to actually read/scroll/highlight.
		tapBackButton(in: app)
		XCTAssertTrue(waitForCell(labeled: Self.libraryFeedName, in: app, timeout: 10),
					  "Sidebar didn't return after navigating back from the timeline.")

		app.staticTexts[Self.libraryFeedName].firstMatch.tap()
		XCTAssertTrue(waitForCell(labeled: Self.focusArticleTitle, in: app, timeout: 10),
					  "Focus article \"\(Self.focusArticleTitle)\" never appeared in the library timeline.")

		app.staticTexts[Self.focusArticleTitle].firstMatch.tap()

		// Wait for the reader's webview to appear, then scroll past the
		// short hand-authored AO3-style preface block into the actual
		// story prose, where the seeded highlight lives.
		let webView = app.webViews.firstMatch
		XCTAssertTrue(webView.waitForExistence(timeout: 10), "Article webview never appeared.")
		webView.swipeUp()
		webView.swipeUp()

		snapshot("03Article")
	}

	// MARK: - Helpers

	private func waitForCell(labeled label: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
		app.staticTexts[label].firstMatch.waitForExistence(timeout: timeout)
	}

	private func waitForCellCount(atLeast count: Int, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
		let predicate = NSPredicate(format: "count >= %d", count)
		let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.cells)
		return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
	}

	/// No accessibility identifiers exist anywhere in the sidebar/timeline/
	/// article UI today (see docs/ui-test-demo-data.md), so this matches
	/// the leading navigation-bar button the way most UINavigationController
	/// screens without a customized back button expose it. If a screen ever
	/// adds a second leading bar button, this needs a more specific match.
	private func tapBackButton(in app: XCUIApplication) {
		app.navigationBars.buttons.element(boundBy: 0).tap()
	}
}
