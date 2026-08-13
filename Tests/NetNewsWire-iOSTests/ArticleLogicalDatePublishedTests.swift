//
//  ArticleLogicalDatePublishedTests.swift
//  NetNewsWire-iOSTests
//
//  Regression coverage for the "timeline date moves backward after content
//  fetch" fix: Article.logicalDatePublished (Shared/Extensions/
//  ArticleUtilities.swift) must report the later of datePublished/
//  dateModified, not prefer datePublished unconditionally -- see
//  database.md and app-chrome-palette.md's sibling docs for why this
//  matters specifically for AO3 items, where a search-results fetch only
//  ever supplies dateModified ("last updated") and a later content fetch
//  supplies the real, often earlier, datePublished.
//

import Testing
import Foundation
import Articles
@testable import Nectar

@MainActor @Suite struct ArticleLogicalDatePublishedTests {

	private static func makeArticle(datePublished: Date?, dateModified: Date?) -> Article {
		let articleID = "test-article-id-\(UUID().uuidString)"
		let dateArrived = Date(timeIntervalSince1970: 1_500_000_000)
		let status = ArticleStatus(articleID: articleID, read: false, starred: false, dateArrived: dateArrived)
		return Article(
			accountID: "test-account-id",
			articleID: articleID,
			feedID: "test-feed-id",
			uniqueID: "test-unique-id",
			title: "Test Title",
			contentHTML: nil,
			contentText: nil,
			markdown: nil,
			url: nil,
			externalURL: nil,
			summary: nil,
			imageURL: nil,
			datePublished: datePublished,
			dateModified: dateModified,
			authors: nil,
			status: status
		)
	}

	@Test("when dateModified is later than datePublished, logicalDatePublished returns dateModified")
	func returnsLaterDateWhenModifiedIsNewer() {
		let published = Date(timeIntervalSince1970: 1_600_000_000)
		let modified = Date(timeIntervalSince1970: 1_700_000_000)
		let article = Self.makeArticle(datePublished: published, dateModified: modified)
		#expect(article.logicalDatePublished == modified)
	}

	@Test("when datePublished is later than dateModified, logicalDatePublished returns datePublished")
	func returnsLaterDateWhenPublishedIsNewer() {
		let published = Date(timeIntervalSince1970: 1_700_000_000)
		let modified = Date(timeIntervalSince1970: 1_600_000_000)
		let article = Self.makeArticle(datePublished: published, dateModified: modified)
		#expect(article.logicalDatePublished == published)
	}

	@Test("when only datePublished is set, logicalDatePublished returns it")
	func fallsBackToPublishedOnly() {
		let published = Date(timeIntervalSince1970: 1_600_000_000)
		let article = Self.makeArticle(datePublished: published, dateModified: nil)
		#expect(article.logicalDatePublished == published)
	}

	@Test("when only dateModified is set, logicalDatePublished returns it")
	func fallsBackToModifiedOnly() {
		let modified = Date(timeIntervalSince1970: 1_600_000_000)
		let article = Self.makeArticle(datePublished: nil, dateModified: modified)
		#expect(article.logicalDatePublished == modified)
	}

	@Test("when neither date is set, logicalDatePublished falls back to status.dateArrived")
	func fallsBackToDateArrivedWhenNeitherSet() {
		let article = Self.makeArticle(datePublished: nil, dateModified: nil)
		#expect(article.logicalDatePublished == article.status.dateArrived)
	}
}
