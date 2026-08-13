//
//  AmbrosiaSQLiteImportTableTests.swift
//  ArticlesDatabaseTests
//
//  Phase 3a: direct coverage of
//  AmbrosiaSQLiteImportTable.copyItems/readAndValidateManifest/importTransfer,
//  the bulk ATTACH + INSERT OR REPLACE ... SELECT machinery that Phase 0's
//  tests only exercised indirectly. Six cases:
//  (1) new-vs-updated split, (2) INSERT OR REPLACE overwrite semantics,
//  (3) contentHTML compress/store/decompress round-trip, (4) wire-format
//  version mismatch throws before ATTACH, (5) page_row_count manifest
//  mismatch, (6) a bad import rolls back with no partial row.
//

import Testing
import Foundation
import RSParser
import Articles
import RSDatabaseObjC
@testable import ArticlesDatabase

@Suite("AmbrosiaSQLiteImportTable copyItems/manifest/rollback")
@MainActor
struct AmbrosiaSQLiteImportTableTests {

	private static let wireFormatVersion: Int32 = 1

	private struct ItemRow {
		let id: String
		let title: String?
		let ao3WorkID: String?
		let contentHTML: String?
		let wordCount: Int?
		let isFinished: Bool
		let isReadLater: Bool
		let isLiked: Bool
		let datePublished: String?
		let dateModified: String?

		init(id: String, title: String? = "Test Title", ao3WorkID: String? = nil, contentHTML: String? = "<p>content</p>", wordCount: Int? = nil, isFinished: Bool = false, isReadLater: Bool = false, isLiked: Bool = false, datePublished: String? = nil, dateModified: String? = nil) {
			self.id = id
			self.title = title
			self.ao3WorkID = ao3WorkID
			self.contentHTML = contentHTML
			self.wordCount = wordCount
			self.isFinished = isFinished
			self.isReadLater = isReadLater
			self.isLiked = isLiked
			self.datePublished = datePublished
			self.dateModified = dateModified
		}
	}

	/// Builds a `.sqlite` transfer page file on disk with a real
	/// `transfer_manifest` row and an `items` table populated from `rows`.
	/// `pageRowCountOverride`/`omitContentHTMLColumn` let individual tests
	/// build deliberately-inconsistent files (case 5) or files missing a
	/// column `copyItems`'s INSERT SQL requires (case 6).
	private func makeTransferFile(
		rows: [ItemRow],
		wireFormatVersion: Int32 = AmbrosiaSQLiteImportTableTests.wireFormatVersion,
		pageRowCountOverride: Int? = nil,
		omitContentHTMLColumn: Bool = false
	) throws -> String {
		let path = FileManager.default.temporaryDirectory
			.appendingPathComponent("ambrosia-transfer-\(UUID().uuidString).sqlite")
			.path

		guard let database = FMDatabase(path: path), database.open() else {
			throw AmbrosiaSQLiteImportError.couldNotOpenTransferFile(path)
		}
		defer { database.close() }

		database.executeStatements("PRAGMA user_version = \(wireFormatVersion);")

		let contentHTMLColumn = omitContentHTMLColumn ? "" : ", content_html TEXT NOT NULL"
		// Full Wire Contract schema ("Wire schema" section) -- copyItems'
		// INSERT...SELECT references every one
		// of these columns by name (t.url, t.summary, t.date_published, etc.),
		// so a fixture missing any of them throws "no such column" the moment
		// that SQL runs, not just the ones a given test cares about checking.
		// Only id/title/ao3_work_id/word_count/is_finished/is_read_later/
		// is_liked/content_html are ever given real values below -- everything
		// else stays NULL/default, which is fine since copyItems' SELECT
		// passes columns straight through with no NOT NULL constraint on the
		// articles side for any of them except what's already covered by
		// ItemRow's existing required fields.
		database.executeStatements("""
		CREATE TABLE items (
		  id TEXT PRIMARY KEY, ao3_work_id TEXT, is_anthology INTEGER NOT NULL DEFAULT 0,
		  ao3_series_id TEXT, series_name TEXT,
		  url TEXT, title TEXT, summary TEXT, date_published TEXT, date_modified TEXT,
		  authors_json TEXT, tags_json TEXT,
		  word_count INTEGER, chapter_current INTEGER, chapter_total INTEGER, is_complete INTEGER,
		  fandoms_json TEXT, relationships_json TEXT, characters_json TEXT, ratings_json TEXT,
		  warnings_json TEXT, categories_json TEXT, series_json TEXT,
		  is_read_later INTEGER NOT NULL DEFAULT 0, is_liked INTEGER NOT NULL DEFAULT 0,
		  is_finished INTEGER NOT NULL DEFAULT 0, reading_progress REAL\(contentHTMLColumn)
		);
		""")
		database.executeStatements("""
		CREATE TABLE transfer_manifest (
		  walk_id TEXT, page_number INTEGER, has_more INTEGER,
		  page_row_count INTEGER, expected_total_row_count INTEGER
		);
		""")

		let insertColumns = omitContentHTMLColumn
			? "id, title, ao3_work_id, word_count, is_finished, is_read_later, is_liked, date_published, date_modified"
			: "id, title, ao3_work_id, word_count, is_finished, is_read_later, is_liked, date_published, date_modified, content_html"

		for row in rows {
			var args: [Any] = [row.id, row.title as Any, row.ao3WorkID as Any, row.wordCount as Any, row.isFinished, row.isReadLater, row.isLiked, row.datePublished as Any, row.dateModified as Any]
			if !omitContentHTMLColumn {
				args.append(row.contentHTML as Any)
			}
			let inserted = database.executeUpdate(
				"INSERT INTO items (\(insertColumns)) VALUES (\(Array(repeating: "?", count: args.count).joined(separator: ", ")));",
				withArgumentsIn: args
			)
			guard inserted else {
				throw AmbrosiaSQLiteImportError.importFailed(database.lastErrorMessage() ?? "insert failed")
			}
		}

		let actualRowCount = rows.count
		let claimedRowCount = pageRowCountOverride ?? actualRowCount
		let manifestInserted = database.executeUpdate(
			"INSERT INTO transfer_manifest (walk_id, page_number, has_more, page_row_count, expected_total_row_count) VALUES (?, ?, ?, ?, ?);",
			withArgumentsIn: ["walk-1", 1, false, claimedRowCount, actualRowCount]
		)
		guard manifestInserted else {
			throw AmbrosiaSQLiteImportError.importFailed(database.lastErrorMessage() ?? "manifest insert failed")
		}

		return path
	}

	// MARK: - 1. New-vs-updated split

	@Test("re-importing one repeated id and one new id splits correctly, with no overlap")
	func newVsUpdatedSplit() async throws {
		let db = TestFixtures.makeDatabase()

		let firstPath = try makeTransferFile(rows: [
			ItemRow(id: "book-1", title: "First Import"),
			ItemRow(id: "book-2", title: "Also First Import")
		])
		defer { try? FileManager.default.removeItem(atPath: firstPath) }
		let firstChanges = try db.importAmbrosiaSQLiteTransfer(temporaryFilePath: firstPath, feedID: "sqlite-feed", wireFormatVersion: Self.wireFormatVersion)
		#expect(firstChanges.new?.count == 2)
		#expect(firstChanges.updated == nil)

		let secondPath = try makeTransferFile(rows: [
			ItemRow(id: "book-1", title: "Re-imported, Changed Title"),
			ItemRow(id: "book-3", title: "New In Second Import")
		])
		defer { try? FileManager.default.removeItem(atPath: secondPath) }
		let secondChanges = try db.importAmbrosiaSQLiteTransfer(temporaryFilePath: secondPath, feedID: "sqlite-feed", wireFormatVersion: Self.wireFormatVersion)

		let newIDs = Set((secondChanges.new ?? []).map(\.articleID))
		let updatedIDs = Set((secondChanges.updated ?? []).map(\.articleID))
		#expect(newIDs == ["book-3"])
		#expect(updatedIDs == ["book-1"])
		#expect(newIDs.isDisjoint(with: updatedIDs))
	}

	// MARK: - 2. INSERT OR REPLACE overwrite semantics

	@Test("re-importing the same id with a changed title/word count overwrites those fields")
	func reimportOverwritesChangedFields() async throws {
		let db = TestFixtures.makeDatabase()

		let firstPath = try makeTransferFile(rows: [ItemRow(id: "book-1", title: "Original Title", wordCount: 1000)])
		defer { try? FileManager.default.removeItem(atPath: firstPath) }
		_ = try db.importAmbrosiaSQLiteTransfer(temporaryFilePath: firstPath, feedID: "sqlite-feed", wireFormatVersion: Self.wireFormatVersion)

		let secondPath = try makeTransferFile(rows: [ItemRow(id: "book-1", title: "Updated Title", wordCount: 2500)])
		defer { try? FileManager.default.removeItem(atPath: secondPath) }
		_ = try db.importAmbrosiaSQLiteTransfer(temporaryFilePath: secondPath, feedID: "sqlite-feed", wireFormatVersion: Self.wireFormatVersion)

		let fetched = db.fetchArticles(articleIDs: ["book-1"])
		#expect(fetched.first?.title == "Updated Title")
		#expect(fetched.first?.wordCount == 2500)
	}

	// MARK: - 3. contentHTML compress/store/decompress round-trip

	@Test("imported contentHTML round-trips through compression and back via fetchArticles")
	func contentHTMLRoundTripsThroughCompression() async throws {
		let db = TestFixtures.makeDatabase()
		let html = "<p>Some non-trivial content with <strong>markup</strong> and unicode: café.</p>"

		let path = try makeTransferFile(rows: [ItemRow(id: "book-1", contentHTML: html)])
		defer { try? FileManager.default.removeItem(atPath: path) }
		_ = try db.importAmbrosiaSQLiteTransfer(temporaryFilePath: path, feedID: "sqlite-feed", wireFormatVersion: Self.wireFormatVersion)

		let fetched = db.fetchArticles(articleIDs: ["book-1"])
		#expect(fetched.first?.contentHTML == html)
	}

	// MARK: - 3b. date_published/date_modified parse into real Date values

	@Test("imported date_published/date_modified (ISO 8601 wire TEXT) parse into the corresponding Date, not a ~1970 epoch artifact")
	func datesParseFromWireISO8601Text() async throws {
		let db = TestFixtures.makeDatabase()

		let path = try makeTransferFile(rows: [
			ItemRow(id: "book-1", datePublished: "2024-01-15T10:30:00Z", dateModified: "2024-03-02T08:00:00Z")
		])
		defer { try? FileManager.default.removeItem(atPath: path) }
		_ = try db.importAmbrosiaSQLiteTransfer(temporaryFilePath: path, feedID: "sqlite-feed", wireFormatVersion: Self.wireFormatVersion)

		let fetched = db.fetchArticles(articleIDs: ["book-1"])
		let article = try #require(fetched.first)

		let expectedPublished = DateParser.date(from: "2024-01-15T10:30:00Z")
		let expectedModified = DateParser.date(from: "2024-03-02T08:00:00Z")

		#expect(article.datePublished == expectedPublished)
		#expect(article.dateModified == expectedModified)

		// Regression guard: before the fix, copyItems copied the ISO 8601 TEXT
		// straight into the numeric datePublished/dateModified columns, and
		// SQLite's TEXT-to-REAL coercion on read parsed only the leading
		// "2024" digit run, producing a bogus ~1970-01-01 date. Assert we're
		// nowhere near 1970 to catch a regression back to that behavior even
		// if DateParser's own output ever changes shape.
		let nineteenSeventy = Date(timeIntervalSince1970: 0)
		#expect(article.datePublished.map { abs($0.timeIntervalSince(nineteenSeventy)) > 60 * 60 * 24 * 365 } == true)
	}

	@Test("a row with no date_published/date_modified imports with nil dates rather than throwing")
	func missingDatesImportAsNil() async throws {
		let db = TestFixtures.makeDatabase()

		let path = try makeTransferFile(rows: [ItemRow(id: "book-1")])
		defer { try? FileManager.default.removeItem(atPath: path) }
		_ = try db.importAmbrosiaSQLiteTransfer(temporaryFilePath: path, feedID: "sqlite-feed", wireFormatVersion: Self.wireFormatVersion)

		let fetched = db.fetchArticles(articleIDs: ["book-1"])
		#expect(fetched.first?.datePublished == nil)
		#expect(fetched.first?.dateModified == nil)
	}

	// MARK: - 4. Wire-format version mismatch throws before ATTACH

	@Test("a wire-format version mismatch throws and writes nothing")
	func wireFormatVersionMismatchThrowsAndWritesNothing() throws {
		let db = TestFixtures.makeDatabase()
		let path = try makeTransferFile(rows: [ItemRow(id: "book-1")], wireFormatVersion: 99)
		defer { try? FileManager.default.removeItem(atPath: path) }

		#expect(throws: AmbrosiaSQLiteImportError.self) {
			try db.importAmbrosiaSQLiteTransfer(temporaryFilePath: path, feedID: "sqlite-feed", wireFormatVersion: Self.wireFormatVersion)
		}

		#expect(db.fetchArticles(articleIDs: ["book-1"]).isEmpty)
	}

	// MARK: - 5. page_row_count manifest mismatch

	@Test("a page_row_count that disagrees with the actual items row count throws manifestRowCountMismatch")
	func manifestRowCountMismatchThrows() throws {
		let path = try makeTransferFile(rows: [ItemRow(id: "book-1"), ItemRow(id: "book-2")], pageRowCountOverride: 5)
		defer { try? FileManager.default.removeItem(atPath: path) }

		do {
			_ = try AmbrosiaSQLiteImportTable.readAndValidateManifest(atPath: path, expectedWireFormatVersion: Self.wireFormatVersion)
			Issue.record("expected manifestRowCountMismatch, but readAndValidateManifest succeeded")
		} catch AmbrosiaSQLiteImportError.manifestRowCountMismatch(let claimed, let actual) {
			#expect(claimed == 5)
			#expect(actual == 2)
		} catch {
			Issue.record("expected manifestRowCountMismatch, got \(error)")
		}
	}

	// MARK: - 6. importFailed rolls back cleanly

	@Test("a malformed transfer file (missing content_html column) fails the whole import with no partial row")
	func malformedTransferFileRollsBackCleanly() throws {
		let db = TestFixtures.makeDatabase()
		let path = try makeTransferFile(rows: [ItemRow(id: "book-1")], omitContentHTMLColumn: true)
		defer { try? FileManager.default.removeItem(atPath: path) }

		#expect(throws: AmbrosiaSQLiteImportError.self) {
			try db.importAmbrosiaSQLiteTransfer(temporaryFilePath: path, feedID: "sqlite-feed", wireFormatVersion: Self.wireFormatVersion)
		}

		#expect(db.fetchArticles(articleIDs: ["book-1"]).isEmpty)
	}
}
