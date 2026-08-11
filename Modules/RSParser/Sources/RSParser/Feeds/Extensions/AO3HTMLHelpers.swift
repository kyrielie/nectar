//
//  AO3HTMLHelpers.swift
//  RSParser
//
//  Shared, non-public helpers for the AO3 HTML extractor cluster
//  (AO3SearchResultsExtractor, AO3SeriesListingExtractor,
//  AO3ChapterHTMLExtractor, AO3SummaryExtractor, AO3ListingPagination).
//  Extracted from byte-identical copies that had drifted in maintenance
//  discipline (only some carried a "keep in sync" comment) and, in two
//  cases (isWorkRow/isRegistrationRequired), had already drifted in actual
//  behavior between files -- see this repo's audit notes.
//
//  Unlike AO3IgnoreList's own copy of classTokens-style logic (blocked by
//  RSParser not being able to depend on Account, and documented as such),
//  there's no layering reason for these extractors -- all in the same
//  module, same target, same directory -- to keep separate copies. This
//  file plays the same role HTMLLiteTree.swift's firstDescendant/
//  flattenedText already play for this cluster: a shared, non-public
//  utility with no new coupling risk.
//
import Foundation

enum AO3HTMLHelpers {

	static let baseURL = "https://archiveofourown.org"

	/// Resolves a possibly-relative AO3 `href` to an absolute URL. Already
	/// absolute (`http(s)://`) hrefs pass through unchanged.
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

	/// `element`'s `class` attribute split on whitespace into individual
	/// class tokens.
	static func classTokens(of element: HTMLLiteElement) -> [String] {
		(element.attributes["class"] ?? "").split(separator: " ").map(String.init)
	}

	/// `li.work-{worknum}` row identification, matched via a class-token
	/// scan rather than a fixed prefix string match on the whole class
	/// attribute, since a real row's class list also carries
	/// `work`/`blurb`/`group` tokens alongside `work-<id>`, in unconfirmed
	/// order. Returns the numeric work id, or nil if `element` isn't a
	/// work row at all.
	///
	/// This is the reconciled version of what used to be two divergent
	/// implementations: AO3SearchResultsExtractor delegated to a
	/// `workID(fromLI:) != nil` check (this function); AO3SeriesListingExtractor
	/// inlined its own `hasPrefix("work-")` + all-digits check with no
	/// work-id extraction. Both selectors target the same `li.work-<id>`
	/// shape, so there was no actual reason for them to diverge -- if AO3
	/// ever adds a second `work-`-prefixed class token that isn't a work
	/// id, both callers now agree on how to handle it instead of
	/// potentially disagreeing.
	static func workID(fromLI element: HTMLLiteElement) -> String? {
		for token in classTokens(of: element) {
			guard token.hasPrefix("work-") else {
				continue
			}
			let digits = token.dropFirst("work-".count)
			guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else {
				continue
			}
			return String(digits)
		}
		return nil
	}

	/// `element` is a work-listing `<li>` row (`li.work-{worknum}`).
	static func isWorkRow(_ element: HTMLLiteElement) -> Bool {
		guard element.tag == "li" else {
			return false
		}
		return workID(fromLI: element) != nil
	}

	/// AO3's `<a href="/works/<id>">`-style permalink -> series id, used
	/// for anthology/combined-series `bookKey` resolution. Shared across
	/// all three sites that need to pull a series id off a link
	/// (search-results author metadata, chapter-page series links, and
	/// AO3SummaryExtractor's parsed `<dl>` fields).
	static func seriesID(fromHref href: String?) -> String? {
		guard let href, let range = href.range(of: "/series/") else {
			return nil
		}
		let rest = href[range.upperBound...]
		let digits = rest.prefix { $0.isNumber }
		return digits.isEmpty ? nil : String(digits)
	}

	/// Registration-required login wall: `div#signin` present AND
	/// containing AO3's specific registration-required text, not just the
	/// div's bare presence.
	///
	/// This is the reconciled version of what used to be two divergent
	/// implementations: AO3ChapterHTMLExtractor treated the mere presence
	/// of `div#signin` as sufficient; AO3SearchResultsExtractor
	/// additionally required the div to contain "This work is only
	/// available to registered users of the Archive." The stricter,
	/// text-matching version is the one kept -- a signin div that appears
	/// for some other reason (rate limiting, a different notice) should
	/// not read as "registration required" on any extraction path, and
	/// treating a login wall as present when it isn't is more disruptive
	/// to the user (blocks a fetch that would otherwise have succeeded)
	/// than the reverse.
	static func isRegistrationRequired(_ root: HTMLLiteElement) -> Bool {
		guard let signinDiv = firstDescendant(of: root, where: { $0.tag == "div" && $0.attributes["id"] == "signin" }) else {
			return false
		}
		return flattenedText(signinDiv).contains("This work is only available to registered users of the Archive.")
	}
}
