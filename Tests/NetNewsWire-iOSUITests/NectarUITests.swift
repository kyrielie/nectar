//
//  NectarUITests.swift
//  Nectar-iOSUITests
//
//  UI test target that drives fastlane's `snapshot()` calls. Without a UI
//  test target actually launching the app and calling `snapshot(...)`,
//  `fastlane snapshot` has nothing to photograph, so it builds and runs
//  successfully but produces no images.
//
//  Each of fastlane's 6 style-combination launches runs this same test,
//  which seeds deterministic offline demo data (-UITestSeedDemoData, see
//  iOS/UITestDemoData/UITestDemoData.swift and docs/ui-test-demo-data.md)
//  and walks Main -> Timeline -> Article, capturing a screenshot at each
//  step. testTakeSettingsScreenshots is a separate test (run by the
//  `settings_screenshots` lane via only_testing) that walks the Settings
//  screens. Row titles below come from iOS/Settings/Settings.storyboard.
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
	private static let timelineFeedName = "Star Trek: The Original Series"
	private static let libraryFeedName = "My Library"
	// Sorts first in the timeline: highest `updated` timestamp among
	// tos-academy-days.atom's 7 entries (see UITestDemoData.swift).
	private static let timelineTopArticleTitle = "Letters Home"
	private static let focusArticleTitle = "A Quiet Kind of Orbit"

	override func setUp() async throws {
		try await super.setUp()
		continueAfterFailure = false

		let app = XCUIApplication()
		setupSnapshot(app)
		// The flag is added here, not only via fastlane, so a bare
		// `xcodebuild test` (./test.sh screenshots) behaves the same as
		// `fastlane screenshots`. `contains` in Platform makes a duplicate harmless.
		if !app.launchArguments.contains("-UITestSeedDemoData") {
			app.launchArguments.append("-UITestSeedDemoData")
		}
		app.launch()
		log("launched; app.state=\(app.state.rawValue)")
	}

	/// On any failure, attach a screenshot and the full accessibility tree to the
	/// result bundle so the failure is diagnosable from the .xcresult alone.
	override func tearDown() async throws {
		if testRun?.hasSucceeded == false {
			attachDiagnostics(XCUIApplication(), named: "final-failure-state")
		}
		try await super.tearDown()
	}

	func testTakeScreenshots() throws {
		let app = XCUIApplication()

		// Give the initial view controller hierarchy -- and the offline
		// OPML import that populates the sidebar -- a moment to settle
		// before the first capture.
		_ = app.wait(for: .runningForeground, timeout: 10)
		XCTAssertTrue(waitForCell(labeledSubstring: Self.timelineFeedName, in: app, timeout: 20),
					  "Seeded feed \"\(Self.timelineFeedName)\" never appeared in the sidebar.")

		snapshot("01MainFeed")

		// Main -> Timeline: open one of the seeded AO3-style feeds, which
		// carries a full, varied 7-entry timeline (ratings/warnings/
		// categories badge variety, plus a read/unread/starred/loved mix),
		// for the Timeline screenshot.
		//
		// Not asserted by counting app.cells: rows are tall enough (full
		// summary text in the label) that only some of the 7 fit in the
		// viewport at once, and an unscrolled collection view never
		// materializes off-screen cells as accessibility elements, so a
		// >= 7 count can never be satisfied here regardless of timeout.
		// Asserting on the newest-`updated` seeded title (sorts first)
		// still catches the actual regression this guards against --
		// LocalAccountDelegate's refreshAll() no-op leaving the timeline
		// empty -- without depending on how many rows fit on screen.
		cell(labeledSubstring: Self.timelineFeedName, in: app).tap()
		XCTAssertTrue(waitForCell(labeledSubstring: Self.timelineTopArticleTitle, in: app, timeout: 20),
					  "Timeline never populated with the seeded articles.")

		snapshot("02Timeline")

		// Timeline -> Article: this feed's items are AO3-metadata-only (no
		// chapter body -- see docs/ui-test-demo-data.md on why), so back
		// out to the sidebar and into the single-item Ambrosia "My
		// Library" feed instead, which carries the one item with real,
		// fully offline chapter content to actually read/scroll/highlight.
		XCTAssertTrue(navigateBackToSidebar(in: app, expecting: Self.libraryFeedName),
					  "Sidebar didn't return after navigating back from the timeline.")

		cell(labeledSubstring: Self.libraryFeedName, in: app).tap()
		XCTAssertTrue(waitForCell(labeledSubstring: Self.focusArticleTitle, in: app, timeout: 10),
					  "Focus article \"\(Self.focusArticleTitle)\" never appeared in the library timeline.")

		cell(labeledSubstring: Self.focusArticleTitle, in: app).tap()

		// Wait for the reader's webview to appear, then scroll past the
		// short hand-authored AO3-style preface block into the actual
		// story prose, where the seeded highlight lives.
		let webView = app.webViews.firstMatch
		XCTAssertTrue(webView.waitForExistence(timeout: 10), "Article webview never appeared.")
		webView.swipeUp()
		webView.swipeUp()

		snapshot("03Article")
	}

	/// Settings screens. Best effort per screen: a row that cannot be found is
	/// logged and skipped rather than failing the run, so one renamed row does not
	/// lose every other capture. Only getting into Settings is asserted.
	/// (substring of the row title, snapshot name). Order is top to bottom of the
	/// Settings list.
	private static let settingsScreens: [(row: String, name: String)] = [
		("Color Palette", "03ColorPalette"),
		("Timeline Layout", "04TimelineLayout"),
		("Reading Gestures", "05ReadingGesturesAndLayout"),
		("Toolbars", "06Toolbars"),
		("Highlights", "07HighlightsAndNotes"),
		("Text Replacement", "08TextReplacement"),
		("Screen Time", "09ScreenTime"),
		("Reading Stats", "10ReadingStats"),
		("Archive of Our Own", "11AO3Account")
	]

	func testTakeSettingsScreenshots() throws {
		let app = XCUIApplication()
		_ = app.wait(for: .runningForeground, timeout: 10)
		XCTAssertTrue(waitForCell(labeledSubstring: Self.timelineFeedName, in: app, timeout: 20),
					  "Seeded feed \"\(Self.timelineFeedName)\" never appeared in the sidebar.")

		// "settingsButton" is set in MainFeedCollectionViewController; the
		// title fallback covers the storyboard's "Settings" bar button.
		let byIdentifier = app.buttons["settingsButton"]
		let byTitle = app.toolbars.buttons["Settings"]
		let settingsButton = byIdentifier.waitForExistence(timeout: 10) ? byIdentifier : byTitle
		XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Settings button not found.")
		settingsButton.tap()

		XCTAssertTrue(waitForCell(labeledSubstring: "Color Palette", in: app, timeout: 10),
					  "Settings list never appeared.")
		snapshot("01SettingsTop")

		app.swipeUp()
		snapshot("02SettingsMore")

		for screen in Self.settingsScreens {
			guard revealRow(labeledSubstring: screen.row, in: app) else {
				log("settings row \"\(screen.row)\" not found; skipping \(screen.name)")
				continue
			}
			cell(labeledSubstring: screen.row, in: app).tap()
			settle()
			snapshot(screen.name)
			popToSettingsList(in: app)
		}
	}

	// MARK: - Helpers

	private func settle() {
		Thread.sleep(forTimeInterval: 0.8)
	}

	/// Scrolls the Settings table until the row is on screen: first as-is, then
	/// down the list, then back up (popping a pushed screen keeps the scroll
	/// position, so the next row may be above or below).
	private func revealRow(labeledSubstring substring: String, in app: XCUIApplication) -> Bool {
		let row = cell(labeledSubstring: substring, in: app)
		if row.exists && row.isHittable { return true }
		let table = app.tables.firstMatch
		for _ in 0..<10 {
			table.swipeUp()
			if row.exists && row.isHittable { return true }
		}
		for _ in 0..<20 {
			table.swipeDown()
			if row.exists && row.isHittable { return true }
		}
		return false
	}

	/// Settings is a navigation stack; the leading navigation-bar button on a
	/// pushed screen is Back. Positional, like navigateBackToSidebar, because
	/// the Settings screens have no accessibility identifiers.
	private func popToSettingsList(in app: XCUIApplication) {
		let back = app.navigationBars.buttons.element(boundBy: 0)
		if back.exists && back.isHittable {
			back.tap()
		} else {
			log("no hittable back button after settings screen")
		}
		settle()
	}

	/// Sidebar and timeline rows are single accessibility elements: the cell is an
	/// accessibility element and its child labels are not (see
	/// MainFeedCollectionViewCell.awakeFromNib, MainTimelineCell). Rows are therefore
	/// exposed as `cells` whose label is the composed accessibilityLabel -- for the
	/// sidebar, "<n>" or "<n> <n> unread" (starts with the name); for the timeline,
	/// "[status flags]<feedName>, <title>, <summary>, <date>" (the title is
	/// mid-string, after any status flags and the feed name, not at the start).
	/// Match by substring, on cells, not by `staticTexts` or `BEGINSWITH`.
	private func cell(labeledSubstring substring: String, in app: XCUIApplication) -> XCUIElement {
		app.cells.matching(NSPredicate(format: "label CONTAINS %@", substring)).firstMatch
	}

	private func waitForCell(labeledSubstring substring: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
		let found = cell(labeledSubstring: substring, in: app).waitForExistence(timeout: timeout)
		if !found {
			// Querying cells of a dead app throws "Failed to resolve query:
			// Application ... is not running", which hides the real cause.
			// Report the crash explicitly instead.
			requireAppRunning(app, during: "waitForCell(\"\(substring)\")")
		}
		log("waitForCell(\"\(substring)\") -> \(found); cells=\(cellLabels(in: app))")
		return found
	}

	/// Returns from the timeline to the sidebar and confirms the sidebar row
	/// containing `substring` is reachable. Tries, in order:
	/// 1. The leading navigation-bar button. No accessibility identifiers
	///    exist in the sidebar/timeline/article UI today (see
	///    docs/ui-test-demo-data.md), so this is a positional match, and it
	///    only counts if the sidebar actually came back.
	/// 2. The interactive-pop edge swipe, in case that button was not the
	///    back button.
	/// 3. Scrolling, since an unscrolled collection view does not
	///    materialize off-screen cells as accessibility elements.
	private func navigateBackToSidebar(in app: XCUIApplication, expecting substring: String) -> Bool {
		requireAppRunning(app, during: "navigateBackToSidebar")
		let row = cell(labeledSubstring: substring, in: app)

		let leadingButton = app.navigationBars.buttons.element(boundBy: 0)
		if leadingButton.exists && leadingButton.isHittable {
			leadingButton.tap()
			if row.waitForExistence(timeout: 4) { return true }
			log("back button tap did not reveal \"\(substring)\"")
		}

		requireAppRunning(app, during: "navigateBackToSidebar (edge swipe)")
		let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
		let across = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
		edge.press(forDuration: 0.1, thenDragTo: across)
		if row.waitForExistence(timeout: 4) { return true }
		log("edge swipe did not reveal \"\(substring)\"")

		for _ in 0..<3 {
			app.swipeUp()
			if row.waitForExistence(timeout: 1) { return true }
		}
		requireAppRunning(app, during: "navigateBackToSidebar (after scrolling)")
		return false
	}

	// MARK: - Diagnostics

	/// Prefixed so it is easy to grep out of a noisy xcodebuild log:
	/// `grep '\[NectarUITest\]' build/ui-test.log`
	private func log(_ message: String) {
		print("[NectarUITest] \(message)")
	}

	private func cellLabels(in app: XCUIApplication) -> [String] {
		guard app.state != .notRunning else { return [] }
		return app.cells.allElementsBoundByIndex.map { $0.label }
	}

	/// Fails the test with an explicit message if the app process is gone
	/// (crashed or terminated), instead of surfacing it later as an
	/// unrelated "Failed to resolve query" error.
	private func requireAppRunning(_ app: XCUIApplication, during context: String) {
		let state = app.state
		log("app.state during \(context): \(state.rawValue)")
		XCTAssertNotEqual(state, .notRunning,
						  "App is not running during \(context); it most likely crashed. "
						  + "Look for a Nectar-*.ips crash report in ~/Library/Logs/DiagnosticReports.")
	}

	/// Prints and attaches the accessibility tree and a screenshot.
	/// Lifetime is `.keepAlways` so it survives in the xcresult even on pass.
	private func attachDiagnostics(_ app: XCUIApplication, named name: String) {
		log("--- \(name) ---")
		log("cells: \(cellLabels(in: app))")
		let tree = XCTAttachment(string: app.debugDescription)
		tree.name = "\(name)-hierarchy"
		tree.lifetime = .keepAlways
		add(tree)
		let shot = XCTAttachment(screenshot: app.screenshot())
		shot.name = "\(name)-screenshot"
		shot.lifetime = .keepAlways
		add(shot)
	}
}
