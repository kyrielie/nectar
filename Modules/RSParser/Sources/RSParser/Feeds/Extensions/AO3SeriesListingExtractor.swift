//
//  AO3SeriesListingExtractor.swift
//  RSParser
//
//  Nectar AO3 direct-reading support, Task 10 ("Prev/next/first
//  navigation -- independent of the grouping toggle") -- see
//  nectar-ao3-features-plan-FINAL.md. AO3's work page carries
//  previous/next Work links but no "first work in series" link anywhere
//  (see AO3ChapterHTMLExtractor.previousNextWorkURLs's doc comment) --
//  reaching work #1 needs the series-listing page itself
//  (`GET .../series/<id>`), fetched lazily only when the reader's
//  "First work" button is tapped.
//
//  Confirmed against a real captured series-listing page
//  (archiveofourown.org/series/348731, 2026-08 -- "for all of the
//  perfect things that i doubt", one <li> per work in ascending Part
//  order): each work row is `<li id="work_<id>" class="work blurb
//  group work-<id> user-<id>" role="article">` under `<ul class="series
//  work index group">` -- byte-for-byte the same "work blurb" partial
//  AO3 reuses for search results (confirmed identical row/title
//  selectors to AO3SearchResultsExtractor's own "confirmed selectors"
//  -- also cross-checked against ao3downloader's
//  parse_soup.get_work_metadata_from_list, which reads a work blurb the
//  identical way: `li.work-<id>` then `h4.heading a` for title+permalink,
//  read for approach only, reimplemented independently here, per the
//  licensing note in nectar-ao3-features-plan-FINAL.md). Only the
//  container's own class (`series work index group`, vs search results'
//  plain `work index group`) differs -- not relied on here, since the
//  row selector alone is sufficient and already proven stable across
//  both listing types. The checked-in fixture (`ao3-series-listing.html`)
//  is a single-page capture of this series' page 1 only -- 10 work
//  rows, confirmed via `grep -c 'work-[0-9]*'` -- not the whole
//  (longer, multi-page) series; don't infer the fixture's row count
//  says anything about the real series' total length.
//
//  Inline-series-navigation plan, Phase 4a:
//  `workPermalinks(fromSeriesListingHTML:)` extends this beyond "first
//  work only" to every work row on one fetched listing page, whether a
//  further page exists (`li.next > a[href]`), and the pagination
//  widget's total page count when present. Still deliberately
//  page-scoped: this file parses whatever single page it's given, it
//  does not itself walk pagination -- the two-fetch-cap walk lives in
//  `AO3SeriesNavigator.openSeriesWork`.
//

import Foundation

public enum AO3SeriesListingExtractor {

	/// The AO3-absolute permalink of the first (lowest "Part N") work
	/// listed on this series page, or nil if no work row was found (an
	/// empty/deleted series, a registration wall, or a page shape this
	/// hasn't been sampled against). Series pages list works in
	/// ascending part order on page 1 -- confirmed against the captured
	/// fixture -- so the first row in document order is always work #1;
	/// no pagination handling is needed here even for a long series,
	/// since #1 is never on a later page.
	public static func firstWorkPermalink(fromSeriesListingHTML html: String) -> String? {
		let root = parseHTMLLiteTree(html)
		guard let firstLI = firstDescendant(of: root, where: { isWorkRow($0) }) else {
			return nil
		}
		guard let headingH4 = firstDescendant(of: firstLI, where: { $0.tag == "h4" && classTokens(of: $0).contains("heading") }),
		      let titleAnchor = firstDescendant(of: headingH4, where: { $0.tag == "a" }) else {
			return nil
		}
		return absoluteURL(titleAnchor.attributes["href"])
	}

	/// One entry per work row on this page, in document order (ascending
	/// Part order -- see header comment), whether AO3's own `li.next`
	/// pagination widget shows a further page, and the widget's total page
	/// count when present. Reuses `isWorkRow`/`absoluteURL` above (same
	/// row/link shape `firstWorkPermalink` already validated) rather than
	/// a separate selector, and reuses `AO3SearchResultsExtractor`'s own
	/// row-metadata helpers for the richer fields below -- the two listing
	/// types share byte-for-byte the same "work blurb" row shape (see
	/// header comment), so the same summary/tag/stat parsing applies
	/// unchanged.
	public static func workPermalinks(fromSeriesListingHTML html: String) -> (permalinks: [WorkListingEntry], hasNextPage: Bool, totalPages: Int?) {
		let root = parseHTMLLiteTree(html)
		let workRows = descendants(of: root, where: { isWorkRow($0) })

		let entries: [WorkListingEntry] = workRows.compactMap { li in
			guard let workID = workID(fromLI: li) else { return nil }
			guard let headingH4 = firstDescendant(of: li, where: { $0.tag == "h4" && classTokens(of: $0).contains("heading") }),
			      let titleAnchor = firstDescendant(of: headingH4, where: { $0.tag == "a" }),
			      let permalink = absoluteURL(titleAnchor.attributes["href"]) else {
				return nil
			}
			let title = flattenedText(titleAnchor)
			return WorkListingEntry(
				workID: workID,
				permalink: permalink,
				title: title,
				summary: AO3SearchResultsExtractor.summaryHTML(fromLI: li),
				fandoms: AO3SearchResultsExtractor.tagTexts(in: li, tag: "h5", classToken: "fandoms"),
				relationships: AO3SearchResultsExtractor.tagTexts(in: li, tag: "li", classToken: "relationships"),
				characters: AO3SearchResultsExtractor.tagTexts(in: li, tag: "li", classToken: "characters"),
				freeformTags: AO3SearchResultsExtractor.tagTexts(in: li, tag: "li", classToken: "freeforms"),
				warnings: AO3SearchResultsExtractor.tagTexts(in: li, tag: "li", classToken: "warnings"),
				ratings: AO3SearchResultsExtractor.symbolTexts(in: li, classToken: "rating"),
				categories: AO3SearchResultsExtractor.symbolTexts(in: li, classToken: "category"),
				wordCount: AO3SearchResultsExtractor.intValue(fromDD: li, classToken: "words")
			)
		}

		return (entries, AO3ListingPagination.hasNextPage(root), AO3ListingPagination.totalPages(root))
	}

	/// One work row from a series-listing page. Extended (inline-series-
	/// navigation plan, Phase 4b/listing-metadata follow-up) beyond the
	/// original bare `(workID, permalink, title)` to reuse
	/// `AO3SearchResultsExtractor`'s row-metadata helpers directly against
	/// the identical row shape -- the series-listing fixture already
	/// contains this data (`dd.words`, `blockquote.summary`, etc.), it was
	/// simply unread before. Every series member other than the one
	/// actually being opened still stays a stub with no `contentHTML`
	/// until it's next opened directly (see `AO3SeriesNavigator`'s stub
	/// builder) -- only the placeholder's metadata gets richer, not its
	/// fetch timing.
	public struct WorkListingEntry: Equatable, Sendable {
		public let workID: String
		public let permalink: String
		public let title: String
		public let summary: String?
		public let fandoms: [String]
		public let relationships: [String]
		public let characters: [String]
		public let freeformTags: [String]
		public let warnings: [String]
		public let ratings: [String]
		public let categories: [String]
		public let wordCount: Int?

		public init(workID: String, permalink: String, title: String, summary: String? = nil, fandoms: [String] = [], relationships: [String] = [], characters: [String] = [], freeformTags: [String] = [], warnings: [String] = [], ratings: [String] = [], categories: [String] = [], wordCount: Int? = nil) {
			self.workID = workID
			self.permalink = permalink
			self.title = title
			self.summary = summary
			self.fandoms = fandoms
			self.relationships = relationships
			self.characters = characters
			self.freeformTags = freeformTags
			self.warnings = warnings
			self.ratings = ratings
			self.categories = categories
			self.wordCount = wordCount
		}
	}
}

private extension AO3SeriesListingExtractor {

	/// Identical row shape to `AO3SearchResultsExtractor.isWorkRow`
	/// (`li.work-<id>`) -- shared via `AO3HTMLHelpers.isWorkRow`.
	static func isWorkRow(_ element: HTMLLiteElement) -> Bool {
		AO3HTMLHelpers.isWorkRow(element)
	}

	static func workID(fromLI element: HTMLLiteElement) -> String? {
		AO3HTMLHelpers.workID(fromLI: element)
	}

	static func classTokens(of element: HTMLLiteElement) -> [String] {
		AO3HTMLHelpers.classTokens(of: element)
	}

	static func absoluteURL(_ href: String?) -> String? {
		AO3HTMLHelpers.absoluteURL(href)
	}
}
