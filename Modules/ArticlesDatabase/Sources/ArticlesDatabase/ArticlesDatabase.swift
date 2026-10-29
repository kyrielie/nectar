//
//  ArticlesDatabase.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/20/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import os
import RSCore
import RSDatabase
import RSDatabaseObjC
import RSParser
import Articles

// This file is the entirety of the public API for ArticlesDatabase.framework.
// Everything else is implementation.

public typealias UnreadCountDictionary = [String: Int] // feedID: unreadCount

public struct ArticleChanges: Sendable {
	public let new: Set<Article>?
	public let updated: Set<Article>?
	public let deleted: Set<Article>?

	public init() {
		self.new = Set<Article>()
		self.updated = Set<Article>()
		self.deleted = Set<Article>()
	}

	public init(new: Set<Article>?, updated: Set<Article>?, deleted: Set<Article>?) {
		self.new = new
		self.updated = updated
		self.deleted = deleted
	}
}

/// Aggregate counts for a single account's articles database.
public struct ArticleCounts: Sendable {
	public let totalCount: Int
	public let unreadCount: Int
	public let starredCount: Int
	public let statusesCount: Int
}

/// One article's stored (compressed) `contentHTML` size, for the Manage
/// Storage screen. `storedContentHTMLSize` is the LZFSE-compressed,
/// base64-encoded size actually held in the `articles.contentHTML` column --
/// an honest number since it's what's actually on disk, not a decompressed
/// estimate.
public struct ArticleStorageInfo: Sendable {
	public let articleID: String
	public let title: String?
	public let bookKey: String?
	public let storedContentHTMLSize: Int
}

/// One article that needs the person's attention on the AO3 "Works Needing
/// Attention" screen: it has an unresolved pending content update, a
/// feed-derived word-count regression flag, or a confirmed-missing flag.
/// Unlike `ArticleStorageInfo`, it includes articles with no stored
/// `contentHTML`, since a work flagged missing may never have had any.
public struct ArticleAttentionInfo: Sendable {
	public let articleID: String
	public let title: String?
	public let bookKey: String?
	public let pendingUpdateDetectedAt: Date?
	public let wordCountRegressionFlaggedAt: Date?
	public let ao3ConfirmedMissingAt: Date?
	/// Whether `pendingUpdateContentHTML` is set. The HTML itself is not
	/// loaded: it can be large and the list does not need it.
	public let hasPendingUpdate: Bool

	public init(articleID: String, title: String?, bookKey: String?, pendingUpdateDetectedAt: Date?, wordCountRegressionFlaggedAt: Date?, ao3ConfirmedMissingAt: Date?, hasPendingUpdate: Bool) {
		self.articleID = articleID
		self.title = title
		self.bookKey = bookKey
		self.pendingUpdateDetectedAt = pendingUpdateDetectedAt
		self.wordCountRegressionFlaggedAt = wordCountRegressionFlaggedAt
		self.ao3ConfirmedMissingAt = ao3ConfirmedMissingAt
		self.hasPendingUpdate = hasPendingUpdate
	}
}

@MainActor public final class ArticlesDatabase {
	public enum RetentionStyle: Sendable {
		case feedBased // Local and iCloud: article retention is defined by contents of feed
		case syncSystem // Feedbin, Feedly, etc.: article retention is defined by external system
	}

	public nonisolated let databasePath: String

	private let articlesTable: ArticlesTable
	// Internal, not private: AmbrosiaSQLiteImportTable (Phase 2 SQLite transfer
	// import) needs direct queue access to ATTACH DATABASE the downloaded
	// transfer file and bulk-copy into articles/statuses on the same
	// connection. Every other reader/writer of this database still goes
	// through articlesTable/queue.runInDatabase* below -- this does not
	// widen the public API surface outside the module.
	let queue: DatabaseQueue
	private let operationQueue = MainThreadOperationQueue()
	private let retentionStyle: RetentionStyle
	private let accountID: String

	nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ArticlesDatabase")

	/// Gates the one-time migration block in `init` below, via `PRAGMA
	/// Schema version tracking on this database's own "main" schema.
	/// Version 1 is the pristine public v1.0 baseline containing all modern
	/// tables, columns, indexes, and FTS search triggers in tableCreationStatements.
	nonisolated private static let currentSchemaVersion: UInt32 = 1

	public init(databaseFilePath: String, accountID: String, retentionStyle: RetentionStyle) {
		Self.logger.debug("Articles Database init \(accountID, privacy: .public)")

		self.databasePath = databaseFilePath
		let queue = DatabaseQueue(databasePath: databaseFilePath)
		self.queue = queue
		self.articlesTable = ArticlesTable(name: DatabaseTableName.articles, accountID: accountID, queue: queue, retentionStyle: retentionStyle)
		self.retentionStyle = retentionStyle
		self.accountID = accountID

		queue.runCreateStatements(ArticlesDatabase.tableCreationStatements)
		queue.runInDatabaseSync { database in
			Self.logger.debug("ArticlesDatabase: checking schema version \(accountID, privacy: .public)")

			let existingVersion = database.userVersion()
			guard existingVersion < Self.currentSchemaVersion else {
				return
			}

			// Newly created database: stamp baseline version 1 and return.
			if existingVersion == 0 {
				database.setUserVersion(Self.currentSchemaVersion)
				return
			}

			// Future migrations will be gated here:
			// if existingVersion < 2 { ... }

			database.setUserVersion(Self.currentSchemaVersion)
		}

		DispatchQueue.main.async {
			self.articlesTable.indexUnindexedArticles()
		}

		// Backfill the authors JSON column cooperatively, yielding between batches
		// so that other database work (fetches, etc.) can interleave.
		Task.detached { [accountID, queue] in
			let migration = AuthorsSchemaMigration(accountID: accountID, queue: queue)
			await migration.run()
		}
	}

	// MARK: - Vacuum

	public func vacuum() async {
		await queue.vacuum()
	}

	// MARK: - Repairing

	/// Repair status rows that disagree with their in-memory statuses,
	/// which can happen when a database write was lost.
	public func repairStatuses() {
		queue.runInDatabase { database in
			self.articlesTable.repairStatuses(database)
		}
	}

	// MARK: - Fetching Articles

	/// Phase 2 (Nectar SQLite transfer): imports a decompressed, version-checked
	/// `.sqlite` transfer file downloaded from Ambrosia's `/feed/collection/<id>.sqlite`,
	/// `/feed/search.sqlite`, or `/feed/random-daily.sqlite` routes. `temporaryFilePath`
	/// must already be the decompressed (LZFSE-decoded) file on disk; this method does
	/// not touch compression. Per the Wire Contract's explicit non-goals, this does not
	/// reindex search or write BookStateTable rows -- confirmed accepted trade-off.
	/// Throws on any failure (I/O, version mismatch, or SQL error) with no partial writes:
	/// the whole import runs inside one transaction and is rolled back on error.
	///
	/// Returns the new/updated Article values from this import so the caller can post
	/// `.AccountDidDownloadArticles` -- previously this import path wrote straight into
	/// the article tables without ever producing Article/ArticleChanges values, so that
	/// notification never fired for `.sqlite`-routed imports.
	@discardableResult
	public func importAmbrosiaSQLiteTransfer(temporaryFilePath: String, feedID: String, wireFormatVersion: Int32) throws -> ArticleChanges {
		Self.logger.debug("ArticlesDatabase: importAmbrosiaSQLiteTransfer \(self.accountID, privacy: .public) feedID: \(feedID, privacy: .public)")
		let (newIDs, updatedIDs) = try AmbrosiaSQLiteImportTable.importTransfer(temporaryFilePath: temporaryFilePath, feedID: feedID, expectedWireFormatVersion: wireFormatVersion, queue: queue)

		// AmbrosiaSQLiteImportTable writes articles/statuses with raw SQL
		// (INSERT OR REPLACE ... SELECT plus per-row UPDATEs) directly against
		// the attached transfer file, bypassing ArticlesTable's normal save
		// path entirely -- so nothing has dropped a stale articlesCache entry
		// for any articleID this import just overwrote. Without this, a
		// second import of a previously-seen id (a re-import with a changed
		// title/word count/etc.) hands back -- and every later fetchArticles
		// call for that id keeps handing back -- the first import's cached
		// Article rather than the row this import just wrote. New ids can't
		// already be cached, so only updatedIDs needs invalidating; same
		// pattern ArticlesTable.saveUpdatedArticle uses after its own direct write.
		if !updatedIDs.isEmpty {
			articlesTable.removeArticleIDsFromCache(updatedIDs)
		}

		let newArticles = newIDs.isEmpty ? nil : articlesTable.fetchArticles(articleIDs: newIDs)
		let updatedArticles = updatedIDs.isEmpty ? nil : articlesTable.fetchArticles(articleIDs: updatedIDs)
		return ArticleChanges(new: newArticles, updated: updatedArticles, deleted: nil)
	}

	/// Nectar Implementation Plan 3c: reads and validates a downloaded `.sqlite`
	/// transfer page's `transfer_manifest` table and wire-format version, without
	/// importing anything. Callers (`AmbrosiaSQLiteTransferFetcher`) use this to
	/// decide whether a page is trustworthy enough to import at all, before ever
	/// calling `importAmbrosiaSQLiteTransfer`. Throws on a wire-format-version
	/// mismatch, a missing/unreadable manifest, or a `page_row_count` that
	/// doesn't match the file's own `items` row count.
	public func readAmbrosiaSQLiteTransferManifest(temporaryFilePath: String, wireFormatVersion: Int32) throws -> AmbrosiaSQLiteTransferManifest {
		Self.logger.debug("ArticlesDatabase: readAmbrosiaSQLiteTransferManifest \(self.accountID, privacy: .public)")
		return try AmbrosiaSQLiteImportTable.readAndValidateManifest(atPath: temporaryFilePath, expectedWireFormatVersion: wireFormatVersion)
	}

	/// Task 4 (SQLite export): bulk-copies this account's articles/statuses
	/// into a fresh `.sqlite` file at `destinationPath`, optionally scoped
	/// to `feedIDs` (nil/empty exports every article in the account).
	/// `destinationPath` must not already exist.
	public func exportArticlesSQLite(feedIDs: Set<String>? = nil, toPath destinationPath: String) throws {
		Self.logger.debug("ArticlesDatabase: exportArticlesSQLite \(self.accountID, privacy: .public)")
		try ArticleSQLiteExportTable.exportArticles(feedIDs: feedIDs, toPath: destinationPath, queue: queue)
	}

	/// Backup/restore: an atomic, consistent copy of the *entire* database
	/// file (`VACUUM INTO`) -- articles, statuses, bookState, annotations,
	/// and the FTS `search` table, all in one call. Unlike
	/// `exportArticlesSQLite` above, this is not feed-scoped and is not
	/// meant for the per-feed "Export..." feature; it exists specifically
	/// so BackupManager can restore a fully-populated, immediately-usable
	/// database via `BackupSQLiteImportTable`, rather than replaying a
	/// partial export and losing bookState/search. `destinationPath` must
	/// not already exist.
	public func exportFullSnapshot(toPath destinationPath: String) throws {
		Self.logger.debug("ArticlesDatabase: exportFullSnapshot \(self.accountID, privacy: .public)")
		try ArticlesDatabaseFullSnapshotExportTable.exportFullSnapshot(toPath: destinationPath, queue: queue)
	}

	/// Backup/restore: non-destructive merge of a backup's full-snapshot
	/// `DB.sqlite3` (produced by `exportFullSnapshot` above, on this device
	/// or another one) into the live database -- articles, statuses,
	/// bookState, and annotations, per-table merge rules documented on
	/// `BackupSQLiteImportTable`. Every statement this issues is additive-only
	/// (`INSERT OR IGNORE` or an `UPDATE` that only ever widens toward "more
	/// true" or "more recent"); nothing is ever deleted, and nothing missing
	/// from the backup is ever touched. Does not reindex `search` -- a
	/// restored article's search row is picked up the same way any other
	/// unindexed article's is, via the existing `indexUnindexedArticles()`
	/// path, not something this import path needs to special-case.
	public func importBackupSnapshot(backupDatabasePath: String) throws {
		Self.logger.debug("ArticlesDatabase: importBackupSnapshot \(self.accountID, privacy: .public)")
		try BackupSQLiteImportTable.importBackup(backupDatabasePath: backupDatabasePath, queue: queue)

		// BackupSQLiteImportTable writes articles/statuses/bookState/annotations
		// with raw SQL directly against the attached backup file, bypassing
		// ArticlesTable/StatusesTable's normal save paths entirely -- so, same
		// reasoning as importAmbrosiaSQLiteTransfer above, any cached Article
		// for an articleID this import just touched (a conflicting statuses row
		// merged in-place) needs to be dropped rather than left stale. articles
		// merges are INSERT OR IGNORE only (no existing row is ever modified),
		// so only statuses' conflict-merge path can change what an already-cached
		// Article should report -- invalidate broadly here rather than trying to
		// thread the exact conflicting-ID set back out of BackupSQLiteImportTable,
		// since a restore is a rare, whole-database operation where cache-clear
		// cost is a non-issue.
		articlesTable.emptyCaches()
	}

	public func fetchArticles(feedID: String) -> Set<Article> {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchArticles(feedID)
	}

	public func fetchArticles(feedIDs: Set<String>) -> Set<Article> {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchArticles(feedIDs)
	}

	public func fetchArticles(articleIDs: Set<String>) -> Set<Article> {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchArticles(articleIDs: articleIDs)
	}

	/// Account-wide, no feed filter -- see `ArticlesTable.fetchArticles(bookKeys:_:)`'s
	/// own doc comment for why this is safe without the pre-migration
	/// uniqueID fallback `articleIDsForBookKeys` needs.
	public func fetchArticles(bookKeys: Set<String>) -> Set<Article> {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchArticles(bookKeys: bookKeys)
	}

	public func fetchUnreadArticles(feedIDs: Set<String>, limit: Int? = nil) -> Set<Article> {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchUnreadArticles(feedIDs, limit)
	}

	public func fetchReadArticles(feedIDs: Set<String>, limit: Int? = nil) -> Set<Article> {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchReadArticles(feedIDs, limit)
	}

	public func fetchReadArticlesCount(feedIDs: Set<String>) -> Int {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchReadArticlesCount(feedIDs)
	}

	public func fetchTodayArticles(feedIDs: Set<String>, limit: Int? = nil) -> Set<Article> {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchArticlesSince(feedIDs, todayCutoffDate(), limit)
	}

	public func fetchStarredArticles(feedIDs: Set<String>, limit: Int? = nil) -> Set<Article> {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchStarredArticles(feedIDs, limit)
	}

	public func fetchStarredArticlesCount(feedIDs: Set<String>) -> Int {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchStarredArticlesCount(feedIDs)
	}

	public func fetchLovedArticles(feedIDs: Set<String>, limit: Int? = nil) -> Set<Article> {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchLovedArticles(feedIDs, limit)
	}

	public func fetchLovedArticlesCount(feedIDs: Set<String>) -> Int {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchLovedArticlesCount(feedIDs)
	}

	// MARK: - Fetching Last Opened Articles (Last Opened smart feed)
	//
	// No fetchLastOpenedArticlesCount -- unlike Read/Loved/Read Later, the
	// badge is suppressed rather than repurposed (see LastOpenedFeedDelegate),
	// since "10" is a constant cap, not information about the library.

	public func fetchLastOpenedArticles(feedIDs: Set<String>, limit: Int? = nil) -> Set<Article> {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchLastOpenedArticles(feedIDs, limit)
	}

	/// Returns aggregate article counts (total, unread, starred, statuses) for the given feeds.
	public func fetchArticleCountsAsync(feedIDs: Set<String>) async -> ArticleCounts {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return await withCheckedContinuation { continuation in
			articlesTable.fetchArticleCountsAsync(feedIDs) { articleCounts in
				continuation.resume(returning: articleCounts)
			}
		}
	}

	/// Largest-N articles by stored (compressed) `contentHTML` size, sorted
	/// descending -- backs the Manage Storage screen's list.
	public func fetchArticleStorageInfo(limit: Int) async -> [ArticleStorageInfo] {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return await withCheckedContinuation { continuation in
			articlesTable.fetchArticleStorageInfoAsync(limit: limit) { info in
				continuation.resume(returning: info)
			}
		}
	}

	/// Newest-first articles with a pending update, a word-count regression
	/// flag or a confirmed-missing flag -- backs the AO3 Works Needing
	/// Attention screen.
	public func fetchAO3AttentionInfo(limit: Int) async -> [ArticleAttentionInfo] {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return await withCheckedContinuation { continuation in
			articlesTable.fetchAO3AttentionInfoAsync(limit: limit) { info in
				continuation.resume(returning: info)
			}
		}
	}

	/// Total stored (compressed) `contentHTML` size across all articles --
	/// backs the Manage Storage screen's total-on-disk-size figure.
	public func fetchTotalContentHTMLSize() async -> Int {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return await withCheckedContinuation { continuation in
			articlesTable.fetchTotalContentHTMLSizeAsync { size in
				continuation.resume(returning: size)
			}
		}
	}

	// MARK: - Kudos-on-like (Task 6)

	/// Whether/how a kudos POST has already been attempted for this book --
	/// nil if never attempted. See Task 6's re-attempt policy: a guest
	/// attempt can be retried once an AO3 account is configured, a
	/// logged-in attempt never can.
	public func kudosAttempt(bookKey: String) async -> (attemptedAt: Date, authenticated: Bool)? {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return await withCheckedContinuation { continuation in
			articlesTable.kudosAttemptAsync(bookKey: bookKey) { result in
				continuation.resume(returning: result)
			}
		}
	}

	/// Records that a kudos POST was attempted for this book, and whether
	/// it was an authenticated (logged-in) or guest attempt.
	public func setKudosAttempted(bookKey: String, authenticated: Bool) async {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		await withCheckedContinuation { continuation in
			articlesTable.setKudosAttemptedAsync(bookKey: bookKey, authenticated: authenticated) {
				continuation.resume()
			}
		}
	}

	// MARK: - Annotations (highlights + notes)

	/// Saves a new annotation, or replaces an existing one with the same
	/// annotationID wholesale (annotationID is client-generated, so this
	/// covers both create and edit). bookKey is re-resolved from articleID
	/// at write time, not trusted from the passed-in Annotation -- see
	/// ArticlesTable.saveAnnotationAsync.
	public func saveAnnotation(_ annotation: Annotation) async {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		await withCheckedContinuation { continuation in
			articlesTable.saveAnnotationAsync(annotation) {
				continuation.resume()
			}
		}
	}

	public func deleteAnnotation(annotationID: String) async {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		await withCheckedContinuation { continuation in
			articlesTable.deleteAnnotationAsync(annotationID: annotationID) {
				continuation.resume()
			}
		}
	}

	public func updateAnnotationNote(annotationID: String, note: String?) async {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		await withCheckedContinuation { continuation in
			articlesTable.updateAnnotationNoteAsync(annotationID: annotationID, note: note) {
				continuation.resume()
			}
		}
	}

	public func updateAnnotationColor(annotationID: String, color: Annotation.Color) async {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		await withCheckedContinuation { continuation in
			articlesTable.updateAnnotationColorAsync(annotationID: annotationID, color: color) {
				continuation.resume()
			}
		}
	}

	/// Marks anchor resolution as having failed to relocate this
	/// annotation's quote against current content -- see docs/annotations.md.
	public func markAnnotationOrphaned(annotationID: String, at date: Date) async {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		await withCheckedContinuation { continuation in
			articlesTable.markAnnotationOrphanedAsync(annotationID: annotationID, at: date) {
				continuation.resume()
			}
		}
	}

	/// Writes back corrected offsets/selector text after a successful
	/// re-anchor pass, clearing any prior orphaned mark -- see
	/// docs/annotations.md.
	public func reanchorAnnotation(annotationID: String, startOffset: Int, endOffset: Int, quoteExact: String, quotePrefix: String, quoteSuffix: String, chapterTitle: String?) async {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		await withCheckedContinuation { continuation in
			articlesTable.reanchorAnnotationAsync(
				annotationID: annotationID,
				startOffset: startOffset,
				endOffset: endOffset,
				quoteExact: quoteExact,
				quotePrefix: quotePrefix,
				quoteSuffix: quoteSuffix,
				chapterTitle: chapterTitle
			) {
				continuation.resume()
			}
		}
	}

	/// Sets hasHighlight/originalText/replacementText directly -- see
	/// docs/annotations.md's "Storage shape". Does not touch offsets/quote/
	/// chapterTitle; a caller that also needs those changed (an edit that
	/// shifts other rows' offsets) calls reanchorAnnotation separately.
	public func setAnnotationEditFields(annotationID: String, hasHighlight: Bool, originalText: String?, replacementText: String?) async {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		await withCheckedContinuation { continuation in
			articlesTable.setAnnotationEditFieldsAsync(
				annotationID: annotationID,
				hasHighlight: hasHighlight,
				originalText: originalText,
				replacementText: replacementText
			) {
				continuation.resume()
			}
		}
	}

	public func fetchAnnotations(articleID: String) async -> [Annotation] {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return await withCheckedContinuation { continuation in
			articlesTable.fetchAnnotationsAsync(articleID: articleID) { annotations in
				continuation.resume(returning: annotations)
			}
		}
	}

	/// Cross-chapter listing: every annotation for every article sharing this
	/// bookKey, regardless of which feed/collection copy each was made on.
	public func fetchAnnotations(bookKey: String) async -> [Annotation] {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return await withCheckedContinuation { continuation in
			articlesTable.fetchAnnotationsAsync(bookKey: bookKey) { annotations in
				continuation.resume(returning: annotations)
			}
		}
	}

	/// Every annotation in this account's database, unscoped -- the
	/// Settings "all my highlights" browse surface.
	public func fetchAllAnnotations() async -> [Annotation] {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return await withCheckedContinuation { continuation in
			articlesTable.fetchAllAnnotationsAsync { annotations in
				continuation.resume(returning: annotations)
			}
		}
	}

	public func fetchArticlesMatching(searchString: String, feedIDs: Set<String>) -> Set<Article> {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchArticlesMatching(searchString, feedIDs)
	}

	public func fetchArticlesMatchingWithArticleIDs(searchString: String, articleIDs: Set<String>) -> Set<Article> {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return articlesTable.fetchArticlesMatchingWithArticleIDs(searchString, articleIDs)
	}

	/// Returns a dictionary of feedID → latest article date for all feeds with articles.
	public func fetchLastUpdateDates() async -> [String: Date] {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return await withCheckedContinuation { continuation in
			articlesTable.fetchLastUpdateDatesAsync { lastUpdateDates in
				continuation.resume(returning: lastUpdateDates)
			}
		}
	}

	// MARK: - Fetching Articles Async

	public func fetchArticlesAsync(feedID: String) async -> Set<Article> {
		await withCheckedContinuation { continuation in
			_fetchArticlesAsync(feedID: feedID) { articles in
				continuation.resume(returning: articles)
			}
		}
	}

	public func fetchArticlesAsync(feedIDs: Set<String>) async -> Set<Article> {
		await withCheckedContinuation { continuation in
			_fetchArticlesAsync(feedIDs: feedIDs) { articles in
				continuation.resume(returning: articles)
			}
		}
	}

	public func fetchArticlesAsync(articleIDs: Set<String>) async -> Set<Article> {
		await withCheckedContinuation { continuation in
			_fetchArticlesAsync(articleIDs: articleIDs) { articles in
				continuation.resume(returning: articles)
			}
		}
	}

	/// Async counterpart to `fetchArticles(bookKeys:)` above.
	public func fetchArticlesAsync(bookKeys: Set<String>) async -> Set<Article> {
		await withCheckedContinuation { continuation in
			_fetchArticlesAsync(bookKeys: bookKeys) { articles in
				continuation.resume(returning: articles)
			}
		}
	}

	public func fetchUnreadArticlesAsync(feedIDs: Set<String>, limit: Int? = nil) async -> Set<Article> {
		await withCheckedContinuation { continuation in
			_fetchUnreadArticlesAsync(feedIDs: feedIDs, limit: limit) { articles in
				continuation.resume(returning: articles)
			}
		}
	}

	public func fetchTodayArticlesAsync(feedIDs: Set<String>, limit: Int? = nil) async -> Set<Article> {
		await withCheckedContinuation { continuation in
			_fetchTodayArticlesAsync(feedIDs: feedIDs, limit: limit) { articles in
				continuation.resume(returning: articles)
			}
		}
	}

	public func fetchedStarredArticlesAsync(feedIDs: Set<String>, limit: Int? = nil) async -> Set<Article> {
		await withCheckedContinuation { continuation in
			_fetchedStarredArticlesAsync(feedIDs: feedIDs, limit: limit) { articles in
				continuation.resume(returning: articles)
			}
		}
	}

	public func fetchedLovedArticlesAsync(feedIDs: Set<String>, limit: Int? = nil) async -> Set<Article> {
		await withCheckedContinuation { continuation in
			_fetchedLovedArticlesAsync(feedIDs: feedIDs, limit: limit) { articles in
				continuation.resume(returning: articles)
			}
		}
	}

	public func fetchedLastOpenedArticlesAsync(feedIDs: Set<String>, limit: Int? = nil) async -> Set<Article> {
		await withCheckedContinuation { continuation in
			_fetchedLastOpenedArticlesAsync(feedIDs: feedIDs, limit: limit) { articles in
				continuation.resume(returning: articles)
			}
		}
	}

	public func fetchedReadArticlesAsync(feedIDs: Set<String>, limit: Int? = nil) async -> Set<Article> {
		await withCheckedContinuation { continuation in
			_fetchedReadArticlesAsync(feedIDs: feedIDs, limit: limit) { articles in
				continuation.resume(returning: articles)
			}
		}
	}

	public func fetchArticlesMatchingAsync(searchString: String, feedIDs: Set<String>) async -> Set<Article> {
		await withCheckedContinuation { continuation in
			_fetchArticlesMatchingAsync(searchString: searchString, feedIDs: feedIDs) { articles in
				continuation.resume(returning: articles)
			}
		}
	}

	public func fetchArticlesMatchingWithArticleIDsAsync(searchString: String, articleIDs: Set<String>) async -> Set<Article> {
		await withCheckedContinuation { continuation in
			_fetchArticlesMatchingWithArticleIDsAsync(searchString: searchString, articleIDs: articleIDs) { articles in
				continuation.resume(returning: articles)
			}
		}
	}

	// MARK: - Unread Counts

	/// Fetch all non-zero unread counts.
	public func fetchAllUnreadCountsAsync() async -> UnreadCountDictionary? {
		await withCheckedContinuation { continuation in
			_fetchAllUnreadCounts { unreadCountDictionary in
				continuation.resume(returning: unreadCountDictionary)
			}
		}
	}

	/// Fetch unread count for a single feed.
	public func fetchUnreadCountAsync(feedID: String) async -> Int {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return await withCheckedContinuation { continuation in
			_fetchUnreadCounts(feedIDs: Set([feedID])) { unreadCountDictionary in
				if let unreadCount = unreadCountDictionary[feedID] {
					continuation.resume(returning: unreadCount)
				} else {
					continuation.resume(returning: 0)
				}
			}
		}
	}

	/// Fetch non-zero unread counts for given feedIDs.
	public func fetchUnreadCountsAsync(feedIDs: Set<String>) async -> UnreadCountDictionary {
		await withCheckedContinuation { continuation in
			_fetchUnreadCounts(feedIDs: feedIDs) { unreadCountDictionary in
				continuation.resume(returning: unreadCountDictionary)
			}
		}
	}

	public func fetchUnreadCountForTodayAsync(feedIDs: Set<String>) async -> Int {
		await withCheckedContinuation { continuation in
			_fetchUnreadCount(feedIDs: feedIDs, since: todayCutoffDate()) { unreadCount in
				continuation.resume(returning: unreadCount)
			}
		}
	}

	public func fetchUnreadCountForStarredArticlesAsync(feedIDs: Set<String>) async -> Int {
		await withCheckedContinuation { continuation in
			_fetchStarredAndUnreadCount(feedIDs: feedIDs) { unreadCount in
				continuation.resume(returning: unreadCount)
			}
		}
	}

	public func fetchUnreadCountForLovedArticlesAsync(feedIDs: Set<String>) async -> Int {
		await withCheckedContinuation { continuation in
			_fetchLovedAndUnreadCount(feedIDs: feedIDs) { unreadCount in
				continuation.resume(returning: unreadCount)
			}
		}
	}

	public func fetchTodayArticlesCountAsync(feedIDs: Set<String>) async -> Int {
		await withCheckedContinuation { continuation in
			articlesTable.fetchArticlesCountSince(feedIDs, todayCutoffDate()) { count in
				continuation.resume(returning: count)
			}
		}
	}

	public func fetchStarredArticlesCountAsync(feedIDs: Set<String>) async -> Int {
		await withCheckedContinuation { continuation in
			articlesTable.fetchStarredArticlesCountAsync(feedIDs) { count in
				continuation.resume(returning: count)
			}
		}
	}

	public func fetchLovedArticlesCountAsync(feedIDs: Set<String>) async -> Int {
		await withCheckedContinuation { continuation in
			articlesTable.fetchLovedArticlesCountAsync(feedIDs) { count in
				continuation.resume(returning: count)
			}
		}
	}

	public func fetchReadArticlesCountAsync(feedIDs: Set<String>) async -> Int {
		await withCheckedContinuation { continuation in
			articlesTable.fetchReadArticlesCountAsync(feedIDs) { count in
				continuation.resume(returning: count)
			}
		}
	}

	// MARK: - Saving, Updating, and Deleting Articles

	/// Update articles and save new ones — for feed-based systems (local and iCloud).
	public func updateAsync(parsedItems: Set<ParsedItem>, feedID: String, deleteOlder: Bool) async -> ArticleChanges {
		await withCheckedContinuation { continuation in
			_update(parsedItems: parsedItems, feedID: feedID, deleteOlder: deleteOlder) { articleChanges in
				continuation.resume(returning: articleChanges)
			}
		}
	}

	/// Update articles and save new ones — for sync systems (Feedbin, Feedly, etc.).
	public func updateAsync(feedIDsAndItems: [String: Set<ParsedItem>], defaultRead: Bool) async -> ArticleChanges {
		await withCheckedContinuation { continuation in
			_update(feedIDsAndItems: feedIDsAndItems, defaultRead: defaultRead) { articleChanges in
				continuation.resume(returning: articleChanges)
			}
		}
	}

	/// Delete articles
	public func deleteAsync(articleIDs: Set<String>) async {
		await withCheckedContinuation { continuation in
			_delete(articleIDs: articleIDs) {
				continuation.resume()
			}
		}
	}

	/// Clear an article's content while leaving its row (and every other
	/// column) intact -- see ArticlesTable.clearContentHTML's doc comment.
	public func clearContentHTMLAsync(articleIDs: Set<String>) async {
		await withCheckedContinuation { continuation in
			_clearContentHTML(articleIDs: articleIDs) {
				continuation.resume()
			}
		}
	}

	// MARK: - ArticleIDs

	/// Fetch the articleIDs of unread articles.
	public func fetchUnreadArticleIDsAsync() async -> Set<String> {
		await withCheckedContinuation { continuation in
			_fetchUnreadArticleIDsAsync { articleIDs in
				continuation.resume(returning: articleIDs)
			}
		}
	}

	public func fetchStarredArticleIDsAsync() async -> Set<String> {
		await withCheckedContinuation { continuation in
			_fetchStarredArticleIDsAsync { articleIDs in
				continuation.resume(returning: articleIDs)
			}
		}
	}

	public func fetchLovedArticleIDsAsync() async -> Set<String> {
		await withCheckedContinuation { continuation in
			_fetchLovedArticleIDsAsync { articleIDs in
				continuation.resume(returning: articleIDs)
			}
		}
	}

	/// Fetch articleIDs for articles that we should have, but don’t. These articles are either starred or newer than the article cutoff date.
	public func fetchArticleIDsForStatusesWithoutArticlesNewerThanCutoffDateAsync() async -> Set<String> {
		await withCheckedContinuation { continuation in
			_fetchArticleIDsForStatusesWithoutArticlesNewerThanCutoffDate { articleIDs in
				continuation.resume(returning: articleIDs)
			}
		}
	}

	// MARK: - Statuses

	/// Mark statuses for articleIDs. Returns the articleIDs whose status actually changed.
	public func markAsync(articleIDs: Set<String>, statusKey: ArticleStatus.Key, flag: Bool) async -> Set<String> {
		await withCheckedContinuation { continuation in
			_mark(articleIDs: articleIDs, statusKey: statusKey, flag: flag) { changedArticleIDs in
				continuation.resume(returning: changedArticleIDs)
			}
		}
	}

	public func markAndFetchNewAsync(articleIDs: Set<String>, statusKey: ArticleStatus.Key, flag: Bool) async -> Set<String> {
		await withCheckedContinuation { continuation in
			_markAndFetchNew(articleIDs: articleIDs, statusKey: statusKey, flag: flag) { articleIDs in
				continuation.resume(returning: articleIDs)
			}
		}
	}

	/// Create statuses for specified articleIDs. For existing statuses, don’t do anything.
	/// For newly-created statuses, mark them as read and not-starred.
	public func createStatusesIfNeededAsync(articleIDs: Set<String>) async {
		await withCheckedContinuation { continuation in
			_createStatusesIfNeeded(articleIDs: articleIDs) {
				continuation.resume()
			}
		}
	}

	/// Per-article scroll position (raw window.scrollY pixel value, same convention as
	/// windowScrollY). Replaces the old single-global AppDefaults.shared.articleWindowScrollY
	/// for cross-article persistence (Phase 2, reading behavior).
	public func saveScrollPositionAsync(_ scrollPosition: Double, articleID: String) async {
		await withCheckedContinuation { continuation in
			_saveScrollPosition(scrollPosition, articleID: articleID) {
				continuation.resume()
			}
		}
	}

	public func fetchScrollPositionAsync(articleID: String) async -> Double {
		await withCheckedContinuation { continuation in
			_fetchScrollPosition(articleID: articleID) { scrollPosition in
				continuation.resume(returning: scrollPosition)
			}
		}
	}

	/// Records that this book was just opened into the reader. bookKey-keyed and
	/// shared across every duplicate copy, same as read/starred/loved/
	/// scrollPosition -- opening any copy bumps the whole book. Does not send
	/// .StatusesDidChange (see StatusesTable.setLastOpenedAt); SceneCoordinator
	/// is responsible for deciding *whether* to call this at all (see
	/// currentArticle's didSet) so that opening a book from the Last Opened feed
	/// itself doesn't reorder that feed.
	public func recordBookOpenedAsync(articleID: String) async {
		await withCheckedContinuation { continuation in
			_recordBookOpened(articleID: articleID) {
				continuation.resume()
			}
		}
	}

	/// Fraction (0...1) of the article read (Phase A1). No fetch counterpart is needed:
	/// readingProgress is loaded in bulk as part of ArticleStatus (see StatusesTable),
	/// the same path `read`/`starred` already use, rather than a per-article async fetch.
	public func saveReadingProgressAsync(_ readingProgress: Double, articleID: String) async -> Set<String> {
		await withCheckedContinuation { continuation in
			_saveReadingProgress(readingProgress, articleID: articleID) { changedArticleIDs in
				continuation.resume(returning: changedArticleIDs)
			}
		}
	}

	// MARK: - Pending content update (Task 8)

	public func setPendingContentUpdateAsync(_ contentHTML: String, detectedAt: Date, articleID: String) async {
		await withCheckedContinuation { continuation in
			_setPendingContentUpdate(contentHTML, detectedAt: detectedAt, articleID: articleID) {
				continuation.resume()
			}
		}
	}

	public func resolvePendingContentUpdateAsync(articleID: String, accept: Bool) async {
		await withCheckedContinuation { continuation in
			_resolvePendingContentUpdate(articleID: articleID, accept: accept) {
				continuation.resume()
			}
		}
	}

	// MARK: - AO3 confirmed-missing

	public func setAO3ConfirmedMissingAsync(articleID: String) async {
		await withCheckedContinuation { continuation in
			_setAO3ConfirmedMissing(detectedAt: Date(), articleID: articleID) {
				continuation.resume()
			}
		}
	}

	public func clearAO3ConfirmedMissingAsync(articleID: String) async {
		await withCheckedContinuation { continuation in
			_clearAO3ConfirmedMissing(articleID: articleID) {
				continuation.resume()
			}
		}
	}

	public func clearWordCountRegressionFlagAsync(articleID: String) async {
		await withCheckedContinuation { continuation in
			_clearWordCountRegressionFlag(articleID: articleID) {
				continuation.resume()
			}
		}
	}

	// MARK: - Caches

	/// Call to free up some memory. Should be done when the app is backgrounded, for instance.
	/// This does not empty *all* caches — just the ones that are empty-able.
	/// `clearStatusesCache` defaults to true (genuine memory pressure); pass false for the
	/// ordinary-backgrounding case, where clearing the (small, cheap) ArticleStatus cache buys
	/// little memory and breaks the live in-place mutation `StatusesTable.saveReadingProgress`
	/// and friends depend on -- see `ArticlesTable.emptyCaches(clearStatusesCache:)`'s own doc
	/// comment for the full story.
	public func emptyCaches(clearStatusesCache: Bool = true) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.emptyCaches(clearStatusesCache: clearStatusesCache)
	}

	// MARK: - Cleanup

	/// Calls the various clean-up functions. To be used only at startup.
	///
	/// This prevents the database from growing forever. If we didn’t do this:
	/// 1) The database would grow to an inordinate size, and
	/// 2) the app would become very slow.
	public func cleanupDatabaseAtStartup(subscribedToFeedIDs: Set<String>) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		if retentionStyle == .syncSystem {
			articlesTable.deleteOldArticles()
		}
		articlesTable.deleteArticlesNotInSubscribedToFeedIDs(subscribedToFeedIDs)
		articlesTable.deleteOldStatuses()
	}

	/// Collapses duplicate article rows within `feedID` that share the same
	/// `bookKey` -- see `ArticlesTable.deduplicateArticles(feedID:completion:)`
	/// for the full rationale and per-group keep/delete rule. Called from
	/// `LocalAccountDelegate.createFeed` once a feed's `feedID` is known, so
	/// that re-adding a previously deleted feed doesn't leave old duplicate
	/// rows visible under the new subscription. A no-op for a `feedID` with
	/// no pre-existing rows, i.e. any genuinely new feed.
	public func deduplicateArticlesAsync(feedID: String) async {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		await withCheckedContinuation { continuation in
			articlesTable.deduplicateArticles(feedID: feedID) {
				continuation.resume()
			}
		}
	}
}

// MARK: - Private

private extension ArticlesDatabase {

	static let tableCreationStatements = """
	CREATE TABLE if not EXISTS articles (articleID TEXT NOT NULL PRIMARY KEY, feedID TEXT NOT NULL, uniqueID TEXT NOT NULL, title TEXT, contentHTML TEXT, contentText TEXT, markdown TEXT, url TEXT, externalURL TEXT, summary TEXT, imageURL TEXT, bannerImageURL TEXT, datePublished DATE, dateModified DATE, searchRowID INTEGER, authors TEXT, wordCount INTEGER, chapterCurrent INTEGER, chapterTotal INTEGER, isComplete BOOL, fandoms TEXT, relationships TEXT, characters TEXT, ratings TEXT, warnings TEXT, categories TEXT, additionalTags TEXT, series TEXT, commentCount INTEGER, kudosCount INTEGER, bookmarkCount INTEGER, hitCount INTEGER, isRestricted BOOL, language TEXT, collections TEXT, dateBookmarked DATE, lastPrefaceFetchDate DATE, isAmbrosiaItem BOOL, bookKey TEXT, pendingUpdateContentHTML TEXT, pendingUpdateDetectedAt DATE, wordCountRegressionFlaggedAt DATE, ao3ConfirmedMissingAt DATE);

	CREATE TABLE if not EXISTS statuses (articleID TEXT NOT NULL PRIMARY KEY, read BOOL NOT NULL DEFAULT 0, starred BOOL NOT NULL DEFAULT 0, loved BOOLEAN NOT NULL DEFAULT 0, dateArrived DATE NOT NULL DEFAULT 0, scrollPosition REAL NOT NULL DEFAULT 0, readingProgress REAL, lastOpenedAt DATE);

	CREATE TABLE if not EXISTS bookState (bookKey TEXT NOT NULL PRIMARY KEY, read BOOL NOT NULL DEFAULT 0, starred BOOL NOT NULL DEFAULT 0, loved BOOL NOT NULL DEFAULT 0, scrollPosition REAL NOT NULL DEFAULT 0, readingProgress REAL, lastOpenedAt DATE, updatedAt DATE NOT NULL, kudosAttemptedAt DATE, kudosAttemptedAuthenticated BOOL NOT NULL DEFAULT 0);

	CREATE TABLE if not EXISTS annotations (annotationID TEXT NOT NULL PRIMARY KEY, articleID TEXT NOT NULL, bookKey TEXT, quoteExact TEXT NOT NULL, quotePrefix TEXT NOT NULL DEFAULT '', quoteSuffix TEXT NOT NULL DEFAULT '', rootSelector TEXT NOT NULL DEFAULT '.articleBody', startOffset INTEGER NOT NULL, endOffset INTEGER NOT NULL, color TEXT NOT NULL DEFAULT 'yellow', note TEXT, createdAt DATE NOT NULL, updatedAt DATE NOT NULL, orphanedAt DATE, lastReanchoredAt DATE, chapterTitle TEXT, hasHighlight BOOL NOT NULL DEFAULT 1, originalText TEXT, replacementText TEXT);

	CREATE INDEX if not EXISTS articles_feedID_datePublished_articleID on articles (feedID, datePublished, articleID);
	CREATE INDEX if not EXISTS articles_bookKey_index on articles(bookKey);
	CREATE INDEX if not EXISTS articles_uniqueID_index on articles(uniqueID);
	CREATE INDEX if not EXISTS articles_searchRowID on articles(searchRowID);

	CREATE INDEX if not EXISTS statuses_starred_index on statuses (starred);

	CREATE INDEX if not EXISTS annotations_articleID_index on annotations(articleID);
	CREATE INDEX if not EXISTS annotations_bookKey_index on annotations(bookKey);

	CREATE VIRTUAL TABLE if not EXISTS search using fts4(title, body);

	CREATE TRIGGER if not EXISTS articles_after_delete_trigger_delete_search_text after delete on articles begin delete from search where rowid = OLD.searchRowID; end;
	"""

	func todayCutoffDate() -> Date {
		// 24 hours previous. Function/property names in this call chain
		// (todayCutoffDate, fetchTodayArticles, fetchUnreadCountForTodayAsync,
		// FetchType.today) still say "today" -- left as-is to keep this change
		// small -- but this now backs the Recently Added smart feed: a rolling
		// 24-hour window of dateArrived (when something entered the library),
		// not datePublished. Should not actually empty out at midnight.
		return Date(timeIntervalSinceNow: -(60 * 60 * 24)) // This does not need to be more precise.
	}

	// MARK: - Operations

	func cancelOperations() {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		Task { @MainActor in
			operationQueue.cancelAll()
		}
	}
}

// MARK: - Articles Table (Private)

typealias UnreadCountDictionaryCompletionBlock = @Sendable (UnreadCountDictionary) -> Void
typealias UpdateArticlesCompletionBlock = @Sendable (ArticleChanges) -> Void
typealias SingleUnreadCountCompletionBlock = @Sendable (Int) -> Void
typealias ArticleSetResultBlock = @Sendable (Set<Article>) -> Void
typealias ArticleIDsCompletionBlock = @Sendable (Set<String>) -> Void

private extension ArticlesDatabase {

	func _fetchAllUnreadCounts(_ completion: @escaping UnreadCountDictionaryCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		Task { @MainActor in
			let operation = FetchAllUnreadCountsOperation(databaseQueue: queue)
			if let operationName = operation.name {
				operationQueue.cancel(named: operationName)
			}
			operation.completionBlock = { operation in
				let fetchOperation = operation as! FetchAllUnreadCountsOperation
				completion(fetchOperation.unreadCountDictionary ?? UnreadCountDictionary())
			}
			operationQueue.add(operation)
		}
	}

	func _fetchUnreadCounts(feedIDs: Set<String>, _ completion: @escaping UnreadCountDictionaryCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchUnreadCounts(feedIDs, completion)
	}

	func _fetchUnreadCount(feedIDs: Set<String>, since: Date, completion: @escaping SingleUnreadCountCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchUnreadCount(feedIDs, since, completion)
	}

	func _fetchStarredAndUnreadCount(feedIDs: Set<String>, completion: @escaping SingleUnreadCountCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchStarredAndUnreadCount(feedIDs, completion)
	}

	func _fetchLovedAndUnreadCount(feedIDs: Set<String>, completion: @escaping SingleUnreadCountCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchLovedAndUnreadCount(feedIDs, completion)
	}

	func _mark(articleIDs: Set<String>, statusKey: ArticleStatus.Key, flag: Bool, completion: @escaping ArticleIDsCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.mark(articleIDs, statusKey, flag, completion)
	}

	func _markAndFetchNew(articleIDs: Set<String>, statusKey: ArticleStatus.Key, flag: Bool, completion: @escaping ArticleIDsCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.markAndFetchNew(articleIDs, statusKey, flag, completion)
	}

	func _createStatusesIfNeeded(articleIDs: Set<String>, completion: @escaping DatabaseCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.createStatusesIfNeeded(articleIDs, completion)
	}

	func _saveScrollPosition(_ scrollPosition: Double, articleID: String, completion: @escaping DatabaseCompletionBlock) {
		articlesTable.saveScrollPosition(scrollPosition, articleID: articleID, completion)
	}

	func _setPendingContentUpdate(_ contentHTML: String, detectedAt: Date, articleID: String, completion: @escaping DatabaseCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.setPendingContentUpdate(contentHTML, detectedAt: detectedAt, articleID: articleID, completion)
	}

	func _resolvePendingContentUpdate(articleID: String, accept: Bool, completion: @escaping DatabaseCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.resolvePendingContentUpdate(articleID: articleID, accept: accept, completion)
	}

	func _setAO3ConfirmedMissing(detectedAt: Date, articleID: String, completion: @escaping DatabaseCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.setAO3ConfirmedMissing(detectedAt: detectedAt, articleID: articleID, completion)
	}

	func _clearAO3ConfirmedMissing(articleID: String, completion: @escaping DatabaseCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.clearAO3ConfirmedMissing(articleID: articleID, completion)
	}

	func _clearWordCountRegressionFlag(articleID: String, completion: @escaping DatabaseCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.clearWordCountRegressionFlag(articleID: articleID, completion)
	}

	func _recordBookOpened(articleID: String, completion: @escaping DatabaseCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.recordBookOpened(articleID: articleID, completion)
	}

	func _fetchScrollPosition(articleID: String, completion: @escaping @Sendable (Double) -> Void) {
		articlesTable.fetchScrollPosition(articleID: articleID, completion)
	}

	func _saveReadingProgress(_ readingProgress: Double, articleID: String, completion: @escaping @Sendable (Set<String>) -> Void) {
		articlesTable.saveReadingProgress(readingProgress, articleID: articleID, completion)
	}

	func _fetchArticlesAsync(feedID: String, _ completion: @escaping ArticleSetResultBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchArticlesAsync(feedID, completion)
	}

	func _fetchArticlesAsync(feedIDs: Set<String>, _ completion: @escaping ArticleSetResultBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchArticlesAsync(feedIDs, completion)
	}

	func _fetchArticlesAsync(articleIDs: Set<String>, _ completion: @escaping  ArticleSetResultBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchArticlesAsync(articleIDs: articleIDs, completion)
	}

	func _fetchArticlesAsync(bookKeys: Set<String>, _ completion: @escaping ArticleSetResultBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchArticlesAsync(bookKeys: bookKeys, completion)
	}

	func _fetchUnreadArticlesAsync(feedIDs: Set<String>, limit: Int? = nil, _ completion: @escaping ArticleSetResultBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchUnreadArticlesAsync(feedIDs, limit, completion)
	}

	func _fetchTodayArticlesAsync(feedIDs: Set<String>, limit: Int? = nil, _ completion: @escaping ArticleSetResultBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchArticlesSinceAsync(feedIDs, todayCutoffDate(), limit, completion)
	}

	func _fetchedStarredArticlesAsync(feedIDs: Set<String>, limit: Int? = nil, _ completion: @escaping ArticleSetResultBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchStarredArticlesAsync(feedIDs, limit, completion)
	}

	func _fetchedLovedArticlesAsync(feedIDs: Set<String>, limit: Int? = nil, _ completion: @escaping ArticleSetResultBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchLovedArticlesAsync(feedIDs, limit, completion)
	}

	func _fetchedLastOpenedArticlesAsync(feedIDs: Set<String>, limit: Int? = nil, _ completion: @escaping ArticleSetResultBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchLastOpenedArticlesAsync(feedIDs, limit, completion)
	}

	func _fetchedReadArticlesAsync(feedIDs: Set<String>, limit: Int? = nil, _ completion: @escaping ArticleSetResultBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchReadArticlesAsync(feedIDs, limit, completion)
	}

	func _fetchArticlesMatchingAsync(searchString: String, feedIDs: Set<String>, _ completion: @escaping ArticleSetResultBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchArticlesMatchingAsync(searchString, feedIDs, completion)
	}

	func _fetchArticlesMatchingWithArticleIDsAsync(searchString: String, articleIDs: Set<String>, _ completion: @escaping ArticleSetResultBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchArticlesMatchingWithArticleIDsAsync(searchString, articleIDs, completion)
	}

	func _update(parsedItems: Set<ParsedItem>, feedID: String, deleteOlder: Bool, completion: @escaping UpdateArticlesCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		precondition(retentionStyle == .feedBased)
		articlesTable.update(parsedItems, feedID, deleteOlder, completion)
	}

	func _update(feedIDsAndItems: [String: Set<ParsedItem>], defaultRead: Bool, completion: @escaping UpdateArticlesCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		precondition(retentionStyle == .syncSystem)
		articlesTable.update(feedIDsAndItems, defaultRead, completion)
	}

	func _delete(articleIDs: Set<String>, completion: DatabaseCompletionBlock?) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.delete(articleIDs: articleIDs, completion: completion)
	}

	func _clearContentHTML(articleIDs: Set<String>, completion: DatabaseCompletionBlock?) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.clearContentHTML(articleIDs: articleIDs, completion: completion)
	}

	func _fetchUnreadArticleIDsAsync(completion: @escaping ArticleIDsCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchUnreadArticleIDsAsync(completion)
	}

	func _fetchStarredArticleIDsAsync(completion: @escaping ArticleIDsCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchStarredArticleIDsAsync(completion)
	}

	func _fetchLovedArticleIDsAsync(completion: @escaping ArticleIDsCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchLovedArticleIDsAsync(completion)
	}

	func _fetchArticleIDsForStatusesWithoutArticlesNewerThanCutoffDate(_ completion: @escaping ArticleIDsCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.fetchArticleIDsForStatusesWithoutArticlesNewerThanCutoffDate(completion)
	}
}
