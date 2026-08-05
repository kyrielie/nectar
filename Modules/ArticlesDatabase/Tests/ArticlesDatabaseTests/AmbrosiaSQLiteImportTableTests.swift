//
//  AmbrosiaSQLiteImportTableTests.swift
//  ArticlesDatabaseTests
//
//  Nectar cleanup plan v2, Phase 3a: direct coverage of
//  AmbrosiaSQLiteImportTable.copyItems/readAndValidateManifest/importTransfer,
//  the bulk ATTACH + INSERT OR REPLACE ... SELECT machinery that Phase 0's
//  tests only exercised indirectly. Six cases, matching the plan's numbering:
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

		init(id: String, title: String? = "Test Title", ao3WorkID: String? = nil, contentHTML: String? = "<p>content</p>", wordCount: Int? = nil, isFinished: Bool = false, isReadLater: Bool = false, isLiked: Bool = false) {
			self.id = id
			self.title = title
			self.ao3WorkID = ao3WorkID
			self.contentHTML = contentHTML
			self.wordCount = wordCount
			self.isFinished = isFinished
			self.isReadLater = isReadLater
			self.isLiked = isLiked
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

		let contentHTMLColumn = omitContentHTMLColumn ? "" : ", content_html TEXT"
		database.executeStatements("""
		CREATE TABLE items (
		  id TEXT PRIMARY KEY, title TEXT, ao3_work_id TEXT, word_count INTEGER,
		  is_finished INTEGER, is_read_later INTEGER, is_liked INTEGER,
		  reading_progress REAL\(contentHTMLColumn)
		);
		""")
		database.executeStatements("""
		CREATE TABLE transfer_manifest (
		  walk_id TEXT, page_number INTEGER, has_more INTEGER,
		  page_row_count INTEGER, expected_total_row_count INTEGER
		);
		""")

		let insertColumns = omitContentHTMLColumn
			? "id, title, ao3_work_id, word_count, is_finished, is_read_later, is_liked"
			: "id, title, ao3_work_id, word_count, is_finished, is_read_later, is_liked, content_html"

		for row in rows {
			var args: [Any] = [row.id, row.title as Any, row.ao3WorkID as Any, row.wordCount as Any, row.isFinished, row.isReadLater, row.isLiked]
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
