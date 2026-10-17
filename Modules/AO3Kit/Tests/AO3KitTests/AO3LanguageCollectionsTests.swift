//
//  AO3LanguageCollectionsTests.swift
//  AO3Kit
//
//  AO3 display language and collections: extraction, slug parsing, and the
//  fetch-policy fallback rules.
//

import Foundation
import Testing
import Articles
import RSParser
@testable import AO3Kit

@Suite struct AO3LanguageCollectionsTests {

	private func extractSuccess(_ html: String) -> AO3ChapterExtractionResult? {
		guard case .success(let result) = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html) else {
			Issue.record("Expected .success")
			return nil
		}
		return result
	}

	// MARK: Work page

	@Test func singleChapterWorkReadsLanguageText() {
		guard let result = extractSuccess(htmlFixtureString("ao3-work-single-chapter.html")) else { return }
		#expect(result.metadata.language == "English")
	}

	@Test func multiChapterWorkReadsLanguageText() {
		guard let result = extractSuccess(htmlFixtureString("ao3-work-multi-chapter.html")) else { return }
		#expect(result.metadata.language == "English")
	}

	@Test func workInCollectionsCarriesNameAndSlug() {
		guard let result = extractSuccess(htmlFixtureString("ao3-work-single-chapter.html")) else { return }
		#expect(result.metadata.collections == [
			ParsedCollectionEntry(name: "Voiceteam 2025", slug: "Voiceteam2025"),
			ParsedCollectionEntry(name: "Voiceteam 2025: Dapper Dormice", slug: "VT2025_Dapper")
		])
	}

	@Test func parsedHeaderWithoutCollectionsReportsEmptyNotNil() {
		// Header parsed, no dd.collections: known to be in none, so a removed
		// membership can clear.
		guard let result = extractSuccess(htmlFixtureString("ao3-work-multi-chapter.html")) else { return }
		#expect(result.metadata.collections == [])
	}

	@Test func missingHeaderReportsUnknownLanguageAndCollections() {
		let html = "<html><body><div id=\"workskin\"><div class=\"chapter\" id=\"chapter-1\"><div class=\"userstuff module\" role=\"article\"><p>Text.</p></div></div></div></body></html>"
		guard let result = extractSuccess(html) else { return }
		#expect(result.metadata.language == nil)
		#expect(result.metadata.collections == nil)
	}

	// MARK: Slug

	@Test(arguments: [
		("/collections/Voiceteam2025", "Voiceteam2025"),
		("https://archiveofourown.org/collections/VT2025_Dapper", "VT2025_Dapper"),
		("/collections/Some%20Name", "Some Name"),
		("/collections/abc?page=2", "abc"),
		("/collections/abc/works", "abc")
	] as [(String, String)])
	func slugParsesFromHref(href: String, expected: String) {
		#expect(AO3ChapterHTMLExtractor.collectionSlug(fromHref: href) == expected)
	}

	@Test(arguments: [nil, "", "/users/foo", "/collections", "/collections/"] as [String?])
	func slugIsNilForOtherShapes(href: String?) {
		#expect(AO3ChapterHTMLExtractor.collectionSlug(fromHref: href) == nil)
	}

	// MARK: Listings

	@Test func searchRowsCarryAO3Language() {
		let html = htmlFixtureString("ao3-search-results-tdwp.html")
		let outcome = AO3SearchResultsExtractor.extract(fromResultsPageHTML: html, feedURL: "https://archiveofourown.org/works")
		guard case .success(let items, _, _, _) = outcome else {
			Issue.record("Expected .success")
			return
		}
		#expect(items.contains { $0.ao3Language == "English" })
		#expect(items.allSatisfy { $0.ao3Language == $0.language })
		#expect(items.allSatisfy { $0.collections == nil })
	}

	@Test func seriesListingEntriesCarryLanguage() {
		let html = htmlFixtureString("ao3-series-listing.html")
		let (works, _, _) = AO3SeriesListingExtractor.workPermalinks(fromSeriesListingHTML: html)
		#expect(works.contains { $0.language == "English" })
	}

	@Test func handBuiltListingEntryDefaultsLanguageToNil() {
		let entry = AO3SeriesListingExtractor.WorkListingEntry(workID: "1", permalink: "https://archiveofourown.org/works/1", title: "T")
		#expect(entry.language == nil)
	}

	// MARK: rebuildParsedItem

	private func article(language: String? = nil, collections: [ArticleCollectionEntry]? = nil) -> Article {
		let articleID = "test-article-id-\(UUID().uuidString)"
		return Article(accountID: "test-account-id", articleID: articleID, feedID: "test-feed-id", uniqueID: "test-unique-id", title: "Test Work", contentHTML: "<p>x</p>", contentText: nil, markdown: nil, url: "https://archiveofourown.org/works/999", externalURL: nil, summary: nil, imageURL: nil, datePublished: nil, dateModified: nil, authors: nil, language: language, collections: collections, bookKey: "ao3-work:999", status: ArticleStatus(articleID: articleID, read: false, starred: false, dateArrived: Date()))
	}

	private func extraction(language: String? = nil, collections: [ParsedCollectionEntry]? = nil) -> AO3ChapterExtractionResult {
		AO3ChapterExtractionResult(contentHTML: "<div id=\"workskin\"></div>", chapters: [AO3ExtractedChapter(id: "chapter-1", title: "Chapter 1")], metadata: AO3WorkPageMetadata(language: language, collections: collections))
	}

	@Test func rebuildTakesLiveLanguage() {
		let item = AO3FetchPolicy.rebuildParsedItem(from: article(language: "French"), workID: "999", extraction: extraction(language: "English"), applyStatsUpdate: true)
		#expect(item.ao3Language == "English")
	}

	@Test func rebuildKeepsStoredLanguageWhenLiveHasNone() {
		let item = AO3FetchPolicy.rebuildParsedItem(from: article(language: "English"), workID: "999", extraction: extraction(), applyStatsUpdate: true)
		#expect(item.ao3Language == "English")
	}

	@Test func rebuildDoesNotTouchFeedLevelLanguage() {
		let item = AO3FetchPolicy.rebuildParsedItem(from: article(language: "English"), workID: "999", extraction: extraction(language: "English"), applyStatsUpdate: true)
		#expect(item.language == nil)
	}

	@Test func rebuildKeepsStoredCollectionsWhenHeaderWasNotParsed() {
		let stored = [ArticleCollectionEntry(name: "A", slug: "a")]
		let item = AO3FetchPolicy.rebuildParsedItem(from: article(collections: stored), workID: "999", extraction: extraction(collections: nil), applyStatsUpdate: true)
		#expect(item.collections == [ParsedCollectionEntry(name: "A", slug: "a")])
	}

	@Test func rebuildEmptyLiveCollectionsReplaceStored() {
		let stored = [ArticleCollectionEntry(name: "A", slug: "a")]
		let item = AO3FetchPolicy.rebuildParsedItem(from: article(collections: stored), workID: "999", extraction: extraction(collections: []), applyStatsUpdate: true)
		#expect(item.collections == [])
	}

	@Test func rebuildTakesLiveCollections() {
		let live = [ParsedCollectionEntry(name: "B", slug: "b")]
		let item = AO3FetchPolicy.rebuildParsedItem(from: article(collections: [ArticleCollectionEntry(name: "A", slug: "a")]), workID: "999", extraction: extraction(collections: live), applyStatsUpdate: true)
		#expect(item.collections == live)
	}
}
