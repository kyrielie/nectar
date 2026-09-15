//
//  ArticleSorterCountTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for ArticleSorter.sortedByCount, backing the .hitCount/
//  .kudosCount/.commentCount/.bookmarkCount sort fields. Mirrors the
//  null-handling ArticleSorter already documents for sortedByWordCount:
//  missing counts sort to the end regardless of direction, and ties
//  break on articleID for determinism.
//

import Testing
import Foundation
import Articles
@testable import Nectar

@MainActor @Suite struct ArticleSorterCountTests {

	private static func makeArticle(articleID: String, hitCount: Int?) -> Article {
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
			summary: nil,
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			hitCount: hitCount,
			status: status
		)
	}

	@Test("all-nil counts fall back to articleID ordering, unaffected by direction")
	func allNilFallsBackToArticleID() {
		let a = Self.makeArticle(articleID: "a", hitCount: nil)
		let b = Self.makeArticle(articleID: "b", hitCount: nil)
		let descending = ArticleSorter.sorted(articles: [b, a], by: .hitCount, sortDirection: .orderedDescending)
		let ascending = ArticleSorter.sorted(articles: [b, a], by: .hitCount, sortDirection: .orderedAscending)
		#expect(descending.map(\.articleID) == ["a", "b"])
		#expect(ascending.map(\.articleID) == ["a", "b"])
	}

	@Test("articles with a nil count always sort after articles with a value, regardless of direction")
	func nilSortsToEndRegardlessOfDirection() {
		let withCount = Self.makeArticle(articleID: "has-count", hitCount: 5)
		let withoutCount = Self.makeArticle(articleID: "no-count", hitCount: nil)

		let descending = ArticleSorter.sorted(articles: [withoutCount, withCount], by: .hitCount, sortDirection: .orderedDescending)
		#expect(descending.map(\.articleID) == ["has-count", "no-count"])

		let ascending = ArticleSorter.sorted(articles: [withoutCount, withCount], by: .hitCount, sortDirection: .orderedAscending)
		#expect(ascending.map(\.articleID) == ["has-count", "no-count"])
	}

	@Test("equal counts break ties on articleID")
	func tiesBreakOnArticleID() {
		let first = Self.makeArticle(articleID: "a", hitCount: 10)
		let second = Self.makeArticle(articleID: "b", hitCount: 10)
		let sorted = ArticleSorter.sorted(articles: [second, first], by: .hitCount, sortDirection: .orderedDescending)
		#expect(sorted.map(\.articleID) == ["a", "b"])
	}

	@Test("descending sorts highest count first; ascending sorts lowest count first")
	func directionOrdersByCount() {
		let low = Self.makeArticle(articleID: "low", hitCount: 1)
		let high = Self.makeArticle(articleID: "high", hitCount: 100)

		let descending = ArticleSorter.sorted(articles: [low, high], by: .hitCount, sortDirection: .orderedDescending)
		#expect(descending.map(\.articleID) == ["high", "low"])

		let ascending = ArticleSorter.sorted(articles: [low, high], by: .hitCount, sortDirection: .orderedAscending)
		#expect(ascending.map(\.articleID) == ["low", "high"])
	}
}
