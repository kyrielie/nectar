//
//  ArticleStringFormatterTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for ArticleStringFormatter.truncatedSummary's caching.
//  summaryCache used to be keyed by (articleID, accountID) identity, so
//  a placeholder-empty summary got cached forever and a later legitimate
//  fetch never displaced it until a backgrounding/low-memory event
//  cleared the whole cache. Rekeying by content (mirroring titleCache's
//  TitleCacheKey) fixes this.
//

import Testing
import Foundation
import Articles
@testable import Nectar

@MainActor @Suite struct ArticleStringFormatterTests {

	private static func makeArticle(articleID: String, summary: String?) -> Article {
		let status = ArticleStatus(articleID: articleID, read: false, starred: false, dateArrived: Date())
		return Article(
			accountID: "test-account-id",
			articleID: articleID,
			feedID: "test-feed-id",
			uniqueID: "test-unique-id-\(articleID)",
			title: "Test Title",
			contentHTML: nil,
			contentText: nil,
			markdown: nil,
			url: "https://archiveofourown.org/works/999",
			externalURL: nil,
			summary: summary,
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			status: status
		)
	}

	// A fresh ArticleStringFormatter instance per test, not .shared, so
	// each test's cache starts empty regardless of test execution order.
	@Test("truncatedSummary reflects a changed summary for the same article, not a stale cached value")
	func truncatedSummaryUpdatesWhenArticleSummaryChanges() {
		let formatter = ArticleStringFormatter()

		let placeholder = Self.makeArticle(articleID: "1", summary: "")
		#expect(formatter.truncatedSummary(placeholder) == "")

		let updated = Self.makeArticle(articleID: "1", summary: "Real summary text now available.")
		#expect(formatter.truncatedSummary(updated) == "Real summary text now available.")
	}

	@Test("truncatedSummary caches by content, so two different articles with identical summary text share a result")
	func truncatedSummaryCachesIdenticalContentAcrossArticles() {
		let formatter = ArticleStringFormatter()

		let articleA = Self.makeArticle(articleID: "a", summary: "Shared text")
		let articleB = Self.makeArticle(articleID: "b", summary: "Shared text")
		#expect(formatter.truncatedSummary(articleA) == formatter.truncatedSummary(articleB))
	}
}
