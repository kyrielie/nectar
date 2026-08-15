//
//  AO3PrefetchQueueTests.swift
//  AccountTests
//
//  Nectar AO3 direct-reading support -- coverage for AO3PrefetchQueue,
//  the pacing/bounding actor behind AO3PrefetchNewWorksPreference's
//  opt-in "fetch new works immediately" path.
//
//  AO3PrefetchQueue.shared is a process-lifetime singleton, same as
//  AO3ChapterFetcher.shared -- every test calls resetForTesting() in
//  setUp/tearDown so pending/countThisCycle/pacing don't leak between
//  tests depending on run order, and every fixture Article below uses a
//  unique workID per call for the same reason AO3ChapterFetcherTests'
//  makeArticle does (AO3ChapterFetcher.shared.attemptDates is keyed by
//  articleID and is itself a process-lifetime singleton).
//
//  Real pacing (AO3ChapterFetcher.secondsBetweenAO3PagedRequests, 5s)
//  would make the budget-cap tests below take well over a minute, so
//  every test shrinks it via setPacingIntervalForTesting(_:) before
//  enqueueing -- the cap itself (20/cycle) is not testing-overridable,
//  since it's the actual behavior under test.
//

import XCTest
import RSWeb
import Articles
@testable import Account

final class AO3PrefetchQueueTests: XCTestCase {

	override func setUp() async throws {
		TestingURLProtocol.reset()
		await AO3PrefetchQueue.shared.resetForTesting()
	}

	override func tearDown() async throws {
		TestingURLProtocol.reset()
		await AO3PrefetchQueue.shared.resetForTesting()
	}

	// MARK: - Basic wiring: enqueue actually fetches

	/// Confirms enqueue's fire-and-forget drain Task really calls
	/// AO3ChapterFetcher.shared.fetchIfNeeded for each article, via the
	/// same TestingURLProtocol.requestedURLs seam
	/// AO3ChapterFetcherTests.testFetchIfNeededStillFetchesReadArticle
	/// uses, rather than asserting on countThisCycleForTesting() alone
	/// -- that only proves the queue's own bookkeeping advanced, not
	/// that a real request went out.
	func testEnqueueFetchesEachArticle() async throws {
		await AO3PrefetchQueue.shared.setPacingIntervalForTesting(0.01)
		let workIDs = (1...3).map { _ in "prefetch-\(UUID().uuidString)" }
		let articles = workIDs.map { Self.makeArticle(ao3WorkID: $0) }

		await AO3PrefetchQueue.shared.enqueue(articles)
		try await Self.waitUntilDrained()

		for workID in workIDs {
			XCTAssertTrue(TestingURLProtocol.requestedURLs.contains {
				$0.absoluteString.contains("archiveofourown.org/works/\(workID)")
			}, "expected a request for workID \(workID)")
		}
	}

	/// Non-AO3 articles (no resolvable ao3WorkID) would already be
	/// filtered out by LocalAccountRefresher before reaching enqueue --
	/// this locks down that fetchIfNeeded's own guard (not the queue's)
	/// is still what actually protects against one slipping through, in
	/// case that filtering is ever accidentally dropped upstream.
	func testEnqueueWithNonAO3ArticleFetchesNothing() async throws {
		await AO3PrefetchQueue.shared.setPacingIntervalForTesting(0.01)
		let article = Self.makeArticle(ao3WorkID: nil, bookKeyOverride: "ao3-series:12345")

		await AO3PrefetchQueue.shared.enqueue([article])
		try await Self.waitUntilDrained()

		XCTAssertTrue(TestingURLProtocol.requestedURLs.isEmpty)
	}

	// MARK: - Per-cycle budget

	func testEnqueueBeyondBudgetDropsRemainderInSameCycle() async throws {
		await AO3PrefetchQueue.shared.setPacingIntervalForTesting(0.001)
		let articles = (1...25).map { _ in Self.makeArticle(ao3WorkID: "prefetch-\(UUID().uuidString)") }

		await AO3PrefetchQueue.shared.enqueue(articles)
		try await Self.waitUntilDrained()

		let count = await AO3PrefetchQueue.shared.countThisCycleForTesting()
		XCTAssertEqual(count, 20)
		let pending = await AO3PrefetchQueue.shared.pendingCountForTesting()
		XCTAssertEqual(pending, 0, "articles past the budget should be dropped, not left queued")
	}

	func testResetForNewRefreshCycleRenewsBudget() async throws {
		await AO3PrefetchQueue.shared.setPacingIntervalForTesting(0.001)
		let firstBatch = (1...20).map { _ in Self.makeArticle(ao3WorkID: "prefetch-\(UUID().uuidString)") }
		await AO3PrefetchQueue.shared.enqueue(firstBatch)
		try await Self.waitUntilDrained()
		var count = await AO3PrefetchQueue.shared.countThisCycleForTesting()
		XCTAssertEqual(count, 20)

		// A 21st article in the same cycle should be dropped -- budget's exhausted.
		let overflowArticle = Self.makeArticle(ao3WorkID: "prefetch-\(UUID().uuidString)")
		await AO3PrefetchQueue.shared.enqueue([overflowArticle])
		try await Self.waitUntilDrained()
		XCTAssertFalse(TestingURLProtocol.requestedURLs.contains {
			$0.absoluteString.contains(overflowArticle.bookKey)
		})

		// Simulates LocalAccountRefresher.refreshFeeds starting a new
		// top-level pass.
		await AO3PrefetchQueue.shared.resetForNewRefreshCycle()
		count = await AO3PrefetchQueue.shared.countThisCycleForTesting()
		XCTAssertEqual(count, 0)

		let secondCycleArticle = Self.makeArticle(ao3WorkID: "prefetch-\(UUID().uuidString)")
		await AO3PrefetchQueue.shared.enqueue([secondCycleArticle])
		try await Self.waitUntilDrained()
		count = await AO3PrefetchQueue.shared.countThisCycleForTesting()
		XCTAssertEqual(count, 1)
	}

	// MARK: - Helpers

	/// Polls pendingCountForTesting() until the queue's drain loop has
	/// worked through everything enqueued so far, rather than a fixed
	/// sleep -- pacingInterval varies per test above, and a fixed sleep
	/// long enough for the 25-article budget test would be needlessly
	/// slow for the 3-article ones.
	private static func waitUntilDrained(timeout: TimeInterval = 5.0) async throws {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			let pending = await AO3PrefetchQueue.shared.pendingCountForTesting()
			let isDraining = await AO3PrefetchQueue.shared.isDrainingForTesting()
			if pending == 0, !isDraining {
				return
			}
			try await Task.sleep(nanoseconds: 5_000_000)
		}
		XCTFail("AO3PrefetchQueue did not finish draining within \(timeout)s")
	}

	private static func makeArticle(ao3WorkID: String?, bookKeyOverride: String? = nil) -> Article {
		let articleID = "test-article-id-\(UUID().uuidString)"
		let status = ArticleStatus(articleID: articleID, read: false, starred: false, dateArrived: Date())
		let bookKey: String = bookKeyOverride ?? ao3WorkID.map { "ao3-work:\($0)" } ?? "ao3-series:unused"
		let url = ao3WorkID.map { "https://archiveofourown.org/works/\($0)" }
		return Article(
			accountID: "test-account-id",
			articleID: articleID,
			feedID: "test-feed-id",
			uniqueID: "test-unique-id-\(articleID)",
			title: "Test Work",
			contentHTML: nil,
			contentText: nil,
			markdown: nil,
			url: url,
			externalURL: nil,
			summary: "A test summary.",
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			bookKey: bookKey,
			status: status
		)
	}
}
