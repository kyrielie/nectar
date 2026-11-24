//
//  AO3ImportMetadataQueueTests.swift
//  AccountTests
//
//  Tests for AO3ImportMetadataQueue:
//  - Pacing interval between requests (3.0s default, verified with controllable interval)
//  - 429 rate limit cooldown suspension
//  - Metadata population in SQLite without chapter bodies (contentHTML == nil)
//  - Queue progress notifications
//

import XCTest
@testable import Account
@testable import AO3Kit
import RSParser
import RSWeb

private actor TestRequestTracker {
	private(set) var times: [Date] = []

	var count: Int {
		times.count
	}

	func record() -> Int {
		times.append(Date())
		return times.count
	}
}

private actor TestProgressTracker {
	private(set) var events: [(completed: Int, total: Int)] = []
	private var didFulfill = false

	func addEvent(completed: Int, total: Int, expectation: XCTestExpectation) {
		events.append((completed, total))
		if completed == 2 && total == 2 && !didFulfill {
			didFulfill = true
			expectation.fulfill()
		}
	}
}

@MainActor final class AO3ImportMetadataQueueTests: XCTestCase {

	private var account: Account!

	override func setUp() async throws {
		account = TestAccountManager.shared.createAccount(type: .onMyMac)
		await AO3ImportMetadataQueue.shared.resetForTesting()
		AO3RateLimitTestBridge.clearCooldowns()
	}

	override func tearDown() async throws {
		await AO3ImportMetadataQueue.shared.resetForTesting()
		AO3RateLimitTestBridge.clearCooldowns()
		TestAccountManager.shared.deleteAccount(account)
		account = nil
	}

	// MARK: - Default Pacing Constant

	func testDefaultPacingIntervalIsThreeSeconds() {
		XCTAssertEqual(AO3ImportMetadataQueue.defaultDelayBetweenRequests, 3.0, accuracy: 0.001)
	}

	// MARK: - Pacing Interval Verification

	func testPacingIntervalBetweenConsecutiveRequests() async throws {
		let queue = AO3ImportMetadataQueue(delayBetweenRequests: 0.1)
		let tracker = TestRequestTracker()

		await queue.setCustomFetchHandlerForTesting { _ in
			_ = await tracker.record()

			let html = Self.sampleWorkHTML(workID: "1", title: "Work", chapters: "1/1")
			let response = HTTPURLResponse(url: URL(string: "https://archiveofourown.org/works/1")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (html.data(using: .utf8), response)
		}

		await queue.enqueue(workIDs: ["101", "102", "103"], accountID: account.accountID, feedID: Account.importedLinksFeedURL)

		// Wait for queue to drain
		while await queue.isDraining {
			try await Task.sleep(nanoseconds: 20_000_000)
		}

		let requestTimes = await tracker.times
		XCTAssertEqual(requestTimes.count, 3)
		if requestTimes.count == 3 {
			let delta1 = requestTimes[1].timeIntervalSince(requestTimes[0])
			let delta2 = requestTimes[2].timeIntervalSince(requestTimes[1])
			XCTAssertGreaterThanOrEqual(delta1, 0.09, "Expected at least 0.1s delay between request 1 and 2, got \(delta1)")
			XCTAssertGreaterThanOrEqual(delta2, 0.09, "Expected at least 0.1s delay between request 2 and 3, got \(delta2)")
		}
	}

	// MARK: - 429 Cooldown Suspension

	func test429CooldownSuspendsQueue() async throws {
		let queue = AO3ImportMetadataQueue(delayBetweenRequests: 0.01)
		let tracker = TestRequestTracker()

		await queue.setCustomFetchHandlerForTesting { url in
			let currentCount = await tracker.record()

			if currentCount == 1 {
				// Return 429 on first request with 1s Retry-After
				let response = HTTPURLResponse(
					url: url,
					statusCode: 429,
					httpVersion: nil,
					headerFields: ["Retry-After": "1"]
				)!
				return (nil, response)
			} else {
				let html = Self.sampleWorkHTML(workID: "2", title: "Recovered Work", chapters: "1/1")
				let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
				return (html.data(using: .utf8), response)
			}
		}

		await queue.enqueue(workIDs: ["201", "202"], accountID: account.accountID, feedID: Account.importedLinksFeedURL)

		while await queue.isDraining {
			try await Task.sleep(nanoseconds: 50_000_000)
		}

		let requestCount = await tracker.count
		let times = await tracker.times
		XCTAssertEqual(requestCount, 2)
		if times.count == 2 {
			let gap = times[1].timeIntervalSince(times[0])
			XCTAssertGreaterThanOrEqual(gap, 0.8, "Expected queue to suspend for 429 cooldown, gap was \(gap)s")
		}
	}

	// MARK: - Metadata Population & Content Invariant

	func testImportMetadataPopulatesArticleAndLeavesContentHTMLNil() async throws {
		let queue = AO3ImportMetadataQueue(delayBetweenRequests: 0.01)

		// 1. Create the placeholder article via importAO3Links
		_ = await account.importAO3Links("https://archiveofourown.org/works/99999")
		let articlesBefore = await account.fetchArticlesAsync(bookKeys: ["ao3-work:99999"])
		let placeholder = try XCTUnwrap(articlesBefore.first)

		XCTAssertEqual(placeholder.title, "AO3 Work 99999")
		XCTAssertNil(placeholder.contentHTML)
		XCTAssertNil(placeholder.summary)
		XCTAssertNil(placeholder.authors)
		XCTAssertNil(placeholder.lastPrefaceFetchDate)

		// 2. Mock fetch with rich metadata
		let sampleHTML = Self.sampleWorkHTML(
			workID: "99999",
			title: "Polite Request fic",
			author: "NectarAuthor",
			summary: "A story about batch pacing.",
			fandom: "Test Fandom",
			chapters: "2/5"
		)

		await queue.setCustomFetchHandlerForTesting { url in
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (sampleHTML.data(using: .utf8), response)
		}

		// 3. Enqueue and wait
		await queue.enqueue(workIDs: ["99999"], accountID: account.accountID, feedID: placeholder.feedID)

		while await queue.isDraining {
			try await Task.sleep(nanoseconds: 20_000_000)
		}

		// 4. Verify SQLite record was updated with metadata
		let articlesAfter = await account.fetchArticlesAsync(bookKeys: ["ao3-work:99999"])
		let updated = try XCTUnwrap(articlesAfter.first)

		XCTAssertEqual(updated.title, "Polite Request fic")
		XCTAssertEqual(updated.summary, "<p>A story about batch pacing.</p>")
		XCTAssertEqual(updated.authors?.first?.name, "NectarAuthor")
		XCTAssertEqual(updated.fandoms, ["Test Fandom"])
		XCTAssertEqual(updated.chapterCurrent, 2)
		XCTAssertEqual(updated.chapterTotal, 5)
		XCTAssertEqual(updated.isComplete, false)
		XCTAssertNotNil(updated.lastPrefaceFetchDate)

		// Invariant: full chapter prose must NEVER be scraped or stored in batch import
		XCTAssertNil(updated.contentHTML)
	}

	// MARK: - Progress Notification

	func testProgressNotificationPosted() async throws {
		let queue = AO3ImportMetadataQueue(delayBetweenRequests: 0.01)
		let tracker = TestProgressTracker()
		let expectation = expectation(description: "Progress completed")
		expectation.assertForOverFulfill = false

		let token = NotificationCenter.default.addObserver(
			forName: AO3ImportMetadataQueue.progressNotification,
			object: nil,
			queue: .main
		) { notification in
			if let userInfo = notification.userInfo,
			   let completed = userInfo[AO3ImportMetadataQueue.progressCompletedKey] as? Int,
			   let total = userInfo[AO3ImportMetadataQueue.progressTotalKey] as? Int {
				Task {
					await tracker.addEvent(completed: completed, total: total, expectation: expectation)
				}
			}
		}

		defer { NotificationCenter.default.removeObserver(token) }

		await queue.setCustomFetchHandlerForTesting { url in
			let html = Self.sampleWorkHTML(workID: "1", title: "Title", chapters: "1/1")
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (html.data(using: .utf8), response)
		}

		await queue.enqueue(workIDs: ["501", "502"], accountID: account.accountID, feedID: Account.importedLinksFeedURL)

		await fulfillment(of: [expectation], timeout: 5.0)
		let events = await tracker.events
		XCTAssertFalse(events.isEmpty)
	}

	// MARK: - Test Fixture Helper

	nonisolated private static func sampleWorkHTML(
		workID: String,
		title: String,
		author: String = "TestAuthor",
		summary: String = "Test summary",
		fandom: String = "Test Fandom",
		chapters: String = "1/1"
	) -> String {
		"""
		<!DOCTYPE html>
		<html>
		<head><title>\(title) - \(author) - Archive of Our Own</title></head>
		<body>
		<div class="wrapper">
		  <dl class="work meta group">
		    <dt class="rating tags">Rating:</dt>
		    <dd class="rating tags"><ul class="commas"><li><a class="tag" href="/tags/General/works">General</a></li></ul></dd>
		    <dt class="warning tags">Archive Warning:</dt>
		    <dd class="warning tags"><ul class="commas"><li><a class="tag" href="/tags/No%20Warnings/works">No Archive Warnings Apply</a></li></ul></dd>
		    <dt class="fandom tags">Fandom:</dt>
		    <dd class="fandom tags"><ul class="commas"><li><a class="tag" href="/tags/\(fandom)/works">\(fandom)</a></li></ul></dd>
		    <dt class="stats">Stats:</dt>
		    <dd class="stats">
		      <dl class="stats">
		        <dt class="published">Published:</dt><dd class="published">2026-10-01</dd>
		        <dt class="words">Words:</dt><dd class="words">1,234</dd>
		        <dt class="chapters">Chapters:</dt><dd class="chapters">\(chapters)</dd>
		        <dt class="kudos">Kudos:</dt><dd class="kudos">42</dd>
		        <dt class="hits">Hits:</dt><dd class="hits">100</dd>
		      </dl>
		    </dd>
		  </dl>
		</div>
		<div id="workskin">
		  <div class="preface group">
		    <h2 class="title heading">\(title)</h2>
		    <h3 class="byline heading"><a rel="author" href="/users/\(author)">\(author)</a></h3>
		    <div class="summary module">
		      <h3 class="heading">Summary:</h3>
		      <blockquote class="userstuff"><p>\(summary)</p></blockquote>
		    </div>
		  </div>
		  <div id="chapters" role="article">
		    <div class="userstuff module" role="article"><p>Chapter prose that must not be stored.</p></div>
		  </div>
		</div>
		</body>
		</html>
		"""
	}
}

private enum AO3RateLimitTestBridge {
	@MainActor static func clearCooldowns() {
		for host in AO3Link.recognizedHosts {
			Downloader.shared.clearCooldown(forHost: host)
		}
	}
}
