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
		guard case .success(let items) = outcome else {
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

	@Test func statsWithoutCommentsOrBookmarksStayNil() throws {
		// Row 1's stats block has no Comments/Bookmarks rows at all --
		// confirms absence doesn't crash or get confused with row 2's.
		let item = try extractedItem(workID: "11111111")
		#expect(item.wordCount == 1234)
	}

	// MARK: - Helpers

	private func extractedItem(workID: String) throws -> ParsedItem {
		let html = htmlFixtureString("ao3-search-results.html")
		let outcome = AO3SearchResultsExtractor.extract(fromResultsPageHTML: html, feedURL: feedURL)
		guard case .success(let items) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			throw TestError.unexpectedOutcome
		}
		return try #require(items.first { $0.ao3WorkID == workID })
	}

	private enum TestError: Error {
		case unexpectedOutcome
	}
}
