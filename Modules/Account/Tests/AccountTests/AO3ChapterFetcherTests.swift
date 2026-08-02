//
//  AO3ChapterFetcherTests.swift
//  AccountTests
//
//  Nectar AO3 direct-reading support, Workstream 2 test plan.
//
//  Downloader.shared isn't mockable (concrete singleton, no injected
//  protocol) — this deliberately doesn't attempt to fake that out. Instead
//  it covers everything in AO3ChapterFetcher that's pure/synchronous:
//  ao3WorkID(fromBookKey:)'s prefix parsing and isStale(article:)'s chapter-
//  count comparison, both against constructed Article fixtures rather than
//  a live fetch. A real network-level test of `download` would need a
//  Downloader seam this codebase doesn't have yet -- flagged here rather
//  than silently skipped.
//

import XCTest
import Articles
@testable import Account

final class AO3ChapterFetcherTests: XCTestCase {

	// MARK: - ao3WorkID(fromBookKey:)

	func testAo3WorkIDFromValidBookKey() {
		XCTAssertEqual(AO3ChapterFetcher.ao3WorkID(fromBookKey: "ao3-work:12345"), "12345")
	}

	func testAo3WorkIDFromNonAO3BookKey() {
		XCTAssertNil(AO3ChapterFetcher.ao3WorkID(fromBookKey: "ambrosia-book-42"))
		XCTAssertNil(AO3ChapterFetcher.ao3WorkID(fromBookKey: "ao3-series:99"))
		XCTAssertNil(AO3ChapterFetcher.ao3WorkID(fromBookKey: "calibre-series:Some Series"))
	}

	func testAo3WorkIDFromEmptyID() {
		XCTAssertNil(AO3ChapterFetcher.ao3WorkID(fromBookKey: "ao3-work:"))
	}

	// MARK: - isStale(article:)

	func testIsStaleWithNilContentHTML() {
		let article = Self.makeArticle(contentHTML: nil, chapterCurrent: 3)
		XCTAssertTrue(AO3ChapterFetcher.shared.isStale(article: article))
	}

	func testIsStaleWithEmptyContentHTML() {
		let article = Self.makeArticle(contentHTML: "", chapterCurrent: 3)
		XCTAssertTrue(AO3ChapterFetcher.shared.isStale(article: article))
	}

	func testIsStaleWithMatchingChapterCount() {
		let article = Self.makeArticle(contentHTML: Self.workPageFixture(chapterCount: 3), chapterCurrent: 3)
		XCTAssertFalse(AO3ChapterFetcher.shared.isStale(article: article))
	}

	func testIsStaleWithBehindChapterCount() {
		let article = Self.makeArticle(contentHTML: Self.workPageFixture(chapterCount: 2), chapterCurrent: 4)
		XCTAssertTrue(AO3ChapterFetcher.shared.isStale(article: article))
	}

	func testIsStaleWithNoChapterCurrentMetadata() {
		// No chapterCurrent to compare against -- shouldn't happen in
		// practice for an AO3-gated article, but shouldn't be treated as
		// stale on every call either. See isStale(article:)'s doc comment.
		let article = Self.makeArticle(contentHTML: Self.workPageFixture(chapterCount: 1), chapterCurrent: nil)
		XCTAssertFalse(AO3ChapterFetcher.shared.isStale(article: article))
	}

	// MARK: - fetchIfNeeded(for:) short-circuit

	func testFetchIfNeededGateForNonAO3BookKey() {
		// bookKey resolves to the plain uniqueID here since no ao3WorkID is
		// set -- confirms fetchIfNeeded's ao3WorkID(fromBookKey:) gate (not
		// just isStale) is what should prevent a fetch attempt.
		// fetchIfNeeded itself is fire-and-forget with no return value to
		// assert against directly (Downloader isn't mockable here — see the
		// file header), so this test documents and locks down the gate it
		// relies on rather than asserting on network behavior.
		let article = Self.makeArticle(contentHTML: nil, chapterCurrent: nil, ao3WorkID: nil)
		XCTAssertNil(AO3ChapterFetcher.ao3WorkID(fromBookKey: article.bookKey))
	}

	// MARK: - Fixtures

	/// A minimal synthetic work page: just enough structure
	/// (`div#workskin` containing `chapterCount` `.chapter` divs) for
	/// AO3ChapterHTMLExtractor to recognize and count, without needing the
	/// full real-page fixtures RSParserTests already covers structurally.
	private static func workPageFixture(chapterCount: Int) -> String {
		let chapters = (1...max(chapterCount, 1)).prefix(chapterCount).map { n in
			"""
			<div class="chapter" id="chapter-\(n)">
			<div class="chapter preface group">
			<h3 class="title"><a>Chapter \(n)</a></h3>
			</div>
			<div class="userstuff module" role="article">
			<h3 class="landmark heading" id="work">Chapter Text</h3>
			<p>Body \(n).</p>
			</div>
			</div>
			"""
		}.joined()
		return "<div id=\"workskin\">\(chapters)</div>"
	}

	private static func makeArticle(contentHTML: String?, chapterCurrent: Int?, ao3WorkID: String? = "999") -> Article {
		let status = ArticleStatus(articleID: "test-article-id", read: false, starred: false, dateArrived: Date())
		let bookKey: String? = ao3WorkID.map { "ao3-work:\($0)" }
		return Article(
			accountID: "test-account-id",
			articleID: "test-article-id",
			feedID: "test-feed-id",
			uniqueID: "test-unique-id",
			title: "Test Work",
			contentHTML: contentHTML,
			contentText: nil,
			markdown: nil,
			url: "https://archiveofourown.org/works/999",
			externalURL: nil,
			summary: "A test summary.",
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			chapterCurrent: chapterCurrent,
			bookKey: bookKey,
			status: status
		)
	}
}
