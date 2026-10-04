//
//  WordCountRegressionFlagTests.swift
//  ArticlesDatabaseTests
//
//  Lifecycle of wordCountRegressionFlaggedAt: set by a feed-derived word
//  count drop, cleared by resolving a pending update either way, and
//  cleared directly by clearWordCountRegressionFlagAsync.
//

import Testing
import Foundation
import RSParser
import Articles
@testable import ArticlesDatabase

@Suite("wordCountRegressionFlaggedAt lifecycle")
@MainActor
struct WordCountRegressionFlagTests {

	private static let feedID = "feed-1"
	private static let feedURL = "https://example.com/feed"

	/// Stores an article, then re-imports it with a large word count drop
	/// so the feed-derived regression flag is set. Returns the articleID.
	private func makeFlaggedArticle(_ db: ArticlesDatabase) async throws -> String {
		let first = TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: Self.feedURL, wordCount: 5000)
		_ = await db.updateAsync(parsedItems: [first], feedID: Self.feedID, deleteOlder: false)
		let articleID = Article.calculatedArticleID(feedID: Self.feedID, uniqueID: "u1")

		let second = TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: Self.feedURL, wordCount: 100)
		_ = await db.updateAsync(parsedItems: [second], feedID: Self.feedID, deleteOlder: false)

		let articles = await db.fetchArticlesAsync(articleIDs: [articleID])
		try #require(articles.first?.wordCountRegressionFlaggedAt != nil)
		return articleID
	}

	@Test("resolving a pending update with accept clears the flag")
	func resolveAcceptClearsFlag() async throws {
		let db = TestFixtures.makeDatabase()
		let articleID = try await makeFlaggedArticle(db)
		await db.setPendingContentUpdateAsync("<p>pending</p>", detectedAt: Date(), articleID: articleID)

		await db.resolvePendingContentUpdateAsync(articleID: articleID, accept: true)

		let article = try #require(await db.fetchArticlesAsync(articleIDs: [articleID]).first)
		#expect(article.wordCountRegressionFlaggedAt == nil)
		#expect(article.pendingUpdateContentHTML == nil)
	}

	@Test("resolving a pending update with keep clears the flag")
	func resolveKeepClearsFlag() async throws {
		let db = TestFixtures.makeDatabase()
		let articleID = try await makeFlaggedArticle(db)
		await db.setPendingContentUpdateAsync("<p>pending</p>", detectedAt: Date(), articleID: articleID)

		await db.resolvePendingContentUpdateAsync(articleID: articleID, accept: false)

		let article = try #require(await db.fetchArticlesAsync(articleIDs: [articleID]).first)
		#expect(article.wordCountRegressionFlaggedAt == nil)
		#expect(article.pendingUpdateContentHTML == nil)
	}

	@Test("clearWordCountRegressionFlagAsync clears only the flag")
	func directClear() async throws {
		let db = TestFixtures.makeDatabase()
		let articleID = try await makeFlaggedArticle(db)
		await db.setPendingContentUpdateAsync("<p>pending</p>", detectedAt: Date(), articleID: articleID)

		await db.clearWordCountRegressionFlagAsync(articleID: articleID)

		let article = try #require(await db.fetchArticlesAsync(articleIDs: [articleID]).first)
		#expect(article.wordCountRegressionFlaggedAt == nil)
		#expect(article.pendingUpdateContentHTML != nil)
	}
}
