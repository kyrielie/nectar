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
		queue.runInDatabase { database in
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

			// Phase 6 (book-level read state): identity key used to dedup a book's
			// read state across collection feeds and re-subscriptions. Nullable --
			// existing rows read back as nil and Article falls back to uniqueID
			// until the article is next re-parsed and picks up a real bookKey.
			if !self.articlesTable.containsColumn("bookKey", in: database) {
				Self.logger.debug("ArticlesDatabase: adding bookKey column \(accountID, privacy: .public)")
				database.executeStatements("ALTER TABLE articles add column bookKey TEXT;")
			}

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
	/// reindex search or write BookReadStateTable rows -- confirmed accepted trade-off.
	/// Throws on any failure (I/O, version mismatch, or SQL error) with no partial writes:
	/// the whole import runs inside one transaction and is rolled back on error.
	public func importAmbrosiaSQLiteTransfer(temporaryFilePath: String, feedID: String, wireFormatVersion: Int32) throws {
		Self.logger.debug("ArticlesDatabase: importAmbrosiaSQLiteTransfer \(self.accountID, privacy: .public) feedID: \(feedID, privacy: .public)")
		try AmbrosiaSQLiteImportTable.importTransfer(temporaryFilePath: temporaryFilePath, feedID: feedID, expectedWireFormatVersion: wireFormatVersion, queue: queue)
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

	/// Returns aggregate article counts (total, unread, starred, statuses) for the given feeds.
	public func fetchArticleCountsAsync(feedIDs: Set<String>) async -> ArticleCounts {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		return await withCheckedContinuation { continuation in
			articlesTable.fetchArticleCountsAsync(feedIDs) { articleCounts in
				continuation.resume(returning: articleCounts)
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

	/// Fraction (0...1) of the article read (Phase A1). No fetch counterpart is needed:
	/// readingProgress is loaded in bulk as part of ArticleStatus (see StatusesTable),
	/// the same path `read`/`starred` already use, rather than a per-article async fetch.
	public func saveReadingProgressAsync(_ readingProgress: Double, articleID: String) async {
		await withCheckedContinuation { continuation in
			_saveReadingProgress(readingProgress, articleID: articleID) {
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

	CREATE TABLE if not EXISTS statuses (articleID TEXT NOT NULL PRIMARY KEY, read BOOL NOT NULL DEFAULT 0, starred BOOL NOT NULL DEFAULT 0, loved BOOLEAN NOT NULL DEFAULT 0, dateArrived DATE NOT NULL DEFAULT 0, scrollPosition REAL NOT NULL DEFAULT 0, readingProgress REAL);

	CREATE TABLE if not EXISTS bookReadState (bookKey TEXT NOT NULL PRIMARY KEY, state TEXT NOT NULL, updatedAt DATE NOT NULL);

	CREATE TABLE if not EXISTS bookStarredState (bookKey TEXT NOT NULL PRIMARY KEY, state TEXT NOT NULL, updatedAt DATE NOT NULL);

	CREATE TABLE if not EXISTS bookLovedState (bookKey TEXT NOT NULL PRIMARY KEY, state TEXT NOT NULL, updatedAt DATE NOT NULL);

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
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
		articlesTable.saveScrollPosition(scrollPosition, articleID: articleID, completion)
	}

	func _fetchScrollPosition(articleID: String, completion: @escaping @Sendable (Double) -> Void) {
		articlesTable.fetchScrollPosition(articleID: articleID, completion)
	}

	func _saveReadingProgress(_ readingProgress: Double, articleID: String, completion: @escaping DatabaseCompletionBlock) {
		Self.logger.debug("ArticlesDatabase: \(#function, privacy: .public) \(self.accountID, privacy: .public)")
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
