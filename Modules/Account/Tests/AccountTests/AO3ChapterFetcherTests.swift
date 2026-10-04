//
//  AO3ChapterFetcherTests.swift
//  AccountTests
//
//  Nectar AO3 direct-reading support, Workstream 2 test coverage.
//
//  Pure policy (isStale, workID/bookKey mapping, network-allowed gate,
//  detectRegression, rebuildParsedItem) moved to AO3KitTests'
//  AO3FetchPolicyTests along with AO3FetchPolicy. What stays here is
//  orchestration: fetchIfNeeded's gating and anthology note, using
//  TestingURLProtocol.requestedURLs (populated regardless of whether a
//  canned response is registered) just to confirm a request went out,
//  without exercising the rest of the download/extraction pipeline.
//

import XCTest
import os
import RSParser
import RSWeb
import Articles
import AO3Kit
@testable import Account

final class AO3ChapterFetcherTests: XCTestCase {

	override func setUp() {
		TestingURLProtocol.reset()
	}

	override func tearDown() {
		TestingURLProtocol.reset()
	}

	// MARK: - Anthology / combined-series bookKeys (fetchIfNeeded)

	/// A combined-series article never resolves an ao3WorkID (covered
	/// above), so fetchIfNeeded can't make a request for it -- this
	/// confirms that no longer means total silence: it should post
	/// .ao3ChapterFetchDidFail with an explanatory message exactly once.
	func testFetchIfNeededNotesAnthologyBookKeyInsteadOfSilentNoOp() {
		let article = Self.makeArticle(contentHTML: nil, chapterCurrent: nil, ao3WorkID: nil, bookKeyOverride: "ao3-series:4242-\(UUID().uuidString)")
		let expectation = XCTNSNotificationExpectation(name: .ao3ChapterFetchDidFail, object: nil, notificationCenter: .default)

		AO3ChapterFetcher.shared.fetchIfNeeded(for: article)

		wait(for: [expectation], timeout: 1.0)
		XCTAssertEqual(
			AO3ChapterFetcher.shared.lastFetchFailureMessage(forArticleID: article.articleID),
			"Combined AO3 series can't be refreshed individually -- showing imported content"
		)
	}

	/// Calling fetchIfNeeded a second time for the same anthology article
	/// must not post a second notification -- it's a one-time note, not a
	/// recurring failure, so it shouldn't behave like the download-retry
	/// path's per-attempt gate.
	func testFetchIfNeededNotesAnthologyBookKeyOnlyOnce() {
		let article = Self.makeArticle(contentHTML: nil, chapterCurrent: nil, ao3WorkID: nil, bookKeyOverride: "calibre-series:Once Only \(UUID().uuidString)")
		let firstExpectation = XCTNSNotificationExpectation(name: .ao3ChapterFetchDidFail, object: nil, notificationCenter: .default)
		AO3ChapterFetcher.shared.fetchIfNeeded(for: article)
		wait(for: [firstExpectation], timeout: 1.0)

		let secondExpectation = XCTNSNotificationExpectation(name: .ao3ChapterFetchDidFail, object: nil, notificationCenter: .default)
		secondExpectation.isInverted = true
		AO3ChapterFetcher.shared.fetchIfNeeded(for: article)
		wait(for: [secondExpectation], timeout: 0.5)
	}

	// MARK: - fetchIfNeeded(for:) short-circuit

	func testFetchIfNeededGateForNonAO3BookKey() {
		// bookKey resolves to the plain uniqueID here since no ao3WorkID is
		// set -- confirms fetchIfNeeded's ao3WorkID(fromBookKey:) gate (not
		// just isStale) is what should prevent a fetch attempt.
		// fetchIfNeeded itself is fire-and-forget with no return value to
		// assert against directly (Downloader isn't mockable here — see the
		// file header), so this test documents and locks down the gate it
		// relies on rather than asserting on network behavior.
		let article = Self.makeArticle(contentHTML: nil, chapterCurrent: nil, ao3WorkID: nil)
		XCTAssertNil(AO3FetchPolicy.workID(fromBookKey: article.bookKey))
	}

	/// Locks down the read-state fix: a read, stale, eligible article must
	/// still trigger a network request from fetchIfNeeded, not be silently
	/// dropped the way the old `!article.status.read` guard used to drop
	/// it. Uses TestingURLProtocol.requestedURLs (populated for every
	/// request regardless of whether a canned response is registered for
	/// it) rather than asserting on the fetch's outcome, since this test
	/// only cares whether a request was attempted at all.
	func testFetchIfNeededStillFetchesReadArticle() {
		let workID = Self.uniqueWorkID()
		let article = Self.makeArticle(contentHTML: nil, chapterCurrent: 3, ao3WorkID: workID, read: true)
		let expectation = XCTNSNotificationExpectation(name: .ao3ChapterFetchDidFail, object: nil, notificationCenter: .default)

		AO3ChapterFetcher.shared.fetchIfNeeded(for: article)

		wait(for: [expectation], timeout: 2.0)
		XCTAssertTrue(TestingURLProtocol.requestedURLs.contains { $0.absoluteString.contains("archiveofourown.org/works/\(workID)") })
	}

	// MARK: - Fixtures

	/// AO3Link.workURL(id:...) requires an ASCII-digits-only id (see
	/// AO3LinkTests.buildersRejectMalformedIDs) -- a bare UUID string
	/// fails that guard and silently short-circuits
	/// AO3ChapterFetcher.download before any request goes out. Used where
	/// a test needs a workID distinct from the "999" default (e.g. so it
	/// doesn't collide with Downloader's own URL-keyed request/response
	/// cache across tests).
	private static let workIDCounter = OSAllocatedUnfairLock(initialState: 0)

	private static func uniqueWorkID() -> String {
		let next = workIDCounter.withLock { count -> Int in
			count += 1
			return count
		}
		return "800000\(next)"
	}

	private static func makeArticle(contentHTML: String?, chapterCurrent: Int?, ao3WorkID: String? = "999", isAmbrosiaItem: Bool = false, lastPrefaceFetchDate: Date? = nil, pendingUpdateContentHTML: String? = nil, wordCountRegressionFlaggedAt: Date? = nil, ao3ConfirmedMissingAt: Date? = nil, bookKeyOverride: String? = nil, summary: String? = "A test summary.", authors: Set<Author>? = nil, datePublished: Date? = nil, dateModified: Date? = nil, fandoms: [String]? = nil, additionalTags: [String]? = nil, read: Bool = false) -> Article {
		// Unique per call -- AO3ChapterFetcher.shared.attemptDates is a
		// process-lifetime singleton cache keyed by articleID, so reusing a
		// fixed ID across tests leaks already-noted/already-attempted state
		// from one test into another depending on run order.
		let articleID = "test-article-id-\(UUID().uuidString)"
		let status = ArticleStatus(articleID: articleID, read: read, starred: false, dateArrived: Date())
		let bookKey: String? = bookKeyOverride ?? ao3WorkID.map { "ao3-work:\($0)" }
		return Article(
			accountID: "test-account-id",
			articleID: articleID,
			feedID: "test-feed-id",
			uniqueID: "test-unique-id",
			title: "Test Work",
			contentHTML: contentHTML,
			contentText: nil,
			markdown: nil,
			url: "https://archiveofourown.org/works/999",
			externalURL: nil,
			summary: summary,
			imageURL: nil,
			datePublished: datePublished,
			dateModified: dateModified,
			authors: authors,
			chapterCurrent: chapterCurrent,
			fandoms: fandoms,
			additionalTags: additionalTags,
			lastPrefaceFetchDate: lastPrefaceFetchDate,
			pendingUpdateContentHTML: pendingUpdateContentHTML,
			wordCountRegressionFlaggedAt: wordCountRegressionFlaggedAt,
			ao3ConfirmedMissingAt: ao3ConfirmedMissingAt,
			isAmbrosiaItem: isAmbrosiaItem,
			bookKey: bookKey,
			status: status
		)
	}
}
