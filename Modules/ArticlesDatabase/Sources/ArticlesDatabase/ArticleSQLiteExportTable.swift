//
//  ArticleSQLiteExportTable.swift
//  ArticlesDatabase
//
//  Task 4 (SQLite export): the export half of the ATTACH DATABASE idiom
//  AmbrosiaSQLiteImportTable already uses for import -- here run in reverse,
//  with a bulk `CREATE TABLE ... AS SELECT` off the app's own articles/
//  statuses tables into a freshly attached, empty destination file, rather
//  than reading every row into Swift structs.
//
//  Deliberately the mirror image of AmbrosiaSQLiteImportTable's non-goals:
//  no bookKey/bookState involvement (this is a plain articles/statuses
//  dump, not a re-import-shaped payload), no content compression/
//  decompression step (contentHTML is copied as stored -- already
//  LZFSE-compressed by ContentHTMLCompression on the way in, and this
//  export isn't required to produce anything AmbrosiaSQLiteImportTable
//  could read back in).
//

import Foundation
import os
import RSDatabase
import RSDatabaseObjC

public enum ArticleSQLiteExportError: Error, CustomStringConvertible {
	case attachFailed
	case exportFailed(String)

	public var description: String {
		switch self {
		case .attachFailed:
			return "Article SQLite export: ATTACH DATABASE failed"
		case .exportFailed(let detail):
			return "Article SQLite export: export failed (\(detail))"
		}
	}
}

enum ArticleSQLiteExportTable {

	private static let logger = Logger(subsystem: "ArticlesDatabase", category: "ArticleSQLiteExportTable")

	/// The alias the destination file is ATTACHed under for the duration of the export.
	private static let attachedSchemaName = "article_export"

	/// Bulk-copies `articles` (optionally scoped to `feedIDs`) and the
	/// matching `statuses` rows into a freshly attached destination file at
	/// `destinationPath`. `feedIDs` nil or empty means every article in
	/// this account -- the "Export All" case; a non-empty set scopes to
	/// those feeds' articles only -- the per-feed "Export…" case.
	///
	/// `destinationPath` must not already exist: ATTACH DATABASE creates a
	/// new file there, and a `CREATE TABLE` against an existing `articles`
	/// table at that path would fail rather than overwrite it.
	static func exportArticles(feedIDs: Set<String>?, toPath destinationPath: String, queue: DatabaseQueue) throws {

		nonisolated(unsafe) var exportError: Error?

		queue.runInTransactionSync { database in
			guard database.executeUpdate("ATTACH DATABASE ? AS \(attachedSchemaName);", withArgumentsIn: [destinationPath]) else {
				exportError = ArticleSQLiteExportError.attachFailed
				return
			}
			defer {
				database.executeUpdate("DETACH DATABASE \(attachedSchemaName);", withArgumentsIn: [])
			}

			do {
				try Self.copyItems(feedIDs: feedIDs, database: database)
			} catch {
				exportError = error
				// Roll back explicitly: runInTransactionSync commits unconditionally
				// on return, matching AmbrosiaSQLiteImportTable's own import path.
				database.executeStatements("ROLLBACK;")
				database.executeStatements("BEGIN TRANSACTION;")
			}
		}

		if let exportError {
			Self.logger.error("ArticleSQLiteExportTable: export failed: \(String(describing: exportError), privacy: .public)")
			throw exportError
		}
	}

	private static func copyItems(feedIDs: Set<String>?, database: FMDatabase) throws {

		var articlesWhereClause = ""
		var articlesArgs = [Any]()
		if let feedIDs, !feedIDs.isEmpty {
			let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
			articlesWhereClause = "WHERE feedID IN \(placeholders)"
			articlesArgs = Array(feedIDs)
		}

		let createArticlesSQL = """
		CREATE TABLE \(attachedSchemaName).articles AS
		SELECT * FROM articles \(articlesWhereClause);
		"""
		guard database.executeUpdate(createArticlesSQL, withArgumentsIn: articlesArgs) else {
			throw ArticleSQLiteExportError.exportFailed("articles export: \(database.lastErrorMessage() ?? "unknown error")")
		}

		// Scoped by a join against the just-created export.articles rather
		// than re-deriving the feedID filter, so this stays correct even if
		// the articles WHERE clause above changes shape later.
		let createStatusesSQL = """
		CREATE TABLE \(attachedSchemaName).statuses AS
		SELECT s.* FROM statuses AS s
		INNER JOIN \(attachedSchemaName).articles AS a ON a.articleID = s.articleID;
		"""
		guard database.executeUpdate(createStatusesSQL, withArgumentsIn: []) else {
			throw ArticleSQLiteExportError.exportFailed("statuses export: \(database.lastErrorMessage() ?? "unknown error")")
		}
	}
}
