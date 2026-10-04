//
//  AO3ConfirmedMissingMigrationTests.swift
//  ArticlesDatabaseTests
//
//  Schema 6 clears every ao3ConfirmedMissingAt written before interstitial
//  classification existed. Needs a file-backed database so it can be closed
//  and reopened at a forced user_version.
//

import Testing
import Foundation
import RSParser
import Articles
import RSDatabaseObjC
@testable import ArticlesDatabase

@Suite("ao3ConfirmedMissingAt schema 6 migration")
@MainActor
struct AO3ConfirmedMissingMigrationTests {

	private static let feedID = "feed-1"
	private static let feedURL = "https://example.com/feed"

	private func makeTemporaryPath() -> String {
		NSTemporaryDirectory() + "ao3-missing-migration-\(UUID().uuidString).sqlite3"
	}

	private func open(_ path: String) -> ArticlesDatabase {
		ArticlesDatabase(databaseFilePath: path, accountID: "test-account", retentionStyle: .feedBased)
	}

	private func setUserVersion(_ version: Int, path: String) throws {
		let database = try #require(FMDatabase(path: path))
		try #require(database.open())
		database.executeStatements("PRAGMA user_version = \(version);")
		database.close()
	}

	private func readUserVersion(path: String) throws -> UInt32 {
		let database = try #require(FMDatabase(path: path))
		try #require(database.open())
		defer { database.close() }
		return database.userVersion()
	}

	@Test("a version 5 database loses its missing flags on reopen and moves to version 6")
	func clearsFlagsAndBumpsVersion() async throws {
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

		try setUserVersion(5, path: path)
		#expect(try readUserVersion(path: path) == 5)

		let reopened = open(path)
		let article = try #require(await reopened.fetchArticlesAsync(articleIDs: [articleID]).first)
		#expect(article.ao3ConfirmedMissingAt == nil)
		#expect(try readUserVersion(path: path) == 6)
	}

	@Test("a version 6 database keeps flags set after the migration")
	func laterFlagsSurviveReopen() async throws {
		let path = makeTemporaryPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		let articleID = Article.calculatedArticleID(feedID: Self.feedID, uniqueID: "u1")
		do {
			let db = open(path)
			let item = TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: Self.feedURL, wordCount: 100)
			_ = await db.updateAsync(parsedItems: [item], feedID: Self.feedID, deleteOlder: false)
			await db.setAO3ConfirmedMissingAsync(articleID: articleID)
		}

		let reopened = open(path)
		let article = try #require(await reopened.fetchArticlesAsync(articleIDs: [articleID]).first)
		#expect(article.ao3ConfirmedMissingAt != nil)
	}
}
