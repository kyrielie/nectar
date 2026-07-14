//
//  AmbrosiaSQLiteImportTable.swift
//  ArticlesDatabase
//
//  Nectar Implementation Plan, Phase 2 (SQLite transfer route, client side),
//  section 2e "Import path" and the Wire Contract's status field mapping.
//
//  This does the entire import in one shot via ATTACH DATABASE + INSERT OR
//  REPLACE ... SELECT, rather than reading every row into Swift structs --
//  the plan explicitly calls this out as "the entire import," with no
//  post-copy search reindexing and no BookReadStateTable writes (Explicit
//  non-goals in the plan; confirmed accepted trade-off, do not add back in).
//
//  bookKey is computed per row with a SQL CASE expression that mirrors
//  ParsedItem.bookKey's precedence exactly (anthology series id/name, then
//  AO3 work id, then the wire row's own `id`) -- see ParsedItem.swift's
//  bookKey doc comment. Do not reorder this without re-checking that source.
//

import Foundation
import os
import RSDatabase
import RSDatabaseObjC

enum AmbrosiaSQLiteImportError: Error, CustomStringConvertible {
	case couldNotOpenTransferFile(String)
	case couldNotReadWireFormatVersion
	case wireFormatVersionMismatch(found: Int32, expected: Int32)
	case attachFailed
	case importFailed(String)

	var description: String {
		switch self {
		case .couldNotOpenTransferFile(let path):
			return "Ambrosia SQLite transfer: could not open downloaded file at \(path)"
		case .couldNotReadWireFormatVersion:
			return "Ambrosia SQLite transfer: could not read PRAGMA user_version from downloaded file"
		case .wireFormatVersionMismatch(let found, let expected):
			return "Ambrosia SQLite transfer: wire format version mismatch (file is v\(found), app expects v\(expected)) -- this is a build/version skew bug, not a compatibility condition to handle gracefully"
		case .attachFailed:
			return "Ambrosia SQLite transfer: ATTACH DATABASE failed"
		case .importFailed(let detail):
			return "Ambrosia SQLite transfer: import failed (\(detail))"
		}
	}
}

enum AmbrosiaSQLiteImportTable {

	private static let logger = Logger(subsystem: "ArticlesDatabase", category: "AmbrosiaSQLiteImportTable")

	/// The alias the transfer file is ATTACHed under for the duration of the import.
	private static let attachedSchemaName = "ambrosia_transfer"

	/// Phase 0 verification item: reads `PRAGMA user_version` off the downloaded,
	/// not-yet-attached file with a lightweight standalone `sqlite3_open`, not a
	/// full `DatabaseQueue`/`FMDatabase` open against the app's own connection.
	/// Must happen before ATTACH DATABASE, not inside the same transaction as
	/// the import -- per the plan's 2b, do this check first and fail hard on
	/// mismatch before touching the app database at all.
	static func readWireFormatVersion(atPath path: String) throws -> Int32 {
		guard let standaloneDatabase = FMDatabase(path: path), standaloneDatabase.open() else {
			throw AmbrosiaSQLiteImportError.couldNotOpenTransferFile(path)
		}
		defer { standaloneDatabase.close() }

		guard let resultSet = standaloneDatabase.executeQuery("PRAGMA user_version;", withArgumentsIn: []) else {
			throw AmbrosiaSQLiteImportError.couldNotReadWireFormatVersion
		}
		defer { resultSet.close() }

		guard resultSet.next() else {
			throw AmbrosiaSQLiteImportError.couldNotReadWireFormatVersion
		}
		return resultSet.int(forColumnIndex: 0)
	}

	/// Runs the version check (2b) and, on success, the full import (2e) --
	/// ATTACH, bulk-copy `items` into `articles`/`statuses` computing `bookKey`
	/// per row, DETACH. Everything after the version check happens inside one
	/// transaction: a hard error midway rolls back cleanly with no partial writes.
	static func importTransfer(temporaryFilePath: String, feedID: String, expectedWireFormatVersion: Int32, queue: DatabaseQueue) throws {

		let foundVersion = try readWireFormatVersion(atPath: temporaryFilePath)
		guard foundVersion == expectedWireFormatVersion else {
			throw AmbrosiaSQLiteImportError.wireFormatVersionMismatch(found: foundVersion, expected: expectedWireFormatVersion)
		}

		var importError: Error?

		queue.runInTransactionSync { database in
			guard database.executeUpdate("ATTACH DATABASE ? AS \(attachedSchemaName);", withArgumentsIn: [temporaryFilePath]) else {
				importError = AmbrosiaSQLiteImportError.attachFailed
				return
			}
			defer {
				database.executeUpdate("DETACH DATABASE \(attachedSchemaName);", withArgumentsIn: [])
			}

			do {
				try Self.copyItems(feedID: feedID, database: database)
			} catch {
				importError = error
				// Roll back explicitly: runInTransactionSync commits unconditionally
				// on return, it doesn't inspect a thrown/rethrown error from inside
				// the block, so an early exit here must be paired with a manual
				// rollback to honor "no partial writes" on failure.
				database.executeStatements("ROLLBACK;")
				database.executeStatements("BEGIN TRANSACTION;")
			}
		}

		if let importError {
			Self.logger.error("AmbrosiaSQLiteImportTable: import failed for feedID \(feedID, privacy: .public): \(String(describing: importError), privacy: .public)")
			throw importError
		}
	}

	/// bookKey precedence, mirrored from ParsedItem.bookKey exactly:
	/// 1. isAnthology && ao3_series_id non-empty -> "ao3-series:<id>"
	/// 2. isAnthology && series_name non-null     -> "calibre-series:<name>"
	/// 3. ao3_work_id non-empty                   -> "ao3-work:<id>"
	/// 4. fallback                                -> the wire row's own id
	private static let bookKeySQLExpression = """
	CASE
	  WHEN is_anthology = 1 AND ao3_series_id IS NOT NULL AND ao3_series_id != '' THEN 'ao3-series:' || ao3_series_id
	  WHEN is_anthology = 1 AND series_name IS NOT NULL THEN 'calibre-series:' || series_name
	  WHEN ao3_work_id IS NOT NULL AND ao3_work_id != '' THEN 'ao3-work:' || ao3_work_id
	  ELSE id
	END
	"""

	private static func copyItems(feedID: String, database: FMDatabase) throws {
		// articles.articleID is calculatedArticleID(feedID:uniqueID:) elsewhere in
		// this codebase, but the wire `id` ("ambrosia-book-<calibre_id>") is already
		// globally stable per the Wire Contract, so it's used directly as both
		// articleID and uniqueID here -- there is no per-feed guid to combine it
		// with the way JSONFeedParser does for ordinary feed items.
		// contentHTML is deliberately left out of this bulk INSERT...SELECT and
		// filled in afterward, one row at a time (below) -- SQL has no LZFSE
		// primitive, so compression (Phase 3, "on both ingestion paths") has to
		// happen in Swift, and ContentHTMLCompression is the same choke point
		// the JSONFeedParser path's Article+Database.swift uses.
		let insertArticlesSQL = """
		INSERT OR REPLACE INTO articles (
		  articleID, feedID, uniqueID, title, url, externalURL, summary,
		  datePublished, dateModified, authors, tags,
		  wordCount, chapterCurrent, chapterTotal, isComplete,
		  fandoms, relationships, characters, ratings, warnings, categories, series,
		  bookKey
		)
		SELECT
		  t.id, ?, t.id, t.title, t.url, t.url, t.summary,
		  t.date_published, t.date_modified, t.authors_json, t.tags_json,
		  t.word_count, t.chapter_current, t.chapter_total, t.is_complete,
		  t.fandoms_json, t.relationships_json, t.characters_json, t.ratings_json,
		  t.warnings_json, t.categories_json, t.series_json,
		  \(bookKeySQLExpression)
		FROM \(attachedSchemaName).items AS t;
		"""
		guard database.executeUpdate(insertArticlesSQL, withArgumentsIn: [feedID]) else {
			throw AmbrosiaSQLiteImportError.importFailed("articles insert: \(database.lastErrorMessage() ?? "unknown error")")
		}

		try Self.copyCompressedContentHTML(database: database)

		// Status field mapping, from the Wire Contract:
		//   is_read_later    -> starred
		//   is_liked         -> loved
		//   is_finished      -> read
		//   reading_progress -> readingProgress
		// dateArrived defaults to "now" (import time) since the wire payload
		// carries no equivalent field and this is a fresh row, not a merge
		// against existing status history -- consistent with the plan's
		// explicit non-goal of not reconciling against prior bookReadState.
		let insertStatusesSQL = """
		INSERT OR REPLACE INTO statuses (
		  articleID, read, starred, loved, dateArrived, readingProgress
		)
		SELECT
		  t.id, t.is_finished, t.is_read_later, t.is_liked, ?, t.reading_progress
		FROM \(attachedSchemaName).items AS t;
		"""
		guard database.executeUpdate(insertStatusesSQL, withArgumentsIn: [Date().timeIntervalSince1970]) else {
			throw AmbrosiaSQLiteImportError.importFailed("statuses insert: \(database.lastErrorMessage() ?? "unknown error")")
		}
	}

	/// Reads `content_html` off the attached transfer file one row at a time,
	/// LZFSE-compresses + base64-encodes it (ContentHTMLCompression, matching
	/// the JSONFeedParser path), and writes it into the just-inserted
	/// articles row. Runs inside the same transaction as copyItems's other
	/// two statements, so a failure partway through still rolls back cleanly.
	private static func copyCompressedContentHTML(database: FMDatabase) throws {
		guard let resultSet = database.executeQuery("SELECT id, content_html FROM \(attachedSchemaName).items;", withArgumentsIn: []) else {
			throw AmbrosiaSQLiteImportError.importFailed("content_html read: \(database.lastErrorMessage() ?? "unknown error")")
		}

		while resultSet.next() {
			guard let id = resultSet.swiftString(forColumn: "id") else {
				continue
			}
			let contentHTML = resultSet.swiftString(forColumn: "content_html")
			let compressed = ContentHTMLCompression.compress(contentHTML)
			guard database.executeUpdate("UPDATE articles SET contentHTML = ? WHERE articleID = ?;", withArgumentsIn: [compressed as Any, id]) else {
				resultSet.close()
				throw AmbrosiaSQLiteImportError.importFailed("contentHTML update: \(database.lastErrorMessage() ?? "unknown error")")
			}
		}
		resultSet.close()
	}
}
