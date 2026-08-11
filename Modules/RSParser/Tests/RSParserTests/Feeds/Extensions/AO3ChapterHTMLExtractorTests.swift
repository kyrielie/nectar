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
		// class="series"> -- confirms seriesEntriesWithNavigation(fromDD:)
		// reads both via its descendants search rather than only the
		// first. Regression coverage, not a new feature: no code change
		// was needed for this case, since descendants(of:where:) already
		// walks all matches.
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
		// Ambrosia's own preface style (see
		// seriesEntriesWithNavigation(fromDD:)).
		#expect(result.contentHTML.contains("Part 6 of"))
		#expect(result.contentHTML.contains("Part 2 of"))

		// Beyond the rendered HTML string above, confirm the *pairing*:
		// each series' own ao3ID and parsed index attach to the right
		// name, not just that both ids/indices are present somewhere in
		// the result -- the two prior assertions above couldn't catch a
		// bug that swapped the two series' ids or indices.
		#expect(result.seriesEntries.count == 2)
		let doubleOrNothing = try #require(result.seriesEntries.first { $0.entry.name == "Double Or Nothing" })
		#expect(doubleOrNothing.entry.ao3ID == "4183855")
		#expect(doubleOrNothing.entry.index == 6)
		let jeMeSouviens = try #require(result.seriesEntries.first { $0.entry.name == "Je Me Souviens" })
		#expect(jeMeSouviens.entry.ao3ID == "4569715")
		#expect(jeMeSouviens.entry.index == 2)
	}

	@Test func previousWorkURLCapturedNextNilWhenLastInBothSeries() throws {
		// Task 10 (superseded by inline series navigation, but the fixture
		// data is still real): ao3-work-two-series.html's two
		// <span class="series"> blocks each carry the same
		// <a class="previous" href="/works/60379705"> and no
		// <a class="next"> (this work is the last part in both series
		// memberships) -- confirms seriesEntriesWithNavigation(fromDD:)
		// reads each block's own link and resolves it to an absolute URL.
		//
		// Both spans happen to carry the *same* previous URL in this
		// fixture, so this test alone can't distinguish "each series kept
		// its own value" from "the first span's value leaked to both" --
		// see seriesEntriesPairPreviousNextIndependentlyPerSeries below
		// for that regression coverage, using a synthetic fixture where
		// the two memberships genuinely differ.
		let html = htmlFixtureString("ao3-work-two-series.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}
		#expect(result.seriesEntries.count == 2)
		for span in result.seriesEntries {
			#expect(span.entry.previousWorkURL == "https://archiveofourown.org/works/60379705")
			#expect(span.entry.nextWorkURL == nil)
		}
	}

	@Test func seriesEntriesPairPreviousNextIndependentlyPerSeries() throws {
		// Synthetic fixture (ao3-work-two-series.html's two spans happen
		// to share the same previous URL and neither has a next, so it
		// can't tell "per-entry pairing" apart from "first span wins" --
		// see the note on previousWorkURLCapturedNextNilWhenLastInBothSeries
		// above). This work is a member of two series with genuinely
		// different previous/next works, mirroring
		// AO3SeriesListingExtractorTests.swift's synthetic-literal style.
		let html = """
		<html><body>
		<dl class="work meta group">
		<dt class="series">Series:</dt>
		<dd class="series">
		<span class="series"><a class="previous" href="/works/111">← Previous Work</a><a class="next" href="/works/222">Next Work →</a><span class="divider"> </span><span class="position">Part 3 of <a href="/series/1001">Series One</a></span></span>, <span class="series"><a class="previous" href="/works/333">← Previous Work</a><span class="divider"> </span><span class="position">Part 5 of <a href="/series/2002">Series Two</a></span></span>
		</dd>
		</dl>
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

		#expect(result.seriesEntries.count == 2)
		let seriesOne = try #require(result.seriesEntries.first { $0.entry.name == "Series One" })
		#expect(seriesOne.entry.ao3ID == "1001")
		#expect(seriesOne.entry.index == 3)
		#expect(seriesOne.entry.previousWorkURL == "https://archiveofourown.org/works/111")
		#expect(seriesOne.entry.nextWorkURL == "https://archiveofourown.org/works/222")

		let seriesTwo = try #require(result.seriesEntries.first { $0.entry.name == "Series Two" })
		#expect(seriesTwo.entry.ao3ID == "2002")
		#expect(seriesTwo.entry.index == 5)
		#expect(seriesTwo.entry.previousWorkURL == "https://archiveofourown.org/works/333")
		#expect(seriesTwo.entry.nextWorkURL == nil)

		// Footer block (Phase 3b): confirms serializedContentHTML appends
		// AO3PrefaceRenderer.seriesFooterHTML's output once, positioned
		// after workSkinDiv's own content marker, using the same
		// per-span data just asserted above -- top and bottom agree
		// because both read from this one parse pass.
		let workskinRange = try #require(result.contentHTML.range(of: "id=\"workskin\""))
		let footerRange = try #require(result.contentHTML.range(of: "id='ao3SeriesFooter'"))
		#expect(workskinRange.lowerBound < footerRange.lowerBound)
		// percentEncodedQueryValue only encodes "&"/"="/"?" (the query
		// string's own delimiters); ":"/"/" are otherwise valid in
		// .urlQueryAllowed and pass through unencoded, so a work URL
		// reads naturally here. The literal "&" *between* the two query
		// params (not inside either value) goes through the HTML
		// attribute escaper afterward, same as any other href -- hence
		// "&amp;" below, not "&".
		#expect(result.contentHTML.contains("href='nectar-series:first?ao3id=1001'"))
		#expect(result.contentHTML.contains("href='nectar-series:previous?ao3id=1001&amp;workurl=https://archiveofourown.org/works/111'"))
		#expect(result.contentHTML.contains("href='nectar-series:next?ao3id=1001&amp;workurl=https://archiveofourown.org/works/222'"))
		#expect(result.contentHTML.contains("href='nectar-series:first?ao3id=2002'"))
		#expect(result.contentHTML.contains("href='nectar-series:previous?ao3id=2002&amp;workurl=https://archiveofourown.org/works/333'"))
		// Series Two has no next work -- rendered as plain muted text,
		// not a nectar-series:next link (Phase 3c).
		#expect(!result.contentHTML.contains("nectar-series:next?ao3id=2002"))
		#expect(result.contentHTML.contains("<span class='ao3SeriesNavDisabled'>Next</span>"))
	}

	@Test func topPrefaceSeriesRowAlsoRendersPerEntryNavigationLinks() throws {
		// Same fixture/setup as seriesEntriesPairPreviousNextIndependentlyPerSeries
		// above, which already confirmed the *footer*'s per-entry links.
		// This test confirms the top preface row (id="ao3Preface") also
		// renders through AO3PrefaceRenderer.html(id:data:)'s
		// isSeriesNavigation branch -- one <dt>Series:</dt><dd>...</dd>
		// pair per series membership, positioned inside the preface
		// itself and ahead of #workskin, not just the trailing footer.
		let html = """
		<html><body>
		<dl class="work meta group">
		<dt class="series">Series:</dt>
		<dd class="series">
		<span class="series"><a class="previous" href="/works/111">← Previous Work</a><a class="next" href="/works/222">Next Work →</a><span class="divider"> </span><span class="position">Part 3 of <a href="/series/1001">Series One</a></span></span>, <span class="series"><a class="previous" href="/works/333">← Previous Work</a><span class="divider"> </span><span class="position">Part 5 of <a href="/series/2002">Series Two</a></span></span>
		</dd>
		</dl>
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

		let prefaceRange = try #require(result.contentHTML.range(of: "id='ao3Preface'"))
		let workskinRange = try #require(result.contentHTML.range(of: "id=\"workskin\""))
		let footerRange = try #require(result.contentHTML.range(of: "id='ao3SeriesFooter'"))
		#expect(prefaceRange.lowerBound < workskinRange.lowerBound)
		#expect(workskinRange.lowerBound < footerRange.lowerBound)

		// The preface block itself (everything before #workskin) gets its
		// own <dt>Series:</dt> pair per entry -- two memberships, two
		// pairs -- not one row with both names comma-joined into a single
		// <dd> the way every other row still renders.
		let prefaceHTML = String(result.contentHTML[result.contentHTML.startIndex..<workskinRange.lowerBound])
		let dtCount = prefaceHTML.components(separatedBy: "<dt>Series:</dt>").count - 1
		#expect(dtCount == 2)
		#expect(prefaceHTML.contains("href='nectar-series:first?ao3id=1001'"))
		#expect(prefaceHTML.contains("href='nectar-series:next?ao3id=1001&amp;workurl=https://archiveofourown.org/works/222'"))
		#expect(prefaceHTML.contains("href='nectar-series:first?ao3id=2002'"))
		#expect(prefaceHTML.contains("<span class='ao3SeriesNavDisabled'>Next</span>"))

		// Same links appear a second time in the trailing footer -- top
		// and bottom both read from the same per-span parse (2a/2b), so
		// they can't drift out of sync with each other.
		#expect(result.contentHTML.components(separatedBy: "href='nectar-series:first?ao3id=1001'").count - 1 == 2)
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

	// MARK: - Work page metadata (byline/summary/tag-groups/dates)

	@Test func metadataParsedFromMultiChapterFixture() throws {
		// ao3-work-multi-chapter.html: byline "JustLookFrightenedAndScuttle",
		// a one-paragraph summary, both Published (2026-07-07) and Updated
		// (2026-08-01) present, plus one value in every tag-group row --
		// confirmed against the fixture directly (see the diagnosis this
		// feature was built against).
		let html = htmlFixtureString("ao3-work-multi-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		let metadata = result.metadata
		#expect(metadata.authors.compactMap(\.name) == ["JustLookFrightenedAndScuttle"])
		#expect(metadata.authors.first?.url == "https://archiveofourown.org/users/JustLookFrightenedAndScuttle/pseuds/JustLookFrightenedAndScuttle")
		#expect(metadata.summary?.contains("Bitty is making it") == true)
		#expect(metadata.fandoms == ["Check Please! (Webcomic)"])
		#expect(metadata.relationships == ["Eric \"Bitty\" Bittle/Jack Zimmermann"])
		#expect(metadata.ratings == ["Teen And Up Audiences"])
		#expect(metadata.warnings == ["No Archive Warnings Apply"])
		#expect(metadata.categories == ["M/M"])
		#expect(metadata.additionalTags.contains("Getting Together") == true)

		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC")!
		if let published = metadata.datePublished {
			let components = calendar.dateComponents([.year, .month, .day], from: published)
			#expect(components.year == 2026 && components.month == 7 && components.day == 7)
		} else {
			Issue.record("Expected non-nil datePublished")
		}
		if let modified = metadata.dateModified {
			let components = calendar.dateComponents([.year, .month, .day], from: modified)
			#expect(components.year == 2026 && components.month == 8 && components.day == 1)
		} else {
			Issue.record("Expected non-nil dateModified")
		}
	}

	@Test func metadataDateModifiedNilWhenNoStatusRow() throws {
		// ao3-work-single-chapter.html's dl.stats has Published but no
		// Updated/Completed row at all (a work with no post-publish edit)
		// -- dateModified should come back nil, not some fallback value,
		// distinguishing "never updated" from "update date unknown."
		let html = htmlFixtureString("ao3-work-single-chapter.html")
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(result.metadata.dateModified == nil)
		#expect(result.metadata.datePublished != nil)
		#expect(result.metadata.authors.compactMap(\.name) == ["RainScrawl"])
		#expect(result.metadata.summary?.contains("What if Jack went first overall") == true)
	}

	@Test func metadataEmptyWhenNoMetaGroupFound() {
		// A page with #workskin/.chapter but no dl.work.meta.group at all
		// (a shape not yet sampled, or a stripped-down test page) should
		// extract successfully with an empty AO3WorkPageMetadata, not
		// crash or fail the whole extraction -- same "optional, absence
		// isn't fatal" contract parseWorkHeader already documents for the
		// metadata block as a whole.
		let html = "<html><body><div id=\"workskin\"><div class=\"chapter\" id=\"chapter-1\"><div class=\"chapter preface group\"><h3 class=\"title\">Chapter 1</h3></div><div class=\"userstuff module\" role=\"article\"><p>Text.</p></div></div></div></body></html>"
		let outcome = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html)
		guard case .success(let result) = outcome else {
			Issue.record("Expected .success, got \(outcome)")
			return
		}

		#expect(result.metadata.authors.isEmpty)
		#expect(result.metadata.summary == nil)
		#expect(result.metadata.datePublished == nil)
		#expect(result.metadata.fandoms.isEmpty)
	}
}
