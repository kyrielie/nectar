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
//  perfect things that i doubt", 40 works, one <li> per work in
//  ascending Part order): each work row is `<li id="work_<id>"
//  class="work blurb group work-<id> user-<id>" role="article">` under
//  `<ul class="series work index group">` -- byte-for-byte the same
//  "work blurb" partial AO3 reuses for search results (confirmed
//  identical row/title selectors to AO3SearchResultsExtractor's own
//  "confirmed selectors" -- also cross-checked against ao3downloader's
//  parse_soup.get_work_metadata_from_list, which reads a work blurb the
//  identical way: `li.work-<id>` then `h4.heading a` for title+permalink,
//  read for approach only, reimplemented independently here, per the
//  licensing note in nectar-ao3-features-plan-FINAL.md). Only the
//  container's own class (`series work index group`, vs search results'
//  plain `work index group`) differs -- not relied on here, since the
//  row selector alone is sufficient and already proven stable across
//  both listing types.
//
//  Deliberately minimal: this extractor answers exactly one question
//  ("what's the permalink of the first work in this series?"), not a
//  general series-listing parser -- Task 10's grouping feature (series
//  member enumeration/pagination for the "load more" cap) is separate,
//  unbuilt work with its own checkpoint; reuse this file's row-finding
//  approach then rather than extending this type's public surface now.
//

import Foundation

public enum AO3SeriesListingExtractor {

	private static let baseURL = "https://archiveofourown.org"

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
}

private extension AO3SeriesListingExtractor {

	/// Identical row shape to `AO3SearchResultsExtractor.isWorkRow`
	/// (`li.work-<id>`) -- see this file's header comment. Not shared
	/// code with that type, same reasoning `AO3SearchResultsExtractor`'s
	/// own doc comments give for not sharing its registration-wall
	/// check: two small, independently-stable selectors, not worth the
	/// coupling.
	static func isWorkRow(_ element: HTMLLiteElement) -> Bool {
		guard element.tag == "li" else {
			return false
		}
		return classTokens(of: element).contains { token in
			guard token.hasPrefix("work-") else { return false }
			let digits = token.dropFirst("work-".count)
			return !digits.isEmpty && digits.allSatisfy(\.isNumber)
		}
	}

	static func classTokens(of element: HTMLLiteElement) -> [String] {
		(element.attributes["class"] ?? "").split(separator: " ").map(String.init)
	}

	/// Identical to `AO3SearchResultsExtractor.absoluteURL` -- not
	/// reused directly to avoid a cross-file dependency for one
	/// three-line helper; keep both in sync if AO3's link shape ever
	/// changes.
	static func absoluteURL(_ href: String?) -> String? {
		guard let href, !href.isEmpty else {
			return nil
		}
		if href.hasPrefix("http://") || href.hasPrefix("https://") {
			return href
		}
		if href.hasPrefix("/") {
			return baseURL + href
		}
		return baseURL + "/" + href
	}
}
