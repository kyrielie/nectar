//
//  AO3ConfirmedMissingMigrationTests.swift
//  ArticlesDatabaseTests
//
//  Baseline schema v1 initialization and persistence.
//

import Testing
import Foundation
import RSParser
import Articles
import RSDatabaseObjC
@testable import ArticlesDatabase

@Suite("ArticlesDatabase schema v1 baseline")
@MainActor
struct AO3ConfirmedMissingMigrationTests {

	private static let feedID = "feed-1"
	private static let feedURL = "https://example.com/feed"

	private func makeTemporaryPath() -> String {
		NSTemporaryDirectory() + "ao3-schema-baseline-\(UUID().uuidString).sqlite3"
	}

	private func open(_ path: String) -> ArticlesDatabase {
		ArticlesDatabase(databaseFilePath: path, accountID: "test-account", retentionStyle: .feedBased)
	}

	private func readUserVersion(path: String) throws -> UInt32 {
		let database = try #require(FMDatabase(path: path))
		try #require(database.open())
		defer { database.close() }
		return database.userVersion()
	}

	@Test("a fresh database initializes at version 1 with complete schema")
	func initializesAtVersion1() async throws {
		let path = makeTemporaryPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		let db = open(path)
		#expect(try readUserVersion(path: path) == 1)

		let articleID = Article.calculatedArticleID(feedID: Self.feedID, uniqueID: "u1")
		let item = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: Self.feedURL,
			wordCount: 1500,
			isRestricted: true,
			ao3Language: "English"
		)
		_ = await db.updateAsync(parsedItems: [item], feedID: Self.feedID, deleteOlder: false)

		let stored = try #require(await db.fetchArticlesAsync(articleIDs: [articleID]).first)
		#expect(stored.wordCount == 1500)
		#expect(stored.isRestricted == true)
		#expect(stored.language == "English")
	}

	@Test("a database reopens cleanly and preserves flags at version 1")
	func reopensPreservingData() async throws {
		let path = makeTemporaryPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		let articleID = Article.calculatedArticleID(feedID: Self.feedID, uniqueID: "u1")
		do {
			let db = open(path)
			let item = TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: Self.feedURL, wordCount: 100)
			_ = await db.updateAsync(parsedItems: [item], feedID: Self.feedID, deleteOlder: false)
			await db.setAO3ConfirmedMissingAsync(articleID: articleID)
			let flagged = try #require(await db.fetchArticlesAsync(articleIDs: [articleID]).first)
			try #require(flagged.ao3ConfirmedMissingAt != nil)
		}

		let reopened = open(path)
		let article = try #require(await reopened.fetchArticlesAsync(articleIDs: [articleID]).first)
		#expect(article.ao3ConfirmedMissingAt != nil)
		#expect(try readUserVersion(path: path) == 1)
	}
}
