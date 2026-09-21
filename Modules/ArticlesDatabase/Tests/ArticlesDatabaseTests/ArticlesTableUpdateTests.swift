//
//  ArticlesTableUpdateTests.swift
//  ArticlesDatabaseTests
//
//  Phase 0.3 (a)-(d) of the database cleanup: regression guards for
//  behavior that currently has no automated coverage. Written against
//  ArticlesDatabase's public API only (ArticlesDatabase.swift:82-825), not
//  ArticlesTable/BookStateTable/StatusesTable directly, so these keep
//  working through the Phase 3 file-split refactor.
//

import Testing
import Foundation
import RSParser
import Articles
@testable import ArticlesDatabase

@Suite("ArticlesTable update/status behavior")
@MainActor
struct ArticlesTableUpdateTests {

	// a. changesFrom never blanks existing data on a nil refresh.
	@Test("a nil field on re-import does not overwrite the previously stored value")
	func nilRefreshDoesNotBlankExistingData() async throws {
		let db = TestFixtures.makeDatabase()

		let first = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: "https://example.com/feed",
			wordCount: 5000,
			fandoms: ["Example Fandom"]
		)
		_ = await db.updateAsync(parsedItems: [first], feedID: "feed-1", deleteOlder: false)

		let second = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: "https://example.com/feed",
			wordCount: nil,
			fandoms: nil
		)
		_ = await db.updateAsync(parsedItems: [second], feedID: "feed-1", deleteOlder: false)

		// articleID is derived from the feedID passed to updateAsync ("feed-1"
		// here), not the ParsedItem's own feedURL -- see ParsedArticle+Database
		// .swift's articleID(feedID:) doc comment.
		let articleID = Article.calculatedArticleID(feedID: "feed-1", uniqueID: "u1")
		let articles = await db.fetchArticlesAsync(articleIDs: [articleID])
		#expect(articles.count == 1)
		#expect(articles.first?.wordCount == 5000)
		#expect(articles.first?.fandoms == ["Example Fandom"])
	}

	// b. mark() propagates read/starred/loved to bookState and to sibling
	// articleIDs sharing a bookKey.
	@Test("marking one articleID read also marks a sibling sharing its bookKey")
	func markPropagatesToSiblingArticleIDs() async throws {
		let db = TestFixtures.makeDatabase()

		let first = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: "https://example.com/feed-a",
			ao3WorkID: "12345"
		)
		let second = TestFixtures.makeParsedItem(
			uniqueID: "u2",
			feedURL: "https://example.com/feed-b",
			ao3WorkID: "12345"
		)
		_ = await db.updateAsync(parsedItems: [first], feedID: "feed-a", deleteOlder: false)
		_ = await db.updateAsync(parsedItems: [second], feedID: "feed-b", deleteOlder: false)

		// articleID is derived from the feedID passed to updateAsync
		// ("feed-a"/"feed-b" here), not the ParsedItem's own feedURL -- see
		// ParsedArticle+Database.swift's articleID(feedID:) doc comment.
		let firstArticleID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "u1")
		let secondArticleID = Article.calculatedArticleID(feedID: "feed-b", uniqueID: "u2")

		let changed = await db.markAsync(articleIDs: [firstArticleID], statusKey: .read, flag: true)
		#expect(changed.contains(firstArticleID))
		#expect(changed.contains(secondArticleID))

		let siblingArticles = await db.fetchArticlesAsync(articleIDs: [secondArticleID])
		#expect(siblingArticles.first?.status.read == true)
	}

	// c. Phase 6 read-state seeding on re-import.
	@Test("a new articleID for an already-read bookKey is seeded as read on import")
	func phase6SeedsReadStateForNewArticleIDOnSameBookKey() async throws {
		let db = TestFixtures.makeDatabase()

		let original = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: "https://example.com/feed-a",
			ao3WorkID: "99999"
		)
		_ = await db.updateAsync(parsedItems: [original], feedID: "feed-a", deleteOlder: false)
		// articleID is derived from the feedID passed to updateAsync, not the
		// ParsedItem's own feedURL -- see ParsedArticle+Database.swift's
		// articleID(feedID:) doc comment.
		let originalArticleID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "u1")
		_ = await db.markAsync(articleIDs: [originalArticleID], statusKey: .read, flag: true)

		// Simulate a re-subscribe: same bookKey (same ao3WorkID), different
		// feedURL/uniqueID, so this is a brand-new articleID/row.
		let resubscribed = TestFixtures.makeParsedItem(
			uniqueID: "u2",
			feedURL: "https://example.com/feed-c",
			ao3WorkID: "99999"
		)
		_ = await db.updateAsync(parsedItems: [resubscribed], feedID: "feed-c", deleteOlder: false)
		let newArticleID = Article.calculatedArticleID(feedID: "feed-c", uniqueID: "u2")

		let articles = await db.fetchArticlesAsync(articleIDs: [newArticleID])
		#expect(articles.first?.status.read == true)
	}

	// b2. saveReadingProgress propagates to a sibling articleID sharing the
	// same bookKey, the same way mark() does for read/starred/loved -- see
	// ArticleStatus.readingProgress's doc comment. (This test previously
	// asserted the opposite, against a since-superseded claim that
	// readingProgress was "not yet" part of BookStateTable's write-through
	// -- but ArticlesTable.saveReadingProgress already calls
	// bookStateTable.setReadingProgress and unions in sibling articleIDs,
	// so that claim was stale relative to the code, not the other way
	// around: the "not yet" migration it described has already happened.
	// book-identity.md now documents the current, non-stale behavior.)
	@Test("saveReadingProgress propagates to a sibling articleID sharing the same bookKey")
	func readingProgressPropagatesToSiblingArticleIDs() async throws {
		let db = TestFixtures.makeDatabase()

		let first = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: "https://example.com/feed-a",
			ao3WorkID: "55555"
		)
		let second = TestFixtures.makeParsedItem(
			uniqueID: "u2",
			feedURL: "https://example.com/feed-b",
			ao3WorkID: "55555"
		)
		_ = await db.updateAsync(parsedItems: [first], feedID: "feed-a", deleteOlder: false)
		_ = await db.updateAsync(parsedItems: [second], feedID: "feed-b", deleteOlder: false)

		// articleID is derived from the feedID passed to updateAsync, not the
		// ParsedItem's own feedURL -- see ParsedArticle+Database.swift's
		// articleID(feedID:) doc comment.
		let firstArticleID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "u1")
		let secondArticleID = Article.calculatedArticleID(feedID: "feed-b", uniqueID: "u2")

		let changed = await db.saveReadingProgressAsync(0.42, articleID: firstArticleID)
		#expect(changed.contains(firstArticleID))
		#expect(changed.contains(secondArticleID))

		let firstArticles = await db.fetchArticlesAsync(articleIDs: [firstArticleID])
		let secondArticles = await db.fetchArticlesAsync(articleIDs: [secondArticleID])
		#expect(firstArticles.first?.status.readingProgress == 0.42)
		#expect(secondArticles.first?.status.readingProgress == 0.42)
	}

	// b2b. bookState is the durable record for readingProgress: a new
	// articleID for a bookKey that already has progress is seeded from it on
	// import, the same way read/starred/loved are, so a re-subscribed or
	// newly collection-imported copy doesn't reset to nil. See
	// book-identity.md ("readingProgress: durable record vs. live read
	// model").
	@Test("a new articleID for a bookKey with saved reading progress is seeded with that progress on import")
	func readingProgressSeedsNewArticleIDOnSameBookKey() async throws {
		let db = TestFixtures.makeDatabase()

		let original = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: "https://example.com/feed-a",
			ao3WorkID: "77777"
		)
		_ = await db.updateAsync(parsedItems: [original], feedID: "feed-a", deleteOlder: false)
		let originalArticleID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "u1")
		_ = await db.saveReadingProgressAsync(0.6, articleID: originalArticleID)

		// Same bookKey (same ao3WorkID), different feed/uniqueID: a
		// brand-new articleID with a brand-new statuses row.
		let resubscribed = TestFixtures.makeParsedItem(
			uniqueID: "u2",
			feedURL: "https://example.com/feed-c",
			ao3WorkID: "77777"
		)
		_ = await db.updateAsync(parsedItems: [resubscribed], feedID: "feed-c", deleteOlder: false)
		let newArticleID = Article.calculatedArticleID(feedID: "feed-c", uniqueID: "u2")

		let articles = await db.fetchArticlesAsync(articleIDs: [newArticleID])
		#expect(articles.first?.status.readingProgress == 0.6)
	}

	// b3. Regression guard for the timeline progress-bar staleness bug:
	// emptyCaches(clearStatusesCache: false) -- the ordinary-backgrounding
	// path (AccountManager.handleAppDidGoToBackground) -- must leave an
	// already-fetched Article's cached ArticleStatus object in place, so a
	// later saveReadingProgress still mutates that same instance and
	// anyone already holding a reference to it (a collection view's
	// diffable-data-source snapshot, in the app) sees the update live,
	// with no re-fetch. emptyCaches(clearStatusesCache: true) -- genuine
	// memory pressure (AccountManager.handleLowMemory) -- is the contrasting
	// case: it's expected, not a bug, for an already-held Article's status
	// to stop updating live after that clear, since the cached object it
	// pointed to is gone; a caller needs a fresh fetch to see further
	// changes. Both halves are asserted here so a future change can't
	// silently flip one behavior into the other.
	@Test("emptyCaches(clearStatusesCache: false) preserves live in-place reading-progress updates; true does not")
	func emptyCachesClearStatusesCacheControlsLiveUpdatePersistence() async throws {
		let backgroundedDB = TestFixtures.makeDatabase()
		let lowMemoryDB = TestFixtures.makeDatabase()

		let backgroundedItem = TestFixtures.makeParsedItem(uniqueID: "u-bg", feedURL: "https://example.com/feed-bg")
		let lowMemoryItem = TestFixtures.makeParsedItem(uniqueID: "u-lm", feedURL: "https://example.com/feed-lm")
		_ = await backgroundedDB.updateAsync(parsedItems: [backgroundedItem], feedID: "feed-bg", deleteOlder: false)
		_ = await lowMemoryDB.updateAsync(parsedItems: [lowMemoryItem], feedID: "feed-lm", deleteOlder: false)
		let backgroundedArticleID = Article.calculatedArticleID(feedID: "feed-bg", uniqueID: "u-bg")
		let lowMemoryArticleID = Article.calculatedArticleID(feedID: "feed-lm", uniqueID: "u-lm")

		// Article objects held onto across the cache clear, the same way the
		// timeline's collection view snapshot holds onto Article objects it
		// fetched before an app backgrounding/memory-pressure event.
		let heldBackgroundedArticle = await backgroundedDB.fetchArticlesAsync(articleIDs: [backgroundedArticleID]).first
		let heldLowMemoryArticle = await lowMemoryDB.fetchArticlesAsync(articleIDs: [lowMemoryArticleID]).first

		_ = await backgroundedDB.saveReadingProgressAsync(0.3, articleID: backgroundedArticleID)
		_ = await lowMemoryDB.saveReadingProgressAsync(0.3, articleID: lowMemoryArticleID)
		#expect(heldBackgroundedArticle?.status.readingProgress == 0.3)
		#expect(heldLowMemoryArticle?.status.readingProgress == 0.3)

		backgroundedDB.emptyCaches(clearStatusesCache: false)
		lowMemoryDB.emptyCaches(clearStatusesCache: true)

		_ = await backgroundedDB.saveReadingProgressAsync(0.75, articleID: backgroundedArticleID)
		_ = await lowMemoryDB.saveReadingProgressAsync(0.75, articleID: lowMemoryArticleID)

		// The disk-persisted value is correct either way -- both DB writes
		// always succeed regardless of cache state.
		let freshBackgroundedArticles = await backgroundedDB.fetchArticlesAsync(articleIDs: [backgroundedArticleID])
		let freshLowMemoryArticles = await lowMemoryDB.fetchArticlesAsync(articleIDs: [lowMemoryArticleID])
		#expect(freshBackgroundedArticles.first?.status.readingProgress == 0.75)
		#expect(freshLowMemoryArticles.first?.status.readingProgress == 0.75)

		// The already-held Article object is where the two cases diverge.
		#expect(heldBackgroundedArticle?.status.readingProgress == 0.75, "clearStatusesCache: false should keep mutating the already-held object in place")
		#expect(heldLowMemoryArticle?.status.readingProgress == 0.3, "clearStatusesCache: true is expected to orphan the already-held object -- this is the documented, deliberate trade-off for genuine memory pressure")
	}

	// e. Regression guard for the AO3 "timeline date moves backward after
	// content fetch" bug, at the storage layer. A search-results fetch
	// (AO3SearchResultsExtractor) only ever supplies dateModified ("last
	// updated" -- AO3 doesn't expose original publish date on that page),
	// leaving datePublished nil; a later content fetch
	// (AO3ChapterHTMLExtractor) supplies the real datePublished, which for
	// any work updated after its original posting is *earlier* than
	// dateModified. Article.init(parsedItem:) previously coerced a nil
	// datePublished into a copy of dateModified before storage, which made
	// the genuinely later real datePublished look like a legitimate change
	// and overwrite that copy. This asserts both dates are now stored
	// exactly as parsed, with no coercion -- see database.md.
	// Article.logicalDatePublished's own later-of-the-two display/sort
	// logic is covered separately in ArticleLogicalDatePublishedTests
	// (Tests/NetNewsWire-iOSTests), since that property lives in Shared/
	// (the app target), not this package.
	@Test("datePublished and dateModified are each stored exactly as parsed, with no cross-field coercion, across a search-results fetch followed by a content fetch")
	func datesAreStoredWithoutCoercionAcrossSearchResultsThenContentFetch() async throws {
		let db = TestFixtures.makeDatabase()

		let lastUpdated = Date(timeIntervalSince1970: 1_700_000_000) // the "later" date
		let realPublished = Date(timeIntervalSince1970: 1_600_000_000) // earlier than lastUpdated

		// Step 1: search-results fetch. Only dateModified is known.
		let searchResultsItem = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: "https://example.com/feed",
			ao3WorkID: "77777",
			dateModified: lastUpdated
		)
		_ = await db.updateAsync(parsedItems: [searchResultsItem], feedID: "feed-1", deleteOlder: false)

		let articleID = Article.calculatedArticleID(feedID: "feed-1", uniqueID: "u1")
		let afterSearchResults = await db.fetchArticlesAsync(articleIDs: [articleID])
		// datePublished must stay nil -- not coerced into a copy of dateModified.
		#expect(afterSearchResults.first?.datePublished == nil)
		#expect(afterSearchResults.first?.dateModified == lastUpdated)

		// Step 2: content fetch. Now the real (earlier) datePublished is known,
		// alongside the same dateModified.
		let contentFetchItem = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: "https://example.com/feed",
			ao3WorkID: "77777",
			datePublished: realPublished,
			dateModified: lastUpdated
		)
		_ = await db.updateAsync(parsedItems: [contentFetchItem], feedID: "feed-1", deleteOlder: false)

		let afterContentFetch = await db.fetchArticlesAsync(articleIDs: [articleID])
		#expect(afterContentFetch.first?.datePublished == realPublished)
		#expect(afterContentFetch.first?.dateModified == lastUpdated)
	}

	// f. Regression guard for the same fix at the SQL ordering layer
	// (ArticlesTable.logicalDatePublishedSQL): a limit-bounded fetch must
	// order by the later of datePublished/dateModified, matching
	// Article.logicalDatePublished, or a limited query could silently drop
	// an article whose only known date is a later dateModified in favor of
	// one with an earlier datePublished.
	@Test("a limit-bounded unread fetch orders by the later of datePublished/dateModified")
	func limitedFetchOrdersByLaterDate() async throws {
		let db = TestFixtures.makeDatabase()

		// "older": only datePublished, older than "newer"'s dateModified.
		let older = TestFixtures.makeParsedItem(
			uniqueID: "u-older",
			feedURL: "https://example.com/feed",
			datePublished: Date(timeIntervalSince1970: 1_000_000_000)
		)
		// "newer": only dateModified is known (the AO3 search-results
		// shape), and it's later than "older"'s datePublished.
		let newer = TestFixtures.makeParsedItem(
			uniqueID: "u-newer",
			feedURL: "https://example.com/feed",
			dateModified: Date(timeIntervalSince1970: 2_000_000_000)
		)
		_ = await db.updateAsync(parsedItems: [older, newer], feedID: "feed-1", deleteOlder: false)

		let olderArticleID = Article.calculatedArticleID(feedID: "feed-1", uniqueID: "u-older")
		let newerArticleID = Article.calculatedArticleID(feedID: "feed-1", uniqueID: "u-newer")

		// Only room for one -- if the SQL ordering wrongly preferred
		// datePublished-over-dateModified, "older" (which has a
		// datePublished at all) would win the limit=1 slot instead of
		// "newer" (whose only date is later).
		let limited = await db.fetchUnreadArticlesAsync(feedIDs: ["feed-1"], limit: 1)
		#expect(limited.count == 1)
		#expect(limited.first?.articleID == newerArticleID)
		#expect(limited.first?.articleID != olderArticleID)
	}
}
