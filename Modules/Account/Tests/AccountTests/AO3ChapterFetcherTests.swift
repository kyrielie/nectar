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
import RSParser
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

	// MARK: - Ambrosia preface preservation (item 4)

	func testIsStaleWithAmbrosiaPrefaceNoWorkskin() {
		// ambrosia_preface_fixture.html is test2.json's real content_html
		// verbatim: Ambrosia's own epub-derived preface, structurally
		// nothing like an AO3 work page (no #workskin at all, calibre*
		// classes instead of AO3's). AO3ChapterHTMLExtractor can't find a
		// chapter count in it, so isStale correctly reports true here --
		// this fixture, on its own, documents why AO3ChapterFetcher must
		// never treat "extraction failed against Ambrosia's own preface" as
		// a reason to overwrite that preface: rebuildParsedItem is only
		// ever reached after a successful download+extraction (see the
		// early returns in download's switch), so this stale/mismatched
		// state is what triggers a fetch attempt, not what a failed one
		// leaves behind.
		let article = Self.makeArticle(contentHTML: Self.ambrosiaPrefaceFixture, chapterCurrent: 1)
		XCTAssertTrue(AO3ChapterFetcher.shared.isStale(article: article))
	}

	func testRebuildParsedItemPreservesIsAmbrosiaItemFromExistingArticle() {
		// The bug this item fixed: rebuildParsedItem used to hardcode
		// isAmbrosiaItem: false regardless of what the existing article
		// actually was. Construct an existingArticle carrying Ambrosia's
		// real preface content and isAmbrosiaItem: true (as
		// AmbrosiaSQLiteImportTable's bulk insert would have set it, or a
		// prior successful chapter fetch would have carried forward), and
		// confirm the rebuilt ParsedItem still says isAmbrosiaItem: true --
		// this is what lets a later failed-fetch code path distinguish
		// this row from a native AO3 item, without needing to be tested
		// here directly against an unmockable Downloader.
		let existingArticle = Self.makeArticle(
			contentHTML: Self.ambrosiaPrefaceFixture,
			chapterCurrent: 1,
			isAmbrosiaItem: true
		)
		// AO3ExtractedChapter/AO3ChapterExtractionResult have no public
		// memberwise init (RSParser is a separate module, imported here
		// normally, not @testable) -- go through the real extractor
		// against a minimal one-chapter fixture instead of hand-
		// constructing the result.
		guard case .success(let extraction) = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: Self.workPageFixture(chapterCount: 1)) else {
			XCTFail("Expected .success extracting the minimal work page fixture")
			return
		}
		let parsedItem = AO3ChapterFetcher.rebuildParsedItem(from: existingArticle, workID: "999", extraction: extraction)
		XCTAssertTrue(parsedItem.isAmbrosiaItem)
		XCTAssertNotNil(parsedItem.lastPrefaceFetchDate)
	}

	func testRebuildParsedItemPreservesIsAmbrosiaItemFalseForNativeAO3Article() {
		// The other half of the same fix: a native AO3 article (never
		// Ambrosia-sourced) must not spuriously flip to true.
		let existingArticle = Self.makeArticle(
			contentHTML: Self.workPageFixture(chapterCount: 1),
			chapterCurrent: 1,
			isAmbrosiaItem: false
		)
		guard case .success(let extraction) = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: Self.workPageFixture(chapterCount: 1)) else {
			XCTFail("Expected .success extracting the minimal work page fixture")
			return
		}
		let parsedItem = AO3ChapterFetcher.rebuildParsedItem(from: existingArticle, workID: "999", extraction: extraction)
		XCTAssertFalse(parsedItem.isAmbrosiaItem)
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

	private static func makeArticle(contentHTML: String?, chapterCurrent: Int?, ao3WorkID: String? = "999", isAmbrosiaItem: Bool = false) -> Article {
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
			isAmbrosiaItem: isAmbrosiaItem,
			bookKey: bookKey,
			status: status
		)
	}

	/// test2.json's real `content_html` verbatim -- Ambrosia's own
	/// epub-derived preface for a book with no AO3 chapter fetch yet.
	private static let ambrosiaPrefaceFixture: String = {
		let fileURL = Bundle.module.resourceURL!.appendingPathComponent("Resources/ambrosia_preface_fixture.html")
		guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
			XCTFail("Unable to read ambrosia_preface_fixture.html at \(fileURL)")
			return ""
		}
		return contents
	}()
}
