//
//  AO3SearchResultsImporterTests.swift
//  AccountTests
//
//  Coverage for the ao3-arbitrary-page-fetch plan (Part 8): direct
//  coverage of AO3SearchResultsImporter.importFetchedPage's own
//  bookkeeping, reached the way AO3SearchResultsFetchCoordinator.presentSolverAndRetry
//  reaches it -- an already-harvested HTML string and an explicit
//  advancePageTo, no live fetch involved.
//

import XCTest
import RSParser
import RSWeb
@testable import Account

@MainActor final class AO3SearchResultsImporterTests: XCTestCase {

	private var account: Account!
	private var feed: Feed!

	private let feedURLString = "https://archiveofourown.org/works?work_search%5Bquery%5D=test"

	override func setUp() async throws {
		account = TestAccountManager.shared.createAccount(type: .onMyMac)
		feed = account.createFeed(with: "Test Search", url: feedURLString, feedID: feedURLString, homePageURL: nil)
	}

	override func tearDown() async throws {
		TestAccountManager.shared.deleteAccount(account)
		account = nil
		feed = nil
	}

	private func searchResultsHTML(workID: String, totalPages: Int? = nil) -> String {
		var html = """
		<html><head><title>Some Fandom - Works | Archive of Our Own</title></head><body>
		<li class="work-\(workID)">
		<h4 class="heading"><a href="/works/\(workID)">A Test Work</a> by <a rel="author" href="/users/author">author</a></h4>
		</li>
		"""
		if let totalPages {
			html += "<ol class=\"pagination\"><li><a href=\"?page=1\">1</a></li><li><a href=\"?page=\(totalPages)\">\(totalPages)</a></li></ol>"
		}
		html += "</body></html>"
		return html
	}

	func testImportFetchedPageInsertsWithoutDisturbingExistingPages() async {
		feed.ao3SearchFetchedPages = [1, 2, 3, 7]
		let html = searchResultsHTML(workID: "44444", totalPages: 9)

		let outcome = await AO3SearchResultsImporter.importFetchedPage(html: html, feedURL: feed.url, feed: feed, account: account, advancePageTo: 4)

		guard case .imported = outcome else {
			XCTFail("expected .imported, got \(outcome)")
			return
		}
		XCTAssertEqual(feed.ao3SearchFetchedPages, [1, 2, 3, 4, 7])
		XCTAssertEqual(feed.ao3SearchTotalPages, 9)
	}

	func testImportFetchedPageOverwritesStaleTotalPages() async {
		feed.ao3SearchFetchedPages = [1]
		feed.ao3SearchTotalPages = 12
		let html = searchResultsHTML(workID: "22222", totalPages: 9)

		_ = await AO3SearchResultsImporter.importFetchedPage(html: html, feedURL: feed.url, feed: feed, account: account, advancePageTo: 2)

		XCTAssertEqual(feed.ao3SearchTotalPages, 9)
	}

	func testImportFetchedPageWithNilAdvancePageToLeavesFetchedPagesUntouched() async {
		feed.ao3SearchFetchedPages = [1, 2]
		let html = searchResultsHTML(workID: "99999")

		_ = await AO3SearchResultsImporter.importFetchedPage(html: html, feedURL: feed.url, feed: feed, account: account, advancePageTo: nil)

		XCTAssertEqual(feed.ao3SearchFetchedPages, [1, 2])
	}

	func testImportFetchedPageNoResultsStillCorrectsTotalPages() async {
		feed.ao3SearchTotalPages = 12
		let html = "<html><head><title>Some Rare Fandom - Works | Archive of Our Own</title></head><body><p>No results found.</p><ol class=\"pagination\"><li><a href=\"?page=1\">1</a></li><li><a href=\"?page=9\">9</a></li></ol></body></html>"

		let outcome = await AO3SearchResultsImporter.importFetchedPage(html: html, feedURL: feed.url, feed: feed, account: account, advancePageTo: 10)

		guard case .noResults = outcome else {
			XCTFail("expected .noResults, got \(outcome)")
			return
		}
		XCTAssertEqual(feed.ao3SearchTotalPages, 9)
		// A .noResults outcome never advances fetchedPages, regardless of
		// advancePageTo -- only a genuine .success import inserts.
		XCTAssertNil(feed.ao3SearchFetchedPages)
	}
}
