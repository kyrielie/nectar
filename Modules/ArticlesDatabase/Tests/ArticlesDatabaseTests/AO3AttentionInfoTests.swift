//
//  AO3AttentionInfoTests.swift
//  ArticlesDatabaseTests
//
//  fetchAO3AttentionInfo: which articles the Works Needing Attention
//  screen lists, what each row carries, and in what order.
//

import Testing
import Foundation
import RSParser
import Articles
@testable import ArticlesDatabase

@Suite("fetchAO3AttentionInfo")
@MainActor
struct AO3AttentionInfoTests {

	private static let feedID = "feed-1"
	private static let feedURL = "https://example.com/feed"

	private static func articleID(_ uniqueID: String) -> String {
		Article.calculatedArticleID(feedID: feedID, uniqueID: uniqueID)
	}

	@discardableResult
	private func store(_ db: ArticlesDatabase, uniqueID: String, title: String? = nil, contentHTML: String? = "<p>content</p>", wordCount: Int? = nil) async -> String {
		let item = TestFixtures.makeParsedItem(uniqueID: uniqueID, feedURL: Self.feedURL, title: title ?? "Title \(uniqueID)", contentHTML: contentHTML, wordCount: wordCount)
		_ = await db.updateAsync(parsedItems: [item], feedID: Self.feedID, deleteOlder: false)
		return Self.articleID(uniqueID)
	}

	/// Stores an article, then re-imports it with a large word count drop so
	/// the feed-derived regression flag is set.
	private func storeRegressionFlagged(_ db: ArticlesDatabase, uniqueID: String) async throws -> String {
		await store(db, uniqueID: uniqueID, wordCount: 5000)
		let id = await store(db, uniqueID: uniqueID, wordCount: 100)
		let article = try #require(await db.fetchArticlesAsync(articleIDs: [id]).first)
		try #require(article.wordCountRegressionFlaggedAt != nil)
		return id
	}

	@Test("an unflagged database lists nothing")
	func emptyWhenNothingIsFlagged() async {
		let db = TestFixtures.makeDatabase()
		await store(db, uniqueID: "u1")

		let info = await db.fetchAO3AttentionInfo(limit: 50)

		#expect(info.isEmpty)
	}

	@Test("a pending update is listed with hasPendingUpdate and its date")
	func pendingUpdateIsListed() async throws {
		let db = TestFixtures.makeDatabase()
		let id = await store(db, uniqueID: "u1", title: "Pending Work")
		await store(db, uniqueID: "other")
		let detectedAt = Date().addingTimeInterval(-3600)
		await db.setPendingContentUpdateAsync("<p>new</p>", detectedAt: detectedAt, articleID: id)

		let info = await db.fetchAO3AttentionInfo(limit: 50)

		#expect(info.count == 1)
		let row = try #require(info.first)
		#expect(row.articleID == id)
		#expect(row.title == "Pending Work")
		#expect(row.hasPendingUpdate)
		#expect(abs((row.pendingUpdateDetectedAt ?? .distantPast).timeIntervalSince(detectedAt)) < 1)
		#expect(row.ao3ConfirmedMissingAt == nil)
	}

	@Test("a regression flag alone is listed with hasPendingUpdate false")
	func regressionFlagAloneIsListed() async throws {
		let db = TestFixtures.makeDatabase()
		let id = try await storeRegressionFlagged(db, uniqueID: "u1")

		let info = await db.fetchAO3AttentionInfo(limit: 50)

		let row = try #require(info.first)
		#expect(info.count == 1)
		#expect(row.articleID == id)
		#expect(row.wordCountRegressionFlaggedAt != nil)
		#expect(!row.hasPendingUpdate)
		#expect(row.pendingUpdateDetectedAt == nil)
	}

	@Test("a confirmed-missing article with no stored content is listed")
	func missingArticleWithoutContentIsListed() async throws {
		let db = TestFixtures.makeDatabase()
		let id = await store(db, uniqueID: "u1", contentHTML: nil)
		await db.setAO3ConfirmedMissingAsync(articleID: id)

		let info = await db.fetchAO3AttentionInfo(limit: 50)

		let row = try #require(info.first)
		#expect(info.count == 1)
		#expect(row.articleID == id)
		#expect(row.ao3ConfirmedMissingAt != nil)
		#expect(!row.hasPendingUpdate)
	}

	@Test("rows are ordered newest first across the three flags")
	func orderedNewestFirst() async {
		let db = TestFixtures.makeDatabase()
		let olderPending = await store(db, uniqueID: "older")
		let newerPending = await store(db, uniqueID: "newer")
		let missing = await store(db, uniqueID: "missing")
		await db.setPendingContentUpdateAsync("<p>a</p>", detectedAt: Date().addingTimeInterval(-300), articleID: olderPending)
		await db.setPendingContentUpdateAsync("<p>b</p>", detectedAt: Date().addingTimeInterval(-100), articleID: newerPending)
		await db.setAO3ConfirmedMissingAsync(articleID: missing)

		let info = await db.fetchAO3AttentionInfo(limit: 50)

		#expect(info.map(\.articleID) == [missing, newerPending, olderPending])
	}

	@Test("limit caps the row count and keeps the newest")
	func limitKeepsTheNewest() async {
		let db = TestFixtures.makeDatabase()
		let older = await store(db, uniqueID: "older")
		let newer = await store(db, uniqueID: "newer")
		await db.setPendingContentUpdateAsync("<p>a</p>", detectedAt: Date().addingTimeInterval(-300), articleID: older)
		await db.setPendingContentUpdateAsync("<p>b</p>", detectedAt: Date().addingTimeInterval(-100), articleID: newer)

		let info = await db.fetchAO3AttentionInfo(limit: 1)

		#expect(info.map(\.articleID) == [newer])
	}

	@Test("clearing a flag removes the article from the list")
	func clearedFlagsDropOut() async {
		let db = TestFixtures.makeDatabase()
		let id = await store(db, uniqueID: "u1")
		await db.setAO3ConfirmedMissingAsync(articleID: id)
		#expect(await db.fetchAO3AttentionInfo(limit: 50).count == 1)

		await db.clearAO3ConfirmedMissingAsync(articleID: id)

		#expect(await db.fetchAO3AttentionInfo(limit: 50).isEmpty)
	}

	@Test("an article with several flags appears once")
	func multipleFlagsAppearOnce() async throws {
		let db = TestFixtures.makeDatabase()
		let id = try await storeRegressionFlagged(db, uniqueID: "u1")
		await db.setPendingContentUpdateAsync("<p>pending</p>", detectedAt: Date(), articleID: id)
		await db.setAO3ConfirmedMissingAsync(articleID: id)

		let info = await db.fetchAO3AttentionInfo(limit: 50)

		let row = try #require(info.first)
		#expect(info.count == 1)
		#expect(row.hasPendingUpdate)
		#expect(row.wordCountRegressionFlaggedAt != nil)
		#expect(row.ao3ConfirmedMissingAt != nil)
	}
}
