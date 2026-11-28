//
//  EPUB3GeneratorTests.swift
//  NetNewsWire-iOSTests
//
//  Verifies normalized preface HTML (<dl class="tags tags-dl">, AO3 tag URL
//  escaping, multi-series, WIP chapters, canonical work link, Language/Stats
//  rows) and opt-in annotation export (off by default).
//

import Foundation
import Testing
import Articles
@testable import Nectar

@MainActor @Suite struct EPUB3GeneratorTests {

	private static func makeArticle() -> Article {
		let status = ArticleStatus(articleID: "art-1", read: false, starred: false, dateArrived: Date())
		return Article(
			accountID: "acct-1",
			articleID: "art-1",
			feedID: "feed-1",
			uniqueID: "12345",
			title: "Test Work",
			contentHTML: "<div id=\"chapters\"><div class=\"chapter\" id=\"chapter-1\"><h3 class=\"title\">Chapter 1</h3><p>This is a full chapter body with enough story content to pass the non-stub check in EPUB3Generator.</p></div></div>",
			contentText: nil,
			markdown: nil,
			url: "https://archiveofourown.org/works/12345?view_adult=true",
			externalURL: nil,
			summary: "<p>A short summary.</p>",
			imageURL: nil,
			datePublished: Date(timeIntervalSince1970: 1_700_000_000),
			dateModified: Date(timeIntervalSince1970: 1_700_100_000),
			authors: Author(authorID: "auth-1", name: "AuthorOne", url: nil, avatarURL: nil, emailAddress: nil).map { [$0] },
			wordCount: 1234,
			chapterCurrent: 5,
			chapterTotal: nil,
			isComplete: false,
			fandoms: ["Original Work"],
			relationships: ["A/B & C"],
			characters: nil,
			ratings: ["General Audiences"],
			warnings: nil,
			categories: ["M/M"],
			additionalTags: ["Dr. Who"],
			series: [
				ArticleSeriesEntry(name: "Series One", index: 1, ao3ID: "100"),
				ArticleSeriesEntry(name: "Series Two", index: 4, ao3ID: "200")
			],
			kudosCount: 42,
			language: "English",
			bookKey: "ao3-work:12345",
			status: status
		)
	}

	@Test func normalizedPrefaceIncludesLinksMultiSeriesWIPChaptersStatsAndLanguage() {
		let article = Self.makeArticle()
		let preface = EPUB3Generator.buildPrefaceHTML(
			article: article,
			authorStr: "AuthorOne",
			language: "en",
			hasWorkskin: false
		)

		#expect(preface.contains("<dl class=\"tags tags-dl\">"))
		#expect(preface.contains("Posted originally on the Archive of Our Own at <a href=\"https://archiveofourown.org/works/12345\">https://archiveofourown.org/works/12345</a>."))
		#expect(preface.contains("https://archiveofourown.org/tags/A*s*B%20*a*%20C/works"))
		#expect(preface.contains("https://archiveofourown.org/tags/Dr*d*%20Who/works"))
		#expect(preface.contains("Part 1 of <a href=\"https://archiveofourown.org/series/100\">Series One</a>"))
		#expect(preface.contains("Part 4 of <a href=\"https://archiveofourown.org/series/200\">Series Two</a>"))
		#expect(preface.contains("<dt>Language:</dt><dd>English</dd>"))
		#expect(preface.contains("<dt>Stats:</dt><dd>"))
		#expect(preface.contains("Chapters: 5/?"))
	}

	@Test func includeAnnotationsDefaultsToFalse() async throws {
		#expect(!AppDefaults.shared.includeAnnotationsInEPUBExport)
		#expect(AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.includeAnnotationsInEPUBExport))

		let article = Self.makeArticle()
		let epubURL = try await EPUB3Generator.generateEPUB(for: article, account: nil, includeAnnotations: false)
		defer { try? FileManager.default.removeItem(at: epubURL) }

		let zipData = try Data(contentsOf: epubURL)
		#expect(zipData.range(of: Data("EPUB/text/preface.xhtml".utf8)) != nil)
		#expect(zipData.range(of: Data("EPUB/text/reader-notes.xhtml".utf8)) == nil)
		#expect(zipData.range(of: Data("EPUB/css/annotations.css".utf8)) == nil)
	}
}
