//
//  NectarUITests.swift
//  Nectar-iOSUITests
//
//  UI test target that drives fastlane's `snapshot()` calls.
//
//  The app is launched with -UITestSeedDemoData, which subscribes it to a plain
//  JSON Feed hosted on GitHub Pages (see iOS/UITestDemoData/UITestDemoData.swift
//  and docs/ui-test-demo-data.md). This test therefore needs network access.
//  It walks Main -> Timeline -> Article and captures a screenshot at each step.
//  The demo feed is a single feed, so there is no back navigation.
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

	// Must match iOS/UITestDemoData/DemoFeeds.opml and demo-feeds/feed.template.json.
	// Kept here because this test target can't import app-target code.
	private static let feedName = "Nectar Demo Reading List"
	private static let feedItemCount = 8
	private static let articleTitle = "A Quiet Kind of Orbit"

	// The feed is fetched over the network on first launch.
	private static let networkTimeout: TimeInterval = 45

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

		_ = app.wait(for: .runningForeground, timeout: 10)

		// The feed's name comes from the bundled OPML, so it appears before any
		// network request completes.
		XCTAssertTrue(waitForCell(labeledPrefix: Self.feedName, in: app, timeout: 20),
					  "Demo feed \"\(Self.feedName)\" never appeared in the sidebar.")
		snapshot("01MainFeed")

		cell(labeledPrefix: Self.feedName, in: app).tap()

		// Articles only exist once the network fetch of the hosted feed completes.
		XCTAssertTrue(waitForCellCount(atLeast: Self.feedItemCount, in: app, timeout: Self.networkTimeout),
					  "Timeline never reached \(Self.feedItemCount) articles. The hosted demo feed may be unreachable or empty (check network, and that .github/workflows/gallery.yml has published demo-feeds/feed.json).")
		snapshot("02Timeline")

		XCTAssertTrue(waitForCell(labeledPrefix: Self.articleTitle, in: app, timeout: 10),
					  "Article \"\(Self.articleTitle)\" not found in the timeline.")
		cell(labeledPrefix: Self.articleTitle, in: app).tap()

		XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10), "Article webview never appeared.")
		snapshot("03Article")
	}

	// MARK: - Helpers

	/// Sidebar and timeline rows are single accessibility elements: the cell is an
	/// accessibility element and its child labels are not (see
	/// MainFeedCollectionViewCell.awakeFromNib, MainTimelineCell). Rows are therefore
	/// exposed as `cells` whose label is the composed accessibilityLabel, e.g.
	/// "<name>" or "<name> <n> unread". Match by label prefix, on cells, not by
	/// `staticTexts`.
	private func cell(labeledPrefix prefix: String, in app: XCUIApplication) -> XCUIElement {
		app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
	}

	private func waitForCell(labeledPrefix prefix: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
		let found = cell(labeledPrefix: prefix, in: app).waitForExistence(timeout: timeout)
		log("waitForCell(\"\(prefix)\") -> \(found); cells=\(cellLabels(in: app))")
		return found
	}

	private func waitForCellCount(atLeast count: Int, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
		let predicate = NSPredicate(format: "count >= %d", count)
		let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.cells)
		let completed = XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
		log("waitForCellCount(>= \(count)) -> \(completed); cells=\(cellLabels(in: app))")
		return completed
	}

	// MARK: - Diagnostics

	/// Prefixed so it is easy to grep out of a noisy xcodebuild log:
	/// `grep '\[NectarUITest\]' build/ui-test.log`
	private func log(_ message: String) {
		print("[NectarUITest] \(message)")
	}

	private func cellLabels(in app: XCUIApplication) -> [String] {
		app.cells.allElementsBoundByIndex.map { $0.label }
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
