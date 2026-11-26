//
//  SearchTableAndDatabaseTests.swift
//  ArticlesDatabaseTests
//
//  Characterization and regression tests for FTS5 search indexing,
//  query sanitization, SQLite PRAGMAs, json_each ID lists, and BLOB storage.
//

import Testing
import Foundation
import os
import RSParser
import Articles
import RSDatabase
import RSDatabaseObjC
@testable import ArticlesDatabase

@Suite("SearchTable FTS5 and database storage")
@MainActor
struct SearchTableAndDatabaseTests {

	private static let feedID = "feed-search-1"
	private static let feedURL = "https://example.com/search-feed"

	private func makeTemporaryPath() -> String {
		NSTemporaryDirectory() + "search-db-test-\(UUID().uuidString).sqlite3"
	}

	@Test("indexes articles into FTS5 and updates index when title or body changes")
	func indexesAndUpdatesFTS5() async throws {
		let db = TestFixtures.makeDatabase()
		let item1 = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: Self.feedURL,
			title: "Starlight Caravan",
			contentHTML: "<p>A quiet journey across the northern ridge.</p>"
		)
		let item2 = TestFixtures.makeParsedItem(
			uniqueID: "u2",
			feedURL: Self.feedURL,
			title: "Harbor Lanterns",
			contentHTML: "<p>Waves against the stone pier at dusk.</p>"
		)

		_ = await db.updateAsync(parsedItems: [item1, item2], feedID: Self.feedID, deleteOlder: false)

		let titleMatches = await db.fetchArticlesMatchingAsync(searchString: "Starlight", feedIDs: [Self.feedID])
		#expect(titleMatches.map(\.uniqueID) == ["u1"])

		let bodyMatches = await db.fetchArticlesMatchingAsync(searchString: "lantern", feedIDs: [Self.feedID])
		#expect(bodyMatches.map(\.uniqueID) == ["u2"])

		// Update item1 with new title and body; old terms should stop matching.
		let updatedItem1 = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: Self.feedURL,
			title: "Clockwork Observatory",
			contentHTML: "<p>Brass gears turning beneath a glass dome.</p>"
		)
		_ = await db.updateAsync(parsedItems: [updatedItem1, item2], feedID: Self.feedID, deleteOlder: false)

		let staleMatches = await db.fetchArticlesMatchingAsync(searchString: "Starlight", feedIDs: [Self.feedID])
		#expect(staleMatches.isEmpty)

		let updatedMatches = await db.fetchArticlesMatchingAsync(searchString: "Observatory", feedIDs: [Self.feedID])
		#expect(updatedMatches.map(\.uniqueID) == ["u1"])
	}

	@Test("handles empty, punctuation-only, and FTS5 reserved-keyword queries safely")
	func handlesReservedAndPunctuationQueriesSafely() async {
		let db = TestFixtures.makeDatabase()
		let item = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: Self.feedURL,
			title: "Not Near Anything",
			contentHTML: "<p>Ordinary prose with e-mail and NOT/NEAR words.</p>"
		)
		_ = await db.updateAsync(parsedItems: [item], feedID: Self.feedID, deleteOlder: false)

		let emptyResults = await db.fetchArticlesMatchingAsync(searchString: "", feedIDs: [Self.feedID])
		#expect(emptyResults.isEmpty)

		let punctuationResults = await db.fetchArticlesMatchingAsync(searchString: "--- ::: !!!", feedIDs: [Self.feedID])
		#expect(punctuationResults.isEmpty)

		let notResults = await db.fetchArticlesMatchingAsync(searchString: "NOT", feedIDs: [Self.feedID])
		#expect(notResults.map(\.uniqueID) == ["u1"])

		let nearResults = await db.fetchArticlesMatchingAsync(searchString: "NEAR", feedIDs: [Self.feedID])
		#expect(nearResults.map(\.uniqueID) == ["u1"])

		let trailingOperatorResults = await db.fetchArticlesMatchingAsync(searchString: "Ordinary AND", feedIDs: [Self.feedID])
		#expect(trailingOperatorResults.map(\.uniqueID) == ["u1"])
	}

	@Test("configures busy_timeout to 5000ms and deletes search rows via trigger without trusted_schema")
	func configuresBusyTimeoutAndDeletesSearchRows() async throws {
		let path = makeTemporaryPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		let db = ArticlesDatabase(databaseFilePath: path, accountID: "test-account", retentionStyle: .feedBased)
		let item = TestFixtures.makeParsedItem(
			uniqueID: "del-1",
			feedURL: Self.feedURL,
			title: "Ephemeral Signal",
			contentHTML: "<p>Temporary content for deletion trigger check.</p>"
		)
		_ = await db.updateAsync(parsedItems: [item], feedID: Self.feedID, deleteOlder: false)

		let initialMatches = await db.fetchArticlesMatchingAsync(searchString: "Ephemeral", feedIDs: [Self.feedID])
		#expect(initialMatches.map(\.uniqueID) == ["del-1"])

		// Verify busy_timeout on DatabaseQueue connection.
		let observedBusyTimeout = OSAllocatedUnfairLock<Int32>(initialState: 0)
		db.queue.runInDatabaseSync { database in
			if let rs = database.executeQuery("PRAGMA busy_timeout;", withArgumentsIn: []), rs.next() {
				let timeout = rs.int(forColumnIndex: 0)
				observedBusyTimeout.withLock { $0 = timeout }
				rs.close()
			}
		}
		#expect(observedBusyTimeout.withLock { $0 } == 5000)

		// Delete article directly and verify trigger cleans up FTS5 search row without trusted_schema = ON.
		let articleID = Article.calculatedArticleID(feedID: Self.feedID, uniqueID: "del-1")
		db.queue.runInDatabaseSync { database in
			database.executeUpdate("DELETE FROM articles WHERE articleID = ?;", withArgumentsIn: [articleID])
		}

		let postDeleteMatches = await db.fetchArticlesMatchingAsync(searchString: "Ephemeral", feedIDs: [Self.feedID])
		#expect(postDeleteMatches.isEmpty)
	}

	@Test("fetches more than 1000 articles by ID using json_each without variable-limit failure")
	func fetchesOverThousandArticlesByID() async {
		let db = TestFixtures.makeDatabase()
		let items = (0..<1100).map { idx in
			TestFixtures.makeParsedItem(
				uniqueID: "bulk-\(idx)",
				feedURL: Self.feedURL,
				title: "Work \(idx)",
				contentHTML: "<p>Body \(idx)</p>"
			)
		}
		_ = await db.updateAsync(parsedItems: Set(items), feedID: Self.feedID, deleteOlder: false)

		let articleIDs = Set((0..<1100).map { Article.calculatedArticleID(feedID: Self.feedID, uniqueID: "bulk-\($0)") })
		let fetched = await db.fetchArticlesAsync(articleIDs: articleIDs)
		#expect(fetched.count == 1100)
	}

	@Test("stores compressed contentHTML as native SQLite BLOB rather than Base64 TEXT")
	func storesContentHTMLAsBlob() async throws {
		let path = makeTemporaryPath()
		defer { try? FileManager.default.removeItem(atPath: path) }

		let db = ArticlesDatabase(databaseFilePath: path, accountID: "test-account", retentionStyle: .feedBased)
		let html = "<p>" + String(repeating: "Archive prose with repeated words. ", count: 20) + "</p>"
		let item = TestFixtures.makeParsedItem(
			uniqueID: "blob-1",
			feedURL: Self.feedURL,
			title: "Blob Storage Check",
			contentHTML: html
		)
		_ = await db.updateAsync(parsedItems: [item], feedID: Self.feedID, deleteOlder: false)

		let rawDB = try #require(FMDatabase(path: path))
		try #require(rawDB.open())
		defer { rawDB.close() }

		let resultSet = try #require(rawDB.executeQuery("SELECT typeof(contentHTML) AS colType FROM articles WHERE uniqueID = ?;", withArgumentsIn: ["blob-1"]))
		defer { resultSet.close() }

		#expect(resultSet.next())
		#expect(resultSet.swiftString(forColumn: "colType") == "blob")
	}

	@Test("aborts search cleanly when SQLiteCancellationToken is pre-cancelled")
	func abortsCancelledSearchCleanly() async {
		let db = TestFixtures.makeDatabase()
		let item = TestFixtures.makeParsedItem(
			uniqueID: "cancel-1",
			feedURL: Self.feedURL,
			title: "Cancellable Work",
			contentHTML: "<p>Searchable text for cancellation check.</p>"
		)
		_ = await db.updateAsync(parsedItems: [item], feedID: Self.feedID, deleteOlder: false)

		let token = SQLiteCancellationToken()
		token.cancel()
		#expect(token.isCancelled)

		let count = db.queue.runInDatabaseSyncResult { database in
			database.withProgressCancellation(token) {
				guard let rs = database.executeQuery("SELECT rowid FROM search WHERE search MATCH ?;", withArgumentsIn: ["\"Cancellable\"*"]) else {
					return 0
				}
				var rows = 0
				while rs.next() {
					rows += 1
				}
				rs.close()
				return rows
			}
		}
		#expect(count == 0)
	}

	@Test("preserves bm25 relevance ordering and filters feedIDs/articleIDs in SQL")
	func preservesBM25OrderAndFiltersInSQL() async {
		let db = TestFixtures.makeDatabase()
		let otherFeedURL = "https://archiveofourown.org/tags/other-search-feed/works"
		let otherFeedID = otherFeedURL

		// Exact title match should rank higher in bm25 than a single buried body mention.
		let titleHit = TestFixtures.makeParsedItem(
			uniqueID: "rank-title",
			feedURL: Self.feedURL,
			title: "Nebula",
			contentHTML: "<p>A short story.</p>"
		)
		let bodyHit = TestFixtures.makeParsedItem(
			uniqueID: "rank-body",
			feedURL: Self.feedURL,
			title: "Long Chronicle",
			contentHTML: "<p>Many unrelated words fill this paragraph before nebula appears once at the end.</p>"
		)
		let otherFeedHit = TestFixtures.makeParsedItem(
			uniqueID: "rank-other",
			feedURL: otherFeedURL,
			title: "Nebula",
			contentHTML: "<p>Nebula in another feed.</p>"
		)

		_ = await db.updateAsync(parsedItems: [bodyHit, titleHit], feedID: Self.feedID, deleteOlder: false)
		_ = await db.updateAsync(parsedItems: [otherFeedHit], feedID: otherFeedID, deleteOlder: false)

		let orderedFeedMatches = await db.fetchArticlesMatchingOrderedAsync(searchString: "Nebula", feedIDs: [Self.feedID])
		#expect(orderedFeedMatches.map(\.uniqueID) == ["rank-title", "rank-body"])

		let scopedArticleIDs = Set(orderedFeedMatches.filter { $0.uniqueID == "rank-body" }.map(\.articleID))
		let scopedMatches = await db.fetchArticlesMatchingWithArticleIDsOrderedAsync(searchString: "Nebula", articleIDs: scopedArticleIDs)
		#expect(scopedMatches.map(\.uniqueID) == ["rank-body"])
	}

	@Test("returns focused FTS5 snippets with body and title fallback")
	func searchSnippetsIncludeDelimitedBodyAndTitleFallback() async throws {
		let db = TestFixtures.makeDatabase()

		let bodyItem = TestFixtures.makeParsedItem(
			uniqueID: "snippet-body",
			feedURL: Self.feedURL,
			title: "Quiet Harbor",
			contentHTML: "<p>Morning mist lingered over the docks while the lantern beside the chronometer hummed softly.</p>"
		)
		let titleOnlyItem = TestFixtures.makeParsedItem(
			uniqueID: "snippet-title",
			feedURL: Self.feedURL,
			title: "Chronometer",
			contentHTML: "<p>An unrelated passage about salt and tide.</p>"
		)

		_ = await db.updateAsync(parsedItems: [bodyItem, titleOnlyItem], feedID: Self.feedID, deleteOlder: false)

		let matches = await db.fetchArticleSearchMatchesOrderedAsync(searchString: "chronometer", feedIDs: [Self.feedID])
		#expect(matches.map(\.article.uniqueID) == ["snippet-title", "snippet-body"])

		let expectedDelimiters = "\(ArticleSearchMatch.matchStartDelimiter)chronometer\(ArticleSearchMatch.matchEndDelimiter)"
		let expectedTitleDelimiters = "\(ArticleSearchMatch.matchStartDelimiter)Chronometer\(ArticleSearchMatch.matchEndDelimiter)"

		let bodyMatch = try #require(matches.first { $0.article.uniqueID == "snippet-body" })
		let bodySnippet = try #require(bodyMatch.snippet)
		#expect(bodySnippet.localizedCaseInsensitiveContains(expectedDelimiters))
		#expect(bodySnippet.contains("lantern"))

		let titleMatch = try #require(matches.first { $0.article.uniqueID == "snippet-title" })
		let titleSnippet = try #require(titleMatch.snippet)
		#expect(titleSnippet.contains(expectedTitleDelimiters))

		let scopedMatches = await db.fetchArticleSearchMatchesWithArticleIDsOrderedAsync(
			searchString: "chronometer",
			articleIDs: [bodyMatch.article.articleID]
		)
		#expect(scopedMatches.map(\.article.uniqueID) == ["snippet-body"])
	}
}
