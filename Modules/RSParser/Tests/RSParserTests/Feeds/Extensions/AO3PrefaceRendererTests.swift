//
//  AO3PrefaceRendererTests.swift
//  RSParser
//
//  Created for the Nectar fork.
//
//  Coverage for inline series navigation (see docs/ao3-preface-rendering.md).
//  AO3ChapterHTMLExtractorTests already
//  covers the footer builder (seriesFooterHTML) end-to-end against real and
//  synthetic fixtures, including the escaping/muted-label cases -- this
//  file targets AO3PrefaceRenderer.html(id:data:)'s isSeriesNavigation
//  branch specifically (the per-entry <dt>/<dd> preface row rendering
//  changes2 added), which had no dedicated coverage before this pass, plus
//  the shared seriesNavigationLinksHTML(ao3ID:index:previousWorkURL:nextWorkURL:)
//  helper's percent-encoding directly.
//

import Foundation
import Testing
@testable import RSParser

@Suite struct AO3PrefaceRendererTests {

	@Test func seriesRowRendersOnePairPerEntryNotCommaJoined() {
		// Two series memberships. html(id:data:) must special-case
		// isSeriesNavigation and emit one <dt>Series:</dt><dd>...</dd>
		// pair per entry (Phase 3b), not the generic single-<dd>,
		// comma-joined shape every other row uses.
		let entries = [
			AO3TagEntry(text: "Series One", href: "/series/1001", prefix: "Part 3 of ", ao3ID: "1001", previousWorkURL: "https://archiveofourown.org/works/111", nextWorkURL: "https://archiveofourown.org/works/222", index: 3),
			AO3TagEntry(text: "Series Two", href: "/series/2002", prefix: "Part 5 of ", ao3ID: "2002", previousWorkURL: "https://archiveofourown.org/works/333", nextWorkURL: nil, index: 5)
		]
		let row = AO3PrefaceRow(label: "Series:", values: entries, isSeriesNavigation: true)
		let data = AO3PrefaceData(rows: [row], statsRows: [])
		let html = AO3PrefaceRenderer.html(id: "ao3Preface", data: data)

		// class='wide' (fix #6, series row overflow): the Series row now
		// renders on its own full-width line, same as Fandom/Relationships/
		// Characters/Additional Tags, instead of being confined to the
		// narrow value column where the nowrap nav-links cluster could
		// overflow the container.
		let dtCount = (html ?? "").components(separatedBy: "<dt class='wide'>Series:</dt>").count - 1
		#expect(dtCount == 2)
		#expect(html?.contains("Series One") == true)
		#expect(html?.contains("Series Two") == true)
		// Never the old joined form -- both names in one <dd> separated by
		// ", " -- which the isSeriesNavigation branch opts out of entirely.
		#expect(html?.contains("Series One</a>, ") != true)
	}

	@Test func seriesRowLinkedNextAndPlainPreviousLabelPerEntry() {
		// One entry with a captured next link, one first-in-series entry
		// with previousWorkURL nil -- confirms the per-entry pairing
		// survives into the rendered preface row, not just the footer
		// (which AO3ChapterHTMLExtractorTests already covers).
		let entries = [
			AO3TagEntry(text: "Has Next", ao3ID: "1001", previousWorkURL: nil, nextWorkURL: "https://archiveofourown.org/works/222", index: 2)
		]
		let row = AO3PrefaceRow(label: "Series:", values: entries, isSeriesNavigation: true)
		let html = AO3PrefaceRenderer.html(id: "ao3Preface", data: AO3PrefaceData(rows: [row], statsRows: []))

		#expect(html?.contains("href='nectar-series:next?ao3id=1001&amp;workurl=https://archiveofourown.org/works/222'") == true)
		#expect(html?.contains("<span class='ao3SeriesNavDisabled'>Previous</span>") == true)
	}

	@Test func ambrosiaSourcedEntryFirstLinkedPreviousNextGrayed() {
		// Ambrosia's _ambrosia.series entries carry ao3_id but never a
		// previous/next-work-URL key (plan's 3b revision note, confirmed
		// against JSONFeedParser.parseAmbrosiaSeries) -- a synthetic-
		// preface series row must still render a live, tappable First
		// link while Previous/Next fall out as the grayed, unlinked
		// state, purely from previousWorkURL/nextWorkURL being nil (no
		// special-casing for the Ambrosia case specifically). index: 4
		// (not 1) keeps this fixture on the "linked" branch -- the
		// index == 1 case (First itself disabled) has its own dedicated
		// test below.
		let entries = [AO3TagEntry(text: "Some Series", prefix: "Part 4 of ", ao3ID: "9999", previousWorkURL: nil, nextWorkURL: nil, index: 4)]
		let row = AO3PrefaceRow(label: "Series:", values: entries, isSeriesNavigation: true)
		let html = AO3PrefaceRenderer.html(id: "ao3SyntheticPreface", data: AO3PrefaceData(rows: [row], statsRows: []))

		#expect(html?.contains("href='nectar-series:first?ao3id=9999'") == true)
		#expect(html?.contains("<span class='ao3SeriesNavDisabled'>Previous</span>") == true)
		#expect(html?.contains("<span class='ao3SeriesNavDisabled'>Next</span>") == true)
	}

	@Test func nonSeriesRowsStillUseGenericCommaJoinedShape() {
		// Regression guard: isSeriesNavigation only special-cases the row
		// it's set on. Any other row (fandom, relationships, etc.) must
		// keep rendering through the original single-<dd>, comma-joined
		// path untouched.
		let fandomRow = AO3PrefaceRow(label: "Fandom:", values: [AO3TagEntry(text: "Fandom One", href: "/tags/1"), AO3TagEntry(text: "Fandom Two", href: "/tags/2")], isWide: true)
		let html = AO3PrefaceRenderer.html(id: "ao3Preface", data: AO3PrefaceData(rows: [fandomRow], statsRows: []))

		#expect(html?.contains("<dt class='wide'>Fandom:</dt><dd class='wide'><a href='/tags/1'>Fandom One</a>, <a href='/tags/2'>Fandom Two</a></dd>") == true)
	}

	@Test func percentEncodingRoundTripsReservedCharsInWorkURL() {
		// Regression coverage for the escaping gap called out in the
		// plan's 3a: a work permalink carrying its own query string
		// ("&"/"="/"?", all three stripped from
		// .nectarSeriesQueryValueAllowed) must have every one of those
		// percent-encoded before assembly, or they'd corrupt this app's
		// own "&"-delimited nectar-series: query string's delimiters.
		// ":"/"/" stay literal (still permitted by .urlQueryAllowed).
		let workURL = "https://archiveofourown.org/works/1?view_adult=true&view_full_work=true"
		let entries = [AO3TagEntry(text: "Weird URL Series", ao3ID: "555", previousWorkURL: workURL, nextWorkURL: nil, index: 2)]
		let row = AO3PrefaceRow(label: "Series:", values: entries, isSeriesNavigation: true)
		let html = AO3PrefaceRenderer.html(id: "ao3Preface", data: AO3PrefaceData(rows: [row], statsRows: []))

		// Every reserved "?"/"="/"&" from the work URL's own query string
		// is percent-encoded (%3F/%3D/%26); the one "&" that legitimately
		// separates this app's own ao3id/workurl params survives as the
		// literal query delimiter, then gets HTML-attribute-escaped to
		// "&amp;" like any other href, same as
		// AO3ChapterHTMLExtractorTests's existing footer assertions.
		#expect(html?.contains("workurl=https://archiveofourown.org/works/1%3Fview_adult%3Dtrue%26view_full_work%3Dtrue'") == true)
		#expect(html?.contains("ao3id=555&amp;workurl=") == true)
	}

	@Test func firstRendersDisabledWhenIndexIsOne() {
		// index == 1 means this entry already is the first work in its
		// series -- First must render as the same disabled/muted label
		// as the ao3ID == nil case, even though ao3ID is populated here,
		// since there's nowhere further to navigate.
		let entries = [AO3TagEntry(text: "Series Opener", ao3ID: "4242", previousWorkURL: nil, nextWorkURL: "https://archiveofourown.org/works/999", index: 1)]
		let row = AO3PrefaceRow(label: "Series:", values: entries, isSeriesNavigation: true)
		let html = AO3PrefaceRenderer.html(id: "ao3Preface", data: AO3PrefaceData(rows: [row], statsRows: []))

		#expect(html?.contains("<span class='ao3SeriesNavDisabled'>First</span>") == true)
		#expect(html?.contains("nectar-series:first?ao3id=4242") != true)
		// Next still links normally -- only First is affected by index == 1.
		#expect(html?.contains("href='nectar-series:next?ao3id=4242&amp;workurl=https://archiveofourown.org/works/999'") == true)
	}
}
