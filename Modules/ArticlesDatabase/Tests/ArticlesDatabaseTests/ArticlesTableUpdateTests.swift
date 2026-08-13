//
//  ArticlesTableUpdateTests.swift
//  ArticlesDatabaseTests
//
//  Phase 0.3 (a)-(d) of the database cleanup plan: regression guards for
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
}
