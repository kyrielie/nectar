//
//  AO3FetchPolicyTests.swift
//  AO3KitTests
//
//  Pure-policy coverage moved here from AccountTests'
//  AO3ChapterFetcherTests when these decisions moved into AO3Kit:
//  workID/bookKey mapping, the network-allowed and can-check gates,
//  isStale (now deterministic through its `now` and `interval`
//  parameters), detectRegression, and rebuildParsedItem. The fetcher's
//  orchestration tests stay in AccountTests.
//
//  Serialized because a few tests set AmbrosiaAO3NetworkPreference or
//  AO3PrefaceRefetchPreference, which are process-wide UserDefaults.
//

import Foundation
import Testing
import Articles
import RSParser
@testable import AO3Kit

@Suite(.serialized) struct AO3FetchPolicyTests {

	private struct ExtractionFailure: Error {}

	// A fixed clock keeps the cadence tests independent of when they run.
	private static let now = Date(timeIntervalSince1970: 1_800_000_000)
	private static let monthly = AO3PrefaceRefetchInterval.monthly.timeInterval
	private static let hour: TimeInterval = 60 * 60
	private static let day: TimeInterval = 24 * 60 * 60

	// MARK: - workID(fromBookKey:) and bookKey(forWorkID:)

	@Test func workIDFromValidBookKey() {
		#expect(AO3FetchPolicy.workID(fromBookKey: "ao3-work:12345") == "12345")
	}

	@Test func workIDFromNonWorkBookKeyIsNil() {
		#expect(AO3FetchPolicy.workID(fromBookKey: "ambrosia-book-42") == nil)
		#expect(AO3FetchPolicy.workID(fromBookKey: "ao3-series:99") == nil)
		#expect(AO3FetchPolicy.workID(fromBookKey: "calibre-series:Some Series") == nil)
	}

	@Test func workIDFromEmptyIDIsNil() {
		#expect(AO3FetchPolicy.workID(fromBookKey: "ao3-work:") == nil)
	}

	@Test func bookKeyRoundTripsThroughWorkID() {
		let bookKey = AO3FetchPolicy.bookKey(forWorkID: "4242")
		#expect(bookKey == "ao3-work:4242")
		#expect(AO3FetchPolicy.workID(fromBookKey: bookKey) == "4242")
	}

	// MARK: - isNetworkRequestAllowed(for:)

	@Test func networkRequestAllowedForNativeArticleRegardlessOfToggle() {
		let article = Self.makeArticle(contentHTML: nil, isAmbrosiaItem: false)
		let original = AmbrosiaAO3NetworkPreference.updatesEnabled
		defer { AmbrosiaAO3NetworkPreference.updatesEnabled = original }
		AmbrosiaAO3NetworkPreference.updatesEnabled = false
		#expect(AO3FetchPolicy.isNetworkRequestAllowed(for: article))
	}

	@Test func networkRequestBlockedForAmbrosiaArticleWithUpdatesOff() {
		let article = Self.makeArticle(contentHTML: nil, isAmbrosiaItem: true)
		let original = AmbrosiaAO3NetworkPreference.updatesEnabled
		defer { AmbrosiaAO3NetworkPreference.updatesEnabled = original }
		AmbrosiaAO3NetworkPreference.updatesEnabled = false
		#expect(!AO3FetchPolicy.isNetworkRequestAllowed(for: article))
	}

	@Test func networkRequestAllowedForAmbrosiaArticleWithUpdatesOn() {
		let article = Self.makeArticle(contentHTML: nil, isAmbrosiaItem: true)
		let original = AmbrosiaAO3NetworkPreference.updatesEnabled
		defer { AmbrosiaAO3NetworkPreference.updatesEnabled = original }
		AmbrosiaAO3NetworkPreference.updatesEnabled = true
		#expect(AO3FetchPolicy.isNetworkRequestAllowed(for: article))
	}

	// MARK: - canCheckForUpdates(for:)

	@Test func canCheckForUpdatesForPlainWork() {
		#expect(AO3FetchPolicy.canCheckForUpdates(for: Self.makeArticle(contentHTML: nil)))
	}

	@Test func cannotCheckForUpdatesWhileAPendingUpdateIsUnresolved() {
		let article = Self.makeArticle(contentHTML: nil, pendingUpdateContentHTML: "<div id=\"workskin\">pending</div>")
		#expect(!AO3FetchPolicy.canCheckForUpdates(for: article))
	}

	@Test func cannotCheckForUpdatesForAnthologyBookKey() {
		let article = Self.makeArticle(contentHTML: nil, ao3WorkID: nil, bookKeyOverride: "ao3-series:4242")
		#expect(!AO3FetchPolicy.canCheckForUpdates(for: article))
	}

	// MARK: - isStale

	@Test func staleWithNilContentHTML() {
		#expect(AO3FetchPolicy.isStale(Self.makeArticle(contentHTML: nil), now: Self.now, interval: Self.monthly))
	}

	@Test func staleWithEmptyContentHTML() {
		#expect(AO3FetchPolicy.isStale(Self.makeArticle(contentHTML: ""), now: Self.now, interval: Self.monthly))
	}

	@Test func notStaleWithPendingContentUpdate() {
		// Content and cadence alone would say stale here (no
		// lastPrefaceFetchDate), so this isolates the pending guard.
		let article = Self.makeArticle(
			contentHTML: Self.workPage(chapterCount: 3),
			pendingUpdateContentHTML: "<div id=\"workskin\">pending</div>"
		)
		#expect(!AO3FetchPolicy.isStale(article, now: Self.now, interval: Self.monthly))
	}

	@Test func notStaleWithWordCountRegressionFlagged() {
		let article = Self.makeArticle(
			contentHTML: Self.workPage(chapterCount: 3),
			wordCountRegressionFlaggedAt: Self.now
		)
		#expect(!AO3FetchPolicy.isStale(article, now: Self.now, interval: Self.monthly))
	}

	@Test func notStaleWithConfirmedMissing() {
		let article = Self.makeArticle(contentHTML: nil, ao3ConfirmedMissingAt: Self.now)
		#expect(!AO3FetchPolicy.isStale(article, now: Self.now, interval: Self.monthly))
	}

	@Test func clearedConfirmedMissingFallsThroughToContentCheck() {
		let article = Self.makeArticle(contentHTML: nil, ao3ConfirmedMissingAt: nil)
		#expect(AO3FetchPolicy.isStale(article, now: Self.now, interval: Self.monthly))
	}

	@Test func guardOrderPendingBeatsEverythingElse() {
		// Documents the contract in isStale's doc comment: with all three
		// flags set the article is simply not stale, whichever is read first.
		let article = Self.makeArticle(
			contentHTML: nil,
			pendingUpdateContentHTML: "<p>pending</p>",
			wordCountRegressionFlaggedAt: Self.now,
			ao3ConfirmedMissingAt: Self.now
		)
		#expect(!AO3FetchPolicy.isStale(article, now: Self.now, interval: Self.monthly))
	}

	@Test func settledArticleWithinCadenceIsNotStale() {
		let article = Self.makeArticle(
			contentHTML: Self.workPage(chapterCount: 3),
			lastPrefaceFetchDate: Self.now.addingTimeInterval(-Self.hour)
		)
		#expect(!AO3FetchPolicy.isStale(article, now: Self.now, interval: Self.monthly))
	}

	@Test func settledArticleBeyondCadenceIsStale() {
		let article = Self.makeArticle(
			contentHTML: Self.workPage(chapterCount: 3),
			lastPrefaceFetchDate: Self.now.addingTimeInterval(-40 * Self.day)
		)
		#expect(AO3FetchPolicy.isStale(article, now: Self.now, interval: Self.monthly))
	}

	@Test func settledArticleExactlyAtCadenceBoundaryIsStale() {
		let article = Self.makeArticle(
			contentHTML: Self.workPage(chapterCount: 3),
			lastPrefaceFetchDate: Self.now.addingTimeInterval(-Self.monthly)
		)
		#expect(AO3FetchPolicy.isStale(article, now: Self.now, interval: Self.monthly))
	}

	@Test func alwaysCadenceMakesAnyRecordedFetchStale() {
		// .always has a zero interval, so even a fetch recorded this
		// instant satisfies ">= interval". The attempt floor in
		// AO3ChapterFetcher, not this function, prevents rapid re-fires.
		let article = Self.makeArticle(
			contentHTML: Self.workPage(chapterCount: 3),
			lastPrefaceFetchDate: Self.now
		)
		#expect(AO3FetchPolicy.isStale(article, now: Self.now, interval: AO3PrefaceRefetchInterval.always.timeInterval))
	}

	@Test func contentWithoutRecordedFetchDateIsStaleUnderEveryCadence() {
		let article = Self.makeArticle(contentHTML: Self.workPage(chapterCount: 3), lastPrefaceFetchDate: nil)
		for interval in AO3PrefaceRefetchInterval.allCases {
			#expect(AO3FetchPolicy.isStale(article, now: Self.now, interval: interval.timeInterval))
		}
	}

	@Test func recentlyFetchedNonAO3ShapedContentIsSettled() {
		// Ambrosia's own preface has no #workskin at all. isStale's content
		// check is a bare non-empty test, so a recently fetched preface of
		// that shape is settled. Guards against an extraction-based check
		// creeping back in and misfiring on this format.
		let article = Self.makeArticle(
			contentHTML: "<div class=\"calibre1\"><p>Ambrosia preface, not an AO3 work page.</p></div>",
			lastPrefaceFetchDate: Self.now.addingTimeInterval(-Self.hour)
		)
		#expect(!AO3FetchPolicy.isStale(article, now: Self.now, interval: Self.monthly))
	}

	@Test func defaultIntervalReadsTheUserPreference() {
		let original = AO3PrefaceRefetchPreference.current
		defer { AO3PrefaceRefetchPreference.current = original }
		let article = Self.makeArticle(
			contentHTML: Self.workPage(chapterCount: 3),
			lastPrefaceFetchDate: Self.now.addingTimeInterval(-Self.hour)
		)

		AO3PrefaceRefetchPreference.current = .monthly
		#expect(!AO3FetchPolicy.isStale(article, now: Self.now))

		AO3PrefaceRefetchPreference.current = .always
		#expect(AO3FetchPolicy.isStale(article, now: Self.now))
	}

	// MARK: - detectRegression

	@Test func noRegressionWhenNothingIsStored() throws {
		let article = Self.makeArticle(contentHTML: nil)
		let extraction = try Self.extraction(from: Self.workPageWithMetadata(chapterCount: 2, words: 100))
		#expect(AO3FetchPolicy.detectRegression(existingArticle: article, extraction: extraction) == nil)
	}

	@Test func noRegressionWhenStoredContentCannotBeReparsed() throws {
		let article = Self.makeArticle(contentHTML: "<div class=\"calibre1\"><p>not a work page</p></div>")
		let extraction = try Self.extraction(from: Self.workPageWithMetadata(chapterCount: 2, words: 100))
		#expect(AO3FetchPolicy.detectRegression(existingArticle: article, extraction: extraction) == nil)
	}

	@Test func fewerChaptersIsAlwaysARegression() throws {
		let article = Self.makeArticle(contentHTML: Self.workPageWithMetadata(chapterCount: 3, words: 100))
		let extraction = try Self.extraction(from: Self.workPageWithMetadata(chapterCount: 2, words: 100))
		#expect(AO3FetchPolicy.detectRegression(existingArticle: article, extraction: extraction) == "chapter count 3 -> 2")
	}

	@Test func largeWordCountDropIsARegression() throws {
		let article = Self.makeArticle(contentHTML: Self.workPageWithMetadata(chapterCount: 2, words: 5000))
		let extraction = try Self.extraction(from: Self.workPageWithMetadata(chapterCount: 2, words: 100))
		let parsedWords = try #require(extraction.wordCount, "fixture word count was not parsed")
		#expect(parsedWords == 100)
		#expect(AO3FetchPolicy.detectRegression(existingArticle: article, extraction: extraction) == "word count 5000 -> 100")
	}

	@Test func smallWordCountDropIsNotARegression() throws {
		let article = Self.makeArticle(contentHTML: Self.workPageWithMetadata(chapterCount: 2, words: 5000))
		let extraction = try Self.extraction(from: Self.workPageWithMetadata(chapterCount: 2, words: 4900))
		#expect(AO3FetchPolicy.detectRegression(existingArticle: article, extraction: extraction) == nil)
	}

	@Test func growthIsNotARegression() throws {
		let article = Self.makeArticle(contentHTML: Self.workPageWithMetadata(chapterCount: 2, words: 1000))
		let extraction = try Self.extraction(from: Self.workPageWithMetadata(chapterCount: 3, words: 4000))
		#expect(AO3FetchPolicy.detectRegression(existingArticle: article, extraction: extraction) == nil)
	}

	// MARK: - rebuildParsedItem

	@Test func rebuildPreservesIsAmbrosiaItemFromExistingArticle() throws {
		// rebuildParsedItem once hardcoded isAmbrosiaItem: false, which
		// stopped a later code path telling an Ambrosia row from a native one.
		let existing = Self.makeArticle(contentHTML: "<div class=\"calibre1\"><p>preface</p></div>", isAmbrosiaItem: true)
		let extraction = try Self.extraction(from: Self.workPage(chapterCount: 1))

		let item = AO3FetchPolicy.rebuildParsedItem(from: existing, workID: "999", extraction: extraction, applyStatsUpdate: true)

		#expect(item.isAmbrosiaItem)
		#expect(item.lastPrefaceFetchDate != nil)
	}

	@Test func rebuildKeepsNativeArticleNonAmbrosia() throws {
		let existing = Self.makeArticle(contentHTML: Self.workPage(chapterCount: 1), isAmbrosiaItem: false)
		let extraction = try Self.extraction(from: Self.workPage(chapterCount: 1))

		let item = AO3FetchPolicy.rebuildParsedItem(from: existing, workID: "999", extraction: extraction, applyStatsUpdate: true)

		#expect(!item.isAmbrosiaItem)
	}

	@Test func rebuildSkipsStatsWhenApplyStatsUpdateIsFalse() throws {
		let existing = Self.makeArticle(contentHTML: Self.workPage(chapterCount: 1), isAmbrosiaItem: true)
		let extraction = try Self.extraction(from: Self.workPage(chapterCount: 1))

		let item = AO3FetchPolicy.rebuildParsedItem(from: existing, workID: "999", extraction: extraction, applyStatsUpdate: false)

		#expect(item.commentCount == existing.commentCount)
		#expect(item.kudosCount == existing.kudosCount)
		#expect(item.bookmarkCount == existing.bookmarkCount)
		#expect(item.hitCount == existing.hitCount)
		// Content is applied independently of the stats toggle.
		#expect(item.contentHTML == extraction.contentHTML)
	}

	@Test func rebuildFillsMetadataForNilStub() throws {
		// A series-navigation stub has summary/authors/dates/tags all nil.
		// The live fetch must populate every one of them, including
		// replacing the placeholder title.
		let existing = Self.makeArticle(contentHTML: nil, summary: nil, authors: nil, datePublished: nil, dateModified: nil, fandoms: nil, additionalTags: nil)
		let extraction = try Self.extraction(from: Self.workPageWithMetadata(chapterCount: 1))

		let item = AO3FetchPolicy.rebuildParsedItem(from: existing, workID: "999", extraction: extraction, applyStatsUpdate: true)

		#expect(item.summary == "<p>Fresh fetched summary text.</p>")
		#expect(item.authors?.first?.name == "FreshFetchedAuthor")
		#expect(item.fandoms == ["Fresh Fetched Fandom"])
		#expect(item.tags == ["Fresh Fetched Tag"])
		#expect(item.datePublished != nil)
		#expect(item.dateModified != nil)
		#expect(item.title == "Fresh Fetched Title")
	}

	@Test func rebuildOverwritesStaleMetadataOnRefetch() throws {
		// The live page is the source of truth on every fetch, not just
		// the first one, including over a real stored title.
		let stale = Author(authorID: nil, name: "Stale Imported Author", url: nil, avatarURL: nil, emailAddress: nil)
		let existing = Self.makeArticle(
			contentHTML: Self.workPageWithMetadata(chapterCount: 1),
			summary: "Stale imported summary.",
			authors: Set([stale].compactMap { $0 }),
			fandoms: ["Stale Imported Fandom"]
		)
		let extraction = try Self.extraction(from: Self.workPageWithMetadata(chapterCount: 1))

		let item = AO3FetchPolicy.rebuildParsedItem(from: existing, workID: "999", extraction: extraction, applyStatsUpdate: true)

		#expect(item.summary == "<p>Fresh fetched summary text.</p>")
		#expect(item.authors?.first?.name == "FreshFetchedAuthor")
		#expect(item.fandoms == ["Fresh Fetched Fandom"])
		#expect(item.summary != existing.summary)
		#expect(item.title == "Fresh Fetched Title")
		#expect(item.title != existing.title)
	}

	@Test func rebuildFallsBackToExistingWhenMetadataBlockIsAbsent() throws {
		// A page with no dl.work.meta.group must not blank real stored
		// metadata.
		let existing = Self.makeArticle(contentHTML: Self.workPage(chapterCount: 1), summary: "Keep this summary.", fandoms: ["Keep This Fandom"])
		let extraction = try Self.extraction(from: Self.workPage(chapterCount: 1))

		let item = AO3FetchPolicy.rebuildParsedItem(from: existing, workID: "999", extraction: extraction, applyStatsUpdate: true)

		#expect(item.summary == "Keep this summary.")
		#expect(item.fandoms == ["Keep This Fandom"])
	}

	// MARK: - Helpers

	private static func extraction(from html: String) throws -> AO3ChapterExtractionResult {
		guard case .success(let result) = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html) else {
			throw ExtractionFailure()
		}
		return result
	}

	private static func chapterDivs(_ chapterCount: Int) -> String {
		(1...max(chapterCount, 1)).prefix(chapterCount).map { n in
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
	}

	/// A minimal synthetic work page: `div#workskin` containing
	/// `chapterCount` chapter divs, enough for the extractor to recognize
	/// and count them.
	private static func workPage(chapterCount: Int) -> String {
		"<div id=\"workskin\">\(chapterDivs(chapterCount))</div>"
	}

	/// The same shape plus a real dl.work.meta.group and preface, with
	/// values distinct from makeArticle's defaults so a test can tell
	/// "came from this fetch" from "existing article leaked through".
	private static func workPageWithMetadata(chapterCount: Int, words: Int = 100) -> String {
		let metaGroup = """
		<dl class="work meta group">
		<dt class="rating tags">Rating:</dt>
		<dd class="rating tags"><ul class="commas"><li><a class="tag" href="/tags/x">Teen And Up Audiences</a></li></ul></dd>
		<dt class="fandom tags">Fandom:</dt>
		<dd class="fandom tags"><ul class="commas"><li><a class="tag" href="/tags/x">Fresh Fetched Fandom</a></li></ul></dd>
		<dt class="freeform tags">Additional Tags:</dt>
		<dd class="freeform tags"><ul class="commas"><li><a class="tag" href="/tags/x">Fresh Fetched Tag</a></li></ul></dd>
		<dt class="stats">Stats:</dt>
		<dd class="stats"><dl class="stats"><dt class="published">Published:</dt><dd class="published">2026-01-01</dd><dt class="status">Updated:</dt><dd class="status">2026-02-02</dd><dt class="words">Words:</dt><dd class="words">\(words)</dd></dl></dd>
		</dl>
		"""
		let preface = """
		<div class="preface group">
		<h2 class="title heading">Fresh Fetched Title</h2>
		<h3 class="byline heading"><a rel="author" href="/users/FreshFetchedAuthor/pseuds/FreshFetchedAuthor">FreshFetchedAuthor</a></h3>
		<div class="summary module"><h3 class="heading">Summary:</h3><blockquote class="userstuff"><p>Fresh fetched summary text.</p></blockquote></div>
		</div>
		"""
		return "\(metaGroup)<div id=\"workskin\">\(preface)\(chapterDivs(chapterCount))</div>"
	}

	private static func makeArticle(contentHTML: String?, ao3WorkID: String? = "999", isAmbrosiaItem: Bool = false, lastPrefaceFetchDate: Date? = nil, pendingUpdateContentHTML: String? = nil, wordCountRegressionFlaggedAt: Date? = nil, ao3ConfirmedMissingAt: Date? = nil, bookKeyOverride: String? = nil, summary: String? = "A test summary.", authors: Set<Author>? = nil, datePublished: Date? = nil, dateModified: Date? = nil, fandoms: [String]? = nil, additionalTags: [String]? = nil) -> Article {
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
			fandoms: fandoms,
			additionalTags: additionalTags,
			lastPrefaceFetchDate: lastPrefaceFetchDate,
			pendingUpdateContentHTML: pendingUpdateContentHTML,
			wordCountRegressionFlaggedAt: wordCountRegressionFlaggedAt,
			ao3ConfirmedMissingAt: ao3ConfirmedMissingAt,
			isAmbrosiaItem: isAmbrosiaItem,
			bookKey: bookKey,
			status: status
		)
	}
}
