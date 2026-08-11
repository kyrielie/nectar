//
//  AO3ChapterFetcherTests.swift
//  AccountTests
//
//  Nectar AO3 direct-reading support, Workstream 2 test plan.
//
//  Downloader.shared now has a TestingURLProtocol seam (see RSWeb's
//  Downloader.swift and AO3SeriesNavigatorTests.swift for a real usage),
//  but AO3ChapterFetcher.download's own Cloudflare/registration-required/
//  retry branches aren't exercised here yet -- this still only covers
//  what's pure/synchronous: ao3WorkID(fromBookKey:)'s prefix parsing and
//  isStale(article:)'s chapter-count comparison, both against constructed
//  Article fixtures rather than a live or stubbed fetch.
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

	// MARK: - Anthology / combined-series bookKeys (fetchIfNeeded)

	/// A combined-series article never resolves an ao3WorkID (covered
	/// above), so fetchIfNeeded can't make a request for it -- this
	/// confirms that no longer means total silence: it should post
	/// .ao3ChapterFetchDidFail with an explanatory message exactly once.
	func testFetchIfNeededNotesAnthologyBookKeyInsteadOfSilentNoOp() {
		let article = Self.makeArticle(contentHTML: nil, chapterCurrent: nil, ao3WorkID: nil, bookKeyOverride: "ao3-series:4242-\(UUID().uuidString)")
		let expectation = XCTNSNotificationExpectation(name: .ao3ChapterFetchDidFail, object: nil, notificationCenter: .default)

		AO3ChapterFetcher.shared.fetchIfNeeded(for: article)

		wait(for: [expectation], timeout: 1.0)
		XCTAssertEqual(
			AO3ChapterFetcher.shared.lastFetchFailureMessage(forArticleID: article.articleID),
			"Combined AO3 series can't be refreshed individually -- showing imported content"
		)
	}

	/// Calling fetchIfNeeded a second time for the same anthology article
	/// must not post a second notification -- it's a one-time note, not a
	/// recurring failure, so it shouldn't behave like the download-retry
	/// path's per-attempt gate.
	func testFetchIfNeededNotesAnthologyBookKeyOnlyOnce() {
		let article = Self.makeArticle(contentHTML: nil, chapterCurrent: nil, ao3WorkID: nil, bookKeyOverride: "calibre-series:Once Only \(UUID().uuidString)")
		let firstExpectation = XCTNSNotificationExpectation(name: .ao3ChapterFetchDidFail, object: nil, notificationCenter: .default)
		AO3ChapterFetcher.shared.fetchIfNeeded(for: article)
		wait(for: [firstExpectation], timeout: 1.0)

		let secondExpectation = XCTNSNotificationExpectation(name: .ao3ChapterFetchDidFail, object: nil, notificationCenter: .default)
		secondExpectation.isInverted = true
		AO3ChapterFetcher.shared.fetchIfNeeded(for: article)
		wait(for: [secondExpectation], timeout: 0.5)
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

	// MARK: - isStale(article:) refetch cadence

	func testIsStaleSettledArticleWithinCadenceIntervalIsNotStale() {
		let previous = AO3PrefaceRefetchPreference.current
		AO3PrefaceRefetchPreference.current = .monthly
		defer { AO3PrefaceRefetchPreference.current = previous }

		let article = Self.makeArticle(
			contentHTML: Self.workPageFixture(chapterCount: 3),
			chapterCurrent: 3,
			lastPrefaceFetchDate: Date().addingTimeInterval(-60 * 60) // 1 hour ago
		)
		XCTAssertFalse(AO3ChapterFetcher.shared.isStale(article: article))
	}

	func testIsStaleSettledArticleExceedingCadenceIntervalIsStale() {
		let previous = AO3PrefaceRefetchPreference.current
		AO3PrefaceRefetchPreference.current = .monthly
		defer { AO3PrefaceRefetchPreference.current = previous }

		let fortyDaysAgo = Date().addingTimeInterval(-40 * 24 * 60 * 60)
		let article = Self.makeArticle(
			contentHTML: Self.workPageFixture(chapterCount: 3),
			chapterCurrent: 3,
			lastPrefaceFetchDate: fortyDaysAgo
		)
		XCTAssertTrue(AO3ChapterFetcher.shared.isStale(article: article))
	}

	func testIsStaleAlwaysCadenceForcesRefetchOfSettledArticle() {
		// .always's timeInterval is 0, so any recorded lastPrefaceFetchDate
		// -- however recent -- satisfies the ">= interval" check. The
		// attemptDates floor in downloadIfNeeded (not isStale) is what
		// actually prevents this from double-firing on rapid re-opens.
		let previous = AO3PrefaceRefetchPreference.current
		AO3PrefaceRefetchPreference.current = .always
		defer { AO3PrefaceRefetchPreference.current = previous }

		let article = Self.makeArticle(
			contentHTML: Self.workPageFixture(chapterCount: 3),
			chapterCurrent: 3,
			lastPrefaceFetchDate: Date()
		)
		XCTAssertTrue(AO3ChapterFetcher.shared.isStale(article: article))
	}

	func testIsStaleSettledArticleWithNoLastPrefaceFetchDateIsNotForcedStale() {
		// A settled article that's never gone through a recorded chapter
		// fetch (nil lastPrefaceFetchDate -- e.g. pre-dating this feature)
		// is left alone by the cadence check rather than treated as
		// perpetually overdue, even under .always.
		let previous = AO3PrefaceRefetchPreference.current
		AO3PrefaceRefetchPreference.current = .always
		defer { AO3PrefaceRefetchPreference.current = previous }

		let article = Self.makeArticle(
			contentHTML: Self.workPageFixture(chapterCount: 3),
			chapterCurrent: 3,
			lastPrefaceFetchDate: nil
		)
		XCTAssertFalse(AO3ChapterFetcher.shared.isStale(article: article))
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
		let parsedItem = AO3ChapterFetcher.rebuildParsedItem(from: existingArticle, workID: "999", extraction: extraction, applyStatsUpdate: true)
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
		let parsedItem = AO3ChapterFetcher.rebuildParsedItem(from: existingArticle, workID: "999", extraction: extraction, applyStatsUpdate: true)
		XCTAssertFalse(parsedItem.isAmbrosiaItem)
	}

	// MARK: - isAO3NetworkRequestAllowed(for:) (Task 8, Ambrosia toggle)

	func testNetworkRequestAllowedForNativeArticleRegardlessOfToggle() {
		let article = Self.makeArticle(contentHTML: nil, chapterCurrent: 1, isAmbrosiaItem: false)
		let original = AmbrosiaAO3NetworkPreference.updatesEnabled
		defer { AmbrosiaAO3NetworkPreference.updatesEnabled = original }
		AmbrosiaAO3NetworkPreference.updatesEnabled = false
		XCTAssertTrue(AO3ChapterFetcher.isAO3NetworkRequestAllowed(for: article))
	}

	func testNetworkRequestBlockedForAmbrosiaArticleWithUpdatesOff() {
		let article = Self.makeArticle(contentHTML: nil, chapterCurrent: 1, isAmbrosiaItem: true)
		let original = AmbrosiaAO3NetworkPreference.updatesEnabled
		defer { AmbrosiaAO3NetworkPreference.updatesEnabled = original }
		AmbrosiaAO3NetworkPreference.updatesEnabled = false
		XCTAssertFalse(AO3ChapterFetcher.isAO3NetworkRequestAllowed(for: article))
	}

	func testNetworkRequestAllowedForAmbrosiaArticleWithUpdatesOn() {
		let article = Self.makeArticle(contentHTML: nil, chapterCurrent: 1, isAmbrosiaItem: true)
		let original = AmbrosiaAO3NetworkPreference.updatesEnabled
		defer { AmbrosiaAO3NetworkPreference.updatesEnabled = original }
		AmbrosiaAO3NetworkPreference.updatesEnabled = true
		XCTAssertTrue(AO3ChapterFetcher.isAO3NetworkRequestAllowed(for: article))
	}

	// MARK: - rebuildParsedItem applyStatsUpdate (Task 8)
	//
	// There is no longer an applyContentUpdate parameter/test: content is
	// always applied from an allowed fetch now, protected only by
	// Self.detectRegression (checked by the caller, download(for:...)'s
	// completion handler, before rebuildParsedItem is ever reached -- not
	// by a separate content toggle here). Nothing in this file currently
	// tests detectRegression directly; it's exercised only indirectly
	// through the fixtures above. That gap predates this change and isn't
	// introduced by it, but is now the only thing standing between a bad
	// AO3 fetch and a silent content overwrite, so it's worth a real test
	// on its own. The content-always-applies half of this change is
	// exercised implicitly below (parsedItem.contentHTML is asserted
	// against the new extraction, not the existing article).

	func testRebuildParsedItemSkipsStatsWhenApplyStatsUpdateFalse() {
		let existingArticle = Self.makeArticle(
			contentHTML: Self.workPageFixture(chapterCount: 1),
			chapterCurrent: 1,
			isAmbrosiaItem: true
		)
		guard case .success(let extraction) = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: Self.workPageFixture(chapterCount: 1)) else {
			XCTFail("Expected .success extracting the minimal work page fixture")
			return
		}
		let parsedItem = AO3ChapterFetcher.rebuildParsedItem(from: existingArticle, workID: "999", extraction: extraction, applyStatsUpdate: false)
		XCTAssertEqual(parsedItem.commentCount, existingArticle.commentCount)
		XCTAssertEqual(parsedItem.kudosCount, existingArticle.kudosCount)
		XCTAssertEqual(parsedItem.bookmarkCount, existingArticle.bookmarkCount)
		XCTAssertEqual(parsedItem.hitCount, existingArticle.hitCount)
		// Content update was still applied independently.
		XCTAssertEqual(parsedItem.contentHTML, extraction.contentHTML)
	}

	// MARK: - rebuildParsedItem metadata overwrite (series-nav stub fix)

	func testRebuildParsedItemFillsMetadataForNilStub() {
		// The bug under investigation: a series-nav stub
		// (AO3SeriesNavigator.placeholderStub) has summary/authors/dates/
		// tag-groups all nil. Confirm rebuildParsedItem now populates
		// every one of them from the live fetch instead of leaving them
		// nil forever.
		let existingArticle = Self.makeArticle(
			contentHTML: nil,
			chapterCurrent: nil,
			summary: nil,
			authors: nil,
			datePublished: nil,
			dateModified: nil,
			fandoms: nil,
			additionalTags: nil
		)
		guard case .success(let extraction) = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: Self.workPageFixtureWithMetadata(chapterCount: 1)) else {
			XCTFail("Expected .success extracting the metadata-bearing fixture")
			return
		}
		let parsedItem = AO3ChapterFetcher.rebuildParsedItem(from: existingArticle, workID: "999", extraction: extraction, applyStatsUpdate: true)

		XCTAssertEqual(parsedItem.summary, "<p>Fresh fetched summary text.</p>")
		XCTAssertEqual(parsedItem.authors?.first?.name, "FreshFetchedAuthor")
		XCTAssertEqual(parsedItem.fandoms, ["Fresh Fetched Fandom"])
		XCTAssertEqual(parsedItem.tags, ["Fresh Fetched Tag"])
		XCTAssertNotNil(parsedItem.datePublished)
		XCTAssertNotNil(parsedItem.dateModified)
	}

	func testRebuildParsedItemOverwritesStaleMetadataOnRefetch() {
		// The other half of Q1's answer: an article that ALREADY has real
		// metadata (search-results import or Ambrosia sync) must still get
		// the live page's fresh values on a normal refetch/sweep, not keep
		// whatever was stored at import time -- the live page is the
		// source of truth on every fetch, not just the first one.
		let existingArticle = Self.makeArticle(
			contentHTML: Self.workPageFixtureWithMetadata(chapterCount: 1),
			chapterCurrent: 1,
			summary: "Stale imported summary.",
			authors: Set([Author(authorID: nil, name: "Stale Imported Author", url: nil, avatarURL: nil, emailAddress: nil)].compactMap { $0 }),
			fandoms: ["Stale Imported Fandom"]
		)
		guard case .success(let extraction) = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: Self.workPageFixtureWithMetadata(chapterCount: 1)) else {
			XCTFail("Expected .success extracting the metadata-bearing fixture")
			return
		}
		let parsedItem = AO3ChapterFetcher.rebuildParsedItem(from: existingArticle, workID: "999", extraction: extraction, applyStatsUpdate: true)

		XCTAssertEqual(parsedItem.summary, "<p>Fresh fetched summary text.</p>")
		XCTAssertEqual(parsedItem.authors?.first?.name, "FreshFetchedAuthor")
		XCTAssertEqual(parsedItem.fandoms, ["Fresh Fetched Fandom"])
		XCTAssertNotEqual(parsedItem.summary, existingArticle.summary)
	}

	func testRebuildParsedItemFallsBackToExistingWhenMetadataBlockAbsent() {
		// When the live page has no dl.work.meta.group at all (gated page,
		// or a shape not yet sampled -- parseWorkHeader returns nil),
		// rebuildParsedItem must not blank out an existing article's real
		// metadata -- fall back to existingArticle's stored value, same
		// "absence isn't a hard failure" contract the extractor itself
		// documents.
		let existingArticle = Self.makeArticle(
			contentHTML: Self.workPageFixture(chapterCount: 1),
			chapterCurrent: 1,
			summary: "Keep this summary.",
			fandoms: ["Keep This Fandom"]
		)
		guard case .success(let extraction) = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: Self.workPageFixture(chapterCount: 1)) else {
			XCTFail("Expected .success extracting the minimal (no-metadata) fixture")
			return
		}
		let parsedItem = AO3ChapterFetcher.rebuildParsedItem(from: existingArticle, workID: "999", extraction: extraction, applyStatsUpdate: true)

		XCTAssertEqual(parsedItem.summary, "Keep this summary.")
		XCTAssertEqual(parsedItem.fandoms, ["Keep This Fandom"])
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

	/// Same minimal shape as workPageFixture, plus a real
	/// dl.work.meta.group/preface so rebuildParsedItem's metadata
	/// overwrite behavior has something to actually overwrite with/from
	/// -- author, summary, one tag per group, and both Published/Updated
	/// dates, all distinct values from makeArticle's own defaults so a
	/// test can tell "came from this fetch" apart from "existingArticle's
	/// stored value leaked through."
	private static func workPageFixtureWithMetadata(chapterCount: Int, published: String = "2026-01-01", updated: String = "2026-02-02") -> String {
		let metaGroup = """
		<dl class="work meta group">
		<dt class="rating tags">Rating:</dt>
		<dd class="rating tags"><ul class="commas"><li><a class="tag" href="/tags/x">Teen And Up Audiences</a></li></ul></dd>
		<dt class="fandom tags">Fandom:</dt>
		<dd class="fandom tags"><ul class="commas"><li><a class="tag" href="/tags/x">Fresh Fetched Fandom</a></li></ul></dd>
		<dt class="freeform tags">Additional Tags:</dt>
		<dd class="freeform tags"><ul class="commas"><li><a class="tag" href="/tags/x">Fresh Fetched Tag</a></li></ul></dd>
		<dt class="stats">Stats:</dt>
		<dd class="stats"><dl class="stats"><dt class="published">Published:</dt><dd class="published">\(published)</dd><dt class="status">Updated:</dt><dd class="status">\(updated)</dd><dt class="words">Words:</dt><dd class="words">100</dd></dl></dd>
		</dl>
		"""
		let preface = """
		<div class="preface group">
		<h2 class="title heading">Fresh Fetched Title</h2>
		<h3 class="byline heading"><a rel="author" href="/users/FreshFetchedAuthor/pseuds/FreshFetchedAuthor">FreshFetchedAuthor</a></h3>
		<div class="summary module"><h3 class="heading">Summary:</h3><blockquote class="userstuff"><p>Fresh fetched summary text.</p></blockquote></div>
		</div>
		"""
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
		return "\(metaGroup)<div id=\"workskin\">\(preface)\(chapters)</div>"
	}

	private static func makeArticle(contentHTML: String?, chapterCurrent: Int?, ao3WorkID: String? = "999", isAmbrosiaItem: Bool = false, lastPrefaceFetchDate: Date? = nil, bookKeyOverride: String? = nil, summary: String? = "A test summary.", authors: Set<Author>? = nil, datePublished: Date? = nil, dateModified: Date? = nil, fandoms: [String]? = nil, additionalTags: [String]? = nil) -> Article {
		// Unique per call -- AO3ChapterFetcher.shared.attemptDates is a
		// process-lifetime singleton cache keyed by articleID, so reusing a
		// fixed ID across tests leaks already-noted/already-attempted state
		// from one test into another depending on run order.
		let articleID = "test-article-id-\(UUID().uuidString)"
		let status = ArticleStatus(articleID: articleID, read: false, starred: false, dateArrived: Date())
		let bookKey: String? = bookKeyOverride ?? ao3WorkID.map { "ao3-work:\($0)" }
		return Article(
			accountID: "test-account-id",
			articleID: articleID,
			feedID: "test-feed-id",
			uniqueID: "test-unique-id",
			title: "Test Work",
			contentHTML: contentHTML,
			contentText: nil,
			markdown: nil,
			url: "https://archiveofourown.org/works/999",
			externalURL: nil,
			summary: summary,
			imageURL: nil,
			datePublished: datePublished,
			dateModified: dateModified,
			authors: authors,
			chapterCurrent: chapterCurrent,
			fandoms: fandoms,
			additionalTags: additionalTags,
			lastPrefaceFetchDate: lastPrefaceFetchDate,
			isAmbrosiaItem: isAmbrosiaItem,
			bookKey: bookKey,
			status: status
		)
	}

	/// test2.json's real `content_html` verbatim -- Ambrosia's own
	/// epub-derived preface for a book with no AO3 chapter fetch yet.
	private static let ambrosiaPrefaceFixture: String = {
		let fileURL = Bundle.module.resourceURL!.appendingPathComponent("ambrosia_preface_fixture.html")
		guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
			XCTFail("Unable to read ambrosia_preface_fixture.html at \(fileURL)")
			return ""
		}
		return contents
	}()
}
