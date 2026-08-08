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

	@Test func nonAO3PageReturnsNotFound() {
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: "<html><body><p>Not a work page.</p></body></html>")
		guard case .notFound = outcome else {
			Issue.record("Expected .notFound, got \(outcome)")
			return
		}
	}

	@Test func adultContentGateDetected() {
		let html = htmlFixtureString("ao3-work-adult-content-gate.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .adultContentGate = outcome else {
			Issue.record("Expected .adultContentGate, got \(outcome)")
			return
		}
	}

	@Test func registrationRequiredDetected() {
		let html = "<html><body><div id=\"signin\"><h3 class=\"heading\">Sorry!</h3><p>This work is only available to registered users of the Archive.</p></div></body></html>"
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .registrationRequired = outcome else {
			Issue.record("Expected .registrationRequired, got \(outcome)")
			return
		}
	}

	// MARK: - CSRF token (Task 6: kudos-on-like)

	@Test func csrfTokenExtractedFromMetaTag() throws {
		let html = htmlFixtureString("ao3-work-single-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}
		#expect(result.csrfToken == "R05MDFtZglfVv9eV-g7azfaIvQ64LHUdTpj5R0-nVwUNXII-BLARRpIkU50mmpImCuMgPwZv46VR6RlBL3gjIg")
	}

	@Test func csrfTokenNilWhenMetaTagMissing() throws {
		let html = htmlFixtureString("ao3-work-multi-chapter.html").replacingOccurrences(of: "<meta name=\"csrf-token\"", with: "<meta name=\"not-csrf-token\"")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}
		#expect(result.csrfToken == nil)
	}

	// MARK: - Multi-chapter, no workskin (ao3-work-multi-chapter.html, from entire.html)

	@Test func multiChapterCountAndOrder() throws {
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(result.chapters.count == 12)
		#expect(result.chapters.map(\.id) == (1...12).map { "chapter-\($0)" })
		#expect(result.chapters.first?.title == "Chapter 1")
	}

	@Test func multiChapterOwnSubtitlePreserved() throws {
		// Chapter 2 of this fixture has its own title beyond "Chapter 2" --
		// confirms the extractor reads the whole heading's text, not just
		// its <a> child.
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}
		let chapter2 = try #require(result.chapters.first { $0.id == "chapter-2" })
		#expect(chapter2.title.hasPrefix("Chapter 2"))
	}

	@Test func noSkinStillWrapsCleanly() throws {
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(!result.contentHTML.contains("<style"))
		#expect(result.contentHTML.contains("id=\"workskin\""))
	}

	@Test func landmarkHeadingStrippedAndTitleRewritten() throws {
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(!result.contentHTML.contains("id=\"work\">Chapter Text"))
		#expect(result.contentHTML.contains("<h2 class=\"heading\">"))
		#expect(!result.contentHTML.contains("<h3 class=\"title\">"))
	}

	@Test func chapterSummaryIsKeptNotStripped() throws {
		// Chapter 2 of this fixture has a populated chapter-level summary --
		// confirm extraction doesn't drop it.
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(result.contentHTML.contains("In which Bitty has lunch with some of the Falcs"))
	}

	@Test func onlyChapterDivsProcessedChromeIgnored() throws {
		// Chapter-index dropdown / nav chrome elsewhere on the live page
		// (outside #workskin) must not be picked up as chapters.
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}
		#expect(result.chapters.count == 12)
	}

	// MARK: - Workskin fixture (ao3-work-workskin.html, from workskinentire.html)

	@Test func workskinStyleAndWrapperBothCaptured() throws {
		let html = htmlFixtureString("ao3-work-workskin.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(result.contentHTML.contains("<style"))
		#expect(result.contentHTML.contains("#workskin .juice"))
		#expect(result.contentHTML.contains("id=\"workskin\""))
		#expect(result.chapters.count == 3)
	}

	@Test func workskinChapterCountAndTitles() throws {
		let html = htmlFixtureString("ao3-work-workskin.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(result.chapters.map(\.id) == ["chapter-1", "chapter-2", "chapter-3"])
		let chapter2 = try #require(result.chapters.first { $0.id == "chapter-2" })
		#expect(chapter2.title.hasPrefix("Chapter 2"))
	}

	// MARK: - Single-chapter (ao3-work-single-chapter.html, from a real work: 87955346)

	@Test func singleChapterHasNoChapterDivButStillExtracts() throws {
		// This work ("Chapters: 1/1") carries no <div class="chapter"> at
		// all -- AO3 renders a single-chapter work's body directly inside
		// <div id="chapters" role="article">. Previously this fell through
		// to .notFound and was misreported as gated/removed even though
		// view_adult=true had already gotten past the real gate.
		let html = htmlFixtureString("ao3-work-single-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(result.chapters.count == 1)
		#expect(result.chapters.first?.id == "chapter-1")
	}

	@Test func singleChapterLandmarkHeadingStripped() throws {
		let html = htmlFixtureString("ao3-work-single-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(!result.contentHTML.contains("id=\"work\">Work Text:"))
		#expect(result.contentHTML.contains("Listen or download via google drive"))
	}

	// MARK: - Work Header metadata block

	@Test func workHeaderRenderedForMultiChapterWork() throws {
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		// The Work Header is now parsed and re-rendered through
		// AO3PrefaceRenderer, not captured verbatim -- confirm it lands as
		// its own unit ahead of the workskin, using the shared preface
		// markup (id="ao3Preface", dl.tags) rather than AO3's own
		// "work meta group" class.
		#expect(result.contentHTML.contains("id='ao3Preface'"))
		#expect(!result.contentHTML.contains("class=\"work meta group\""))
		// Real, AO3-encoded tag link ("M/M" -> "M*s*M") -- confirms hrefs
		// are read directly off the source <a> elements, not synthesized.
		#expect(result.contentHTML.contains("href='/tags/M*s*M/works'"))
		#expect(result.contentHTML.contains("Check Please! (Webcomic)"))
	}

	@Test func workHeaderStatsCountsParsedForMultiChapterWork() throws {
		// Same fixture's dl.stats -- confirmed values: Comments: 272,
		// Kudos: 113, Bookmarks: 14 (wrapped in an <a>, so this also
		// confirms flattenedText is used rather than the dd's direct
		// text), Hits: 1,776 (comma-formatted, parsed with commas
		// stripped), Words: 50,038 (Task 8's regression-guard field).
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(result.commentCount == 272)
		#expect(result.kudosCount == 113)
		#expect(result.bookmarkCount == 14)
		#expect(result.hitCount == 1776)
		#expect(result.wordCount == 50038)
	}

	@Test func workHeaderStatsCountsNilWhenMetadataBlockAbsent() throws {
		// A minimal work page with a workskin+chapter but no
		// dl.work.meta.group at all (matches the two known gate pages,
		// and any future page shape not yet sampled) -- confirms
		// extraction still succeeds and the stats counts default to nil
		// rather than 0 or crashing.
		let html = """
		<html><body>
		<div id="workskin">
		<div class="chapter" id="chapter-1">
		<div class="chapter preface group"><h3 class="title">Chapter 1</h3></div>
		<div class="userstuff module" role="article">Body text.</div>
		</div>
		</div>
		</body></html>
		"""
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(result.commentCount == nil)
		#expect(result.kudosCount == nil)
		#expect(result.bookmarkCount == nil)
		#expect(result.hitCount == nil)
		#expect(result.wordCount == nil)
	}

	@Test func seriesRowHandlesTwoCommaSeparatedSeries() throws {
		// ao3-work-two-series.html: a work belonging to two series at once
		// ("Double Or Nothing" and "Je Me Souviens"), each rendered as its
		// own comma-separated <span class="series"> inside one <dd
		// class="series"> -- confirms seriesEntries(fromDD:) reads both via
		// its descendants search rather than only the first. Regression
		// coverage, not a new feature: no code change was needed for this
		// case, since descendants(of:where:) already walks all matches.
		let html = htmlFixtureString("ao3-work-two-series.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(result.contentHTML.contains("href='/series/4183855'"))
		#expect(result.contentHTML.contains("Double Or Nothing"))
		#expect(result.contentHTML.contains("href='/series/4569715'"))
		#expect(result.contentHTML.contains("Je Me Souviens"))
		// Only the linked series name comes from the anchor text; the "Part
		// <N> of " prefix ahead of it is unlinked plain text, matching
		// Ambrosia's own preface style (see seriesEntries(fromDD:)).
		#expect(result.contentHTML.contains("Part 6 of"))
		#expect(result.contentHTML.contains("Part 2 of"))
	}

	@Test func previousWorkURLCapturedNextNilWhenLastInBothSeries() throws {
		// Task 10: ao3-work-two-series.html's two <span class="series">
		// blocks each carry the same <a class="previous"
		// href="/works/60379705"> and no <a class="next"> (this work is
		// the last part in both series memberships) -- confirms
		// previousNextWorkURLs(fromDD:) reads the first block's link for
		// each direction and resolves it to an absolute URL.
		let html = htmlFixtureString("ao3-work-two-series.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}
		#expect(result.previousWorkURL == "https://archiveofourown.org/works/60379705")
		#expect(result.nextWorkURL == nil)
	}

	@Test func metaGroupCollectionsRowRenderedForSingleChapterWork() throws {
		// This fixture's Work Header includes a Collections row -- the only
		// one of the four fixtures that does. Confirms a row this app
		// doesn't special-case by name (no dedicated Article field for
		// collections) still comes through the tags/collections generic
		// link-reading path rather than being silently dropped, now that
		// the block is parsed field-by-field instead of captured whole.
		let html = htmlFixtureString("ao3-work-single-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(result.contentHTML.contains("href='/collections/Voiceteam2025'"))
		#expect(result.contentHTML.contains("Voiceteam 2025"))
		#expect(result.contentHTML.contains("href='/collections/VT2025_Dapper'"))
	}

	@Test func metaGroupPrecedesStyleAndWorkskin() throws {
		let html = htmlFixtureString("ao3-work-workskin.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		let metaRange = try #require(result.contentHTML.range(of: "id='ao3Preface'"))
		let styleRange = try #require(result.contentHTML.range(of: "<style"))
		let workskinRange = try #require(result.contentHTML.range(of: "id=\"workskin\""))
		#expect(metaRange.lowerBound < styleRange.lowerBound)
		#expect(styleRange.lowerBound < workskinRange.lowerBound)
	}

	// MARK: - TOC regression

	@Test func workTitleIsNotAToCHeading() throws {
		// tocNodes() (main_ios.js) collects h1, h2.heading, h2.toc-heading.
		// The work's own title must not survive as an h2.heading -- only
		// the rewritten chapter titles should.
		let html = htmlFixtureString("ao3-work-workskin.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		let root = parseHTMLLiteTree(result.contentHTML)
		let tocHeadings = descendants(of: root, where: {
			($0.tag == "h1") || ($0.tag == "h2" && ($0.attributes["class"] == "heading" || $0.attributes["class"] == "toc-heading"))
		})

		#expect(tocHeadings.count == 3)
		for heading in tocHeadings {
			#expect(!flattenedText(heading).contains("Borrow Somebody's Dreams Till Tomorrow"))
		}
	}

	@Test func singleChapterWorkTitleIsNotAToCHeading() throws {
		// A single-chapter work's own preface title must not survive as
		// any tocNodes()-matching heading (h1, h2.heading, or
		// h2.toc-heading) in the *extracted* contentHTML -- same
		// treatment as the multi-chapter branch's workTitleIsNotAToCHeading
		// above, via the same stripPhantomTitleHeadingClass call.
		//
		// This intentionally does NOT assert an h1 shows up here. An
		// earlier version of this fix rewrote the title to <h1> instead
		// of stripping it, reasoning that tocNodes() would otherwise find
		// nothing to show for a single-chapter work. That's true of this
		// extractor's own output in isolation, but the assembled article
		// page always has its own top-level <h1> already, from
		// template.html's `<div class="articleTitle"><h1>...`, which is
		// what's meant to serve that role -- see
		// TableOfContentsViewController's fallback to the lone <h1> entry
		// when there are no <h2> chapters. Promoting AO3's own title to a
		// second <h1> here doubled that up: the assembled page ended up
		// with two <h1>s, which made TableOfContentsViewController treat
		// the work as a (degenerate, two-row) anthology instead of a
		// single book with one entry. See
		// singleChapterWorkTemplateHeadingIsTheOnlyTocEntry below for the
		// full assembled-page shape this is protecting.
		let html = htmlFixtureString("ao3-work-single-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		let root = parseHTMLLiteTree(result.contentHTML)
		let tocHeadings = descendants(of: root, where: {
			($0.tag == "h1") || ($0.tag == "h2" && ($0.attributes["class"] == "heading" || $0.attributes["class"] == "toc-heading"))
		})

		#expect(tocHeadings.isEmpty)
	}

	@Test func singleChapterWorkTemplateHeadingIsTheOnlyTocEntry() throws {
		// End-to-end shape of the page tocNodes() actually runs against:
		// template.html's own `<div class="articleTitle"><h1>...` wrapper
		// around the article title, followed by this extractor's
		// contentHTML. For a single-chapter work that contentHTML has no
		// heading of its own (previous test), so the template's <h1>
		// should be the one and only tocNodes() match -- not zero (the
		// original empty-ToC bug) and not two (the regression this fix
		// replaces).
		let html = htmlFixtureString("ao3-work-single-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		let assembledPage = "<div class=\"articleTitle\"><h1>Some Work Title</h1></div>" + result.contentHTML
		let root = parseHTMLLiteTree(assembledPage)
		let tocHeadings = descendants(of: root, where: {
			($0.tag == "h1") || ($0.tag == "h2" && ($0.attributes["class"] == "heading" || $0.attributes["class"] == "toc-heading"))
		})

		#expect(tocHeadings.count == 1)
		#expect(tocHeadings.first?.tag == "h1")
	}
}
