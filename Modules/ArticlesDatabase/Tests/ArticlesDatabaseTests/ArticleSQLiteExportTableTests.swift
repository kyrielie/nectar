//
//  ArticleSQLiteExportTableTests.swift
//  ArticlesDatabaseTests
//
//  Nectar cleanup plan v2, Phase 3c: direct coverage of
//  ArticlesDatabase.exportArticlesSQLite / ArticleSQLiteExportTable, which
//  had zero coverage before this. Three cases, matching the plan's
//  numbering: (1) feedIDs: nil exports everything, a non-empty set scopes
//  correctly, (2) the statuses export is scoped by the articles join, not
//  re-filtered by feedID -- an orphaned status (no matching articles row)
//  is excluded regardless of feedID scoping, (3) an already-existing
//  destinationPath fails rather than silently overwriting.
//

import Testing
import Foundation
import RSParser
import RSDatabaseObjC
@testable import ArticlesDatabase

@Suite("ArticleSQLiteExportTable feedID scoping / statuses join / destination-exists")
@MainActor
struct ArticleSQLiteExportTableTests {

	private func tempPath() -> String {
		FileManager.default.temporaryDirectory
			.appendingPathComponent("article-export-\(UUID().uuidString).sqlite")
			.path
	}

	private func rowCount(atPath path: String, table: String) -> Int {
		guard let database = FMDatabase(path: path), database.open() else {
			return -1
		}
		defer { database.close() }
		guard let resultSet = database.executeQuery("SELECT COUNT(*) FROM \(table);", withArgumentsIn: []) else {
			return -1
		}
		defer { resultSet.close() }
		guard resultSet.next() else {
			return -1
		}
		return Int(resultSet.int(forColumnIndex: 0))
	}

	// MARK: - 1. feedIDs scoping

	@Test("feedIDs: nil exports every article across every feed")
	func nilFeedIDsExportsEverything() async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)
		_ = await db.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u2", feedURL: "https://example.com/feed-b")], feedID: "feed-b", deleteOlder: false)

		let destinationPath = tempPath()
		defer { try? FileManager.default.removeItem(atPath: destinationPath) }
		try db.exportArticlesSQLite(feedIDs: nil, toPath: destinationPath)

		#expect(rowCount(atPath: destinationPath, table: "articles") == 2)
	}

	@Test("a non-empty feedIDs set scopes the export to only that feed's articles")
	func nonEmptyFeedIDsScopesExport() async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)
		_ = await db.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u2", feedURL: "https://example.com/feed-b")], feedID: "feed-b", deleteOlder: false)

		let destinationPath = tempPath()
		defer { try? FileManager.default.removeItem(atPath: destinationPath) }
		try db.exportArticlesSQLite(feedIDs: ["feed-a"], toPath: destinationPath)

		#expect(rowCount(atPath: destinationPath, table: "articles") == 1)
	}

	// MARK: - 2. statuses scoped by the articles join, not re-filtered by feedID

	@Test("an orphaned statuses row (no matching articles row) is excluded from the export regardless of feedID scoping")
	func orphanedStatusExcludedFromExport() async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)

		// Seed an orphaned statuses row directly: a status for an articleID
		// with no corresponding articles row, which can legitimately exist
		// per ArticlesTable.deleteOldStatuses.
		db.queue.runInDatabaseSync { database in
			_ = database.executeUpdate(
				"INSERT INTO statuses (articleID, read, starred, loved, dateArrived) VALUES (?, ?, ?, ?, ?);",
				withArgumentsIn: ["orphaned-article-id", false, false, false, Date()]
			)
		}

		let destinationPath = tempPath()
		defer { try? FileManager.default.removeItem(atPath: destinationPath) }
		try db.exportArticlesSQLite(feedIDs: nil, toPath: destinationPath)

		// One real article's status should be present; the orphan should not.
		guard let database = FMDatabase(path: destinationPath), database.open() else {
			Issue.record("could not open exported file")
			return
		}
		defer { database.close() }
		guard let resultSet = database.executeQuery("SELECT articleID FROM statuses;", withArgumentsIn: []) else {
			Issue.record("could not query exported statuses")
			return
		}
		defer { resultSet.close() }
		var exportedArticleIDs = Set<String>()
		while resultSet.next() {
			if let articleID = resultSet.swiftString(forColumn: "articleID") {
				exportedArticleIDs.insert(articleID)
			}
		}
		#expect(!exportedArticleIDs.contains("orphaned-article-id"))
		#expect(exportedArticleIDs.count == 1)
	}

	// MARK: - 3. destinationPath already existing fails, doesn't silently overwrite

	@Test("exporting to a destinationPath that already contains an articles table throws rather than overwriting")
	func existingDestinationPathThrows() async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)

		// Pre-create the destination as a real ArticlesDatabase (on disk),
		// so it already has an `articles` table -- exercising the same
		// "CREATE TABLE against an existing table fails" path the export's
		// own doc comment describes, rather than an arbitrary non-sqlite file.
		let destinationPath = tempPath()
		defer { try? FileManager.default.removeItem(atPath: destinationPath) }
		let preExisting = ArticlesDatabase(databaseFilePath: destinationPath, accountID: "pre-existing", retentionStyle: .feedBased)
		_ = await preExisting.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "existing", feedURL: "https://example.com/existing-feed")], feedID: "existing-feed", deleteOlder: false)

		#expect(throws: ArticleSQLiteExportError.self) {
			try db.exportArticlesSQLite(feedIDs: nil, toPath: destinationPath)
		}
	}
}
