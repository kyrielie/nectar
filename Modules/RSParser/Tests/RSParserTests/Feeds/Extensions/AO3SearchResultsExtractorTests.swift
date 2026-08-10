//
//  AO3SearchResultsExtractorTests.swift
//  RSParser
//
//  Created for the Nectar fork.
//

import Foundation
import Testing
@testable import RSParser

@Suite struct AO3SearchResultsExtractorTests {

	private let feedURL = "https://archiveofourown.org/works?work_search%5Bquery%5D=test"

	@Test func noResultsOnPageWithNoWorkRows() {
		let outcome = AO3SearchResultsExtractor.extract(fromResultsPageHTML: "<html><body><p>No results found.</p></body></html>", feedURL: feedURL)
		guard case .noResults = outcome else {
			Issue.record("Expected .noResults, got \(outcome)")
			return
		}
	}

	@Test func registrationRequiredDetected() {
		let html = "<html><body><div id=\"signin\"><h3 class=\"heading\">Sorry!</h3><p>This work is only available to registered users of the Archive.</p></div></body></html>"
		let outcome = AO3SearchResultsExtractor.extract(fromResultsPageHTML: html, feedURL: feedURL)
		guard case .registrationRequired = outcome else {
			Issue.record("Expected .registrationRequired, got \(outcome)")
			return
		}
	}

	@Test func extractsBothRowsInDocumentOrder() throws {
		let html = htmlFixtureString("ao3-search-results.html")
		let outcome = AO3SearchResultsExtractor.extract(fromResultsPageHTML: html, feedURL: feedURL)
		guard case .success(let items, _) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}
		#expect(items.count == 2)
		#expect(items.map(\.ao3WorkID) == ["11111111", "22222222"])
	}

	// MARK: - Row 1: single author, single series-free work

	@Test func singleAuthorRowFields() throws {
		let item = try extractedItem(workID: "11111111")
		#expect(item.title == "A Single Work")
		#expect(item.url == "https://archiveofourown.org/works/11111111")
		#expect(item.authors?.count == 1)
		#expect(item.authors?.first?.name == "onlyauthor")
		#expect(item.authors?.first?.url == "https://archiveofourown.org/users/onlyauthor/pseuds/onlyauthor")
		#expect(item.fandoms == ["Some Fandom"])
		#expect(item.warnings == ["No Archive Warnings Apply"])
		#expect(item.tags == Set(["Fluff", "One Shot"]))
		#expect(item.wordCount == 1234)
		#expect(item.chapterCurrent == 1)
		#expect(item.chapterTotal == 1)
		#expect(item.isComplete == true)
		#expect(item.series == nil)
		#expect(item.summary?.contains("Two paragraphs of summary.") == true)
		#expect(item.language == "English")
		#expect(item.kudosCount == 10)
		#expect(item.hitCount == 200)
		// Row 1's stats block has no Comments/Bookmarks rows -- confirms
		// their absence stays nil rather than crashing or picking up
		// row 2's values.
		#expect(item.commentCount == nil)
		#expect(item.bookmarkCount == nil)
	}

	@Test func datetimeParsedAsUTCDayGranularity() throws {
		// "01 Jan 2026" -- fixed to UTC by the extractor's own formatter
		// (see AO3SearchResultsExtractor.datetimeFormatter's doc comment
		// for why), so this is deterministic across machines/timezones.
		let item = try extractedItem(workID: "11111111")
		var expected = DateComponents()
		expected.year = 2026
		expected.month = 1
		expected.day = 1
		var utcCalendar = Calendar(identifier: .gregorian)
		utcCalendar.timeZone = try #require(TimeZone(identifier: "UTC"))
		#expect(item.dateModified == utcCalendar.date(from: expected))
		// datePublished is never set from a search-results row -- AO3
		// doesn't expose original publish date on this page at all, only
		// "last updated" -- so Article.logicalDatePublished's fallback
		// chain reaches dateModified for these items.
		#expect(item.datePublished == nil)
	}

	// MARK: - Row 2: co-authored, multi-series, WIP with unknown chapter total

	@Test func coAuthoredRowHasBothAuthors() throws {
		let item = try extractedItem(workID: "22222222")
		let names = Set(item.authors?.compactMap(\.name) ?? [])
		#expect(names == ["firstauthor", "secondauthor"])
	}

	@Test func multiSeriesRowHasBothMemberships() throws {
		let item = try extractedItem(workID: "22222222")
		let series = try #require(item.series)
		#expect(series.count == 2)
		#expect(series.contains { $0.name == "The First Series" && $0.index == 2 && $0.ao3ID == "333333" })
		#expect(series.contains { $0.name == "The Second Series" && $0.index == 7 && $0.ao3ID == "444444" })
	}

	@Test func unknownChapterTotalLeavesTotalNilAndNotComplete() throws {
		let item = try extractedItem(workID: "22222222")
		#expect(item.chapterCurrent == 3)
		#expect(item.chapterTotal == nil)
		#expect(item.isComplete == false)
	}

	@Test func multipleWarningTagsAndCategorySpansCollected() throws {
		let item = try extractedItem(workID: "22222222")
		#expect(item.warnings == ["Rape/Non-Con", "Major Character Death"])
		#expect(item.categories == ["F/M", "Other"])
		#expect(item.relationships == ["Character A/Character B"])
		#expect(item.characters == ["Character A", "Character B"])
	}

	@Test func allFourStatsCountsPresentOnRow2() throws {
		// Row 2's stats block has Comments/Kudos/Bookmarks/Hits all
		// present (unlike row 1, which only has Kudos/Hits) -- confirms
		// all four selectors independently, not just their absence.
		let item = try extractedItem(workID: "22222222")
		#expect(item.commentCount == 5)
		#expect(item.kudosCount == 99)
		#expect(item.bookmarkCount == 3)
		#expect(item.hitCount == 1000)
		#expect(item.language == "English")
	}

	// MARK: - Helpers

	private func extractedItem(workID: String) throws -> ParsedItem {
		let html = htmlFixtureString("ao3-search-results.html")
		let outcome = AO3SearchResultsExtractor.extract(fromResultsPageHTML: html, feedURL: feedURL)
		guard case .success(let items, _) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			throw TestError.unexpectedOutcome
		}
		return try #require(items.first { $0.ao3WorkID == workID })
	}

	private enum TestError: Error {
		case unexpectedOutcome
	}
}
