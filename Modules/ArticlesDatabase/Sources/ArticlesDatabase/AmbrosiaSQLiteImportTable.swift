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
import RSParser

/// Manifest describing one page's position within a paginated `.sqlite`
/// transfer walk (Nectar plan 3a/3c), read from the `transfer_manifest`
/// table Ambrosia writes alongside `items` in every page file. Public so
/// `AmbrosiaSQLiteTransferFetcher` (Account module) can read and validate a
/// page before deciding whether to import it at all.
public struct AmbrosiaSQLiteTransferManifest: Sendable {
	public let walkID: String
	public let pageNumber: Int
	public let hasMore: Bool
	public let pageRowCount: Int
	public let expectedTotalRowCount: Int
}

public enum AmbrosiaSQLiteImportError: Error, CustomStringConvertible {
	case couldNotOpenTransferFile(String)
	case couldNotReadWireFormatVersion
	case wireFormatVersionMismatch(found: Int32, expected: Int32)
	case attachFailed
	case importFailed(String)
	case manifestMissing
	case manifestRowCountMismatch(claimed: Int, actual: Int)

	public var description: String {
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
		case .manifestMissing:
			return "Ambrosia SQLite transfer: transfer_manifest table missing or unreadable in downloaded page file"
		case .manifestRowCountMismatch(let claimed, let actual):
			return "Ambrosia SQLite transfer: transfer_manifest page_row_count (\(claimed)) does not match actual items row count (\(actual)) in downloaded page file"
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

	/// Reads and validates `transfer_manifest` off the downloaded, not-yet-attached
	/// page file, after first re-running the same wire-format-version check as
	/// `readWireFormatVersion` (both must happen before ATTACH DATABASE, and
	/// before any decision is made about whether this page is trustworthy
	/// enough to import at all -- Nectar plan 3c).
	///
	/// Also verifies `page_row_count` against the actual row count in this
	/// file's own `items` table: a page whose manifest disagrees with its own
	/// row data is internally inconsistent and must not be imported, per 3c
	/// ("this page's file is internally inconsistent, don't trust any of it").
	static func readAndValidateManifest(atPath path: String, expectedWireFormatVersion: Int32) throws -> AmbrosiaSQLiteTransferManifest {
		let foundVersion = try readWireFormatVersion(atPath: path)
		guard foundVersion == expectedWireFormatVersion else {
			throw AmbrosiaSQLiteImportError.wireFormatVersionMismatch(found: foundVersion, expected: expectedWireFormatVersion)
		}

		guard let standaloneDatabase = FMDatabase(path: path), standaloneDatabase.open() else {
			throw AmbrosiaSQLiteImportError.couldNotOpenTransferFile(path)
		}
		defer { standaloneDatabase.close() }

		guard let manifestResultSet = standaloneDatabase.executeQuery(
			"SELECT walk_id, page_number, has_more, page_row_count, expected_total_row_count FROM transfer_manifest LIMIT 1;",
			withArgumentsIn: []
		) else {
			throw AmbrosiaSQLiteImportError.manifestMissing
		}
		guard manifestResultSet.next(), let walkID = manifestResultSet.swiftString(forColumn: "walk_id") else {
			manifestResultSet.close()
			throw AmbrosiaSQLiteImportError.manifestMissing
		}
		let pageNumber = Int(manifestResultSet.int(forColumn: "page_number"))
		let hasMore = manifestResultSet.bool(forColumn: "has_more")
		let pageRowCount = Int(manifestResultSet.int(forColumn: "page_row_count"))
		let expectedTotalRowCount = Int(manifestResultSet.int(forColumn: "expected_total_row_count"))
		manifestResultSet.close()

		guard let countResultSet = standaloneDatabase.executeQuery("SELECT COUNT(*) FROM items;", withArgumentsIn: []),
		      let actualRowCount = countResultSet.intWithCountResult() else {
			throw AmbrosiaSQLiteImportError.manifestMissing
		}
		guard actualRowCount == pageRowCount else {
			throw AmbrosiaSQLiteImportError.manifestRowCountMismatch(claimed: pageRowCount, actual: actualRowCount)
		}

		return AmbrosiaSQLiteTransferManifest(
			walkID: walkID,
			pageNumber: pageNumber,
			hasMore: hasMore,
			pageRowCount: pageRowCount,
			expectedTotalRowCount: expectedTotalRowCount
		)
	}

	/// Runs the version check (2b) and, on success, the full import (2e) --
	/// ATTACH, bulk-copy `items` into `articles`/`statuses` computing `bookKey`
	/// per row, DETACH. Everything after the version check happens inside one
	/// transaction: a hard error midway rolls back cleanly with no partial writes.
	///
	/// Returns which incoming articleIDs were new vs. already-present before
	/// this import, so the caller can construct an `ArticleChanges` and post
	/// `.AccountDidDownloadArticles` -- previously this import path wrote
	/// straight into `articles`/`statuses` via `INSERT OR REPLACE ... SELECT`
	/// without ever producing `Article` values, so that notification never
	/// fired for `.sqlite`-routed imports.
	static func importTransfer(temporaryFilePath: String, feedID: String, expectedWireFormatVersion: Int32, queue: DatabaseQueue) throws -> (new: Set<String>, updated: Set<String>) {

		let foundVersion = try readWireFormatVersion(atPath: temporaryFilePath)
		guard foundVersion == expectedWireFormatVersion else {
			throw AmbrosiaSQLiteImportError.wireFormatVersionMismatch(found: foundVersion, expected: expectedWireFormatVersion)
		}

		// DatabaseBlock is declared `@Sendable`, so the compiler treats this
		// closure as potentially concurrent even though runInTransactionSync
		// is a synchronous, single-threaded call -- this var is never touched
		// from more than one thread at a time in practice.
		nonisolated(unsafe) var importError: Error?
		nonisolated(unsafe) var newIDs = Set<String>()
		nonisolated(unsafe) var updatedIDs = Set<String>()

		queue.runInTransactionSync { database in
			guard database.executeUpdate("ATTACH DATABASE ? AS \(attachedSchemaName);", withArgumentsIn: [temporaryFilePath]) else {
				importError = AmbrosiaSQLiteImportError.attachFailed
				return
			}
			defer {
				// DatabaseQueue opens every connection with
				// setShouldCacheStatements(true), so the SELECT/UPDATE statements
				// copyItems/copyCompressedContentHTML just ran against
				// `attachedSchemaName` weren't finalized when their result sets
				// were closed -- FMDB just sqlite3_reset() them and parks the
				// compiled sqlite3_stmt in its cache, keyed by SQL text, for
				// reuse on the next call with the same SQL. SQLite refuses to
				// DETACH a database that any prepared statement still
				// references, even one that's merely reset and not currently
				// stepping. Left uncleared, DETACH below fails silently (its
				// result was never checked), the alias stays attached, and the
				// *next* importAmbrosiaSQLiteTransfer call's ATTACH under the
				// same alias fails with attachFailed -- reproducible any time
				// two imports run against the same DatabaseQueue in one
				// process. Clearing the cache finalizes those statements first
				// so DETACH actually succeeds.
				database.clearCachedStatements()
				if !database.executeUpdate("DETACH DATABASE \(attachedSchemaName);", withArgumentsIn: []) {
					Self.logger.error("AmbrosiaSQLiteImportTable: DETACH DATABASE \(attachedSchemaName, privacy: .public) failed -- \(database.lastErrorMessage(), privacy: .public)")
				}
			}

			do {
				(newIDs, updatedIDs) = try Self.copyItems(feedID: feedID, database: database)
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

		return (newIDs, updatedIDs)
	}

	/// bookKey precedence, mirrored from ParsedItem.bookKey exactly:
	/// 1. ao3_series_id non-empty                  -> "ao3-series:<id>"
	///    (routes on ao3_series_id's presence, not is_anthology -- a series-group
	///    row sets ao3_series_id without is_anthology, and needs the same
	///    single-pre-merged-row keying an anthology-with-a-series-id gets)
	/// 2. isAnthology && series_name non-null     -> "calibre-series:<name>"
	/// 3. ao3_work_id non-empty                   -> "ao3-work:<id>"
	/// 4. fallback                                -> the wire row's own id
	/// `internal`-by-default (not `public`): nothing outside the module
	/// gains access, but this widening lets `@testable import
	/// ArticlesDatabase` see it from `ArticlesDatabaseTests` so a parity
	/// test can run this exact SQL and compare it against
	/// `ParsedItem.bookKey`, rather than trusting the two stay in sync by
	/// convention alone. `AmbrosiaSQLiteImportTable` is itself a
	/// non-public `enum`, so this does not change the framework's public
	/// API surface described at the top of ArticlesDatabase.swift.
	static let bookKeySQLExpression = """
	CASE
	  WHEN ao3_series_id IS NOT NULL AND ao3_series_id != '' THEN 'ao3-series:' || ao3_series_id
	  WHEN is_anthology = 1 AND series_name IS NOT NULL THEN 'calibre-series:' || series_name
	  WHEN ao3_work_id IS NOT NULL AND ao3_work_id != '' THEN 'ao3-work:' || ao3_work_id
	  ELSE id
	END
	"""

	private static func copyItems(feedID: String, database: FMDatabase) throws -> (new: Set<String>, updated: Set<String>) {
		// Read the incoming IDs off the attached transfer file, then check which
		// of them already exist in `articles`, before running the INSERT OR
		// REPLACE below -- INSERT OR REPLACE doesn't distinguish insert-vs-update
		// in its result, and sqlite3_changes() isn't reliably per-row-classified
		// either, so this is the simplest correct way to get the new/updated split.
		guard let incomingIDsResultSet = database.executeQuery("SELECT id FROM \(attachedSchemaName).items;", withArgumentsIn: []) else {
			throw AmbrosiaSQLiteImportError.importFailed("incoming id read: \(database.lastErrorMessage() ?? "unknown error")")
		}
		var incomingIDs = Set<String>()
		while incomingIDsResultSet.next() {
			if let id = incomingIDsResultSet.swiftString(forColumn: "id") {
				incomingIDs.insert(id)
			}
		}
		incomingIDsResultSet.close()

		var existingIDsBeforeImport = Set<String>()
		if !incomingIDs.isEmpty {
			// AmbrosiaSQLiteImportTable is a plain enum, not a DatabaseTable
			// conformer, so the selectRowsWhere(key:inValues:in:) helper other
			// tables get via that protocol isn't directly callable here --
			// this is the same query inlined by hand, matching how ArticlesTable
			// builds its own "articleID in (...)" queries elsewhere.
			let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(incomingIDs.count))!
			let sql = "SELECT articleID FROM articles WHERE articleID IN \(placeholders);"
			guard let existingIDsResultSet = database.executeQuery(sql, withArgumentsIn: Array(incomingIDs)) else {
				throw AmbrosiaSQLiteImportError.importFailed("existing id read: \(database.lastErrorMessage() ?? "unknown error")")
			}
			while existingIDsResultSet.next() {
				if let id = existingIDsResultSet.swiftString(forColumn: "articleID") {
					existingIDsBeforeImport.insert(id)
				}
			}
			existingIDsResultSet.close()
		}

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
		// isAmbrosiaItem is set to 1 unconditionally here, unlike the AO3
		// Work Header stats columns above it (commentCount/kudosCount/
		// bookmarkCount/hitCount), which are deliberately left out of this
		// column list so they stay NULL. Every row on this import path came
		// from an Ambrosia SQLite transfer by definition -- leaving this
		// column NULL/default would be wrong here, not just harmlessly
		// absent, since it's what lets AO3ChapterFetcher/ArticleRenderer
		// tell an Ambrosia-sourced row from a native AO3 one.
		// No `tags`/`t.tags_json` column here: `articles` has never had a `tags`
		// column (confirmed against the schema in ArticlesDatabase.swift -- the
		// only `tags` this database ever had was upstream NetNewsWire's separate
		// relational tags table, dropped entirely, see the `DROP TABLE if EXISTS
		// tags` migration). `ParsedItem.tags` (the standard JSON Feed field) is
		// parsed but never persisted on the ordinary feed-import path -- this
		// bulk INSERT previously referenced a `tags` column that has never
		// existed, which made every `.sqlite` transfer import throw. Dropping
		// it here matches the ordinary path's existing (silent) behavior.
		//
		// No `additionalTags`/`t.additional_tags_json` column here either, but
		// for a different reason than the above: `Article.additionalTags` does
		// exist now (added alongside AO3ChapterHTMLExtractor's work-page
		// metadata parsing -- freeform "Additional Tags" fandom/relationship/
		// etc. sibling), it's just that Ambrosia's wire format has nothing to
		// copy it from. Confirmed against the Wire Contract: Ambrosia only
		// ever includes freeform tags baked into `content_html`'s rendered
		// prose, never as a structured field on `items` the way fandoms_json/
		// relationships_json/etc. are -- there is no `additional_tags_json`
		// column on the transfer file to read. Leaving this column out of the
		// bulk INSERT is therefore not a gap to backfill here: an Ambrosia-
		// imported article gets additionalTags populated the same way a
		// native-AO3-feed stub does, from AO3ChapterFetcher.rebuildParsedItem's
		// live-page metadata on its first successful chapter fetch (AO3 is
		// already the source of truth there -- see AO3ChapterHTMLExtractor's
		// AO3WorkPageMetadata and rebuildParsedItem's always-overwrite
		// behavior). Until that first fetch happens, additionalTags is nil on
		// import, same gap fandoms/ratings/etc. already have on this path and
		// already accept.
		// datePublished/dateModified are deliberately left out of this bulk
		// INSERT...SELECT, the same way contentHTML is: the wire format sends
		// date_published/date_modified as ISO 8601 TEXT (see the Wire Contract
		// in docs/nectar-implementation-plan.md), but the local `articles`
		// table's datePublished/dateModified columns hold numeric
		// timeIntervalSince1970 values -- every other write path gets that
		// conversion for free because FMDB's dictionary/positional binding
		// converts a Swift `Date` to a double before it ever reaches SQLite
		// (see FMDatabase.bindObject:toColumn:inStatement:). A raw
		// SELECT-and-copy of the TEXT column skips that conversion entirely:
		// SQLite's TEXT-to-REAL coercion on read parses only the leading
		// digit run of an ISO 8601 string (e.g. "2024-01-15T10:30:00Z" ->
		// 2024.0), so every date silently became a bogus ~1970 timestamp
		// (see logicalDatePublished's fallback in Shared/Extensions/
		// ArticleUtilities.swift, and MainTimelineCellData, which read
		// whatever ends up in these columns). Parsed and written per row by
		// copyParsedDates below, using RSParser.DateParser -- the same parser
		// JSONFeedParser uses for date_published/date_modified on the
		// ordinary HTTP JSON Feed path -- so both import routes produce the
		// same Date value from the same wire string.
		let insertArticlesSQL = """
		INSERT OR REPLACE INTO articles (
		  articleID, feedID, uniqueID, title, url, externalURL, summary,
		  authors,
		  wordCount, chapterCurrent, chapterTotal, isComplete,
		  fandoms, relationships, characters, ratings, warnings, categories, series,
		  isAmbrosiaItem, bookKey
		)
		SELECT
		  t.id, ?, t.id, t.title, t.url, t.url, t.summary,
		  t.authors_json,
		  t.word_count, t.chapter_current, t.chapter_total, t.is_complete,
		  t.fandoms_json, t.relationships_json, t.characters_json, t.ratings_json,
		  t.warnings_json, t.categories_json, t.series_json,
		  1, \(bookKeySQLExpression)
		FROM \(attachedSchemaName).items AS t;
		"""
		guard database.executeUpdate(insertArticlesSQL, withArgumentsIn: [feedID]) else {
			throw AmbrosiaSQLiteImportError.importFailed("articles insert: \(database.lastErrorMessage() ?? "unknown error")")
		}

		try Self.copyCompressedContentHTML(database: database)
		try Self.copyParsedDates(database: database)

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

		return (incomingIDs.subtracting(existingIDsBeforeImport), incomingIDs.intersection(existingIDsBeforeImport))
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

	/// Reads `date_published`/`date_modified` off the attached transfer file
	/// one row at a time, parses them with `RSParser.DateParser` (the ISO
	/// 8601 wire format -- see the Wire Contract), and writes the resulting
	/// `Date` values into the just-inserted articles row via parameter
	/// binding, so FMDB stores them the same way every other write path
	/// does (`timeIntervalSince1970`, not the raw ISO 8601 string). Runs
	/// inside the same transaction as copyItems's other statements, so a
	/// failure partway through still rolls back cleanly. Same pattern as
	/// copyCompressedContentHTML above, and for the same reason: the bulk
	/// INSERT...SELECT can't be trusted to move these two columns as-is.
	///
	/// A row with no parseable date (missing, empty, or malformed) writes
	/// NULL for that column, same as every other field on this import
	/// route -- copyItems's INSERT OR REPLACE already wholesale-replaces a
	/// re-imported row rather than diffing field-by-field, so a date that
	/// disappears from the wire disappears here too, consistent with the
	/// rest of this path rather than a new exception.
	private static func copyParsedDates(database: FMDatabase) throws {
		guard let resultSet = database.executeQuery("SELECT id, date_published, date_modified FROM \(attachedSchemaName).items;", withArgumentsIn: []) else {
			throw AmbrosiaSQLiteImportError.importFailed("date read: \(database.lastErrorMessage() ?? "unknown error")")
		}

		while resultSet.next() {
			guard let id = resultSet.swiftString(forColumn: "id") else {
				continue
			}
			let datePublished = resultSet.swiftString(forColumn: "date_published").flatMap { DateParser.date(from: $0) }
			let dateModified = resultSet.swiftString(forColumn: "date_modified").flatMap { DateParser.date(from: $0) }
			guard database.executeUpdate("UPDATE articles SET datePublished = ?, dateModified = ? WHERE articleID = ?;", withArgumentsIn: [datePublished as Any, dateModified as Any, id]) else {
				resultSet.close()
				throw AmbrosiaSQLiteImportError.importFailed("date update: \(database.lastErrorMessage() ?? "unknown error")")
			}
		}
		resultSet.close()
	}
}
