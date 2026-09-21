//
//  ScrollPositionFallbackTests.swift
//  ArticlesDatabaseTests
//
//  Regression coverage for a read-path gap found while investigating
//  ArticlesTable.saveScrollPosition/fetchScrollPosition's asymmetry with
//  saveReadingProgress (see the reading-progress refactor investigation
//  plan, Part 3, "step 3 result"): fetchScrollPosition read only
//  bookStateTable whenever a bookKey resolved, with no fallback to
//  statuses.scrollPosition unless the bookKey itself failed to resolve.
//  BookStateTable.scrollPosition(for:) collapsed "no row for this bookKey"
//  to 0, which is indistinguishable from a real top-of-document position --
//  so a bookKey that resolves but has no bookState row yet (reachable for
//  any position written back when statuses.scrollPosition was the only
//  store, before bookState became primary, for a book not since re-opened)
//  silently read back as 0 instead of the real value still sitting in
//  statuses.
//
//  Written against ArticlesDatabase's public API for the assertion itself,
//  matching ArticlesTableUpdateTests' convention -- but setup needs to
//  reach past that API to create exactly the "resolved bookKey, no
//  bookState row, real value in statuses" state, since every public write
//  path (saveScrollPositionAsync) now creates the bookState row as part of
//  writing at all. That state is only reachable via direct SQL against the
//  statuses table, standing in for a pre-existing row from before this
//  fix (or before bookState existed at all).
//

import Testing
import Foundation
import RSParser
import Articles
@testable import ArticlesDatabase

@Suite("Scroll position: no-bookState-row fallback")
@MainActor
struct ScrollPositionFallbackTests {

	@Test("a resolved bookKey with no bookState row falls back to statuses.scrollPosition, not 0")
	func fallsBackToStatusesWhenNoBookStateRowExists() async throws {
		let db = TestFixtures.makeDatabase()

		let item = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: "https://example.com/feed",
			ao3WorkID: "12345"
		)
		_ = await db.updateAsync(parsedItems: [item], feedID: "feed-1", deleteOlder: false)
		let articleID = Article.calculatedArticleID(feedID: "feed-1", uniqueID: "u1")

		// Simulate a position written before this article's bookState row
		// existed: write statuses.scrollPosition directly via SQL, bypassing
		// saveScrollPositionAsync entirely so no bookState row gets created.
		let legacyPosition = 842.0
		db.queue.runInDatabaseSync { database in
			database.executeUpdate(
				"UPDATE \(DatabaseTableName.statuses) SET \(DatabaseKey.scrollPosition) = ? WHERE \(DatabaseKey.articleID) = ?",
				withArgumentsIn: [legacyPosition, articleID]
			)
		}

		// Confirmed precondition: the bookKey resolves (this article has an
		// ao3WorkID-derived bookKey), but bookState has no row for it -- the
		// gap only exists in exactly this combination.
		let bookKey = try #require(await db.fetchArticlesAsync(articleIDs: [articleID]).first?.bookKey)
		#expect(!bookKey.isEmpty)

		let fetched = await db.fetchScrollPositionAsync(articleID: articleID)
		#expect(fetched == legacyPosition)
	}

	@Test("once a bookState row exists, it takes precedence over statuses.scrollPosition")
	func bookStateRowTakesPrecedenceOnceItExists() async throws {
		let db = TestFixtures.makeDatabase()

		let item = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: "https://example.com/feed",
			ao3WorkID: "12345"
		)
		_ = await db.updateAsync(parsedItems: [item], feedID: "feed-1", deleteOlder: false)
		let articleID = Article.calculatedArticleID(feedID: "feed-1", uniqueID: "u1")

		// A stale statuses value from before the real (bookState-backed) save.
		db.queue.runInDatabaseSync { database in
			database.executeUpdate(
				"UPDATE \(DatabaseTableName.statuses) SET \(DatabaseKey.scrollPosition) = ? WHERE \(DatabaseKey.articleID) = ?",
				withArgumentsIn: [111.0, articleID]
			)
		}

		await db.saveScrollPositionAsync(958.0, articleID: articleID)

		let fetched = await db.fetchScrollPositionAsync(articleID: articleID)
		#expect(fetched == 958.0)
	}

	@Test("two feeds' copies of the same book share the fallback the same way they share a real bookState row")
	func fallbackIsPerArticleUntilABookStateRowUnifiesIt() async throws {
		let db = TestFixtures.makeDatabase()

		let first = TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a", ao3WorkID: "12345")
		let second = TestFixtures.makeParsedItem(uniqueID: "u2", feedURL: "https://example.com/feed-b", ao3WorkID: "12345")
		_ = await db.updateAsync(parsedItems: [first], feedID: "feed-a", deleteOlder: false)
		_ = await db.updateAsync(parsedItems: [second], feedID: "feed-b", deleteOlder: false)

		let firstArticleID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "u1")
		let secondArticleID = Article.calculatedArticleID(feedID: "feed-b", uniqueID: "u2")

		// Only the first copy has a legacy statuses value; neither has a
		// bookState row yet.
		db.queue.runInDatabaseSync { database in
			database.executeUpdate(
				"UPDATE \(DatabaseTableName.statuses) SET \(DatabaseKey.scrollPosition) = ? WHERE \(DatabaseKey.articleID) = ?",
				withArgumentsIn: [500.0, firstArticleID]
			)
		}

		#expect(await db.fetchScrollPositionAsync(articleID: firstArticleID) == 500.0)
		// The second copy has its own (untouched, default-0) statuses row and
		// no bookState row shared with the first yet -- so it falls back to
		// its own statuses value, not the sibling's. This is expected, not
		// a second bug: the bookKey-shared behavior only takes effect once a
		// real write (saveScrollPositionAsync) creates the shared bookState
		// row, same as read/starred/loved before their first toggle.
		#expect(await db.fetchScrollPositionAsync(articleID: secondArticleID) == 0.0)

		// Once one copy is saved through the real path, the shared bookState
		// row exists and both copies read the same, shared value.
		await db.saveScrollPositionAsync(777.0, articleID: firstArticleID)
		#expect(await db.fetchScrollPositionAsync(articleID: firstArticleID) == 777.0)
		#expect(await db.fetchScrollPositionAsync(articleID: secondArticleID) == 777.0)
	}
}
