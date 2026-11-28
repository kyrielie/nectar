//
//  AO3SeriesTimelineViewModelTests.swift
//  NetNewsWire-iOSTests
//
//  Verifies AO3SeriesFeedDelegate ordering (ascending Part N) and
//  bookKey deduplication (preferring downloaded content and originating feed).
//

import Foundation
import Testing
import Articles
@testable import Nectar

@MainActor @Suite struct AO3SeriesFeedDelegateTests {

	private static func makeArticle(
		articleID: String,
		feedID: String = "feed-1",
		workID: String,
		title: String,
		seriesID: String,
		part: Int,
		contentHTML: String? = nil
	) -> Article {
		let status = ArticleStatus(articleID: articleID, read: false, starred: false, dateArrived: Date())
		return Article(
			accountID: "acct",
			articleID: articleID,
			feedID: feedID,
			uniqueID: workID,
			title: title,
			contentHTML: contentHTML,
			contentText: nil,
			markdown: nil,
			url: "https://archiveofourown.org/works/\(workID)",
			externalURL: nil,
			summary: nil,
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			series: [ArticleSeriesEntry(name: "Test Series", index: part, ao3ID: seriesID)],
			bookKey: "ao3-work:\(workID)",
			status: status
		)
	}

	@Test func ordersByPartIndexAndDeduplicatesBookKeyPreferringContent() {
		let stubPart2 = Self.makeArticle(articleID: "a2-stub", feedID: "feed-1", workID: "102", title: "Part Two", seriesID: "55", part: 2, contentHTML: nil)
		let fullPart2 = Self.makeArticle(articleID: "a2-full", feedID: "feed-2", workID: "102", title: "Part Two", seriesID: "55", part: 2, contentHTML: "<p>Full</p>")
		let part1 = Self.makeArticle(articleID: "a1", feedID: "feed-1", workID: "101", title: "Part One", seriesID: "55", part: 1, contentHTML: nil)

		let ordered = AO3SeriesFeedDelegate.orderedArticles(
			from: [stubPart2, fullPart2, part1],
			ao3SeriesID: "55",
			preferredFeedID: "feed-1"
		)

		#expect(ordered.map(\.articleID) == ["a1", "a2-full"])
	}
}
