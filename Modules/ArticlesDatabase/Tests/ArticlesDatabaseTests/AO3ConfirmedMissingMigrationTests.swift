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

	@Test("a fresh database initializes at version 3 with complete schema")
	func initializesAtVersion3() async throws {
		let path = makeTemporaryPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		let db = open(path)
		#expect(try readUserVersion(path: path) == 3)

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

	@Test("a database reopens cleanly and preserves flags at version 3")
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
		#expect(try readUserVersion(path: path) == 3)
	}

	@Test("migrating a v1 database to v3 upgrades search table to FTS5")
	func migratesV1ToV3() async throws {
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

		// Open with ArticlesDatabase (runs v1 -> v3 migration):
		_ = open(path)
		#expect(try readUserVersion(path: path) == 3)

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

	@Test("reopening a v2 database missing isRestricted, language, and collections adds them cleanly")
	func repairsMissingAO3ColumnsInV2Database() async throws {
		let path = makeTemporaryPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		let articleID = Article.calculatedArticleID(feedID: Self.feedID, uniqueID: "stub-1")
		do {
			let db = open(path)
			let stub = TestFixtures.makeParsedItem(uniqueID: "stub-1", feedURL: Self.feedURL, contentHTML: nil)
			_ = await db.updateAsync(parsedItems: [stub], feedID: Self.feedID, deleteOlder: false)
		}

		// Simulate an older v2 database created before isRestricted/language/collections existed.
		do {
			let database = try #require(FMDatabase(path: path))
			try #require(database.open())
			database.executeStatements("ALTER TABLE articles DROP COLUMN isRestricted;")
			database.executeStatements("ALTER TABLE articles DROP COLUMN language;")
			database.executeStatements("ALTER TABLE articles DROP COLUMN collections;")
			database.close()
		}

		let repaired = open(path)
		let fullWork = TestFixtures.makeParsedItem(
			uniqueID: "stub-1",
			feedURL: Self.feedURL,
			contentHTML: "<p>Full chapter text</p>",
			isRestricted: false,
			ao3Language: "English",
			collections: [ParsedCollectionEntry(name: "Test Collection", slug: "test_collection")]
		)
		_ = await repaired.updateAsync(parsedItems: [fullWork], feedID: Self.feedID, deleteOlder: false)

		let stored = try #require(await repaired.fetchArticlesAsync(articleIDs: [articleID]).first)
		#expect(stored.contentHTML == "<p>Full chapter text</p>")
		#expect(stored.isRestricted == false)
		#expect(stored.language == "English")
		#expect(stored.collections == [ArticleCollectionEntry(name: "Test Collection", slug: "test_collection")])
	}

	@Test("migrating a database missing bookKey creates bookKey indexes after adding columns")
	func createsBookKeyIndexesAfterAddingMissingColumns() async throws {
		let path = makeTemporaryPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		do {
			let database = try #require(FMDatabase(path: path))
			try #require(database.open())
			database.executeStatements("CREATE TABLE articles (articleID TEXT NOT NULL PRIMARY KEY, feedID TEXT NOT NULL, uniqueID TEXT NOT NULL);")
			database.executeStatements("CREATE TABLE annotations (annotationID TEXT NOT NULL PRIMARY KEY, articleID TEXT NOT NULL);")
			database.setUserVersion(2)
			database.close()
		}

		_ = open(path)

		let database = try #require(FMDatabase(path: path))
		try #require(database.open())
		defer { database.close() }
		let indexNames = Set(["articles_bookKey_index", "annotations_bookKey_index"])
		guard let rs = database.executeQuery("SELECT name FROM sqlite_master WHERE type='index';", withArgumentsIn: []) else {
			Issue.record("Failed to query sqlite_master for indexes")
			return
		}
		var found = Set<String>()
		while rs.next() {
			if let name = rs.string(forColumn: "name") {
				found.insert(name)
			}
		}
		#expect(indexNames.isSubset(of: found))
	}
}
