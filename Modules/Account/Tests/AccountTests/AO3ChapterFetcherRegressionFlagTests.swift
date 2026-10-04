//
//  AO3ChapterFetcherRegressionFlagTests.swift
//  AccountTests
//
//  wordCountRegressionFlaggedAt lifecycle through AO3ChapterFetcher: a
//  successful non-regression fetch clears the flag; a regression fetch
//  leaves it set (the flag clears only when the pending update is
//  resolved).
//

import XCTest
import RSParser
import RSWeb
import Articles
import AO3Kit
@testable import Account

final class AO3ChapterFetcherRegressionFlagTests: XCTestCase {

	private static let workID = "87955347"
	private var account: Account!
	private var feedID: String!
	private var articleID: String!

	@MainActor override func setUp() async throws {
		TestingURLProtocol.reset()
		DownloadCache.shared.removeAll()
		account = TestAccountManager.shared.createAccount(type: .onMyMac)
		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/\(Self.workID)")
		let feed = try XCTUnwrap(account.existingFeed(withURL: Account.importedLinksFeedURL))
		feedID = feed.feedID
		articleID = Article.calculatedArticleID(feedID: feedID, uniqueID: Self.workID)
	}

	@MainActor override func tearDown() async throws {
		TestingURLProtocol.reset()
		TestAccountManager.shared.deleteAccount(account)
		account = nil
	}

	private func fixtureHTML() throws -> String {
		let url = try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("ao3-work-single-chapter.html")
		return try String(contentsOf: url, encoding: .utf8)
	}

	private func item(contentHTML: String, wordCount: Int) -> ParsedItem {
		ParsedItem(syncServiceID: nil, uniqueID: Self.workID, feedURL: feedID,
		           url: "https://archiveofourown.org/works/\(Self.workID)", externalURL: nil,
		           title: "Flag Test", language: nil, contentHTML: contentHTML,
		           contentText: nil, markdown: nil, summary: nil, imageURL: nil, bannerImageURL: nil,
		           datePublished: nil, dateModified: nil, authors: nil, tags: nil, attachments: nil,
		           wordCount: wordCount, ao3WorkID: Self.workID)
	}

	/// Stores `storedHTML`, then re-imports with a large feed word count
	/// drop so wordCountRegressionFlaggedAt is set.
	private func storeFlaggedArticle(storedHTML: String) async throws {
		_ = await account.updateAsync(feedID: feedID, parsedItems: [item(contentHTML: storedHTML, wordCount: 5000)], deleteOlder: false)
		_ = await account.updateAsync(feedID: feedID, parsedItems: [item(contentHTML: storedHTML, wordCount: 100)], deleteOlder: false)
		let article = try await XCTUnwrapAsync(await account.fetchArticlesAsync(.articleIDs([articleID])).first)
		XCTAssertNotNil(article.wordCountRegressionFlaggedAt)
	}

	private func XCTUnwrapAsync<T>(_ value: @autoclosure () async throws -> T?) async throws -> T {
		let resolved = try await value()
		return try XCTUnwrap(resolved)
	}

	private func runDownload() async {
		let completed = expectation(forNotification: .ao3ChapterFetchDidComplete, object: nil)
		AO3ChapterFetcher.shared.download(workID: Self.workID, articleID: articleID, accountID: account.accountID, feedID: feedID)
		await fulfillment(of: [completed], timeout: 5.0)
	}

	func testSuccessfulNonRegressionFetchClearsFlag() async throws {
		// Stored content matches the fixture, so the fetch is not a regression.
		try await storeFlaggedArticle(storedHTML: fixtureHTML())
		TestingURLProtocol.setResponse("archiveofourown.org/works/\(Self.workID)", file: "ao3-work-single-chapter.html")

		await runDownload()

		let article = try await XCTUnwrapAsync(await account.fetchArticlesAsync(.articleIDs([articleID])).first)
		XCTAssertNil(article.wordCountRegressionFlaggedAt)
		XCTAssertNil(article.pendingUpdateContentHTML)
	}

	func testRegressionFetchLeavesFlagSetAndStashesPendingUpdate() async throws {
		// Stored content claims far more words than the fixture, so the
		// fetch trips the content-level regression guard.
		let inflated = try fixtureHTML().replacingOccurrences(of: ">45</dd>", with: ">5000</dd>")
		XCTAssertNotEqual(inflated, try fixtureHTML(), "fixture word count marker not found")
		try await storeFlaggedArticle(storedHTML: inflated)
		TestingURLProtocol.setResponse("archiveofourown.org/works/\(Self.workID)", file: "ao3-work-single-chapter.html")

		await runDownload()

		let article = try await XCTUnwrapAsync(await account.fetchArticlesAsync(.articleIDs([articleID])).first)
		XCTAssertNotNil(article.wordCountRegressionFlaggedAt)
		XCTAssertNotNil(article.pendingUpdateContentHTML)
	}
}
