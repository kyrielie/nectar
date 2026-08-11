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
	/// search-results page where `li.next` wrapped a live `<a>`, and
	/// against `longseries.html`'s real series-listing pagination widget
	/// (page 1's `li.next` wraps a live `<a href="...?page=2">`); the
	/// disabled shape on an actual last page (by symmetry with
	/// `li.previous`'s confirmed `<span class="disabled">` shape on page
	/// 1) is not independently confirmed from a captured last-page
	/// sample of either listing type -- treat as plausible-but-unverified
	/// per the project's own rule about not guessing markup. Either way
	/// this resolves safely: absence of a live anchor (missing `<li>`, or
	/// `<li>` present but only wrapping a disabled `<span>`) both read as
	/// `false`.
	static func hasNextPage(_ root: HTMLLiteElement) -> Bool {
		guard let nextLI = firstDescendant(of: root, where: { $0.tag == "li" && AO3HTMLHelpers.classTokens(of: $0).contains("next") }) else {
			return false
		}
		return firstDescendant(of: nextLI, where: { $0.tag == "a" && $0.attributes["href"] != nil }) != nil
	}
}
