//
//  ArticlesDatabaseFullSnapshotExport.swift
//  ArticlesDatabase
//
//  Backup/restore plan, "Suggested build order" step 1:
//  ArticlesDatabase.exportFullSnapshot(toPath:), an atomic, consistent
//  full-database copy via `VACUUM INTO ?` -- deliberately not
//  ArticleSQLiteExportTable's ATTACH + CREATE TABLE AS SELECT idiom,
//  which is a partial (articles/statuses/annotations only, no bookState,
//  no search) copy meant for the existing per-feed "Export..." feature.
//  This is the whole database, byte-for-byte consistent as of the moment
//  VACUUM INTO runs, including bookState and the FTS `search` virtual
//  table -- see ArticlesDatabaseFullSnapshotExportTests for the round-trip
//  proof that FTS specifically survives this.
//
//  `VACUUM INTO` cannot run inside an explicit transaction (SQLite
//  rejects it), so this goes through `runInDatabaseSync`, not
//  `runInTransactionSync` -- the other ATTACH-based export/import paths
//  in this file (ArticleSQLiteExportTable, AmbrosiaSQLiteImportTable) use
//  runInTransactionSync because they run ordinary DML they can roll back;
//  VACUUM INTO has no equivalent partial-failure state to roll back from,
//  it either produces a complete, valid destination file or it doesn't
//  run at all.
//

import Foundation
import os
import RSDatabase
import RSDatabaseObjC

public enum ArticlesDatabaseFullSnapshotExportError: Error, CustomStringConvertible {
	case destinationAlreadyExists(String)
	case vacuumIntoFailed(String)

	public var description: String {
		switch self {
		case .destinationAlreadyExists(let path):
			return "ArticlesDatabase full snapshot export: destination already exists at \(path)"
		case .vacuumIntoFailed(let detail):
			return "ArticlesDatabase full snapshot export: VACUUM INTO failed (\(detail))"
		}
	}
}

enum ArticlesDatabaseFullSnapshotExportTable {

	private static let logger = Logger(subsystem: "ArticlesDatabase", category: "ArticlesDatabaseFullSnapshotExport")

	/// `destinationPath` must not already exist -- same contract as
	/// ArticleSQLiteExportTable.exportArticles, and for the same reason:
	/// `VACUUM INTO` refuses to write over an existing file, so a stale
	/// leftover from a prior failed export would otherwise surface as a
	/// confusing SQL error rather than this explicit, named case.
	static func exportFullSnapshot(toPath destinationPath: String, queue: DatabaseQueue) throws {
		if FileManager.default.fileExists(atPath: destinationPath) {
			throw ArticlesDatabaseFullSnapshotExportError.destinationAlreadyExists(destinationPath)
		}

		nonisolated(unsafe) var exportError: Error?

		queue.runInDatabaseSync { database in
			guard database.executeUpdate("VACUUM INTO ?;", withArgumentsIn: [destinationPath]) else {
				exportError = ArticlesDatabaseFullSnapshotExportError.vacuumIntoFailed(database.lastErrorMessage() ?? "unknown error")
				return
			}
		}

		if let exportError {
			Self.logger.error("ArticlesDatabaseFullSnapshotExportTable: export failed: \(String(describing: exportError), privacy: .public)")
			throw exportError
		}
	}
}
