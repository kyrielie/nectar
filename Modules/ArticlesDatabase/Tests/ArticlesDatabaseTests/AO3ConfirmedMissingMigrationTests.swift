//
//  AO3ConfirmedMissingMigrationTests.swift
//  ArticlesDatabaseTests
//
//  Baseline schema v2 initialization, migration from v1, and persistence.
//

import Testing
import Foundation
import RSParser
import Articles
import RSDatabaseObjC
@testable import ArticlesDatabase

@Suite("ArticlesDatabase schema v2 baseline and migration")
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

	@Test("a fresh database initializes at version 2 with complete schema")
	func initializesAtVersion2() async throws {
		let path = makeTemporaryPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		let db = open(path)
		#expect(try readUserVersion(path: path) == 2)

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

	@Test("a database reopens cleanly and preserves flags at version 2")
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
		#expect(try readUserVersion(path: path) == 2)
	}

	@Test("migrating a v1 database to v2 upgrades search table to FTS5")
	func migratesV1ToV2() async throws {
		let path = makeTemporaryPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		// Simulate legacy v1 database:
		do {
			let database = try #require(FMDatabase(path: path))
			try #require(database.open())
			database.executeStatements("CREATE TABLE articles (articleID TEXT PRIMARY KEY, feedID TEXT, uniqueID TEXT, searchRowID INTEGER);")
			database.executeStatements("CREATE VIRTUAL TABLE search USING fts4(title, body);")
			database.executeStatements("INSERT INTO articles VALUES('a1', 'f1', 'u1', 1);")
			database.executeStatements("INSERT INTO search (rowid, title, body) VALUES(1, 'Test Title', 'Test Body');")
			database.setUserVersion(1)
			database.close()
		}

		// Open with ArticlesDatabase (runs v1 -> v2 migration):
		_ = open(path)
		#expect(try readUserVersion(path: path) == 2)

		// Verify search table is now FTS5:
		let database = try #require(FMDatabase(path: path))
		try #require(database.open())
		defer { database.close() }
		guard let resultSet = database.executeQuery("SELECT sql FROM sqlite_master WHERE name='search';", withArgumentsIn: []) else {
			Issue.record("Failed to query sqlite_master for search table")
			return
		}
		if resultSet.next() {
			let sql = resultSet.swiftString(forColumn: "sql") ?? ""
			#expect(sql.lowercased().contains("fts5"))
		} else {
			Issue.record("search table not found in sqlite_master")
		}
	}
}
