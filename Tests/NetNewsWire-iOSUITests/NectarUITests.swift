//
//  NectarUITests.swift
//  Nectar-iOSUITests
//
//  UI test target that drives fastlane's `snapshot()` calls. This target
//  did not exist before; without a UI test target actually launching the
//  app and calling `snapshot(...)`, `fastlane snapshot` has nothing to
//  photograph, so it builds and runs successfully but produces no images.
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

	override func setUp() async throws {
		try await super.setUp()
		continueAfterFailure = false

		let app = XCUIApplication()
		setupSnapshot(app)
		app.launch()
	}

	func testTakeScreenshots() throws {
		let app = XCUIApplication()

		// Give the initial view controller hierarchy a moment to settle
		// before the first capture.
		_ = app.wait(for: .runningForeground, timeout: 10)

		snapshot("01MainFeed")

		// Add more navigation + snapshot("0N...") calls here as needed to
		// capture additional screens (timeline, article view, settings...).
	}
}
