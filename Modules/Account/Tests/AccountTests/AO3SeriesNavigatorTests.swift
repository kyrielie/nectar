//
//  AO3SeriesNavigatorTests.swift
//  AccountTests
//
//  Nectar remediation plan, Part 1.3: coverage for AO3SeriesNavigator
//  (Task 10's prev/next/first navigation), previously untested despite
//  shipping with a five-case public error enum.
//
//  Same limitation AO3ChapterFetcherTests documents: Downloader.shared and
//  AO3ChapterFetcher.shared.download are concrete singletons with no
//  injected seam, so the network-dependent paths --
//  .emptySeriesListing/.networkError/.fetchFailed, and the success path --
//  can't be exercised here. This covers what's actually reachable without
//  a network call: fetchAdjacentWork's/fetchFirstWorkInSeries's early
//  guards, both of which return before AO3SeriesNavigator ever touches
//  Downloader or AO3ChapterFetcher (AO3SeriesNavigator.swift:62-67, 85-88).
//  Flagged here rather than silently narrowed to "whatever's easy": a real
//  test of the success/network-error paths needs that seam built first,
//  the same gap AO3ChapterFetcherTests already calls out.
//

import XCTest
import Articles
@testable import Account

@MainActor final class AO3SeriesNavigatorTests: XCTestCase {

	private var account: Account!

	override func setUp() async throws {
		account = TestAccountManager.shared.createAccount(type: .onMyMac)
	}

	override func tearDown() async throws {
		TestAccountManager.shared.deleteAccount(account)
		account = nil
	}

	// MARK: - fetchAdjacentWork: .noAdjacentWork

	func testFetchPreviousWorkWithNilPreviousWorkURLFailsWithNoAdjacentWork() async {
		let article = Self.makeArticle(previousWorkURL: nil, nextWorkURL: "https://archiveofourown.org/works/456")

		let result = await AO3SeriesNavigator.fetchAdjacentWork(direction: .previous, from: article, account: account)

		switch result {
		case .success:
			XCTFail("Expected .noAdjacentWork, got success")
		case .failure(let error):
			guard case .noAdjacentWork = error else {
				return XCTFail("Expected .noAdjacentWork, got \(error)")
			}
		}
	}

	func testFetchNextWorkWithNilNextWorkURLFailsWithNoAdjacentWork() async {
		let article = Self.makeArticle(previousWorkURL: "https://archiveofourown.org/works/123", nextWorkURL: nil)

		let result = await AO3SeriesNavigator.fetchAdjacentWork(direction: .next, from: article, account: account)

		switch result {
		case .success:
			XCTFail("Expected .noAdjacentWork, got success")
		case .failure(let error):
			guard case .noAdjacentWork = error else {
				return XCTFail("Expected .noAdjacentWork, got \(error)")
			}
		}
	}

	/// A malformed permalink AO3SummaryExtractor.ao3WorkID can't parse an
	/// ID out of takes the same .noAdjacentWork path as a nil URL --
	/// AO3SeriesNavigator.swift:63 guards both together in one condition.
	func testFetchAdjacentWorkWithUnparseablePermalinkFailsWithNoAdjacentWork() async {
		let article = Self.makeArticle(previousWorkURL: "https://example.com/not-an-ao3-work-url", nextWorkURL: nil)

		let result = await AO3SeriesNavigator.fetchAdjacentWork(direction: .previous, from: article, account: account)

		switch result {
		case .success:
			XCTFail("Expected .noAdjacentWork, got success")
		case .failure(let error):
			guard case .noAdjacentWork = error else {
				return XCTFail("Expected .noAdjacentWork, got \(error)")
			}
		}
	}

	// MARK: - fetchFirstWorkInSeries: .noSeriesID

	func testFetchFirstWorkInSeriesWithNilSeriesFailsWithNoSeriesID() async {
		let article = Self.makeArticle(series: nil)

		let result = await AO3SeriesNavigator.fetchFirstWorkInSeries(from: article, account: account)

		switch result {
		case .success:
			XCTFail("Expected .noSeriesID, got success")
		case .failure(let error):
			guard case .noSeriesID = error else {
				return XCTFail("Expected .noSeriesID, got \(error)")
			}
		}
	}

	/// Every series membership has a nil ao3ID (e.g. a Calibre-only
	/// series with no AO3 counterpart) -- same failure as no series at
	/// all, since fetchFirstWorkInSeries (AO3SeriesNavigator.swift:85)
	/// filters for a non-nil ao3ID specifically, not just series' presence.
	func testFetchFirstWorkInSeriesWithNoAO3SeriesIDFailsWithNoSeriesID() async {
		let article = Self.makeArticle(series: [ArticleSeriesEntry(name: "Calibre-only Series", index: 1, ao3ID: nil)])

		let result = await AO3SeriesNavigator.fetchFirstWorkInSeries(from: article, account: account)

		switch result {
		case .success:
			XCTFail("Expected .noSeriesID, got success")
		case .failure(let error):
			guard case .noSeriesID = error else {
				return XCTFail("Expected .noSeriesID, got \(error)")
			}
		}
	}

	/// A work in multiple series picks the first membership with a
	/// non-nil ao3ID (AO3SeriesNavigator.swift:79-83's documented "first
	/// one wins" rule) -- this confirms a nil-ao3ID entry ahead of a
	/// real one doesn't itself trigger .noSeriesID. Can't assert which
	/// series URL gets fetched without a Downloader seam, but this at
	/// least confirms the guard clears (doesn't fail synchronously) when
	/// a later entry has a usable ao3ID.
	func testFetchFirstWorkInSeriesSkipsNilAO3IDEntriesToFindALaterOne() async {
		let article = Self.makeArticle(series: [
			ArticleSeriesEntry(name: "Calibre-only Series", index: 1, ao3ID: nil),
			ArticleSeriesEntry(name: "The Real Series", index: 2, ao3ID: "9999")
		])

		let result = await AO3SeriesNavigator.fetchFirstWorkInSeries(from: article, account: account)

		// The .noSeriesID guard must have cleared -- whatever happens
		// next depends on a real network call this test can't make, but
		// it must not be .noSeriesID specifically.
		if case .failure(.noSeriesID) = result {
			XCTFail("Expected the noSeriesID guard to clear once a later entry has a non-nil ao3ID")
		}
	}
}

private extension AO3SeriesNavigatorTests {

	static func makeArticle(previousWorkURL: String? = nil, nextWorkURL: String? = nil, series: [ArticleSeriesEntry]? = nil) -> Article {
		let articleID = "test-article-id-\(UUID().uuidString)"
		let status = ArticleStatus(articleID: articleID, read: false, starred: false, dateArrived: Date())
		// fetchAdjacentWork (interim Phase 1/2 shim -- see the doc comment
		// on AO3SeriesNavigator.fetchAdjacentWork) now reads previous/next
		// off `series` entries, not the singular Article-level fields the
		// inline-series-navigation plan's Phase 1 removed. When a caller
		// below only wants to simulate a bare previous/next pair (not
		// exercising genuinely multi-series behavior), wrap it in one
		// synthetic ArticleSeriesEntry here so those call sites don't each
		// need to build their own `series` array by hand.
		let resolvedSeries: [ArticleSeriesEntry]?
		if let series {
			resolvedSeries = series
		} else if previousWorkURL != nil || nextWorkURL != nil {
			resolvedSeries = [ArticleSeriesEntry(name: "Test Series", index: 1, ao3ID: "1", previousWorkURL: previousWorkURL, nextWorkURL: nextWorkURL)]
		} else {
			resolvedSeries = nil
		}
		return Article(
			accountID: "test-account-id",
			articleID: articleID,
			feedID: "test-feed-id",
			uniqueID: "test-unique-id",
			title: "Test Work",
			contentHTML: nil,
			contentText: nil,
			markdown: nil,
			url: "https://archiveofourown.org/works/999",
			externalURL: nil,
			summary: "A test summary.",
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			series: resolvedSeries,
			bookKey: "ao3-work:999",
			status: status
		)
	}
}
