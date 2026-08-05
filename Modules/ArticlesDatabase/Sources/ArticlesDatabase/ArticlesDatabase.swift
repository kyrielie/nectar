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

	public init(databaseFilePath: String, accountID: String, retentionStyle: RetentionStyle) {
		Self.logger.debug("Articles Database init \(accountID, privacy: .public)")

		self.databasePath = databaseFilePath
		let queue = DatabaseQueue(databasePath: databaseFilePath)
		self.queue = queue
		self.articlesTable = ArticlesTable(name: DatabaseTableName.articles, accountID: accountID, queue: queue, retentionStyle: retentionStyle)
		self.retentionStyle = retentionStyle
		self.accountID = accountID

		queue.runCreateStatements(ArticlesDatabase.tableCreationStatements)
		// Must run synchronously: runInDatabase dispatches asynchronously and
		// returns immediately, so init() could return -- and callers could
		// start querying articles/statuses -- before these ALTER TABLE
		// migrations (e.g. pendingUpdateContentHTML/pendingUpdateDetectedAt/
		// wordCountRegressionFlaggedAt below) have actually run, producing
		// "no such column" warnings on every early read.
		queue.runInDatabaseSync { database in
			Self.logger.debug("ArticlesDatabase: creating tables \(accountID, privacy: .public)")
			if !self.articlesTable.containsColumn("searchRowID", in: database) {
				database.executeStatements("ALTER TABLE articles add column searchRowID INTEGER;")
			}
			if !self.articlesTable.containsColumn("markdown", in: database) {
				Self.logger.debug("ArticlesDatabase: adding markdown column \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE articles add column markdown TEXT;")
			}
			if !self.articlesTable.containsColumn("authors", in: database) {
				Self.logger.debug("ArticlesDatabase: adding authors column \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE articles add column authors TEXT;")
			}

			// Ambrosia extension columns. Additive only — every column here is
			// nullable, so a fresh ALTER TABLE per missing column is safe to
			// run unconditionally on every launch via the containsColumn guard.
			let ambrosiaIntegerColumns = ["wordCount", "chapterCurrent", "chapterTotal"]
			for column in ambrosiaIntegerColumns {
				if !self.articlesTable.containsColumn(column, in: database) {
					Self.logger.debug("ArticlesDatabase: adding \(column, privacy: .public) column \(accountID, privacy: .public)")
					database.executeStatements("ALTER TABLE articles add column \(column) INTEGER;")
				}
			}
			if !self.articlesTable.containsColumn("isComplete", in: database) {
				Self.logger.debug("ArticlesDatabase: adding isComplete column \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE articles add column isComplete BOOL;")
			}
			let ambrosiaTextColumns = ["fandoms", "relationships", "characters", "ratings", "warnings", "categories", "series"]
			for column in ambrosiaTextColumns {
				if !self.articlesTable.containsColumn(column, in: database) {
					Self.logger.debug("ArticlesDatabase: adding \(column, privacy: .public) column \(accountID, privacy: .public)")
					database.executeStatements("ALTER TABLE articles add column \(column) TEXT;")
				}
			}

			// AO3 Work Header stats (Comments/Kudos/Bookmarks/Hits), read off
			// AO3's live dl.stats block by AO3ChapterHTMLExtractor on each
			// successful chapter fetch -- not part of the `_ambrosia`
			// extension object above, so a separate additive-only column
			// group, same containsColumn-guarded ALTER TABLE pattern.
			let ao3StatsColumns = ["commentCount", "kudosCount", "bookmarkCount", "hitCount"]
			for column in ao3StatsColumns {
				if !self.articlesTable.containsColumn(column, in: database) {
					Self.logger.debug("ArticlesDatabase: adding \(column, privacy: .public) column \(accountID, privacy: .public)")
					database.executeStatements("ALTER TABLE articles add column \(column) INTEGER;")
				}
			}

			// Task 10 ("Prev/next/first navigation") -- previous/next work
			// URLs, read off the same live work-page fetch as the stats
			// above, but stored as TEXT (URLs, not counts). Same additive,
			// containsColumn-guarded pattern.
			let ao3SeriesNavigationColumns = ["previousWorkURL", "nextWorkURL"]
			for column in ao3SeriesNavigationColumns {
				if !self.articlesTable.containsColumn(column, in: database) {
					Self.logger.debug("ArticlesDatabase: adding \(column, privacy: .public) column \(accountID, privacy: .public)")
					database.executeStatements("ALTER TABLE articles add column \(column) TEXT;")
				}
			}

			// lastPrefaceFetchDate (AO3ChapterFetcher's own "when did this last
			// succeed" bookkeeping, for the refetch-cadence setting) and
			// isAmbrosiaItem (an Ambrosia-vs-native-AO3 marker, needed so
			// AO3ChapterFetcher/ArticleRenderer can tell a failed refetch should
			// leave Ambrosia's own preface alone). Same additive, containsColumn-
			// guarded pattern as the columns above.
			if !self.articlesTable.containsColumn("lastPrefaceFetchDate", in: database) {
				Self.logger.debug("ArticlesDatabase: adding lastPrefaceFetchDate column \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE articles add column lastPrefaceFetchDate DATE;")
			}
			if !self.articlesTable.containsColumn("isAmbrosiaItem", in: database) {
				Self.logger.debug("ArticlesDatabase: adding isAmbrosiaItem column \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE articles add column isAmbrosiaItem BOOL;")
			}

			// Task 8 (pending-update diff/regression guard): read/written throughout
			// ArticlesTable/Article+Database (setPendingContentUpdate,
			// resolvePendingContentUpdate, changesFrom, row hydration in Article.init)
			// but never migrated in here -- on a real pre-Task-8 database these three
			// columns don't exist, so every read/write against them throws a SQLite
			// "no such column" error, and Article.init reads all three unconditionally
			// on every row hydration, so this broke on first launch after upgrade.
			// Same additive, containsColumn-guarded ALTER TABLE pattern as
			// lastPrefaceFetchDate/isAmbrosiaItem above. pendingUpdateContentHTML is
			// TEXT (compressed via ContentHTMLCompression, same as contentHTML/
			// contentText); the two *At columns are DATE, both nullable (nil = no
			// pending diff / no regression flagged).
			if !self.articlesTable.containsColumn(DatabaseKey.pendingUpdateContentHTML, in: database) {
				Self.logger.debug("ArticlesDatabase: adding pendingUpdateContentHTML column \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE articles add column \(DatabaseKey.pendingUpdateContentHTML) TEXT;")
			}
			if !self.articlesTable.containsColumn(DatabaseKey.pendingUpdateDetectedAt, in: database) {
				Self.logger.debug("ArticlesDatabase: adding pendingUpdateDetectedAt column \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE articles add column \(DatabaseKey.pendingUpdateDetectedAt) DATE;")
			}
			if !self.articlesTable.containsColumn(DatabaseKey.wordCountRegressionFlaggedAt, in: database) {
				Self.logger.debug("ArticlesDatabase: adding wordCountRegressionFlaggedAt column \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE articles add column \(DatabaseKey.wordCountRegressionFlaggedAt) DATE;")
			}

			// Phase 2 (reading behavior): per-article scroll position, replacing the old
			// single-global AppDefaults.shared.articleWindowScrollY. Additive/nullable-with-
			// default, so the same containsColumn-guarded ALTER TABLE pattern as the columns
			// above applies here, just against the statuses table instead of articles.
			if !self.statusesTableContainsScrollPositionColumn(database) {
				Self.logger.debug("ArticlesDatabase: adding scrollPosition column \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE statuses add column scrollPosition REAL NOT NULL DEFAULT 0;")
			}

			// Phase A1 (visible reading progress): fraction (0...1) of the article read.
			// Nullable with no default -- nil/NULL means "never computed," distinct from
			// 0 ("computed, at the very top"), so this can't use the NOT NULL DEFAULT 0
			// pattern the scrollPosition column above uses.
			if !self.statusesTableContainsReadingProgressColumn(database) {
				Self.logger.debug("ArticlesDatabase: adding readingProgress column \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE statuses add column readingProgress REAL;")
			}

			// Phase 5 (loved status): a second, independent boolean status, same tier
			// as starred -- same containsColumn-guarded ALTER TABLE pattern.
			if !self.statusesTableContainsLovedColumn(database) {
				Self.logger.debug("ArticlesDatabase: adding loved column \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE statuses add column loved BOOLEAN NOT NULL DEFAULT 0;")
			}

			// Last Opened smart feed: per-articleID denormalized copy of bookState's
			// lastOpenedAt, propagated the same way loved/starred are, so the
			// timeline can query/order by it with a plain WHERE/ORDER BY -- same
			// reasoning as the loved column above.
			if !self.statusesTableContainsLastOpenedAtColumn(database) {
				Self.logger.debug("ArticlesDatabase: adding lastOpenedAt column (statuses) \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE statuses add column lastOpenedAt DATE;")
			}
			if !self.bookStateTableContainsLastOpenedAtColumn(database) {
				Self.logger.debug("ArticlesDatabase: adding lastOpenedAt column (bookState) \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE bookState add column lastOpenedAt DATE;")
			}

			// Task 6 (kudos-on-like): forward-only kudos-attempt tracking per
			// book, bookState-only (no statuses-table mirror -- see the
			// DatabaseKey.kudosAttemptedAt doc comment). kudosAttemptedAt
			// nullable (nil = never attempted); kudosAttemptedAuthenticated
			// records guest vs logged-in once an attempt has happened, which
			// the re-attempt policy in Task 6 depends on. Same
			// containsColumn-guarded ALTER TABLE pattern as lastOpenedAt above.
			if !self.bookStateTableContainsKudosAttemptedAtColumn(database) {
				Self.logger.debug("ArticlesDatabase: adding kudosAttemptedAt column (bookState) \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE bookState add column kudosAttemptedAt DATE;")
			}
			if !self.bookStateTableContainsKudosAttemptedAuthenticatedColumn(database) {
				Self.logger.debug("ArticlesDatabase: adding kudosAttemptedAuthenticated column (bookState) \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE bookState add column kudosAttemptedAuthenticated BOOL NOT NULL DEFAULT 0;")
			}

			// Phase 6 (book-level read state): identity key used to dedup a book's
			// read state across collection feeds and re-subscriptions. Nullable --
			// existing rows read back as nil and Article falls back to uniqueID
			// until the article is next re-parsed and picks up a real bookKey.
			if !self.articlesTable.containsColumn("bookKey", in: database) {
				Self.logger.debug("ArticlesDatabase: adding bookKey column \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE articles add column bookKey TEXT;")
			}

			// One-time data fix for the ParsedItem.bookKey routing change (series-group
			// items now route to "ao3-series:<id>" like an anthology-with-a-series-id
			// does, instead of falling through to the bare uniqueID -- see
			// ParsedItem.swift's bookKey doc comment). Only bookKey itself is a stored
			// column here; ao3SeriesID/isAnthology/seriesName are ParsedItem-only
			// fields consumed at parse/import time and never persisted to `articles`,
			// so this can't be driven off an ao3SeriesID column the way the plan for
			// this fix originally assumed. Instead it's driven off Ambrosia's own wire
			// id scheme for a series-group item, "ambrosia-series-ao3:<id>" (confirmed
			// against Ambrosia's LocalFeedServer output, not against anything in this
			// repo) -- a pre-fix row still sitting on its old bookKey == uniqueID
			// fallback is recognized by that prefix and repointed directly, since it
			// would otherwise only self-heal on that feed's next refresh (which
			// ArticlesTable.update's diff-and-update path already handles for the
			// articles.bookKey column, per Article's == including bookKey -- this
			// block exists only because BookStateTable has no such self-heal: it's
			// keyed by value with no relationship to article identity). Self-limiting/
			// idempotent via the WHERE clause below, same as AuthorsSchemaMigration's
			// approach elsewhere in this init -- no separate one-shot flag needed,
			// since a row this UPDATE has already fixed no longer matches it.
			let seriesGroupUniqueIDPrefix = "ambrosia-series-ao3:"
			database.executeStatements("""
				INSERT OR IGNORE INTO bookState (bookKey, read, starred, loved, scrollPosition, readingProgress, lastOpenedAt, updatedAt, kudosAttemptedAt, kudosAttemptedAuthenticated)
				SELECT 'ao3-series:' || substr(a.uniqueID, \(seriesGroupUniqueIDPrefix.count + 1)), b.read, b.starred, b.loved, b.scrollPosition, b.readingProgress, b.lastOpenedAt, b.updatedAt, b.kudosAttemptedAt, b.kudosAttemptedAuthenticated
				FROM articles a
				JOIN bookState b ON b.bookKey = a.uniqueID
				WHERE a.isAmbrosiaItem = 1 AND a.bookKey = a.uniqueID AND a.uniqueID LIKE '\(seriesGroupUniqueIDPrefix)%';

				DELETE FROM bookState WHERE bookKey IN (
				  SELECT a.uniqueID FROM articles a
				  WHERE a.isAmbrosiaItem = 1 AND a.bookKey = a.uniqueID AND a.uniqueID LIKE '\(seriesGroupUniqueIDPrefix)%'
				);

				UPDATE articles SET bookKey = 'ao3-series:' || substr(uniqueID, \(seriesGroupUniqueIDPrefix.count + 1))
				WHERE isAmbrosiaItem = 1 AND bookKey = uniqueID AND uniqueID LIKE '\(seriesGroupUniqueIDPrefix)%';
				""")

			// nectarfixes #3: bookKeysForArticleIDs/articleIDsForBookKeys (ArticlesTable)
			// run a WHERE bookKey IN (...) and a WHERE uniqueID IN (...) lookup on every
			// single read/starred/loved toggle now, to write through to the book-level
			// state tables and live-propagate to sibling copies of the same book. Neither
			// column had an index, so both lookups were full table scans of `articles` --
			// on every tap, regardless of library size. Indexing them turns the toggle's
			// DB transaction back into an index lookup instead of O(n).
			database.executeStatements("CREATE INDEX if not EXISTS articles_bookKey_index on articles(bookKey);")
			database.executeStatements("CREATE INDEX if not EXISTS articles_uniqueID_index on articles(uniqueID);")

			database.executeStatements("CREATE INDEX if not EXISTS articles_searchRowID on articles(searchRowID);")
			database.executeStatements("DROP TABLE if EXISTS tags;DROP INDEX if EXISTS tags_tagName_index;DROP INDEX if EXISTS articles_feedID_index;DROP INDEX if EXISTS statuses_read_index;DROP TABLE if EXISTS attachments;DROP TABLE if EXISTS attachmentsLookup;")
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

	// MARK: - Caches

	/// Call to free up some memory. Should be done when the app is backgrounded, for instance.
	/// This does not empty *all* caches — just the ones that are empty-able.
	public func emptyCaches() {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.emptyCaches()
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
}

// MARK: - Private

private extension ArticlesDatabase {

	static let tableCreationStatements = """
	CREATE TABLE if not EXISTS articles (articleID TEXT NOT NULL PRIMARY KEY, feedID TEXT NOT NULL, uniqueID TEXT NOT NULL, title TEXT, contentHTML TEXT, contentText TEXT, markdown TEXT, url TEXT, externalURL TEXT, summary TEXT, imageURL TEXT, bannerImageURL TEXT, datePublished DATE, dateModified DATE, searchRowID INTEGER, authors TEXT, wordCount INTEGER, chapterCurrent INTEGER, chapterTotal INTEGER, isComplete BOOL, fandoms TEXT, relationships TEXT, characters TEXT, ratings TEXT, warnings TEXT, categories TEXT, series TEXT);

	CREATE TABLE if not EXISTS statuses (articleID TEXT NOT NULL PRIMARY KEY, read BOOL NOT NULL DEFAULT 0, starred BOOL NOT NULL DEFAULT 0, loved BOOLEAN NOT NULL DEFAULT 0, dateArrived DATE NOT NULL DEFAULT 0, scrollPosition REAL NOT NULL DEFAULT 0, readingProgress REAL, lastOpenedAt DATE);

	CREATE TABLE if not EXISTS bookState (bookKey TEXT NOT NULL PRIMARY KEY, read BOOL NOT NULL DEFAULT 0, starred BOOL NOT NULL DEFAULT 0, loved BOOL NOT NULL DEFAULT 0, scrollPosition REAL NOT NULL DEFAULT 0, readingProgress REAL, lastOpenedAt DATE, updatedAt DATE NOT NULL, kudosAttemptedAt DATE, kudosAttemptedAuthenticated BOOL NOT NULL DEFAULT 0);

	CREATE INDEX if not EXISTS articles_feedID_datePublished_articleID on articles (feedID, datePublished, articleID);

	CREATE INDEX if not EXISTS statuses_starred_index on statuses (starred);

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

	/// Mirrors DatabaseTable.containsColumn's logic (see RSDatabase), but against the
	/// statuses table specifically. ArticlesDatabase only holds a reference to
	/// articlesTable (whose containsColumn is hardwired to the "articles" table via its
	/// own `name`), not statusesTable, so it's duplicated here rather than plumbed through.
	nonisolated func statusesTableContainsScrollPositionColumn(_ database: FMDatabase) -> Bool {
		guard let resultSet = database.executeQuery("select * from statuses limit 1;", withArgumentsIn: nil),
			  let columnMap = resultSet.columnNameToIndexMap else {
			return false
		}
		return columnMap["scrollposition"] != nil
	}

	/// Same approach as `statusesTableContainsScrollPositionColumn` above.
	nonisolated func statusesTableContainsReadingProgressColumn(_ database: FMDatabase) -> Bool {
		guard let resultSet = database.executeQuery("select * from statuses limit 1;", withArgumentsIn: nil),
			  let columnMap = resultSet.columnNameToIndexMap else {
			return false
		}
		return columnMap["readingprogress"] != nil
	}

	/// Same approach as `statusesTableContainsScrollPositionColumn` above.
	nonisolated func statusesTableContainsLovedColumn(_ database: FMDatabase) -> Bool {
		guard let resultSet = database.executeQuery("select * from statuses limit 1;", withArgumentsIn: nil),
			  let columnMap = resultSet.columnNameToIndexMap else {
			return false
		}
		return columnMap["loved"] != nil
	}

	/// Same approach as `statusesTableContainsScrollPositionColumn` above.
	nonisolated func statusesTableContainsLastOpenedAtColumn(_ database: FMDatabase) -> Bool {
		guard let resultSet = database.executeQuery("select * from statuses limit 1;", withArgumentsIn: nil),
			  let columnMap = resultSet.columnNameToIndexMap else {
			return false
		}
		return columnMap["lastopenedat"] != nil
	}

	/// Same approach as `statusesTableContainsScrollPositionColumn` above, against
	/// bookState instead. ArticlesDatabase only holds a reference to articlesTable
	/// (whose containsColumn is hardwired to the "articles" table), not
	/// bookStateTable, so this is duplicated here rather than plumbed through --
	/// same reasoning as the statuses-table helpers above.
	nonisolated func bookStateTableContainsLastOpenedAtColumn(_ database: FMDatabase) -> Bool {
		guard let resultSet = database.executeQuery("select * from bookState limit 1;", withArgumentsIn: nil),
			  let columnMap = resultSet.columnNameToIndexMap else {
			return false
		}
		return columnMap["lastopenedat"] != nil
	}

	/// Same approach as `statusesTableContainsScrollPositionColumn` above, against
	/// bookState instead. Task 6's two kudos-attempt columns.
	nonisolated func bookStateTableContainsKudosAttemptedAtColumn(_ database: FMDatabase) -> Bool {
		guard let resultSet = database.executeQuery("select * from bookState limit 1;", withArgumentsIn: nil),
			  let columnMap = resultSet.columnNameToIndexMap else {
			return false
		}
		return columnMap["kudosattemptedat"] != nil
	}

	nonisolated func bookStateTableContainsKudosAttemptedAuthenticatedColumn(_ database: FMDatabase) -> Bool {
		guard let resultSet = database.executeQuery("select * from bookState limit 1;", withArgumentsIn: nil),
			  let columnMap = resultSet.columnNameToIndexMap else {
			return false
		}
		return columnMap["kudosattemptedauthenticated"] != nil
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
