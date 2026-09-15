//
//  ArticleSorterDateBookmarkedTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for ArticleSorter.sortedByDateBookmarked, backing the
//  .dateBookmarked sort field. Same null-handling shape as
//  ArticleSorterCountTests' sortedByCount coverage, just on Date instead
//  of Int: missing dateBookmarked (every non-bookmarks-sourced article)
//  sorts to the end regardless of direction, and ties break on articleID
//  for determinism.
//

import Testing
import Foundation
import Articles
@testable import Nectar

@MainActor @Suite struct ArticleSorterDateBookmarkedTests {

	private static func makeArticle(articleID: String, dateBookmarked: Date?) -> Article {
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
			dateBookmarked: dateBookmarked,
			status: status
		)
	}

	@Test("all-nil dateBookmarked falls back to articleID ordering, unaffected by direction")
	func allNilFallsBackToArticleID() {
		let a = Self.makeArticle(articleID: "a", dateBookmarked: nil)
		let b = Self.makeArticle(articleID: "b", dateBookmarked: nil)
		let descending = ArticleSorter.sorted(articles: [b, a], by: .dateBookmarked, sortDirection: .orderedDescending)
		let ascending = ArticleSorter.sorted(articles: [b, a], by: .dateBookmarked, sortDirection: .orderedAscending)
		#expect(descending.map(\.articleID) == ["a", "b"])
		#expect(ascending.map(\.articleID) == ["a", "b"])
	}

	@Test("articles with a nil dateBookmarked always sort after articles with a value, regardless of direction")
	func nilSortsToEndRegardlessOfDirection() {
		let withDate = Self.makeArticle(articleID: "has-date", dateBookmarked: Date())
		let withoutDate = Self.makeArticle(articleID: "no-date", dateBookmarked: nil)

		let descending = ArticleSorter.sorted(articles: [withoutDate, withDate], by: .dateBookmarked, sortDirection: .orderedDescending)
		#expect(descending.map(\.articleID) == ["has-date", "no-date"])

		let ascending = ArticleSorter.sorted(articles: [withoutDate, withDate], by: .dateBookmarked, sortDirection: .orderedAscending)
		#expect(ascending.map(\.articleID) == ["has-date", "no-date"])
	}

	@Test("equal dateBookmarked values break ties on articleID")
	func tiesBreakOnArticleID() {
		let sharedDate = Date()
		let first = Self.makeArticle(articleID: "a", dateBookmarked: sharedDate)
		let second = Self.makeArticle(articleID: "b", dateBookmarked: sharedDate)
		let sorted = ArticleSorter.sorted(articles: [second, first], by: .dateBookmarked, sortDirection: .orderedDescending)
		#expect(sorted.map(\.articleID) == ["a", "b"])
	}

	@Test("descending sorts most recently bookmarked first; ascending sorts earliest bookmarked first")
	func directionOrdersByDate() {
		let earlier = Self.makeArticle(articleID: "earlier", dateBookmarked: Date(timeIntervalSince1970: 1_000))
		let later = Self.makeArticle(articleID: "later", dateBookmarked: Date(timeIntervalSince1970: 100_000))

		let descending = ArticleSorter.sorted(articles: [earlier, later], by: .dateBookmarked, sortDirection: .orderedDescending)
		#expect(descending.map(\.articleID) == ["later", "earlier"])

		let ascending = ArticleSorter.sorted(articles: [earlier, later], by: .dateBookmarked, sortDirection: .orderedAscending)
		#expect(ascending.map(\.articleID) == ["earlier", "later"])
	}
}
