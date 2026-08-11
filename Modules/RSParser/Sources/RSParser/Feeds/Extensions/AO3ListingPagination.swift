//
//  AO3ListingPagination.swift
//  RSParser
//
//  Inline-series-navigation plan, Phase 4a: `AO3SeriesListingExtractor`
//  needs the same "is there another page?" check
//  `AO3SearchResultsExtractor.hasNextPage(_:)` already implemented, on
//  byte-for-byte identical markup (`li.next > a[href]` -- confirmed
//  structurally identical on a real series-listing page via
//  `longseries.html`'s multi-page pagination widget, plan revision
//  notes). Hoisted here so both extractors call one implementation
//  instead of maintaining two copies of the same selector.
//

import Foundation

enum AO3ListingPagination {

	/// `li.next` containing a real `<a href>` -- present and enabled when
	/// another page exists. Confirmed against a captured page-1-of-4601
	/// search-results page where `li.next` wrapped a live `<a>`, against
	/// `longseries.html`'s real series-listing page-1 pagination widget,
	/// and against a real series last page whose `li.next` wraps only a
	/// disabled `<span>`. Absence of a live anchor (missing `<li>`, or
	/// `<li>` present but only wrapping a disabled `<span>`) reads as
	/// `false`.
	static func hasNextPage(_ root: HTMLLiteElement) -> Bool {
		guard let nextLI = firstDescendant(of: root, where: { $0.tag == "li" && AO3HTMLHelpers.classTokens(of: $0).contains("next") }) else {
			return false
		}
		return firstDescendant(of: nextLI, where: { $0.tag == "a" && $0.attributes["href"] != nil }) != nil
	}

	/// Total page count read from AO3's pagination widget. This mirrors
	/// ao3downloader's approach (read numeric pagination entries and take
	/// the max) while using this project's HTMLLiteTree helpers. A missing
	/// pagination widget means a single-page listing and returns nil.
	static func totalPages(_ root: HTMLLiteElement) -> Int? {
		guard let paginationList = firstDescendant(of: root, where: {
			$0.tag == "ol" && AO3HTMLHelpers.classTokens(of: $0).contains("pagination")
		}) else {
			return nil
		}
		let pageNumbers = descendants(of: paginationList, where: { $0.tag == "li" }).compactMap { li -> Int? in
			let digits = flattenedText(li).filter(\.isNumber)
			guard !digits.isEmpty else {
				return nil
			}
			return Int(String(digits))
		}
		return pageNumbers.max()
	}
}
