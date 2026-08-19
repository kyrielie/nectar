//
//  BackupSQLiteImportTable.swift
//  ArticlesDatabase
//
//  Backup/restore plan, "Suggested build order" step 4: merges a backup's
//  full-snapshot `DB.sqlite3` (produced by ArticlesDatabaseFullSnapshotExportTable's
//  `VACUUM INTO`, see ArticlesDatabaseFullSnapshotExport.swift) into the live
//  database via `ATTACH DATABASE`, following the "Merge guarantees" table in
//  the backup/restore plan exactly:
//
//    articles     -- INSERT OR IGNORE keyed on articleID (immutable once
//                    fetched; nothing to prefer, only present-or-not).
//    statuses,
//    bookState    -- OR-of-booleans for read/starred/loved (never let a
//                    real action "un-happen" because the other copy hadn't
//                    caught up); scrollPosition/readingProgress taken from
//                    whichever row has the later lastOpenedAt (statuses) /
//                    updatedAt (bookState) -- these two tables use different
//                    timestamp columns to arbitrate because that's what each
//                    table actually maintains (see below).
//    annotations  -- NOT a plain INSERT OR IGNORE, despite the plan's
//                    initial assumption. AnnotationsTable.save is a full
//                    ON CONFLICT DO UPDATE upsert, and updateNote/
//                    updateColor/markOrphaned/reanchor all mutate an
//                    existing row in place keyed by the same annotationID --
//                    so the same annotationID genuinely can hold diverged
//                    values on two devices (a note added on device A, an
//                    independent re-anchor on device B). Every one of those
//                    mutation paths also stamps `updatedAt`, so the correct
//                    rule -- and the one implemented here -- is: on a
//                    conflicting annotationID, keep whichever row (local vs.
//                    backup) has the later updatedAt, not "local always
//                    wins" and not a blind union.
//
//  This mirrors AmbrosiaSQLiteImportTable's ATTACH/BEGIN/DETACH ordering
//  exactly -- see the extended comment on that ordering in
//  AmbrosiaSQLiteImportTable.importTransfer, which is not repeated in full
//  here. In short: DETACH must run only after the transaction touching the
//  attached database has itself been committed or rolled back (SQLite
//  refuses to DETACH a database still part of an open transaction), so
//  transaction control is handled by hand via runInDatabaseSync rather than
//  runInTransactionSync, with DETACH issued after an explicit commit/
//  rollback and its own result checked (logged, not thrown, on failure --
//  a failed DETACH doesn't undo an already-committed import).
//
//  Every statement in this file is additive-only by construction: no DELETE,
//  no INSERT OR REPLACE. Definition of done in the backup/restore plan
//  requires this to hold for the whole import path.
//

import Foundation
import os
import RSDatabase
import RSDatabaseObjC

public enum BackupSQLiteImportError: Error, CustomStringConvertible {
	case attachFailed(String)
	case importFailed(String)

	public var description: String {
		switch self {
		case .attachFailed(let detail):
			return "Backup SQLite import: ATTACH DATABASE failed (\(detail))"
		case .importFailed(let detail):
			return "Backup SQLite import: merge failed (\(detail))"
		}
	}
}

enum BackupSQLiteImportTable {

	private static let logger = Logger(subsystem: "ArticlesDatabase", category: "BackupSQLiteImportTable")

	/// The alias the backup's DB.sqlite3 is ATTACHed under for the duration of the merge.
	private static let attachedSchemaName = "backup_restore"

	/// Runs the full non-destructive merge described at the top of this file.
	/// `backupDatabasePath` is a backup's `DB.sqlite3` (a full-snapshot export,
	/// so it has every table this database does -- articles, statuses,
	/// bookState, annotations, search). Throws on any failure with no partial
	/// writes: everything after ATTACH runs inside one explicit transaction,
	/// rolled back on error before DETACH is attempted.
	static func importBackup(backupDatabasePath: String, queue: DatabaseQueue) throws {
		nonisolated(unsafe) var importError: Error?

		// runInDatabaseSync, not runInTransactionSync -- see the file-level
		// comment above and AmbrosiaSQLiteImportTable.importTransfer's own
		// comment on why DETACH has to run after an explicit commit/rollback,
		// not inside runInTransactionSync's deferred-COMMIT block.
		queue.runInDatabaseSync { database in
			guard database.executeUpdate("ATTACH DATABASE ? AS \(attachedSchemaName);", withArgumentsIn: [backupDatabasePath]) else {
				importError = BackupSQLiteImportError.attachFailed(database.lastErrorMessage() ?? "unknown error")
				return
			}

			database.beginTransaction()
			do {
				try Self.mergeArticles(database: database)
				try Self.mergeStatuses(database: database)
				try Self.mergeBookState(database: database)
				try Self.mergeAnnotations(database: database)
				database.commit()
			} catch {
				importError = error
				database.rollback()
			}

			// Same ordering constraint as AmbrosiaSQLiteImportTable.importTransfer:
			// DETACH must come after the transaction has been committed or
			// rolled back, or SQLite refuses it ("database ... is locked").
			database.clearCachedStatements()
			if !database.executeUpdate("DETACH DATABASE \(attachedSchemaName);", withArgumentsIn: []) {
				Self.logger.error("BackupSQLiteImportTable: DETACH DATABASE \(attachedSchemaName, privacy: .public) failed -- \(database.lastErrorMessage(), privacy: .public)")
			}
		}

		if let importError {
			Self.logger.error("BackupSQLiteImportTable: import failed: \(String(describing: importError), privacy: .public)")
			throw importError
		}
	}

	// MARK: - articles

	/// Keep both; new-only rows added, existing rows untouched. An article's
	/// content is immutable once fetched -- there's nothing to "prefer," only
	/// present-or-not.
	///
	/// Column list: the base `CREATE TABLE if not EXISTS articles` in
	/// ArticlesDatabase.swift only carries a subset of the columns this table
	/// actually has today -- `bookKey`, `isAmbrosiaItem`, the four AO3 Work
	/// Header stats columns (`commentCount`/`kudosCount`/`bookmarkCount`/
	/// `hitCount`), `previousWorkURL`/`nextWorkURL`, `lastPrefaceFetchDate`,
	/// and the Task 8 pending-update/regression-guard columns
	/// (`pendingUpdateContentHTML`/`pendingUpdateDetectedAt`/
	/// `wordCountRegressionFlaggedAt`/`ao3ConfirmedMissingAt`) all arrive via
	/// separate `containsColumn`-guarded `ALTER TABLE` statements in
	/// `ArticlesDatabase.performInitialSetup`/schema-migration code, not the
	/// CREATE TABLE literal. Both the live DB and a backup produced by this
	/// app version have every one of these columns, since
	/// `exportFullSnapshot` runs `VACUUM INTO` against the already-migrated
	/// live schema -- so this list is the full, current column set (verified
	/// against every `ALTER TABLE articles add column` in
	/// ArticlesDatabase.swift and DatabaseKey's declarations), not just the
	/// base CREATE TABLE's subset.
	///
	/// `searchRowID` is deliberately excluded from both the column list and
	/// the SELECT -- it's not portable article data, it's a foreign-key-like
	/// pointer into *this* database's own FTS `search.rowid`
	/// (`articles_after_delete_trigger_delete_search_text` deletes `search`
	/// rows by matching `OLD.searchRowID`). Copying the backup's raw
	/// searchRowID value would point at whatever row happens to have that
	/// rowid in the local `search` table -- wrong article, or nonexistent,
	/// take your pick. Leaving the column out of this INSERT lets it default
	/// to its natural NULL, which is exactly the "never indexed yet" state
	/// `SearchTable.fetchUnindexedArticles`'s `searchRowID is null` query
	/// already looks for -- a restored article gets indexed the ordinary way
	/// via the existing `indexUnindexedArticles()` path, not something this
	/// import needs to special-case.
	private static func mergeArticles(database: FMDatabase) throws {
		let sql = """
		INSERT OR IGNORE INTO articles (
		  articleID, feedID, uniqueID, title, contentHTML, contentText, markdown,
		  url, externalURL, summary, imageURL, bannerImageURL, datePublished, dateModified,
		  authors, wordCount, chapterCurrent, chapterTotal, isComplete,
		  fandoms, relationships, characters, ratings, warnings, categories, additionalTags, series,
		  bookKey, isAmbrosiaItem,
		  commentCount, kudosCount, bookmarkCount, hitCount,
		  previousWorkURL, nextWorkURL, lastPrefaceFetchDate,
		  pendingUpdateContentHTML, pendingUpdateDetectedAt, wordCountRegressionFlaggedAt, ao3ConfirmedMissingAt
		)
		SELECT
		  b.articleID, b.feedID, b.uniqueID, b.title, b.contentHTML, b.contentText, b.markdown,
		  b.url, b.externalURL, b.summary, b.imageURL, b.bannerImageURL, b.datePublished, b.dateModified,
		  b.authors, b.wordCount, b.chapterCurrent, b.chapterTotal, b.isComplete,
		  b.fandoms, b.relationships, b.characters, b.ratings, b.warnings, b.categories, b.additionalTags, b.series,
		  b.bookKey, b.isAmbrosiaItem,
		  b.commentCount, b.kudosCount, b.bookmarkCount, b.hitCount,
		  b.previousWorkURL, b.nextWorkURL, b.lastPrefaceFetchDate,
		  b.pendingUpdateContentHTML, b.pendingUpdateDetectedAt, b.wordCountRegressionFlaggedAt, b.ao3ConfirmedMissingAt
		FROM \(attachedSchemaName).articles AS b;
		"""
		guard database.executeUpdate(sql, withArgumentsIn: []) else {
			throw BackupSQLiteImportError.importFailed("articles merge: \(database.lastErrorMessage() ?? "unknown error")")
		}
	}

	// MARK: - statuses

	/// OR-of-booleans for read/starred/loved -- a real action should never
	/// un-happen because the other copy hadn't caught up yet. scrollPosition/
	/// readingProgress are taken from whichever row (local vs. backup) has the
	/// later `lastOpenedAt` -- `statuses` has no `updatedAt` column (confirmed
	/// against the schema; only `lastOpenedAt`/`dateArrived` exist), so
	/// `lastOpenedAt` is the only real per-row timestamp this table maintains,
	/// and is what arbitrates here. A row present only in the backup is
	/// inserted as-is; a row present only locally is untouched by construction
	/// (this statement only ever touches articleIDs the backup also has).
	private static func mergeStatuses(database: FMDatabase) throws {
		// New-only rows: statuses whose articleID exists in the backup but not
		// locally. Plain INSERT OR IGNORE is correct here since there is no
		// local row to merge against.
		let insertNewSQL = """
		INSERT OR IGNORE INTO statuses (
		  articleID, read, starred, loved, dateArrived, scrollPosition, readingProgress, lastOpenedAt
		)
		SELECT
		  b.articleID, b.read, b.starred, b.loved, b.dateArrived, b.scrollPosition, b.readingProgress, b.lastOpenedAt
		FROM \(attachedSchemaName).statuses AS b;
		"""
		guard database.executeUpdate(insertNewSQL, withArgumentsIn: []) else {
			throw BackupSQLiteImportError.importFailed("statuses insert-new: \(database.lastErrorMessage() ?? "unknown error")")
		}

		// Conflicting rows (articleID exists on both sides): OR the booleans,
		// and take scrollPosition/readingProgress from whichever side has the
		// later lastOpenedAt. INSERT OR IGNORE above already made every
		// backup-only row a real local row, so this UPDATE...FROM only needs
		// to handle genuine both-sides conflicts -- it's a no-op for rows the
		// INSERT above just created (their values already match).
		let mergeConflictsSQL = """
		UPDATE statuses SET
		  read = read OR (SELECT b.read FROM \(attachedSchemaName).statuses AS b WHERE b.articleID = statuses.articleID),
		  starred = starred OR (SELECT b.starred FROM \(attachedSchemaName).statuses AS b WHERE b.articleID = statuses.articleID),
		  loved = loved OR (SELECT b.loved FROM \(attachedSchemaName).statuses AS b WHERE b.articleID = statuses.articleID),
		  scrollPosition = CASE
		    WHEN (SELECT b.lastOpenedAt FROM \(attachedSchemaName).statuses AS b WHERE b.articleID = statuses.articleID) > statuses.lastOpenedAt
		    THEN (SELECT b.scrollPosition FROM \(attachedSchemaName).statuses AS b WHERE b.articleID = statuses.articleID)
		    ELSE statuses.scrollPosition
		  END,
		  readingProgress = CASE
		    WHEN (SELECT b.lastOpenedAt FROM \(attachedSchemaName).statuses AS b WHERE b.articleID = statuses.articleID) > statuses.lastOpenedAt
		    THEN (SELECT b.readingProgress FROM \(attachedSchemaName).statuses AS b WHERE b.articleID = statuses.articleID)
		    ELSE statuses.readingProgress
		  END,
		  lastOpenedAt = CASE
		    WHEN (SELECT b.lastOpenedAt FROM \(attachedSchemaName).statuses AS b WHERE b.articleID = statuses.articleID) > statuses.lastOpenedAt
		    THEN (SELECT b.lastOpenedAt FROM \(attachedSchemaName).statuses AS b WHERE b.articleID = statuses.articleID)
		    ELSE statuses.lastOpenedAt
		  END
		WHERE articleID IN (SELECT b.articleID FROM \(attachedSchemaName).statuses AS b);
		"""
		guard database.executeUpdate(mergeConflictsSQL, withArgumentsIn: []) else {
			throw BackupSQLiteImportError.importFailed("statuses merge-conflicts: \(database.lastErrorMessage() ?? "unknown error")")
		}
	}

	// MARK: - bookState

	/// Same OR-of-booleans / later-timestamp shape as statuses, but keyed on
	/// bookKey and arbitrated by `updatedAt` -- bookState (unlike statuses)
	/// has a real `updatedAt` column stamped by every upsert path (setRead/
	/// setStarred/setLoved/setScrollPosition/setReadingProgress/
	/// setLastOpenedAt/setKudosAttempted, see BookStateTable.upsert), so
	/// `updatedAt` is the correct arbiter here rather than `lastOpenedAt`.
	/// `kudosAttemptedAt`/`kudosAttemptedAuthenticated` gate a network
	/// side-effect (posting a kudos) rather than describing reading state, so
	/// they get their own rule rather than folding into the timestamp
	/// arbitration above: prefer whichever side has already attempted
	/// (`kudosAttemptedAt IS NOT NULL`), since "attempted" only ever gates
	/// skipping a future attempt and never triggers a re-post -- this can
	/// never cause a duplicate kudos, only (correctly, conservatively) avoid
	/// one that already happened on the other device.
	private static func mergeBookState(database: FMDatabase) throws {
		let insertNewSQL = """
		INSERT OR IGNORE INTO bookState (
		  bookKey, read, starred, loved, scrollPosition, readingProgress, lastOpenedAt,
		  updatedAt, kudosAttemptedAt, kudosAttemptedAuthenticated
		)
		SELECT
		  b.bookKey, b.read, b.starred, b.loved, b.scrollPosition, b.readingProgress, b.lastOpenedAt,
		  b.updatedAt, b.kudosAttemptedAt, b.kudosAttemptedAuthenticated
		FROM \(attachedSchemaName).bookState AS b;
		"""
		guard database.executeUpdate(insertNewSQL, withArgumentsIn: []) else {
			throw BackupSQLiteImportError.importFailed("bookState insert-new: \(database.lastErrorMessage() ?? "unknown error")")
		}

		let mergeConflictsSQL = """
		UPDATE bookState SET
		  read = read OR (SELECT b.read FROM \(attachedSchemaName).bookState AS b WHERE b.bookKey = bookState.bookKey),
		  starred = starred OR (SELECT b.starred FROM \(attachedSchemaName).bookState AS b WHERE b.bookKey = bookState.bookKey),
		  loved = loved OR (SELECT b.loved FROM \(attachedSchemaName).bookState AS b WHERE b.bookKey = bookState.bookKey),
		  scrollPosition = CASE
		    WHEN (SELECT b.updatedAt FROM \(attachedSchemaName).bookState AS b WHERE b.bookKey = bookState.bookKey) > bookState.updatedAt
		    THEN (SELECT b.scrollPosition FROM \(attachedSchemaName).bookState AS b WHERE b.bookKey = bookState.bookKey)
		    ELSE bookState.scrollPosition
		  END,
		  readingProgress = CASE
		    WHEN (SELECT b.updatedAt FROM \(attachedSchemaName).bookState AS b WHERE b.bookKey = bookState.bookKey) > bookState.updatedAt
		    THEN (SELECT b.readingProgress FROM \(attachedSchemaName).bookState AS b WHERE b.bookKey = bookState.bookKey)
		    ELSE bookState.readingProgress
		  END,
		  lastOpenedAt = CASE
		    WHEN (SELECT b.updatedAt FROM \(attachedSchemaName).bookState AS b WHERE b.bookKey = bookState.bookKey) > bookState.updatedAt
		    THEN (SELECT b.lastOpenedAt FROM \(attachedSchemaName).bookState AS b WHERE b.bookKey = bookState.bookKey)
		    ELSE bookState.lastOpenedAt
		  END,
		  kudosAttemptedAt = CASE
		    WHEN bookState.kudosAttemptedAt IS NOT NULL THEN bookState.kudosAttemptedAt
		    ELSE (SELECT b.kudosAttemptedAt FROM \(attachedSchemaName).bookState AS b WHERE b.bookKey = bookState.bookKey)
		  END,
		  kudosAttemptedAuthenticated = CASE
		    WHEN bookState.kudosAttemptedAt IS NOT NULL THEN bookState.kudosAttemptedAuthenticated
		    ELSE (SELECT b.kudosAttemptedAuthenticated FROM \(attachedSchemaName).bookState AS b WHERE b.bookKey = bookState.bookKey)
		  END,
		  updatedAt = CASE
		    WHEN (SELECT b.updatedAt FROM \(attachedSchemaName).bookState AS b WHERE b.bookKey = bookState.bookKey) > bookState.updatedAt
		    THEN (SELECT b.updatedAt FROM \(attachedSchemaName).bookState AS b WHERE b.bookKey = bookState.bookKey)
		    ELSE bookState.updatedAt
		  END
		WHERE bookKey IN (SELECT b.bookKey FROM \(attachedSchemaName).bookState AS b);
		"""
		guard database.executeUpdate(mergeConflictsSQL, withArgumentsIn: []) else {
			throw BackupSQLiteImportError.importFailed("bookState merge-conflicts: \(database.lastErrorMessage() ?? "unknown error")")
		}
	}

	// MARK: - annotations

	/// NOT a plain union-merge -- see the file-level comment for why. On a
	/// conflicting annotationID (present on both sides with possibly-diverged
	/// values), keep whichever row has the later `updatedAt`; every mutation
	/// path on AnnotationsTable (save/updateNote/updateColor/markOrphaned/
	/// reanchor) stamps updatedAt, so it's a reliable arbiter here the same
	/// way it is for bookState. New-only annotationIDs are inserted as-is.
	/// Column list includes `chapterTitle`, added via an ALTER TABLE
	/// migration after the base CREATE TABLE (see AnnotationsTable.swift's
	/// header comment) -- both the local DB and a backup produced by this
	/// app version have it, since exportFullSnapshot runs against the live,
	/// already-migrated schema.
	private static func mergeAnnotations(database: FMDatabase) throws {
		let insertNewSQL = """
		INSERT OR IGNORE INTO annotations (
		  annotationID, articleID, bookKey, quoteExact, quotePrefix, quoteSuffix,
		  rootSelector, startOffset, endOffset, color, note, chapterTitle,
		  createdAt, updatedAt, orphanedAt, lastReanchoredAt
		)
		SELECT
		  b.annotationID, b.articleID, b.bookKey, b.quoteExact, b.quotePrefix, b.quoteSuffix,
		  b.rootSelector, b.startOffset, b.endOffset, b.color, b.note, b.chapterTitle,
		  b.createdAt, b.updatedAt, b.orphanedAt, b.lastReanchoredAt
		FROM \(attachedSchemaName).annotations AS b;
		"""
		guard database.executeUpdate(insertNewSQL, withArgumentsIn: []) else {
			throw BackupSQLiteImportError.importFailed("annotations insert-new: \(database.lastErrorMessage() ?? "unknown error")")
		}

		// Conflicting annotationIDs: replace the local row wholesale with the
		// backup's row only when the backup's updatedAt is strictly later --
		// a full-row overwrite (not a column-by-column OR/CASE like
		// statuses/bookState above) because AnnotationsTable.save itself is a
		// full-row upsert, not a partial one: there's no "leave the other
		// columns alone" case for an annotation the way there is for
		// bookState's single-column upsert helper, so the later row wins in
		// full, matching how the annotation was actually written on its own
		// device.
		let mergeConflictsSQL = """
		UPDATE annotations SET
		  articleID = (SELECT b.articleID FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID),
		  bookKey = (SELECT b.bookKey FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID),
		  quoteExact = (SELECT b.quoteExact FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID),
		  quotePrefix = (SELECT b.quotePrefix FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID),
		  quoteSuffix = (SELECT b.quoteSuffix FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID),
		  rootSelector = (SELECT b.rootSelector FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID),
		  startOffset = (SELECT b.startOffset FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID),
		  endOffset = (SELECT b.endOffset FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID),
		  color = (SELECT b.color FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID),
		  note = (SELECT b.note FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID),
		  chapterTitle = (SELECT b.chapterTitle FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID),
		  updatedAt = (SELECT b.updatedAt FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID),
		  orphanedAt = (SELECT b.orphanedAt FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID),
		  lastReanchoredAt = (SELECT b.lastReanchoredAt FROM \(attachedSchemaName).annotations AS b WHERE b.annotationID = annotations.annotationID)
		WHERE annotationID IN (
		  SELECT b.annotationID FROM \(attachedSchemaName).annotations AS b
		  WHERE b.updatedAt > annotations.updatedAt
		);
		"""
		guard database.executeUpdate(mergeConflictsSQL, withArgumentsIn: []) else {
			throw BackupSQLiteImportError.importFailed("annotations merge-conflicts: \(database.lastErrorMessage() ?? "unknown error")")
		}
	}
}
