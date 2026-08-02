//
//  AO3ChapterHTMLExtractorTests.swift
//  RSParser
//
//  Created for the Nectar fork.
//

import Foundation
import Testing
@testable import RSParser

@Suite struct AO3ChapterHTMLExtractorTests {

	@Test func nonAO3PageReturnsNil() {
		let result = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: "<html><body><p>Not a work page.</p></body></html>")
		#expect(result == nil)
	}

	// MARK: - Multi-chapter, no workskin (ao3-work-multi-chapter.html, from entire.html)

	@Test func multiChapterCountAndOrder() throws {
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let result = try #require(AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html))

		#expect(result.chapters.count == 12)
		#expect(result.chapters.map(\.id) == (1...12).map { "chapter-\($0)" })
		#expect(result.chapters.first?.title == "Chapter 1")
	}

	@Test func multiChapterOwnSubtitlePreserved() throws {
		// Chapter 2 of this fixture has its own title beyond "Chapter 2" --
		// confirms the extractor reads the whole heading's text, not just
		// its <a> child.
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let result = try #require(AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html))
		let chapter2 = try #require(result.chapters.first { $0.id == "chapter-2" })
		#expect(chapter2.title.hasPrefix("Chapter 2"))
	}

	@Test func noSkinStillWrapsCleanly() throws {
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let result = try #require(AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html))

		#expect(!result.contentHTML.contains("<style"))
		#expect(result.contentHTML.contains("id=\"workskin\""))
	}

	@Test func landmarkHeadingStrippedAndTitleRewritten() throws {
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let result = try #require(AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html))

		#expect(!result.contentHTML.contains("id=\"work\">Chapter Text"))
		#expect(result.contentHTML.contains("<h2 class=\"heading\">"))
		#expect(!result.contentHTML.contains("<h3 class=\"title\">"))
	}

	@Test func chapterSummaryIsKeptNotStripped() throws {
		// Chapter 2 of this fixture has a populated chapter-level summary --
		// confirm extraction doesn't drop it.
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let result = try #require(AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html))

		#expect(result.contentHTML.contains("In which Bitty has lunch with some of the Falcs"))
	}

	@Test func onlyChapterDivsProcessedChromeIgnored() throws {
		// Chapter-index dropdown / nav chrome elsewhere on the live page
		// (outside #workskin) must not be picked up as chapters.
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let result = try #require(AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html))
		#expect(result.chapters.count == 12)
	}

	// MARK: - Workskin fixture (ao3-work-workskin.html, from workskinentire.html)

	@Test func workskinStyleAndWrapperBothCaptured() throws {
		let html = htmlFixtureString("ao3-work-workskin.html")
		let result = try #require(AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html))

		#expect(result.contentHTML.contains("<style"))
		#expect(result.contentHTML.contains("#workskin .juice"))
		#expect(result.contentHTML.contains("id=\"workskin\""))
		#expect(result.chapters.count == 3)
	}

	@Test func workskinChapterCountAndTitles() throws {
		let html = htmlFixtureString("ao3-work-workskin.html")
		let result = try #require(AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html))

		#expect(result.chapters.map(\.id) == ["chapter-1", "chapter-2", "chapter-3"])
		let chapter2 = try #require(result.chapters.first { $0.id == "chapter-2" })
		#expect(chapter2.title.hasPrefix("Chapter 2"))
	}

	// MARK: - TOC regression

	@Test func workTitleIsNotAToCHeading() throws {
		// tocNodes() (main_ios.js) collects h1, h2.heading, h2.toc-heading.
		// The work's own title must not survive as an h2.heading -- only
		// the rewritten chapter titles should.
		let html = htmlFixtureString("ao3-work-workskin.html")
		let result = try #require(AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html))

		let root = parseHTMLLiteTree(result.contentHTML)
		let tocHeadings = descendants(of: root, where: {
			($0.tag == "h1") || ($0.tag == "h2" && ($0.attributes["class"] == "heading" || $0.attributes["class"] == "toc-heading"))
		})

		#expect(tocHeadings.count == 3)
		for heading in tocHeadings {
			#expect(!flattenedText(heading).contains("Borrow Somebody's Dreams Till Tomorrow"))
		}
	}
}
