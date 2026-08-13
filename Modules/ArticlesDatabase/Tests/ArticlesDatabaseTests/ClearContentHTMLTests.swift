//
//  ClearContentHTMLTests.swift
//  ArticlesDatabaseTests
//
//  Part 1.1: direct coverage of
//  ArticlesTable.clearContentHTML (ArticlesTable.swift:665), the
//  delete-vs-clear archival fix.
//  This is the newest correctness-sensitive change in the codebase and had
//  zero coverage before this file -- a regression here silently
//  reintroduces the original bug (account.delete's full row/metadata loss
//  on what's supposed to be a content-only clear), and nothing else in the
//  suite would catch it.
//

import Testing
import Foundation
import RSParser
import Articles
@testable import ArticlesDatabase

@Suite("ArticlesTable.clearContentHTML")
@MainActor
struct ClearContentHTMLTests {

	// 1. Clears exactly the five documented columns, nothing else.
	@Test("clearing content leaves title/wordCount/fandoms/bookKey/status untouched")
	func clearsOnlyContentColumns() async throws {
		let db = TestFixtures.makeDatabase()

		let item = TestFixtures.makeParsedItem(
			uniqueID: "u1",
			feedURL: "https://example.com/feed",
			title: "Original Title",
			contentHTML: "<p>original content</p>",
			wordCount: 5000,
			fandoms: ["Example Fandom"],
			ao3WorkID: "12345"
		)
		_ = await db.updateAsync(parsedItems: [item], feedID: "feed-1", deleteOlder: false)
		let articleID = Article.calculatedArticleID(feedID: "feed-1", uniqueID: "u1")

		// Mark read/starred so status has non-default state to check survives.
		_ = await db.markAsync(articleIDs: [articleID], statusKey: .read, flag: true)
		_ = await db.markAsync(articleIDs: [articleID], statusKey: .starred, flag: true)

		await db.clearContentHTMLAsync(articleIDs: [articleID])

		let articles = await db.fetchArticlesAsync(articleIDs: [articleID])
		#expect(articles.count == 1)
		let article = try #require(articles.first)

		#expect(article.contentHTML == nil)
		#expect(article.contentText == nil)

		// Everything else must survive the clear untouched.
		#expect(article.title == "Original Title")
		#expect(article.wordCount == 5000)
		#expect(article.fandoms == ["Example Fandom"])
		#expect(article.bookKey == "ao3-work:12345")
		#expect(article.status.read == true)
		#expect(article.status.starred == true)
	}

	// 2. D5: pendingUpdateContentHTML/pendingUpdateDetectedAt nulled together.
	@Test("clearing content nulls a staged pending content update")
	func clearsPendingContentUpdate() async throws {
		let db = TestFixtures.makeDatabase()

		let item = TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed")
		_ = await db.updateAsync(parsedItems: [item], feedID: "feed-1", deleteOlder: false)
		let articleID = Article.calculatedArticleID(feedID: "feed-1", uniqueID: "u1")

		await db.setPendingContentUpdateAsync("<p>staged update</p>", detectedAt: Date(), articleID: articleID)

		var articles = await db.fetchArticlesAsync(articleIDs: [articleID])
		#expect(articles.first?.pendingUpdateContentHTML != nil)
		#expect(articles.first?.pendingUpdateDetectedAt != nil)

		await db.clearContentHTMLAsync(articleIDs: [articleID])

		articles = await db.fetchArticlesAsync(articleIDs: [articleID])
		#expect(articles.first?.pendingUpdateContentHTML == nil)
		#expect(articles.first?.pendingUpdateDetectedAt == nil)
	}

	// 3. D5: wordCountRegressionFlaggedAt nulled -- guards AO3ChapterFetcher
	// .isStale (AO3ChapterFetcher.swift:233-244) against a cleared row being
	// permanently locked out of ever refetching.
	@Test("clearing content nulls a flagged word-count regression")
	func clearsRegressionFlag() async throws {
		let db = TestFixtures.makeDatabase()

		let first = TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed", wordCount: 5000)
		_ = await db.updateAsync(parsedItems: [first], feedID: "feed-1", deleteOlder: false)
		let articleID = Article.calculatedArticleID(feedID: "feed-1", uniqueID: "u1")

		// A large enough drop to trip AO3RegressionThreshold.isRegression via
		// Article+Database.changesFrom (see that file's wordCount handling).
		let second = TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed", wordCount: 100)
		_ = await db.updateAsync(parsedItems: [second], feedID: "feed-1", deleteOlder: false)

		var articles = await db.fetchArticlesAsync(articleIDs: [articleID])
		#expect(articles.first?.wordCountRegressionFlaggedAt != nil)

		await db.clearContentHTMLAsync(articleIDs: [articleID])

		articles = await db.fetchArticlesAsync(articleIDs: [articleID])
		#expect(articles.first?.wordCountRegressionFlaggedAt == nil)
	}

	// 4. Cache invalidation -- clearContentHTML calls
	// removeArticleIDsFromCache (ArticlesTable.swift:674) after the write;
	// this is what confirms that call is actually doing its job, given this
	// session's proven stale-articlesCache bug in ArticlesTable.update.
	@Test("a fetch after clearing reflects the clear, not a stale cached Article")
	func cacheReflectsClear() async throws {
		let db = TestFixtures.makeDatabase()

		let item = TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed", contentHTML: "<p>content</p>")
		_ = await db.updateAsync(parsedItems: [item], feedID: "feed-1", deleteOlder: false)
		let articleID = Article.calculatedArticleID(feedID: "feed-1", uniqueID: "u1")

		// Populate the cache with the pre-clear Article.
		let beforeClear = await db.fetchArticlesAsync(articleIDs: [articleID])
		#expect(beforeClear.first?.contentHTML != nil)

		await db.clearContentHTMLAsync(articleIDs: [articleID])

		let afterClear = await db.fetchArticlesAsync(articleIDs: [articleID])
		#expect(afterClear.first?.contentHTML == nil)
	}

	// 5. Multiple articleIDs in one call.
	@Test("clearing multiple articleIDs in one call clears and evicts all of them")
	func clearsMultipleArticleIDs() async throws {
		let db = TestFixtures.makeDatabase()

		let first = TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a", contentHTML: "<p>a</p>")
		let second = TestFixtures.makeParsedItem(uniqueID: "u2", feedURL: "https://example.com/feed-b", contentHTML: "<p>b</p>")
		_ = await db.updateAsync(parsedItems: [first], feedID: "feed-a", deleteOlder: false)
		_ = await db.updateAsync(parsedItems: [second], feedID: "feed-b", deleteOlder: false)

		let firstID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "u1")
		let secondID = Article.calculatedArticleID(feedID: "feed-b", uniqueID: "u2")

		await db.clearContentHTMLAsync(articleIDs: [firstID, secondID])

		let articles = await db.fetchArticlesAsync(articleIDs: [firstID, secondID])
		#expect(articles.count == 2)
		#expect(articles.allSatisfy { $0.contentHTML == nil })
	}

	// 6. No-op on an unknown articleID -- shouldn't throw or corrupt state.
	@Test("clearing an unknown articleID is a harmless no-op")
	func unknownArticleIDIsNoOp() async throws {
		let db = TestFixtures.makeDatabase()

		let item = TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed", contentHTML: "<p>content</p>")
		_ = await db.updateAsync(parsedItems: [item], feedID: "feed-1", deleteOlder: false)
		let articleID = Article.calculatedArticleID(feedID: "feed-1", uniqueID: "u1")

		await db.clearContentHTMLAsync(articleIDs: ["never-seen"])

		// The real article must be completely unaffected.
		let articles = await db.fetchArticlesAsync(articleIDs: [articleID])
		#expect(articles.first?.contentHTML == "<p>content</p>")
	}
}
