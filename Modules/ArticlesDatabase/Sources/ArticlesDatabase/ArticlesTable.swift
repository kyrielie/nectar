//
//  ArticlesTable.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 5/9/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import os
import RSCore
import RSDatabase
import RSDatabaseObjC
import RSParser
import Articles

final class ArticlesTable: DatabaseTable, Sendable {
	let name: String

	private let accountID: String
	private let queue: DatabaseQueue
	private let statusesTable: StatusesTable
	private let bookReadStateTable: BookReadStateTable
	private let bookStarredStateTable: BookStarredStateTable
	private let bookLovedStateTable: BookLovedStateTable
	private let searchTable: SearchTable
	private let retentionStyle: ArticlesDatabase.RetentionStyle
	private let articlesCache = OSAllocatedUnfairLock(initialState: [String: Article]())

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ArticlesTable")
	private static let signposter = OSSignposter(subsystem: Bundle.main.bundleIdentifier!, category: .pointsOfInterest)

	// TODO: update articleCutoffDate as time passes and based on user preferences.
	let articleCutoffDate = Date().bySubtracting(days: 90)

	private typealias ArticlesFetchMethod = @Sendable (FMDatabase) -> Set<Article>
	private typealias ArticlesCountFetchMethod = @Sendable (FMDatabase) -> Int

	init(name: String, accountID: String, queue: DatabaseQueue, retentionStyle: ArticlesDatabase.RetentionStyle) {
		self.name = name
		self.accountID = accountID
		self.queue = queue
		self.statusesTable = StatusesTable(queue: queue)
		self.bookReadStateTable = BookReadStateTable(queue: queue)
		self.bookStarredStateTable = BookStarredStateTable(queue: queue)
		self.bookLovedStateTable = BookLovedStateTable(queue: queue)
		self.retentionStyle = retentionStyle

		self.searchTable = SearchTable(queue: queue)
		self.searchTable.articlesTable = self

		NotificationCenter.default.addObserver(self, selector: #selector(handleLowMemory(_:)), name: .lowMemory, object: nil)
	}

	// MARK: - Fetching Articles for Feed

	func fetchArticles(_ feedID: String) -> Set<Article> {
		fetchArticles { self.fetchArticlesForFeedID(feedID, $0) }
	}

	func fetchArticlesAsync(_ feedID: String, _ completion: @escaping ArticleSetResultBlock) {
		fetchArticlesAsync({ self.fetchArticlesForFeedID(feedID, $0) }, completion)
	}

	func fetchArticles(_ feedIDs: Set<String>) -> Set<Article> {
		fetchArticles { self.fetchArticles(feedIDs, $0) }
	}

	func fetchArticlesAsync(_ feedIDs: Set<String>, _ completion: @escaping ArticleSetResultBlock) {
		fetchArticlesAsync({ self.fetchArticles(feedIDs, $0) }, completion)
	}

	// MARK: - Fetching Articles by articleID

	func fetchArticles(articleIDs: Set<String>) -> Set<Article> {
		fetchArticles { self.fetchArticles(articleIDs: articleIDs, $0) }
	}

	func fetchArticlesAsync(articleIDs: Set<String>, _ completion: @escaping ArticleSetResultBlock) {
		return fetchArticlesAsync({ self.fetchArticles(articleIDs: articleIDs, $0) }, completion)
	}

	// MARK: - Fetching Unread Articles

	func fetchUnreadArticles(_ feedIDs: Set<String>, _ limit: Int?) -> Set<Article> {
		fetchArticles { self.fetchUnreadArticles(feedIDs, limit, $0) }
	}

	func fetchUnreadArticlesAsync(_ feedIDs: Set<String>, _ limit: Int?, _ completion: @escaping ArticleSetResultBlock) {
		fetchArticlesAsync({ self.fetchUnreadArticles(feedIDs, limit, $0) }, completion)
	}

	// MARK: - Fetching Read Articles

	func fetchReadArticles(_ feedIDs: Set<String>, _ limit: Int?) -> Set<Article> {
		fetchArticles { self.fetchReadArticles(feedIDs, limit, $0) }
	}

	func fetchReadArticlesAsync(_ feedIDs: Set<String>, _ limit: Int?, _ completion: @escaping ArticleSetResultBlock) {
		fetchArticlesAsync({ self.fetchReadArticles(feedIDs, limit, $0) }, completion)
	}

	func fetchReadArticlesCount(_ feedIDs: Set<String>) -> Int {
		fetchArticlesCount { self.fetchReadArticlesCount(feedIDs, $0) }
	}

	// MARK: - Fetching Today Articles

	func fetchArticlesSince(_ feedIDs: Set<String>, _ cutoffDate: Date, _ limit: Int?) -> Set<Article> {
		fetchArticles { self.fetchArticlesSince(feedIDs, cutoffDate, limit, $0) }
	}

	func fetchArticlesSinceAsync(_ feedIDs: Set<String>, _ cutoffDate: Date, _ limit: Int?, _ completion: @escaping ArticleSetResultBlock) {
		fetchArticlesAsync({ self.fetchArticlesSince(feedIDs, cutoffDate, limit, $0) }, completion)
	}

	// MARK: - Fetching Starred Articles

	func fetchStarredArticles(_ feedIDs: Set<String>, _ limit: Int?) -> Set<Article> {
		fetchArticles { self.fetchStarredArticles(feedIDs, limit, $0) }
	}

	func fetchStarredArticlesAsync(_ feedIDs: Set<String>, _ limit: Int?, _ completion: @escaping ArticleSetResultBlock) {
		fetchArticlesAsync({ self.fetchStarredArticles(feedIDs, limit, $0) }, completion)
	}

	func fetchStarredArticlesCount(_ feedIDs: Set<String>) -> Int {
		fetchArticlesCount { self.fetchStarredArticlesCount(feedIDs, $0) }
	}

	// MARK: - Fetching Loved Articles (Phase 5)

	func fetchLovedArticles(_ feedIDs: Set<String>, _ limit: Int?) -> Set<Article> {
		fetchArticles { self.fetchLovedArticles(feedIDs, limit, $0) }
	}

	func fetchLovedArticlesAsync(_ feedIDs: Set<String>, _ limit: Int?, _ completion: @escaping ArticleSetResultBlock) {
		fetchArticlesAsync({ self.fetchLovedArticles(feedIDs, limit, $0) }, completion)
	}

	func fetchLovedArticlesCount(_ feedIDs: Set<String>) -> Int {
		fetchArticlesCount { self.fetchLovedArticlesCount(feedIDs, $0) }
	}

	// MARK: - Fetching Counts Async

	func fetchArticleCountsAsync(_ feedIDs: Set<String>, _ completion: @escaping @Sendable (ArticleCounts) -> Void) {
		queue.runInDatabase { database in
			let counts = self.articleCounts(feedIDs: feedIDs, database: database)
			DispatchQueue.main.async {
				completion(counts)
			}
		}
	}

	// MARK: - Fetching Last Update Dates

	func fetchLastUpdateDatesAsync(_ completion: @escaping @Sendable ([String: Date]) -> Void) {
		queue.runInDatabase { database in
			let lastUpdateDates = self.fetchLastUpdateDates(database)
			DispatchQueue.main.async {
				completion(lastUpdateDates)
			}
		}
	}

	// MARK: - Fetching Search Articles

	func fetchArticlesMatching(_ searchString: String) -> Set<Article> {
		nonisolated(unsafe) var articles: Set<Article> = Set<Article>()

		queue.runInDatabaseSync { database in
			articles = self.fetchArticlesMatching(searchString, database)
		}

		return articles
	}

	func fetchArticlesMatching(_ searchString: String, _ feedIDs: Set<String>) -> Set<Article> {
		var articles = fetchArticlesMatching(searchString)
		articles = articles.filter { feedIDs.contains($0.feedID) }
		return articles
	}

	func fetchArticlesMatchingWithArticleIDs(_ searchString: String, _ articleIDs: Set<String>) -> Set<Article> {
		var articles = fetchArticlesMatching(searchString)
		articles = articles.filter { articleIDs.contains($0.articleID) }
		return articles
	}

	func fetchArticlesMatchingAsync(_ searchString: String, _ feedIDs: Set<String>, _ completion: @escaping ArticleSetResultBlock) {
		fetchArticlesAsync({ self.fetchArticlesMatching(searchString, feedIDs, $0) }, completion)
	}

	func fetchArticlesMatchingWithArticleIDsAsync(_ searchString: String, _ articleIDs: Set<String>, _ completion: @escaping ArticleSetResultBlock) {
		fetchArticlesAsync({ self.fetchArticlesMatchingWithArticleIDs(searchString, articleIDs, $0) }, completion)
	}

	// MARK: - Fetching Articles for Indexer

	func fetchArticleSearchInfos(_ articleIDs: Set<String>, in database: FMDatabase) -> Set<ArticleSearchInfo>? {
		let parameters = articleIDs.map { $0 as AnyObject }
		let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(articleIDs.count))!
		let query = "select articleID, title, contentHTML, contentText, summary, searchRowID, authors from articles where articleID in \(placeholders);"

		if let resultSet = database.executeQuery(query, withArgumentsIn: parameters) {
			return resultSet.mapToSet { (row) -> ArticleSearchInfo? in
				let articleID = row.swiftString(forColumn: DatabaseKey.articleID)!
				let title = row.swiftString(forColumn: DatabaseKey.title)
				// contentHTML is stored compressed (Phase 3) -- this query reads the
				// raw articles table directly rather than going through Article, so
				// it needs its own decompress call rather than inheriting Article's.
				let contentHTML = ContentHTMLCompression.decompress(row.swiftString(forColumn: DatabaseKey.contentHTML))
				let contentText = row.swiftString(forColumn: DatabaseKey.contentText)
				let summary = row.swiftString(forColumn: DatabaseKey.summary)
				let authorsNames = Self.authorsNames(from: row)

				let searchRowIDObject = row.object(forColumnName: DatabaseKey.searchRowID)
				var searchRowID: Int?
				if searchRowIDObject != nil && !(searchRowIDObject is NSNull) {
					searchRowID = Int(row.longLongInt(forColumn: DatabaseKey.searchRowID))
				}

				return ArticleSearchInfo(articleID: articleID, title: title, contentHTML: contentHTML, contentText: contentText, summary: summary, authorsNames: authorsNames, searchRowID: searchRowID)
			}
		}
		return nil
	}

	private static func authorsNames(from row: FMResultSet) -> String? {
		guard let json = row.swiftString(forColumn: DatabaseKey.authors), !json.isEmpty, let data = json.data(using: .utf8) else {
			return nil
		}
		guard let authors = Author.authorsWithJSON(data) else {
			return nil
		}
		let names = authors.compactMap { $0.name }
		if names.isEmpty {
			return nil
		}
		return names.joined(separator: " ")
	}

	// MARK: - Updating and Deleting

	func update(_ parsedItems: Set<ParsedItem>, _ feedID: String, _ deleteOlder: Bool, _ completion: @escaping UpdateArticlesCompletionBlock) {
		precondition(retentionStyle == .feedBased)
		if parsedItems.isEmpty {
			callUpdateArticlesCompletionBlock(nil, nil, nil, completion)
			return
		}

		// 1. Ensure statuses for all the incoming articles.
		// 2. Create incoming articles with parsedItems.
		// 3. [Deleted - this step is no longer needed]
		// 4. Fetch all articles for the feed.
		// 5. Create array of Articles not in database and save them.
		// 6. Create array of updated Articles and save what’s changed.
		// 7. Call back with new and updated Articles.
		// 8. Delete Articles in database no longer present in the feed.
		// 9. Update search index.

		self.queue.runInTransaction { database in

			let articleIDs = parsedItems.articleIDs()

			// Diagnostic: `articleIDs` is a Set<String> built from parsedItems'
			// computed `articleID` (calculatedArticleID(feedID:uniqueID:)). If two
			// different incoming items hash to the same articleID -- e.g. an
			// upstream feed emitting one shared guid for what should be several
			// distinct items -- they silently collapse into one entry right here,
			// before anything else in this function has a chance to notice. Once
			// that happens, nothing downstream can tell one work was dropped: it
			// never reaches `incomingArticles`, so it's not "not new" or "not
			// updated," it's just absent. Logging the raw-vs-distinct count at the
			// point of collapse is the only place that catches it.
			if parsedItems.count != articleIDs.count {
				Self.logger.warning("ArticlesTable: update(feedID:\(feedID, privacy: .public)) articleID collision -- \(parsedItems.count, privacy: .public) incoming parsedItems collapsed to \(articleIDs.count, privacy: .public) distinct articleIDs (\(parsedItems.count - articleIDs.count, privacy: .public) lost here)")
			}

			// Phase 6: for any incoming article whose bookKey already has a
			// BookReadState row -- a re-subscribe, or the same book turning up in
			// a second collection feed -- seed the new article's status from that
			// row instead of the unread-on-import default below.
			//
			// Starred/loved are seeded the same way, from BookStarredState /
			// BookLovedState, below (after status creation, since
			// ensureStatusesForArticleIDs only takes a read flag -- starred/loved
			// default false on the newly-created row and get corrected
			// afterward for whichever articleIDs need it true).
			var bookKeysByArticleID = [String: String]()
			for parsedItem in parsedItems {
				bookKeysByArticleID[parsedItem.articleID] = parsedItem.bookKey
			}
			let bookReadStateByBookKey = self.bookReadStateTable.state(for: Set(bookKeysByArticleID.values), database)
			let overrideArticleIDs = Set(bookKeysByArticleID.compactMap { articleID, bookKey in
				bookReadStateByBookKey[bookKey] != nil ? articleID : nil
			})

			let remainingArticleIDs = articleIDs.subtracting(overrideArticleIDs)

			// All newly-arrived articles default to unread regardless of
			// datePublished. Previously this split by age (~6 months) and
			// created older items with read=true, on the theory that a
			// long-stale post is unlikely to be something the person wants
			// to see as new -- but that meant genuinely new arrivals whose
			// datePublished happened to be old (e.g. backlog/collection
			// imports) silently never appeared in the unread timeline, even
			// though every row was correctly persisted to the articles
			// table. Every remaining article ID is now treated as recent.
			let recentArticleIDs = remainingArticleIDs

			var (statusesDictionary, _) = self.statusesTable.ensureStatusesForArticleIDs(recentArticleIDs, false, database) // 1a

			// Override group: one ensureStatusesForArticleIDs call per distinct
			// read/unread value present, since that function takes a single flag
			// for the whole set passed in.
			let readOverrideIDs = Set(overrideArticleIDs.filter { bookReadStateByBookKey[bookKeysByArticleID[$0] ?? ""] == true })
			let unreadOverrideIDs = overrideArticleIDs.subtracting(readOverrideIDs)
			let (readOverrideStatuses, _) = self.statusesTable.ensureStatusesForArticleIDs(readOverrideIDs, true, database)
			let (unreadOverrideStatuses, _) = self.statusesTable.ensureStatusesForArticleIDs(unreadOverrideIDs, false, database)
			statusesDictionary.merge(readOverrideStatuses) { current, _ in current }
			statusesDictionary.merge(unreadOverrideStatuses) { current, _ in current }

			// Starred/loved overrides: every article just created (recentArticleIDs
			// union overrideArticleIDs, i.e. all of articleIDs) got a fresh statuses
			// row defaulting starred/loved to false; flip it true here for any
			// articleID whose bookKey already has a starred/loved book-level row.
			// Unlike read/unread, there's no "unstarred override" branch needed --
			// false is already the row's default, so only the true set needs a
			// write.
			let bookStarredStateByBookKey = self.bookStarredStateTable.state(for: Set(bookKeysByArticleID.values), database)
			let starredOverrideArticleIDs = Set(bookKeysByArticleID.compactMap { articleID, bookKey in
				bookStarredStateByBookKey[bookKey] == true ? articleID : nil
			})
			if !starredOverrideArticleIDs.isEmpty {
				_ = self.statusesTable.mark(starredOverrideArticleIDs, .starred, true, database)
			}

			let bookLovedStateByBookKey = self.bookLovedStateTable.state(for: Set(bookKeysByArticleID.values), database)
			let lovedOverrideArticleIDs = Set(bookKeysByArticleID.compactMap { articleID, bookKey in
				bookLovedStateByBookKey[bookKey] == true ? articleID : nil
			})
			if !lovedOverrideArticleIDs.isEmpty {
				_ = self.statusesTable.mark(lovedOverrideArticleIDs, .loved, true, database)
			}

			assert(statusesDictionary.count == articleIDs.count)

			// Diagnostic: the assert above is compiled out in Release builds, so
			// a partition bug that drops an articleID before it reaches
			// ensureStatusesForArticleIDs would otherwise vanish silently --
			// the row still lands in `articles` but never gets a matching
			// `statuses` row, and the natural join in fetchArticlesWithWhereClause
			// then join-away that row from every fetch with no error anywhere.
			// Log the exact missing articleIDs so a production refresh of an
			// affected feed points straight back to the partition logic.
			if statusesDictionary.count != articleIDs.count {
				let missing = articleIDs.subtracting(statusesDictionary.keys)
				Self.logger.warning("ArticlesTable: update(feedID:\(feedID, privacy: .public)) missing statuses for \(missing.count, privacy: .public) articleIDs: \(missing.sorted().joined(separator: ","), privacy: .public)")
			}

			let incomingArticles = Article.articlesWithParsedItems(parsedItems, feedID, self.accountID, statusesDictionary) // 2
			if incomingArticles.isEmpty {
				self.callUpdateArticlesCompletionBlock(nil, nil, nil, completion)
				return
			}

			// Diagnostic: `articlesWithParsedItems` maps each parsedItem to an
			// Article keyed by the same articleID computed above -- if it builds a
			// Dictionary/Set internally, a second collision point exists here even
			// when `articleIDs.count` above matched `parsedItems.count`, e.g. two
			// items with distinct articleIDs that both resolve to the same
			// Article.articleID via a different code path. Comparing against
			// `articleIDs.count` (not `parsedItems.count`) isolates this stage.
            if incomingArticles.count != articleIDs.count {
                Self.logger.warning("ArticlesTable: update(feedID:\(feedID, privacy: .public)) incomingArticles.count (\(incomingArticles.count, privacy: .public)) != distinct articleIDs.count (\(articleIDs.count, privacy: .public)) -- \(articleIDs.count - incomingArticles.count, privacy: .public) lost building Article values")
            }

			let fetchedArticles = self.fetchArticlesForFeedID(feedID, database) // 4
			let fetchedArticlesDictionary = fetchedArticles.dictionary()

			let newArticles = self.findAndSaveNewArticles(incomingArticles, fetchedArticlesDictionary, database) // 5
			let updatedArticles = self.findAndSaveUpdatedArticles(incomingArticles, fetchedArticlesDictionary, database) // 6

			// Articles to delete are 1) not starred, not loved, and 2) older than 30 days and 3) no longer in feed.
			let articlesToDelete: Set<Article>
			if deleteOlder {
				let cutoffDate = Date().bySubtracting(days: 30)
				articlesToDelete = fetchedArticles.filter { (article) -> Bool in
					return !article.status.starred && !article.status.loved && article.status.dateArrived < cutoffDate && !articleIDs.contains(article.articleID)
				}
			} else {
				articlesToDelete = Set<Article>()
			}

			// Diagnostic: full reconciliation for this feed's update, logged once
			// per call regardless of outcome, so a "some works missing" report can
			// be checked against exact numbers instead of reconstructed from
			// separate log lines scattered across the transaction. `unchanged`
			// is incoming articles that matched an existing row with no detected
			// diff (neither new nor updated) -- previously invisible; now counted
			// explicitly so it can't be mistaken for "lost."
			let newCount = newArticles?.count ?? 0
			let updatedCount = updatedArticles?.count ?? 0
			let matchedExistingCount = incomingArticles.filter { fetchedArticlesDictionary[$0.articleID] != nil }.count
			let unchangedCount = matchedExistingCount - updatedCount
			let unaccountedCount = incomingArticles.count - newCount - matchedExistingCount
			Self.logger.info("ArticlesTable: update(feedID:\(feedID, privacy: .public)) incoming=\(incomingArticles.count, privacy: .public) existingBeforeUpdate=\(fetchedArticles.count, privacy: .public) new=\(newCount, privacy: .public) updated=\(updatedCount, privacy: .public) unchanged=\(unchangedCount, privacy: .public) toDelete=\(articlesToDelete.count, privacy: .public) unaccounted=\(unaccountedCount, privacy: .public)")
			if unaccountedCount != 0 {
				Self.logger.warning("ArticlesTable: update(feedID:\(feedID, privacy: .public)) unaccounted != 0 -- \(unaccountedCount, privacy: .public) incoming articles were neither classified as new nor matched to an existing row")
			}

			self.callUpdateArticlesCompletionBlock(newArticles, updatedArticles, articlesToDelete, completion) // 7

			self.addArticlesToCache(newArticles)
			self.addArticlesToCache(updatedArticles)

			// 8. Delete articles no longer in feed.
			let articleIDsToDelete = articlesToDelete.articleIDs()
			if !articleIDsToDelete.isEmpty {
				// Diagnostic: previously silent -- a `deleteOlder` pass wide enough
				// to explain "missing" articles (e.g. every pre-pagination article
				// that predates the cutoff and isn't in this incoming batch) should
				// be visible, not just its count.
				Self.logger.info("ArticlesTable: update(feedID:\(feedID, privacy: .public)) deleting \(articleIDsToDelete.count, privacy: .public) articles: \(articleIDsToDelete.sorted().joined(separator: ","), privacy: .public)")
				self.removeArticles(articleIDsToDelete, database)
				self.removeArticleIDsFromCache(articleIDsToDelete)
			}

			// 9. Update search index.
			if let newArticles = newArticles {
				self.searchTable.indexNewArticles(newArticles, database)
			}
			if let updatedArticles = updatedArticles {
				self.searchTable.indexUpdatedArticles(updatedArticles, database)
			}

			// Diagnostic: authoritative persisted count for this feed, read back
			// from the database after every write in this transaction has been
			// issued -- the one number that can't drift from what actually landed
			// on disk, to compare directly against the feed's own `mergedItems`
			// total logged by LocalAccountRefresher.
			if let countResultSet = database.executeQuery("SELECT COUNT(*) FROM articles WHERE feedID = ?", withArgumentsIn: [feedID]) {
				if countResultSet.next() {
					let persistedCount = countResultSet.long(forColumnIndex: 0)
					Self.logger.info("ArticlesTable: update(feedID:\(feedID, privacy: .public)) persistedCountAfterUpdate=\(persistedCount, privacy: .public)")
				}
				countResultSet.close()
			}

			// Diagnostic: cross-check the COUNT(*) above against a rowid scan of
			// the same table/predicate. If these two numbers ever disagree, the
			// COUNT(*) query itself is suspect (e.g. stale index, wrong filter)
			// rather than the insert step -- narrowing the gap to a query bug
			// instead of a data bug.
			if let rowIDResultSet = database.executeQuery("SELECT rowid FROM articles WHERE feedID = ?", withArgumentsIn: [feedID]) {
				var rowIDScanCount = 0
				while rowIDResultSet.next() {
					rowIDScanCount += 1
				}
				rowIDResultSet.close()
				Self.logger.info("ArticlesTable: update(feedID:\(feedID, privacy: .public)) rowIDScanCountAfterUpdate=\(rowIDScanCount, privacy: .public)")
			}
		}
	}

	func update(_ feedIDsAndItems: [String: Set<ParsedItem>], _ read: Bool, _ completion: @escaping UpdateArticlesCompletionBlock) {
		precondition(retentionStyle == .syncSystem)
		if feedIDsAndItems.isEmpty {
			callUpdateArticlesCompletionBlock(nil, nil, nil, completion)
			return
		}

		// 1. Ensure statuses for all the incoming articles.
		// 2. Create incoming articles with parsedItems.
		// 3. Ignore incoming articles that are (!starred and read and really old)
		// 4. Fetch all articles for the feed.
		// 5. Create array of Articles not in database and save them.
		// 6. Create array of updated Articles and save what’s changed.
		// 7. Call back with new and updated Articles.
		// 8. Update search index.

		self.queue.runInTransaction { database in

			var articleIDs = Set<String>()
			for (_, parsedItems) in feedIDsAndItems {
				articleIDs.formUnion(parsedItems.articleIDs())
			}

			let (statusesDictionary, _) = self.statusesTable.ensureStatusesForArticleIDs(articleIDs, read, database) // 1
			assert(statusesDictionary.count == articleIDs.count)

			let allIncomingArticles = Article.articlesWithFeedIDsAndItems(feedIDsAndItems, self.accountID, statusesDictionary) // 2
			if allIncomingArticles.isEmpty {
				self.callUpdateArticlesCompletionBlock(nil, nil, nil, completion)
				return
			}

			let incomingArticles = self.filterIncomingArticles(allIncomingArticles) // 3
			if incomingArticles.isEmpty {
				self.callUpdateArticlesCompletionBlock(nil, nil, nil, completion)
				return
			}

			let incomingArticleIDs = incomingArticles.articleIDs()
			let fetchedArticles = self.fetchArticles(articleIDs: incomingArticleIDs, database) // 4
			let fetchedArticlesDictionary = fetchedArticles.dictionary()

			let newArticles = self.findAndSaveNewArticles(incomingArticles, fetchedArticlesDictionary, database) //
			let updatedArticles = self.findAndSaveUpdatedArticles(incomingArticles, fetchedArticlesDictionary, database) // 6

			self.callUpdateArticlesCompletionBlock(newArticles, updatedArticles, nil, completion) // 7

			self.addArticlesToCache(newArticles)
			self.addArticlesToCache(updatedArticles)

			// 8. Update search index.
			if let newArticles = newArticles {
				self.searchTable.indexNewArticles(newArticles, database)
			}
			if let updatedArticles = updatedArticles {
				self.searchTable.indexUpdatedArticles(updatedArticles, database)
			}
		}
	}

	public func delete(articleIDs: Set<String>, completion: DatabaseCompletionBlock?) {
		self.queue.runInTransaction { database in
			self.removeArticles(articleIDs, database)
			DispatchQueue.main.async {
				completion?()
			}
		}
	}

	// MARK: - Unread Counts

	func fetchUnreadCounts(_ feedIDs: Set<String>, _ completion: @escaping UnreadCountDictionaryCompletionBlock) {
		if feedIDs.isEmpty {
			completion(UnreadCountDictionary())
			return
		}

		queue.runInDatabase { database in
			let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
			let sql = "select distinct feedID, count(*) from articles natural join statuses where feedID in \(placeholders) and read=0 group by feedID;"

			let parameters = Array(feedIDs) as [Any]

			guard let resultSet = database.executeQuery(sql, withArgumentsIn: parameters) else {
				DispatchQueue.main.async {
					completion(UnreadCountDictionary())
				}
				return
			}
			defer {
				resultSet.close()
			}

			var unreadCountDictionary = UnreadCountDictionary()
			while resultSet.next() {
				let unreadCount = resultSet.long(forColumnIndex: 1)
				if let feedID = resultSet.swiftString(forColumnIndex: 0) {
					unreadCountDictionary[feedID] = unreadCount
				}
			}

			DispatchQueue.main.async {
				completion(unreadCountDictionary)
			}
		}
	}

	func fetchUnreadCount(_ feedIDs: Set<String>, _ since: Date, _ completion: @escaping SingleUnreadCountCompletionBlock) {
		// Get unread count for Recently Added, for instance. Uses dateArrived
		// specifically (not datePublished) -- this answers "added to the
		// library since," not "published since," which is what the old
		// Today smart feed asked and doesn't apply to a book collection.
		if feedIDs.isEmpty {
			completion(0)
			return
		}

		queue.runInDatabase { database in
			let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
			let sql = "select count(*) from articles natural join statuses where feedID in \(placeholders) and dateArrived > ? and read=0;"

			var parameters = [Any]()
			parameters += Array(feedIDs) as [Any]
			parameters += [since] as [Any]

			let unreadCount = self.numberWithSQLAndParameters(sql, parameters, in: database)

			DispatchQueue.main.async {
				completion(unreadCount)
			}
		}
	}

	func fetchStarredAndUnreadCount(_ feedIDs: Set<String>, _ completion: @escaping SingleUnreadCountCompletionBlock) {
		if feedIDs.isEmpty {
			completion(0)
			return
		}

		queue.runInDatabase { database in
			let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
			let sql = "select count(*) from articles natural join statuses where feedID in \(placeholders) and read=0 and starred=1;"
			let parameters = Array(feedIDs) as [Any]

			let unreadCount = self.numberWithSQLAndParameters(sql, parameters, in: database)

			DispatchQueue.main.async {
				completion(unreadCount)
			}
		}
	}

	func fetchLovedAndUnreadCount(_ feedIDs: Set<String>, _ completion: @escaping SingleUnreadCountCompletionBlock) {
		if feedIDs.isEmpty {
			completion(0)
			return
		}

		queue.runInDatabase { database in
			let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
			let sql = "select count(*) from articles natural join statuses where feedID in \(placeholders) and read=0 and loved=1;"
			let parameters = Array(feedIDs) as [Any]

			let unreadCount = self.numberWithSQLAndParameters(sql, parameters, in: database)

			DispatchQueue.main.async {
				completion(unreadCount)
			}
		}
	}

	func fetchArticlesCountSince(_ feedIDs: Set<String>, _ cutoffDate: Date, _ completion: @escaping SingleUnreadCountCompletionBlock) {
		// Total count (read and unread) added to the library since a cutoff
		// date -- Recently Added's count, for instance.
		if feedIDs.isEmpty {
			completion(0)
			return
		}

		queue.runInDatabase { database in
			let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
			let sql = "select count(*) from articles natural join statuses where feedID in \(placeholders) and dateArrived > ?;"

			var parameters = [Any]()
			parameters += Array(feedIDs) as [Any]
			parameters += [cutoffDate] as [Any]

			let count = self.numberWithSQLAndParameters(sql, parameters, in: database)

			DispatchQueue.main.async {
				completion(count)
			}
		}
	}

	func fetchStarredArticlesCountAsync(_ feedIDs: Set<String>, _ completion: @escaping SingleUnreadCountCompletionBlock) {
		if feedIDs.isEmpty {
			completion(0)
			return
		}

		queue.runInDatabase { database in
			let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
			let sql = "select count(*) from articles natural join statuses where feedID in \(placeholders) and starred=1;"
			let parameters = Array(feedIDs) as [Any]

			let count = self.numberWithSQLAndParameters(sql, parameters, in: database)

			DispatchQueue.main.async {
				completion(count)
			}
		}
	}

	func fetchLovedArticlesCountAsync(_ feedIDs: Set<String>, _ completion: @escaping SingleUnreadCountCompletionBlock) {
		if feedIDs.isEmpty {
			completion(0)
			return
		}

		queue.runInDatabase { database in
			let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
			let sql = "select count(*) from articles natural join statuses where feedID in \(placeholders) and loved=1;"
			let parameters = Array(feedIDs) as [Any]

			let count = self.numberWithSQLAndParameters(sql, parameters, in: database)

			DispatchQueue.main.async {
				completion(count)
			}
		}
	}

	func fetchReadArticlesCountAsync(_ feedIDs: Set<String>, _ completion: @escaping SingleUnreadCountCompletionBlock) {
		if feedIDs.isEmpty {
			completion(0)
			return
		}

		queue.runInDatabase { database in
			let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
			let sql = "select count(*) from articles natural join statuses where feedID in \(placeholders) and read=1;"
			let parameters = Array(feedIDs) as [Any]

			let count = self.numberWithSQLAndParameters(sql, parameters, in: database)

			DispatchQueue.main.async {
				completion(count)
			}
		}
	}

	// MARK: - Statuses

	func fetchUnreadArticleIDsAsync(_ completion: @escaping ArticleIDsCompletionBlock) {
		statusesTable.fetchArticleIDsAsync(.read, false, completion)
	}

	func fetchStarredArticleIDsAsync(_ completion: @escaping ArticleIDsCompletionBlock) {
		statusesTable.fetchArticleIDsAsync(.starred, true, completion)
	}

	func fetchLovedArticleIDsAsync(_ completion: @escaping ArticleIDsCompletionBlock) {
		statusesTable.fetchArticleIDsAsync(.loved, true, completion)
	}

	func fetchStarredArticleIDs() -> Set<String> {
		statusesTable.fetchStarredArticleIDs()
	}

	func fetchLovedArticleIDs() -> Set<String> {
		statusesTable.fetchLovedArticleIDs()
	}

	func fetchArticleIDsForStatusesWithoutArticlesNewerThanCutoffDate(_ completion: @escaping ArticleIDsCompletionBlock) {
		statusesTable.fetchArticleIDsForStatusesWithoutArticlesNewerThan(articleCutoffDate, completion)
	}

	func mark(_ articleIDs: Set<String>, _ statusKey: ArticleStatus.Key, _ flag: Bool, _ completion: @escaping ArticleIDsCompletionBlock) {
		queue.runInTransaction { database in
			var changedArticleIDs = self.statusesTable.mark(articleIDs, statusKey, flag, database)

			// Phase 6 (read) / nectarfixes #3 (starred, loved): write through to
			// the book-level state table on every read/unread, starred/unstarred,
			// or loved/unloved toggle, so the book-level store stays in sync with
			// whatever the user just did, regardless of which (feed, guid) pair
			// they did it through -- and propagate the same flag live to every
			// other articleID sharing that bookKey, so any other feed's copy of
			// the same book updates immediately, without waiting for that copy's
			// next import/refresh.
			//
			// This function's return value is what account.updateStatusesAsync
			// forwards into the .StatusesDidChange notification's articleIDs
			// payload, so folding sibling IDs into changedArticleIDs is what
			// makes already-visible timelines/article views for the sibling
			// copies repaint live -- no separate notification plumbing needed.
			if [.read, .starred, .loved].contains(statusKey), !changedArticleIDs.isEmpty {
				let bookKeys = self.bookKeysForArticleIDs(changedArticleIDs, database)
				if !bookKeys.isEmpty {
					switch statusKey {
					case .read:
						self.bookReadStateTable.setState(flag, bookKeys: bookKeys, database)
					case .starred:
						self.bookStarredStateTable.setState(flag, bookKeys: bookKeys, database)
					case .loved:
						self.bookLovedStateTable.setState(flag, bookKeys: bookKeys, database)
					}

					let siblingArticleIDs = self.articleIDsForBookKeys(bookKeys, excluding: changedArticleIDs, database)
					if !siblingArticleIDs.isEmpty {
						let siblingChangedArticleIDs = self.statusesTable.mark(siblingArticleIDs, statusKey, flag, database)
						changedArticleIDs.formUnion(siblingChangedArticleIDs)
					}
				}
			}

			DispatchQueue.main.async {
				completion(changedArticleIDs)
			}
		}
	}

	/// bookKey values for a set of articleIDs. Small helper for the write-through
	/// in `mark(_:_:_:_:)` above -- StatusesTable has no access to `bookKey`,
	/// since that column lives on `articles`, not `statuses`.
	private func bookKeysForArticleIDs(_ articleIDs: Set<String>, _ database: FMDatabase) -> Set<String> {
		guard let resultSet = self.selectRowsWhere(key: DatabaseKey.articleID, inValues: Array(articleIDs), in: database) else {
			return []
		}
		var bookKeys = Set<String>()
		while resultSet.next() {
			if let bookKey = resultSet.swiftString(forColumn: DatabaseKey.bookKey), !bookKey.isEmpty {
				bookKeys.insert(bookKey)
			} else if let uniqueID = resultSet.swiftString(forColumn: DatabaseKey.uniqueID) {
				// Pre-migration row with no bookKey persisted yet -- same fallback
				// Article.init uses (bookKey ?? uniqueID).
				bookKeys.insert(uniqueID)
			}
		}
		return bookKeys
	}

	/// The reverse of bookKeysForArticleIDs above: every articleID whose
	/// bookKey (or, for pre-migration rows with no bookKey, whose uniqueID
	/// used as the bookKey fallback -- see bookKeysForArticleIDs) is in the
	/// given set, excluding articleIDs already known-changed. Used by
	/// `mark(_:_:_:_:)` to find every other copy of "the same book" so a
	/// starred/loved/read toggle on one copy can be live-propagated to the
	/// rest, not just persisted to the book-level state table for the next
	/// import to pick up.
	private func articleIDsForBookKeys(_ bookKeys: Set<String>, excluding: Set<String>, _ database: FMDatabase) -> Set<String> {
		guard !bookKeys.isEmpty else {
			return []
		}

		var articleIDs = Set<String>()

		if let resultSet = self.selectRowsWhere(key: DatabaseKey.bookKey, inValues: Array(bookKeys), in: database) {
			while resultSet.next() {
				if let articleID = resultSet.swiftString(forColumn: DatabaseKey.articleID) {
					articleIDs.insert(articleID)
				}
			}
		}

		// Pre-migration fallback: rows with no bookKey use uniqueID in its
		// place (see bookKeysForArticleIDs). These rows won't match the
		// bookKey lookup above, so also match on uniqueID.
		if let resultSet = self.selectRowsWhere(key: DatabaseKey.uniqueID, inValues: Array(bookKeys), in: database) {
			while resultSet.next() {
				if let articleID = resultSet.swiftString(forColumn: DatabaseKey.articleID),
				   let bookKey = resultSet.swiftString(forColumn: DatabaseKey.bookKey), bookKey.isEmpty {
					articleIDs.insert(articleID)
				}
			}
		}

		return articleIDs.subtracting(excluding)
	}

	func markAndFetchNew(_ articleIDs: Set<String>, _ statusKey: ArticleStatus.Key, _ flag: Bool, _ completion: @escaping ArticleIDsCompletionBlock) {
		queue.runInTransaction { database in
			let newStatusIDs = self.statusesTable.markAndFetchNew(articleIDs, statusKey, flag, database)
			DispatchQueue.main.async {
				completion(newStatusIDs)
			}
		}
	}

	func createStatusesIfNeeded(_ articleIDs: Set<String>, _ completion: @escaping DatabaseCompletionBlock) {
		guard !articleIDs.isEmpty else {
			completion()
			return
		}

		queue.runInTransaction { database in
			self.statusesTable.ensureStatusesForArticleIDs(articleIDs, true, database)
			DispatchQueue.main.async {
				completion()
			}
		}
	}

	// MARK: - Scroll position (Phase 2)

	func saveScrollPosition(_ scrollPosition: Double, articleID: String, _ completion: @escaping DatabaseCompletionBlock) {
		queue.runInTransaction { database in
			self.statusesTable.saveScrollPosition(scrollPosition, articleID: articleID, database)
			DispatchQueue.main.async {
				completion()
			}
		}
	}

	func fetchScrollPosition(articleID: String, _ completion: @escaping @Sendable (Double) -> Void) {
		queue.runInDatabase { database in
			let scrollPosition = self.statusesTable.fetchScrollPosition(articleID: articleID, database)
			DispatchQueue.main.async {
				completion(scrollPosition)
			}
		}
	}

	// MARK: - Reading progress (Phase A1)

	func saveReadingProgress(_ readingProgress: Double, articleID: String, _ completion: @escaping DatabaseCompletionBlock) {
		queue.runInTransaction { database in
			self.statusesTable.saveReadingProgress(readingProgress, articleID: articleID, database)
			DispatchQueue.main.async {
				completion()
			}
		}
	}

	// MARK: - Indexing

	func indexUnindexedArticles() {
		queue.runInDatabase { database in
			let sql = "select articleID from articles where searchRowID is null limit 500;"
			guard let resultSet = database.executeQuery(sql, withArgumentsIn: nil) else {
				return
			}
			let articleIDs = resultSet.mapToSet { $0.swiftString(forColumn: DatabaseKey.articleID) }
			if articleIDs.isEmpty {
				return
			}
			self.searchTable.ensureIndexedArticles(articleIDs, database)

			DispatchQueue.main.async {
				self.indexUnindexedArticles()
			}
		}
	}

	// MARK: - Caches

	@objc func handleLowMemory(_ notification: Notification) {
		emptyCaches()
	}

	func emptyCaches() {
		queue.runInDatabase { _ in
			self.articlesCache.withLock { $0 = [String: Article]() }
		}
	}

	// MARK: - Cleanup

	/// Delete articles that we won’t show in the UI any longer
	/// — their arrival date is before our 90-day recency window;
	/// they are read; they are not starred.
	///
	/// Because deleting articles might block the database for too long,
	/// we do this in a careful way: delete articles older than a year,
	/// check to see how much time has passed, then decide whether or not to continue.
	/// Repeat for successively more-recent dates.
	///
	/// Returns `true` if it deleted old articles all the way up to the 90 day cutoff date.
	func deleteOldArticles() {
		precondition(retentionStyle == .syncSystem)

		queue.runInTransaction { database in
			func deleteOldArticles(cutoffDate: Date) {
				let sql = "delete from articles where articleID in (select articleID from articles natural join statuses where dateArrived<? and read=1 and starred=0 and loved=0);"
				let parameters = [cutoffDate] as [Any]
				database.executeUpdate(sql, withArgumentsIn: parameters)
			}

			let startTime = Date()
			func tooMuchTimeHasPassed() -> Bool {
				let timeElapsed = Date().timeIntervalSince(startTime)
				return timeElapsed > 2.0
			}

			let dayIntervals = [365, 300, 225, 150]
			for dayInterval in dayIntervals {
				deleteOldArticles(cutoffDate: startTime.bySubtracting(days: dayInterval))
				if tooMuchTimeHasPassed() {
					return
				}
			}
			deleteOldArticles(cutoffDate: self.articleCutoffDate)
		}
	}

	/// Delete old statuses.
	func deleteOldStatuses() {
		queue.runInTransaction { database in
			let sql: String
			let cutoffDate: Date

			switch self.retentionStyle {
			case .syncSystem:
				sql = "delete from statuses where dateArrived<? and read=1 and starred=0 and loved=0 and articleID not in (select articleID from articles);"
				cutoffDate = Date().bySubtracting(days: 180)
			case .feedBased:
				sql = "delete from statuses where dateArrived<? and starred=0 and loved=0 and articleID not in (select articleID from articles);"
				cutoffDate = Date().bySubtracting(days: 30)
			}

			let parameters = [cutoffDate] as [Any]
			database.executeUpdate(sql, withArgumentsIn: parameters)
		}
	}

	/// Delete articles from feeds that are no longer in the current set of subscribed-to feeds.
	/// This deletes from the articles and articleStatuses tables,
	/// and, via a trigger, it also deletes from the search index.
	///
	/// Only articles with no user-generated state are eligible: this must never
	/// delete anything the person has read, starred, loved, or made reading
	/// progress on. A feed going missing from the subscribed set isn't
	/// necessarily "the person doesn't want this anymore" -- for a paired
	/// local-server account (Ambrosia), it can simply mean the server's
	/// address changed and the old feed entry hasn't been cleaned up yet.
	/// Treating that the same as an intentional unsubscribe would silently
	/// delete books out from under the person. Only fully untouched articles
	/// (never opened, not starred, not loved) are reaped here.
	func deleteArticlesNotInSubscribedToFeedIDs(_ feedIDs: Set<String>) {
		if feedIDs.isEmpty {
			return
		}
		queue.runInDatabase { database in
			let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
			let sql = "select articleID from articles natural join statuses where feedID not in \(placeholders) and read=0 and starred=0 and loved=0 and (readingProgress is null or readingProgress<=0);"
			let parameters = Array(feedIDs) as [Any]
			guard let resultSet = database.executeQuery(sql, withArgumentsIn: parameters) else {
				return
			}
			let articleIDs = resultSet.mapToSet { $0.swiftString(forColumn: DatabaseKey.articleID) }
			if articleIDs.isEmpty {
				return
			}
			self.removeArticles(articleIDs, database)
			self.statusesTable.removeStatuses(articleIDs, database)
		}
	}
}

// MARK: - Private

nonisolated private extension ArticlesTable {

	// MARK: - Fetching

	private func fetchArticles(_ fetchMethod: @escaping ArticlesFetchMethod) -> Set<Article> {
		nonisolated(unsafe) var articles = Set<Article>()

		queue.runInDatabaseSync { database in
			articles = fetchMethod(database)
		}
		return articles
	}

	private func fetchArticlesCount(_ fetchMethod: @escaping ArticlesCountFetchMethod) -> Int {
		nonisolated(unsafe) var articlesCount = 0

		queue.runInDatabaseSync { database in
			articlesCount = fetchMethod(database)
		}
		return articlesCount
	}

	private func fetchArticlesAsync(_ fetchMethod: @escaping ArticlesFetchMethod, _ completion: @escaping ArticleSetResultBlock) {
		queue.runInDatabase { database in
			let articles = fetchMethod(database)
			DispatchQueue.main.async {
				completion(articles)
			}
		}
	}

	func articlesWithResultSet(_ resultSet: FMResultSet, _ database: FMDatabase) -> Set<Article> {
		var articles = Set<Article>()

		// Diagnostic: previously this loop discarded a row with a bare
		// `continue` whenever articleID/status lookup or the failable
		// Article(row:) initializer returned nil -- in a Release build
		// (where assertionFailure is a no-op) that's a completely silent
		// drop. Since the write path has already been confirmed correct
		// (saveNewArticles reports totalChanges matching attempted, and
		// persistedCountAfterUpdate/rowIDScanCountAfterUpdate agree), if
		// fetched count is still short, this loop is where to look: count
		// every row scanned vs. every Article actually produced, and log
		// the specific reason and articleID for each row that's dropped.
		var rowsScanned = 0
		var droppedNoArticleID = 0
		var droppedNoStatus = 0
		var droppedInitFailed = [String]()
		var cacheHits = 0

		while resultSet.next() {
			rowsScanned += 1

			guard let articleID = resultSet.swiftString(forColumn: DatabaseKey.articleID) else {
				assertionFailure("Expected articleID.")
				droppedNoArticleID += 1
				continue
			}

			if let cachedArticle = articlesCache.withLock({ $0[articleID] }) {
				cacheHits += 1
				articles.insert(cachedArticle)
				continue
			}

			// The resultSet is a result of a JOIN query with the statuses table,
			// so we can get the statuses at the same time and avoid additional database lookups.
			guard let status = statusesTable.statusWithRow(resultSet, articleID: articleID) else {
				assertionFailure("Expected status.")
				droppedNoStatus += 1
				continue
			}

			guard let article = Article(accountID: accountID, row: resultSet, status: status) else {
				droppedInitFailed.append(articleID)
				continue
			}
			articlesCache.withLock { $0[articleID] = article }
			articles.insert(article)
		}

		if droppedNoArticleID > 0 || droppedNoStatus > 0 || !droppedInitFailed.isEmpty {
			Self.logger.warning("ArticlesTable: articlesWithResultSet rowsScanned=\(rowsScanned, privacy: .public) produced=\(articles.count, privacy: .public) droppedNoArticleID=\(droppedNoArticleID, privacy: .public) droppedNoStatus=\(droppedNoStatus, privacy: .public) droppedInitFailed=\(droppedInitFailed.count, privacy: .public) initFailedArticleIDs=\(droppedInitFailed.joined(separator: ","), privacy: .public)")
		}

		// Diagnostic: unconditional -- the warning above only fires on a
		// drop, so a clean run (rowsScanned == produced) previously left no
		// trace at all. Log every call so a shortfall between this
		// function's own scan and the SQL layer's row count can be told
		// apart from a shortfall introduced upstream of this function.
		// cacheHits is broken out separately so a stale in-memory cache
		// (holding a pre-merge snapshot) can be distinguished from rows
		// genuinely built fresh off this result set.
		Self.logger.info("ArticlesTable: articlesWithResultSet rowsScanned=\(rowsScanned, privacy: .public) producedCount=\(articles.count, privacy: .public) cacheHits=\(cacheHits, privacy: .public)")

		resultSet.close()
		return articles
	}

	func fetchArticlesWithWhereClause(_ database: FMDatabase, whereClause: String, parameters: [AnyObject]) -> Set<Article> {
		let sql = "select * from articles natural join statuses where \(whereClause);"
		return articlesWithSQL(sql, parameters, database)
	}

	func fetchArticleCountsWithWhereClause(_ database: FMDatabase, whereClause: String, parameters: [AnyObject]) -> Int {
		let sql = "select count(*) from articles natural join statuses where \(whereClause);"
		guard let resultSet = database.executeQuery(sql, withArgumentsIn: parameters) else {
			return 0
		}
		var articlesCount = 0
		if resultSet.next() {
			articlesCount = resultSet.long(forColumnIndex: 0)
		}
		resultSet.close()
		return articlesCount
	}

	func fetchArticlesMatching(_ searchString: String, _ database: FMDatabase) -> Set<Article> {
		let sql = "select rowid from search where search match ?;"
		let sqlSearchString = sqliteSearchString(with: searchString)
		let searchStringParameters = [sqlSearchString]
		guard let resultSet = database.executeQuery(sql, withArgumentsIn: searchStringParameters) else {
			return Set<Article>()
		}
		let searchRowIDs = resultSet.mapToSet { $0.longLongInt(forColumnIndex: 0) }
		if searchRowIDs.isEmpty {
			return Set<Article>()
		}

		let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(searchRowIDs.count))!
		let whereClause = "searchRowID in \(placeholders)"
		let parameters: [AnyObject] = Array(searchRowIDs) as [AnyObject]
		return fetchArticlesWithWhereClause(database, whereClause: whereClause, parameters: parameters)
	}

	func sqliteSearchString(with searchString: String) -> String {
		var s = ""
		searchString.enumerateSubstrings(in: searchString.startIndex..<searchString.endIndex, options: .byWords) { (word, _, _, _) in
			guard let word else {
				return
			}
			s += word
			if word != "AND" && word != "OR" {
				s += "*"
			}
			s += " "
		}
		return s
	}

	func articlesWithSQL(_ sql: String, _ parameters: [AnyObject], _ database: FMDatabase) -> Set<Article> {
		let signpostState = Self.signposter.beginInterval("Fetch articles")
		let startTime = Date()

		guard let resultSet = database.executeQuery(sql, withArgumentsIn: parameters) else {
			Self.signposter.endInterval("Fetch articles", signpostState, "no result set")
			return Set<Article>()
		}
		let articles = articlesWithResultSet(resultSet, database)

		let elapsed = Date().timeIntervalSince(startTime)
		Self.signposter.endInterval("Fetch articles", signpostState, "\(articles.count) articles")
		Self.logger.info("ArticlesTable: fetched \(articles.count, privacy: .public) articles in \(elapsed, privacy: .public) seconds in account \(self.accountID, privacy: .public)")

		// Diagnostic: this query joins articles to statuses, which silently
		// drops any articles row that lacks a matching statuses row. If a
		// merge inserted articles without corresponding status rows, the
		// join-based fetch above will undercount even though the articles
		// table itself has every row. Compare a raw, join-free count for
		// the same articleIDs against what the join actually returned.
		let joinedArticleIDs = Set(articles.map { $0.articleID })
		if !joinedArticleIDs.isEmpty || sql.contains("natural join statuses") {
			let rawWhereClause = sql
				.replacingOccurrences(of: "select * from articles natural join statuses where ", with: "")
				.replacingOccurrences(of: ";", with: "")
			let rawSQL = "select count(*) from articles where \(rawWhereClause);"
			if let rawResultSet = database.executeQuery(rawSQL, withArgumentsIn: parameters) {
				var rawCount = 0
				if rawResultSet.next() {
					rawCount = rawResultSet.long(forColumnIndex: 0)
				}
				rawResultSet.close()
				if rawCount != articles.count {
					Self.logger.warning("ArticlesTable: articlesWithSQL join mismatch rawArticlesCount=\(rawCount, privacy: .public) joinedFetchedCount=\(articles.count, privacy: .public) sql=\(sql, privacy: .public)")
				}
			}
		}

		return articles
	}

	func fetchArticles(_ feedIDs: Set<String>, _ database: FMDatabase) -> Set<Article> {
		// select * from articles natural join statuses where feedID in ('http://ranchero.com/xml/rss.xml') and read=0
		if feedIDs.isEmpty {
			return Set<Article>()
		}
		let parameters = feedIDs.map { $0 as AnyObject }
		let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
		let whereClause = "feedID in \(placeholders)"
		return fetchArticlesWithWhereClause(database, whereClause: whereClause, parameters: parameters)
	}

	func fetchUnreadArticles(_ feedIDs: Set<String>, _ limit: Int?, _ database: FMDatabase) -> Set<Article> {
		// select * from articles natural join statuses where feedID in ('http://ranchero.com/xml/rss.xml') and read=0
		if feedIDs.isEmpty {
			return Set<Article>()
		}
		let parameters = feedIDs.map { $0 as AnyObject }
		let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
		var whereClause = "feedID in \(placeholders) and read=0"
		if let limit = limit {
			whereClause.append(" order by coalesce(datePublished, dateModified, dateArrived) desc limit \(limit)")
		}

		// Diagnostic: confirms the exact where-clause and feed count used
		// for this fetch, so a shortfall can be told apart as either
		// "query is correct but excludes rows" (e.g. read=0 filtering out
		// newly-merged articles that didn't get a status row) versus
		// "query itself is scoped wrong" (stale feedIDs, wrong limit).
		Self.logger.info("ArticlesTable: fetchUnreadArticles feedIDs=\(feedIDs.count, privacy: .public) whereClause=\(whereClause, privacy: .public)")

		return fetchArticlesWithWhereClause(database, whereClause: whereClause, parameters: parameters)
	}

	func fetchArticlesForFeedID(_ feedID: String, _ database: FMDatabase) -> Set<Article> {
		return fetchArticlesWithWhereClause(database, whereClause: "articles.feedID = ?", parameters: [feedID as AnyObject])
	}

	func fetchReadArticles(_ feedIDs: Set<String>, _ limit: Int?, _ database: FMDatabase) -> Set<Article> {
		// select * from articles natural join statuses where feedID in ('http://ranchero.com/xml/rss.xml') and read=1;
		if feedIDs.isEmpty {
			return Set<Article>()
		}
		let parameters = feedIDs.map { $0 as AnyObject }
		let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
		var whereClause = "feedID in \(placeholders) and read=1"
		if let limit = limit {
			whereClause.append(" order by coalesce(datePublished, dateModified, dateArrived) desc limit \(limit)")
		}
		return fetchArticlesWithWhereClause(database, whereClause: whereClause, parameters: parameters)
	}

	func fetchReadArticlesCount(_ feedIDs: Set<String>, _ database: FMDatabase) -> Int {
		// select count from articles natural join statuses where feedID in ('http://ranchero.com/xml/rss.xml') and read=1;
		if feedIDs.isEmpty {
			return 0
		}
		let parameters = feedIDs.map { $0 as AnyObject }
		let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
		let whereClause = "feedID in \(placeholders) and read=1"
		return fetchArticleCountsWithWhereClause(database, whereClause: whereClause, parameters: parameters)
	}

	func fetchArticles(articleIDs: Set<String>, _ database: FMDatabase) -> Set<Article> {
		if articleIDs.isEmpty {
			return Set<Article>()
		}
		let parameters = articleIDs.map { $0 as AnyObject }
		let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(articleIDs.count))!
		let whereClause = "articleID in \(placeholders)"
		return fetchArticlesWithWhereClause(database, whereClause: whereClause, parameters: parameters)
	}

	func fetchArticlesSince(_ feedIDs: Set<String>, _ cutoffDate: Date, _ limit: Int?, _ database: FMDatabase) -> Set<Article> {
		// select * from articles natural join statuses where feedID in ('http://ranchero.com/xml/rss.xml') and dateArrived > ?
		//
		// Used by the Recently Added smart feed: dateArrived is when the
		// article/book entered the library, which is what "recently added"
		// means. Deliberately not datePublished -- a book's publish/added
		// date on the wire (Calibre's metadata) has no bearing on when you
		// actually got it, unlike a blog post where "published" and
		// "arrived" are close to the same moment.
		if feedIDs.isEmpty {
			return Set<Article>()
		}
		let parameters = feedIDs.map { $0 as AnyObject } + [cutoffDate as AnyObject]
		let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
		var whereClause = "feedID in \(placeholders) and dateArrived > ?"
		if let limit = limit {
			whereClause.append(" order by dateArrived desc limit \(limit)")
		}
		return fetchArticlesWithWhereClause(database, whereClause: whereClause, parameters: parameters)
	}

	func fetchStarredArticles(_ feedIDs: Set<String>, _ limit: Int?, _ database: FMDatabase) -> Set<Article> {
		// select * from articles natural join statuses where feedID in ('http://ranchero.com/xml/rss.xml') and starred=1;
		if feedIDs.isEmpty {
			return Set<Article>()
		}
		let parameters = feedIDs.map { $0 as AnyObject }
		let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
		var whereClause = "feedID in \(placeholders) and starred=1"
		if let limit = limit {
			whereClause.append(" order by coalesce(datePublished, dateModified, dateArrived) desc limit \(limit)")
		}
		return fetchArticlesWithWhereClause(database, whereClause: whereClause, parameters: parameters)
		}

	func fetchStarredArticlesCount(_ feedIDs: Set<String>, _ database: FMDatabase) -> Int {
		// select count from articles natural join statuses where feedID in ('http://ranchero.com/xml/rss.xml') and starred=1;
		if feedIDs.isEmpty {
			return 0
		}
		let parameters = feedIDs.map { $0 as AnyObject }
		let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
		let whereClause = "feedID in \(placeholders) and starred=1"
		return fetchArticleCountsWithWhereClause(database, whereClause: whereClause, parameters: parameters)
	}

	func fetchLovedArticles(_ feedIDs: Set<String>, _ limit: Int?, _ database: FMDatabase) -> Set<Article> {
		// select * from articles natural join statuses where feedID in ('http://ranchero.com/xml/rss.xml') and loved=1;
		if feedIDs.isEmpty {
			return Set<Article>()
		}
		let parameters = feedIDs.map { $0 as AnyObject }
		let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
		var whereClause = "feedID in \(placeholders) and loved=1"
		if let limit = limit {
			whereClause.append(" order by coalesce(datePublished, dateModified, dateArrived) desc limit \(limit)")
		}
		return fetchArticlesWithWhereClause(database, whereClause: whereClause, parameters: parameters)
	}

	func fetchLovedArticlesCount(_ feedIDs: Set<String>, _ database: FMDatabase) -> Int {
		// select count from articles natural join statuses where feedID in ('http://ranchero.com/xml/rss.xml') and loved=1;
		if feedIDs.isEmpty {
			return 0
		}
		let parameters = feedIDs.map { $0 as AnyObject }
		let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
		let whereClause = "feedID in \(placeholders) and loved=1"
		return fetchArticleCountsWithWhereClause(database, whereClause: whereClause, parameters: parameters)
	}

	static func statusesCount(_ database: FMDatabase) -> Int {
		guard let resultSet = database.executeQuery("select count(*) from statuses;", withArgumentsIn: nil) else {
			return 0
		}
		var count = 0
		if resultSet.next() {
			count = Int(resultSet.int(forColumnIndex: 0))
		}
		resultSet.close()
		return count
	}

	func articleCounts(feedIDs: Set<String>, database: FMDatabase) -> ArticleCounts {
		let totalCount: Int
		let unreadCount: Int
		let starredCount: Int

		if feedIDs.isEmpty {
			totalCount = 0
			unreadCount = 0
			starredCount = 0
		} else {
			let parameters = feedIDs.map { $0 as AnyObject }
			let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedIDs.count))!
			let feedIDClause = "feedID in \(placeholders)"
			totalCount = fetchArticleCountsWithWhereClause(database, whereClause: feedIDClause, parameters: parameters)
			unreadCount = fetchArticleCountsWithWhereClause(database, whereClause: "\(feedIDClause) and read=0", parameters: parameters)
			starredCount = fetchArticleCountsWithWhereClause(database, whereClause: "\(feedIDClause) and starred=1", parameters: parameters)
		}

		return ArticleCounts(
			totalCount: totalCount,
			unreadCount: unreadCount,
			starredCount: starredCount,
			statusesCount: Self.statusesCount(database)
		)
	}

	func fetchArticlesMatching(_ searchString: String, _ feedIDs: Set<String>, _ database: FMDatabase) -> Set<Article> {
		let articles = fetchArticlesMatching(searchString, database)
		// TODO: include the feedIDs in the SQL rather than filtering here.
		return articles.filter { feedIDs.contains($0.feedID) }
	}

	func fetchArticlesMatchingWithArticleIDs(_ searchString: String, _ articleIDs: Set<String>, _ database: FMDatabase) -> Set<Article> {
		let articles = fetchArticlesMatching(searchString, database)
		// TODO: include the articleIDs in the SQL rather than filtering here.
		return articles.filter { articleIDs.contains($0.articleID) }
	}

	func fetchLastUpdateDates(_ database: FMDatabase) -> [String: Date] {
		guard let resultSet = database.executeQuery("SELECT feedID, MAX(coalesce(datePublished, dateModified, dateArrived)) as latestDate FROM articles natural join statuses GROUP BY feedID;", withArgumentsIn: []) else {
			return [:]
		}
		defer {
			resultSet.close()
		}

		var result = [String: Date]()
		while resultSet.next() {
			guard let feedID = resultSet.string(forColumn: "feedID") else {
				continue
			}
			if !resultSet.columnIsNull("latestDate") {
				result[feedID] = resultSet.date(forColumn: "latestDate")
			}
		}
		return result
	}

	// MARK: - Saving Parsed Items

	func callUpdateArticlesCompletionBlock(_ newArticles: Set<Article>?, _ updatedArticles: Set<Article>?, _ deletedArticles: Set<Article>?, _ completion: @escaping UpdateArticlesCompletionBlock) {
		let articleChanges = ArticleChanges(new: newArticles, updated: updatedArticles, deleted: deletedArticles)
		DispatchQueue.main.async {
			completion(articleChanges)
		}
	}

	// MARK: - Saving New Articles

	func findNewArticles(_ incomingArticles: Set<Article>, _ fetchedArticlesDictionary: [String: Article]) -> Set<Article>? {
		let newArticles = Set(incomingArticles.filter { fetchedArticlesDictionary[$0.articleID] == nil })
		return newArticles.isEmpty ? nil : newArticles
	}

	func findAndSaveNewArticles(_ incomingArticles: Set<Article>, _ fetchedArticlesDictionary: [String: Article], _ database: FMDatabase) -> Set<Article>? { // 5
		guard let newArticles = findNewArticles(incomingArticles, fetchedArticlesDictionary) else {
			return nil
		}
		self.saveNewArticles(newArticles, database)
		return newArticles
	}

	func saveNewArticles(_ articles: Set<Article>, _ database: FMDatabase) {
		// Diagnostic: insertRows(_:insertType:in:) discards FMDB's per-row
		// success/failure result, so a silently-failing INSERT (constraint
		// violation, type mismatch, etc.) would previously vanish without a
		// trace -- the row would never land in `articles`, but nothing here
		// would say so. Insert row-by-row instead so each failure is logged
		// with FMDB's own error message, and log SQLite's actual changes()
		// count so it can be compared against `articles.count` to see
		// whether every row that should have landed on disk actually did.
		var failedArticleIDs = [String]()
		var totalChanges = 0
		for dictionary in articles.databaseDictionaries() {
			let didSucceed = database.rs_insertRow(with: dictionary, insertType: .orReplace, tableName: self.name)
			if didSucceed {
				totalChanges += Int(database.changes())
			} else {
				let articleID = dictionary[DatabaseKey.articleID] as? String ?? "?"
				failedArticleIDs.append(articleID)
				Self.logger.warning("ArticlesTable: saveNewArticles insert failed for articleID \(articleID, privacy: .public) -- \(database.lastErrorMessage(), privacy: .public)")
			}
		}
		Self.logger.info("ArticlesTable: saveNewArticles attempted=\(articles.count, privacy: .public) totalChanges=\(totalChanges, privacy: .public) failed=\(failedArticleIDs.count, privacy: .public)")
	}

	// MARK: - Updating Existing Articles

	func findUpdatedArticles(_ incomingArticles: Set<Article>, _ fetchedArticlesDictionary: [String: Article]) -> Set<Article>? {
		let updatedArticles = incomingArticles.filter { (incomingArticle) -> Bool in // 6
			if let existingArticle = fetchedArticlesDictionary[incomingArticle.articleID] {
				if existingArticle != incomingArticle {
					return true
				}
			}
			return false
		}

		return updatedArticles.isEmpty ? nil : updatedArticles
	}

	func findAndSaveUpdatedArticles(_ incomingArticles: Set<Article>, _ fetchedArticlesDictionary: [String: Article], _ database: FMDatabase) -> Set<Article>? { // 6
		guard let updatedArticles = findUpdatedArticles(incomingArticles, fetchedArticlesDictionary) else {
			return nil
		}
		saveUpdatedArticles(Set(updatedArticles), fetchedArticlesDictionary, database)
		return updatedArticles
	}

	func saveUpdatedArticles(_ updatedArticles: Set<Article>, _ fetchedArticles: [String: Article], _ database: FMDatabase) {
		for updatedArticle in updatedArticles {
			saveUpdatedArticle(updatedArticle, fetchedArticles, database)
		}
	}

	func saveUpdatedArticle(_ updatedArticle: Article, _ fetchedArticles: [String: Article], _ database: FMDatabase) {
		// Only update exactly what has changed in the Article (if anything).
		// Untested theory: this gets us better performance and less database fragmentation.

		guard let fetchedArticle = fetchedArticles[updatedArticle.articleID] else {
			assertionFailure("Expected to find matching fetched article.")
			saveNewArticles(Set([updatedArticle]), database)
			return
		}
		guard let changesDictionary = updatedArticle.changesFrom(fetchedArticle), changesDictionary.count > 0 else {
			// Not unexpected. There may be no changes.
			return
		}

		updateRowsWithDictionary(changesDictionary, whereKey: DatabaseKey.articleID, matches: updatedArticle.articleID, database: database)
	}

	func addArticlesToCache(_ articles: Set<Article>?) {
		guard let articles else {
			return
		}
		articlesCache.withLock { articlesCache in
			for article in articles {
				articlesCache[article.articleID] = article
			}
		}
	}

	func removeArticleIDsFromCache(_ articleIDs: Set<String>) {
		articlesCache.withLock { articlesCache in
			for articleID in articleIDs {
				articlesCache[articleID] = nil
			}
		}
	}

	func articleIsIgnorable(_ article: Article) -> Bool {
		if article.status.starred || !article.status.read {
			return false
		}
		return article.status.dateArrived < articleCutoffDate
	}

	func filterIncomingArticles(_ articles: Set<Article>) -> Set<Article> {
		// Drop Articles that we can ignore.
		precondition(retentionStyle == .syncSystem)
		return Set(articles.filter { !articleIsIgnorable($0) })
	}

	func removeArticles(_ articleIDs: Set<String>, _ database: FMDatabase) {
		deleteRowsWhere(key: DatabaseKey.articleID, equalsAnyValue: Array(articleIDs), in: database)
	}
}

private extension Set where Element == ParsedItem {
	func articleIDs() -> Set<String> {
		return Set<String>(map { $0.articleID })
	}
}
