//
//  ArticleIsRestrictedTests.swift
//  ArticlesDatabaseTests
//
//  Schema 7: isRestricted (AO3 archive lock). Nullable BOOL, nil = unknown.
//  Migration tests need a file-backed database so it can be closed,
//  altered and reopened at a forced user_version.
//

import Testing
import Foundation
import RSParser
import Articles
import RSDatabaseObjC
@testable import ArticlesDatabase

@Suite("isRestricted storage (schema 7)")
@MainActor
struct ArticleIsRestrictedTests {

	private static let feedID = "feed-1"
	private static let feedURL = "https://example.com/feed"
	private static let articleID = Article.calculatedArticleID(feedID: feedID, uniqueID: "u1")

	private func item(isRestricted: Bool?) -> ParsedItem {
		TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: Self.feedURL, isRestricted: isRestricted)
	}

	private func stored(_ db: ArticlesDatabase) async throws -> Article {
		try #require(await db.fetchArticlesAsync(articleIDs: [Self.articleID]).first)
	}

	// MARK: Round trip and diff rules

	@Test("nil, true and false each round trip through the database", arguments: [nil, true, false] as [Bool?])
	func roundTrip(value: Bool?) async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [item(isRestricted: value)], feedID: Self.feedID, deleteOlder: false)
		#expect(try await stored(db).isRestricted == value)
	}

	@Test("a nil refresh never blanks a stored true")
	func nilDoesNotBlankTrue() async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [item(isRestricted: true)], feedID: Self.feedID, deleteOlder: false)
		_ = await db.updateAsync(parsedItems: [item(isRestricted: nil)], feedID: Self.feedID, deleteOlder: false)
		#expect(try await stored(db).isRestricted == true)
	}

	@Test("true to false is written, for a work its author unlocked")
	func trueToFalseWrites() async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [item(isRestricted: true)], feedID: Self.feedID, deleteOlder: false)
		_ = await db.updateAsync(parsedItems: [item(isRestricted: false)], feedID: Self.feedID, deleteOlder: false)
		#expect(try await stored(db).isRestricted == false)
	}

	@Test("false to true is written")
	func falseToTrueWrites() async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [item(isRestricted: false)], feedID: Self.feedID, deleteOlder: false)
		_ = await db.updateAsync(parsedItems: [item(isRestricted: true)], feedID: Self.feedID, deleteOlder: false)
		#expect(try await stored(db).isRestricted == true)
	}

	// MARK: Migration

	private func makeTemporaryPath() -> String {
		NSTemporaryDirectory() + "is-restricted-migration-\(UUID().uuidString).sqlite3"
	}

	private func open(_ path: String) -> ArticlesDatabase {
		ArticlesDatabase(databaseFilePath: path, accountID: "test-account", retentionStyle: .feedBased)
	}

	private func withRawDatabase(_ path: String, _ body: (FMDatabase) throws -> Void) throws {
		let database = try #require(FMDatabase(path: path))
		try #require(database.open())
		defer { database.close() }
		try body(database)
	}

	@Test("a version 6 database gains the column, keeps its rows as unknown, and moves to version 7")
	func migratesVersion6() async throws {
		let path = makeTemporaryPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		do {
			let db = open(path)
			_ = await db.updateAsync(parsedItems: [item(isRestricted: true)], feedID: Self.feedID, deleteOlder: false)
		}

		// Rebuild the version 6 shape: no isRestricted column, user_version 6.
		// Relies on SQLite ALTER TABLE DROP COLUMN (3.35+).
		try withRawDatabase(path) { database in
			database.executeStatements("ALTER TABLE articles DROP COLUMN isRestricted;")
			database.executeStatements("PRAGMA user_version = 6;")
		}
		try withRawDatabase(path) { database in
			#expect(database.userVersion() == 6)
		}

		let reopened = open(path)
		let article = try await stored(reopened)
		#expect(article.isRestricted == nil)
		try withRawDatabase(path) { database in
			#expect(database.userVersion() == 7)
		}

		// The new column is writable after the migration.
		_ = await reopened.updateAsync(parsedItems: [item(isRestricted: true)], feedID: Self.feedID, deleteOlder: false)
		#expect(try await stored(reopened).isRestricted == true)
	}
}
