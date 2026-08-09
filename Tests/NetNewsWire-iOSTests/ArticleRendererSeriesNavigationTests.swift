//
//  ArticleRendererSeriesNavigationTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for inline series navigation (nectar-inline-series-nav-
//  implementation-plan.md, Phase 3), synthetic-preface (pre-fetch,
//  Ambrosia-sourced) path: ArticleRenderer.ao3SyntheticPrefaceHTML's Series
//  row and ArticleRenderer.ao3SyntheticSeriesFooterHTML, both added by this
//  pass. Deliberately tests these two static functions directly rather than
//  the full ArticleRenderer.articleHTML(article:theme:) pipeline --
//  ArticleTheme() reads core.css/template.html via Bundle.main.path(...)!,
//  which doesn't resolve inside the test bundle (see the equivalent scoping
//  note this repo already follows in
//  ArticleRendererStripFakeParagraphIndentsTests, the only other direct
//  ArticleRenderer coverage: it tests stripFakeParagraphIndents directly for
//  the same reason). ao3SyntheticPrefaceHTML/ao3SyntheticSeriesFooterHTML
//  take only an Article, no ArticleTheme, so they're safe to call as-is.
//

import Testing
import Foundation
import Articles
@testable import Nectar

@MainActor @Suite struct ArticleRendererSeriesNavigationTests {

	private static func makeArticle(
		contentHTML: String? = nil,
		fandoms: [String]? = nil,
		series: [ArticleSeriesEntry]? = nil
	) -> Article {
		let articleID = "test-article-id-\(UUID().uuidString)"
		let status = ArticleStatus(articleID: articleID, read: false, starred: false, dateArrived: Date())
		return Article(
			accountID: "test-account-id",
			articleID: articleID,
			feedID: "test-feed-id",
			uniqueID: "test-unique-id",
			title: "Test Title",
			contentHTML: contentHTML,
			contentText: nil,
			markdown: nil,
			url: "https://archiveofourown.org/works/999",
			externalURL: nil,
			summary: nil,
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			fandoms: fandoms,
			series: series,
			status: status
		)
	}

	// MARK: - ao3SyntheticSeriesFooterHTML

	@Test("nil when the article has no series membership")
	func footerNilWithNoSeries() {
		let article = Self.makeArticle(series: nil)
		#expect(ArticleRenderer.ao3SyntheticSeriesFooterHTML(for: article) == nil)
	}

	@Test("nil when the article's series array is empty")
	func footerNilWithEmptySeriesArray() {
		let article = Self.makeArticle(series: [])
		#expect(ArticleRenderer.ao3SyntheticSeriesFooterHTML(for: article) == nil)
	}

	@Test("nil once contentHTML exists -- the real-fetch path's own footer is already baked in")
	func footerNilOnceContentHTMLExists() {
		let series = [ArticleSeriesEntry(name: "Some Series", index: 1, ao3ID: "1001")]
		let article = Self.makeArticle(contentHTML: "<p>Already fetched.</p>", series: series)
		#expect(ArticleRenderer.ao3SyntheticSeriesFooterHTML(for: article) == nil)
	}

	@Test("renders the footer block when contentHTML is nil and series is present")
	func footerRendersForSyntheticSeriesArticle() throws {
		let series = [ArticleSeriesEntry(name: "Some Series", index: 4, ao3ID: "1001", previousWorkURL: "https://archiveofourown.org/works/111", nextWorkURL: nil)]
		let article = Self.makeArticle(contentHTML: nil, series: series)
		let footer = try #require(ArticleRenderer.ao3SyntheticSeriesFooterHTML(for: article))

		#expect(footer.contains("id='ao3SeriesFooter'"))
		#expect(footer.contains("This work is part of a series:"))
		#expect(footer.contains("Part 4 of Some Series"))
		#expect(footer.contains("href='nectar-series:previous?ao3id=1001&amp;workurl=https://archiveofourown.org/works/111'"))
		// No next link captured -- Ambrosia's wire format never carries
		// one (plan's 3b revision note) -- renders as the grayed, plain
		// label instead of a nectar-series:next href.
		#expect(footer.contains("<span class='ao3SeriesNavDisabled'>Next</span>"))
	}

	// MARK: - ao3SyntheticPrefaceHTML: Series row

	@Test("synthetic preface Series row carries ao3ID/previousWorkURL/nextWorkURL through and marks isSeriesNavigation")
	func prefaceSeriesRowCarriesNavigationFields() throws {
		// ao3SyntheticPrefaceHTML's own early-return guard requires at
		// least one of fandoms/ratings/warnings/categories to be
		// non-nil before it renders anything at all (pre-existing gate,
		// unrelated to this pass) -- fandoms supplies that here so the
		// Series row actually gets a chance to render.
		let originalStatsVisible = AppDefaults.shared.statsVisible
		AppDefaults.shared.statsVisible = true
		defer { AppDefaults.shared.statsVisible = originalStatsVisible }

		let series = [ArticleSeriesEntry(name: "Some Series", index: 2, ao3ID: "2002", previousWorkURL: nil, nextWorkURL: "https://archiveofourown.org/works/222")]
		let article = Self.makeArticle(fandoms: ["Some Fandom"], series: series)
		let preface = try #require(ArticleRenderer.ao3SyntheticPrefaceHTML(for: article))

		// First is tappable purely off ao3ID -- Ambrosia's _ambrosia.series
		// entries do carry ao3_id (plan's 3b revision note) even though
		// this is the pre-fetch, no-real-page-yet path.
		#expect(preface.contains("href='nectar-series:first?ao3id=2002'"))
		#expect(preface.contains("href='nectar-series:next?ao3id=2002&amp;workurl=https://archiveofourown.org/works/222'"))
		// previousWorkURL is nil (Ambrosia has no such key at all) --
		// grayed, unlinked label, not a broken/empty href.
		#expect(preface.contains("<span class='ao3SeriesNavDisabled'>Previous</span>"))
	}

	@Test("no Series row at all when the article has no series membership")
	func prefaceOmitsSeriesRowWhenNoSeries() throws {
		let originalStatsVisible = AppDefaults.shared.statsVisible
		AppDefaults.shared.statsVisible = true
		defer { AppDefaults.shared.statsVisible = originalStatsVisible }

		// fandoms present (so the preface renders something at all,
		// same gate as above) but series nil -- confirms the Series row
		// specifically is what's absent, not that the whole preface is
		// empty for an unrelated reason.
		let article = Self.makeArticle(fandoms: ["Some Fandom"], series: nil)
		let preface = try #require(ArticleRenderer.ao3SyntheticPrefaceHTML(for: article))
		#expect(!preface.contains("Series:"))
	}
}
