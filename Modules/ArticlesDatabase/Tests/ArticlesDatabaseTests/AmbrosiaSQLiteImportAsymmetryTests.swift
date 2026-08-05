//
//  AmbrosiaSQLiteImportAsymmetryTests.swift
//  ArticlesDatabaseTests
//
//  Phase 0.3(e): AmbrosiaSQLiteImportTable does *not* seed read state from an
//  existing bookState row on a matching bookKey (AmbrosiaSQLiteImportTable.swift:8-11,
//  the "no BookReadStateTable writes" comment) -- unlike the ordinary feed-based
//  update() path, which does (see phase6SeedsReadStateForNewArticleIDOnSameBookKey
//  in ArticlesTableUpdateTests.swift). This test documents that asymmetry as
//  intentional so a future change to either path trips a test instead of
//  silently changing behavior only one path.
//

import Testing
import Foundation
import RSParser
import Articles
import RSDatabaseObjC
@testable import ArticlesDatabase

@Suite("AmbrosiaSQLiteImportTable read-state asymmetry")
@MainActor
struct AmbrosiaSQLiteImportAsymmetryTests {

	/// Builds a minimal, valid Ambrosia `.sqlite` transfer page file on disk
	/// (`importAmbrosiaSQLiteTransfer` ATTACHes a real file path -- this
	/// can't be `":memory:"` the way the app's own in-memory test database
	/// can, since ATTACH DATABASE opens a second, independent connection).
	/// Only the columns `AmbrosiaSQLiteImportTable.copyItems` actually reads
	/// are populated; everything else is left at SQLite's column default.
	private func makeTransferFile(id: String, ao3WorkID: String, isFinished: Bool, wireFormatVersion: Int32) throws -> String {
		let path = FileManager.default.temporaryDirectory
			.appendingPathComponent("ambrosia-transfer-\(UUID().uuidString).sqlite")
			.path

		guard let database = FMDatabase(path: path), database.open() else {
			throw AmbrosiaSQLiteImportError.couldNotOpenTransferFile(path)
		}
		defer { database.close() }

		database.executeStatements("PRAGMA user_version = \(wireFormatVersion);")

		database.executeStatements("""
		CREATE TABLE items (
		  id TEXT PRIMARY KEY, title TEXT, url TEXT, summary TEXT,
		  date_published REAL, date_modified REAL, authors_json TEXT, tags_json TEXT,
		  word_count INTEGER, chapter_current INTEGER, chapter_total INTEGER, is_complete INTEGER,
		  fandoms_json TEXT, relationships_json TEXT, characters_json TEXT, ratings_json TEXT,
		  warnings_json TEXT, categories_json TEXT, series_json TEXT,
		  is_anthology INTEGER, ao3_series_id TEXT, series_name TEXT, ao3_work_id TEXT,
		  content_html TEXT, is_finished INTEGER, is_read_later INTEGER, is_liked INTEGER,
		  reading_progress REAL
		);
		""")

		let insertSQL = """
		INSERT INTO items (id, title, ao3_work_id, content_html, is_finished, is_read_later, is_liked)
		VALUES (?, ?, ?, ?, ?, ?, ?);
		"""
		let inserted = database.executeUpdate(insertSQL, withArgumentsIn: [
			id, "Test Title", ao3WorkID, "<p>content</p>", isFinished, false, false
		])
		guard inserted else {
			throw AmbrosiaSQLiteImportError.importFailed(database.lastErrorMessage() ?? "insert failed")
		}

		return path
	}

	@Test("importing a .sqlite transfer for an already-read bookKey does not seed the new row as read")
	func sqliteImportDoesNotSeedFromExistingBookState() async throws {
		let db = TestFixtures.makeDatabase()
		let wireFormatVersion: Int32 = 1

		// Mark a book read via the ordinary feed-based path.
		let feedItem = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: "https://example.com/feed-a",
			ao3WorkID: "77777"
		)
		_ = await db.updateAsync(parsedItems: [feedItem], feedID: "feed-a", deleteOlder: false)
		let feedArticleID = Article.calculatedArticleID(feedID: "https://example.com/feed-a", uniqueID: "u1")
		_ = await db.markAsync(articleIDs: [feedArticleID], statusKey: .read, flag: true)

		// Import a .sqlite transfer payload for the same bookKey (same
		// ao3WorkID) via the bulk import path -- a different wire `id`,
		// since this path's `id` is used directly as both articleID and
		// uniqueID (AmbrosiaSQLiteImportTable.swift:261-265), not combined
		// with a feedID/uniqueID pair the way the feed-based path's
		// articleID is.
		let transferFilePath = try makeTransferFile(id: "ambrosia-book-transfer-1", ao3WorkID: "77777", isFinished: false, wireFormatVersion: wireFormatVersion)
		defer { try? FileManager.default.removeItem(atPath: transferFilePath) }

		let changes = try db.importAmbrosiaSQLiteTransfer(temporaryFilePath: transferFilePath, feedID: "sqlite-feed", wireFormatVersion: wireFormatVersion)

		let importedArticle = changes.new?.first { $0.articleID == "ambrosia-book-transfer-1" }
		#expect(importedArticle != nil)
		#expect(importedArticle?.status.read == false)
	}
}
