//
//  AO3SearchResultsExtractor.swift
//  RSParser
//
//  Nectar AO3 direct-reading support, Task 9 ("AO3 search-result extractor +
//  pagination + author parsing") -- see nectar-ao3-features-plan-FINAL.md.
//  This file covers Task 9's first checkpoint only (the extractor and its
//  selectors); feed routing/pagination/retry (checkpoint 2) and ignore-list
//  wiring (checkpoint 3) are separate, later patches.
//
//  Selectors below are the ones the plan calls "confirmed" -- validated
//  against production AO3 markup by ao3downloader's own
//  parse_soup.get_work_metadata_from_list (GPL-3.0, (c) nianeyna), read for
//  approach only and reimplemented independently here in Swift, per the
//  licensing note in nectar-ao3-features-plan-FINAL.md ("Licensing &
//  attribution"): no ao3downloader source was transcribed, only its
//  documented selector choices and the shape of the data they target.
//
//  Live-fetch confirmation (2026-08-04): this session had web access but
//  only through a markdown-extracting fetch tool, not raw HTML -- exactly
//  the caveat the plan's "Environment & harness" section calls out ("a
//  markdown-extracting fetch tool won't show you raw CSS class names").
//  A real https://archiveofourown.org/works listing was fetched and
//  confirmed the *shape* this extractor assumes: title+author links,
//  a Fandoms line, a symbols row, a Tags block (with bolded warning tags),
//  a Summary blockquote, one "Part <N> of <name>" line per series
//  membership (confirming multi-series works render as multiple such
//  lines, not a single combined one), and Words/Chapters/Comments/Kudos/
//  Bookmarks/Hits stats in that order. It did NOT confirm the literal CSS
//  class names below byte-for-byte, since the fetch tool doesn't expose
//  raw markup. Treat the selectors as ao3downloader-sourced-and-plausible,
//  not independently re-verified here -- if the checkpoint 2 fetch path
//  comes back with a lot of .noResults on pages that clearly have results,
//  this file's selectors are the first thing to recheck against a saved
//  View Source capture (see the plan's "What only the user can do").
//
//  Deliberately out of scope for this checkpoint, per the plan's own
//  checkpoint split: feed routing/pagination bookkeeping/retry+Cloudflare
//  handling (checkpoint 2), and AO3IgnoreList wiring (checkpoint 3).
//

import Foundation

/// The three ways a fetched AO3 search-results page can come back, as
/// distinguished by document shape alone.
///
/// Deliberately three cases, not four: unlike `AO3ChapterExtractionOutcome`
/// (which mirrors a chapter fetch, where AO3 returns HTTP 200 for a rate
/// limit indistinguishable from a real page), a search-results fetch's rate
/// limiting is a genuine HTTP 429 that `Downloader`'s existing per-host
/// cooldown (see `nectar-architecture.md`, "AO3 preface rendering...")
/// already intercepts before any HTML reaches this extractor. Task 9's
/// checkpoint 2 (fetch path, not yet built) is expected to surface that
/// cooldown as its own `.rateLimited` case on a *fetcher*-level result type
/// that wraps this one -- this extractor only ever sees HTML AO3 actually
/// sent, so it has no rate-limit case of its own. If checkpoint 2 finds a
/// genuine 200-status AO3 rate-limit interstitial (distinct from the 429
/// case), add a case here then, backed by a real captured sample -- not
/// guessed now.
public enum AO3SearchResultsOutcome: Sendable {
	/// At least one recognizable work row was found.
	case success([ParsedItem])
	/// The page parsed as a real AO3 search-results page but listed no
	/// work rows -- a legitimate zero-result search, not a parse failure.
	case noResults
	/// AO3's "restricted to registered users" login wall -- same detection
	/// as `AO3ChapterHTMLExtractor`'s `.registrationRequired`.
	case registrationRequired
}

/// Extracts a page of works from a fetched AO3 search-results page
/// (`GET .../works?work_search[...]&view_adult=true`), one `ParsedItem`
/// per listed work.
///
/// `feedURL` is threaded straight through to each `ParsedItem` -- this
/// extractor has no notion of which search-feed subscription it's being
/// called for; that's the caller's (checkpoint 2's) job.
public enum AO3SearchResultsExtractor {

	private static let baseURL = "https://archiveofourown.org"

	public static func extract(fromResultsPageHTML html: String, feedURL: String) -> AO3SearchResultsOutcome {
		let root = parseHTMLLiteTree(html)

		if isRegistrationRequired(root) {
			return .registrationRequired
		}

		let workLis = descendants(of: root, where: { isWorkRow($0) })
		guard !workLis.isEmpty else {
			return .noResults
		}

		let items = workLis.compactMap { parsedItem(fromWorkLI: $0, feedURL: feedURL) }
			.filter { !AO3IgnoreList.shouldExclude($0) }
		guard !items.isEmpty else {
			return .noResults
		}
		return .success(items)
	}
}

// MARK: - Registration wall

private extension AO3SearchResultsExtractor {

	/// Same shape as `AO3ChapterHTMLExtractor`'s registration-wall check:
	/// `div#signin` containing "This work is only available to registered
	/// users of the Archive." -- reused here rather than shared code,
	/// since the two extractors otherwise have nothing else in common and
	/// a shared helper for one three-line check isn't worth the coupling.
	static func isRegistrationRequired(_ root: HTMLLiteElement) -> Bool {
		guard let signinDiv = firstDescendant(of: root, where: { $0.tag == "div" && $0.attributes["id"] == "signin" }) else {
			return false
		}
		return flattenedText(signinDiv).contains("This work is only available to registered users of the Archive.")
	}
}

// MARK: - Work row identification

private extension AO3SearchResultsExtractor {

	/// `li.work-{worknum}` -- confirmed selector (see header comment).
	/// Matched via a class-token scan rather than a fixed prefix string
	/// match on the whole class attribute, since the row's real class
	/// list also carries `work`/`blurb`/`group` tokens alongside
	/// `work-<id>`, in unconfirmed order.
	static func isWorkRow(_ element: HTMLLiteElement) -> Bool {
		guard element.tag == "li" else {
			return false
		}
		return workID(fromLI: element) != nil
	}

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

	static func classTokens(of element: HTMLLiteElement) -> [String] {
		(element.attributes["class"] ?? "").split(separator: " ").map(String.init)
	}
}

// MARK: - One work row -> ParsedItem

private extension AO3SearchResultsExtractor {

	static func parsedItem(fromWorkLI li: HTMLLiteElement, feedURL: String) -> ParsedItem? {
		guard let workID = workID(fromLI: li) else {
			return nil
		}

		// Title: h4.heading a -- also the canonical permalink for this
		// row, and (redundantly, as a cross-check) the same work id as
		// the row's own class token.
		guard let headingH4 = firstDescendant(of: li, where: { $0.tag == "h4" && classTokens(of: $0).contains("heading") }),
		      let titleAnchor = firstDescendant(of: headingH4, where: { $0.tag == "a" }) else {
			return nil
		}
		let title = flattenedText(titleAnchor).trimmingCharacters(in: .whitespacesAndNewlines)
		guard let permalink = absoluteURL(titleAnchor.attributes["href"]) else {
			return nil
		}

		// Authors: every a[rel=author] in the heading -- co-authored
		// works render one link per author/pseud in the same byline.
		let authorAnchors = descendants(of: headingH4, where: { $0.tag == "a" && $0.attributes["rel"] == "author" })
		let authors: Set<ParsedAuthor> = Set(authorAnchors.compactMap { anchor -> ParsedAuthor? in
			let name = flattenedText(anchor).trimmingCharacters(in: .whitespacesAndNewlines)
			guard !name.isEmpty else {
				return nil
			}
			return ParsedAuthor(name: name, url: absoluteURL(anchor.attributes["href"]), avatarURL: nil, emailAddress: nil)
		})

		let summary = summaryHTML(fromLI: li)
		let fandoms = tagTexts(in: li, tag: "h5", classToken: "fandoms")
		let warnings = tagTexts(in: li, tag: "li", classToken: "warnings")
		let characters = tagTexts(in: li, tag: "li", classToken: "characters")
		let relationships = tagTexts(in: li, tag: "li", classToken: "relationships")
		let freeformTags = tagTexts(in: li, tag: "li", classToken: "freeforms")
		let ratings = symbolTexts(in: li, classToken: "rating")
		let categories = symbolTexts(in: li, classToken: "category")
		let series = seriesEntries(fromLI: li)

		let wordCount = intValue(fromDD: li, classToken: "words")
		let (chapterCurrent, chapterTotal) = chapterCounts(fromLI: li)
		let isComplete = completionState(fromLI: li, chapterCurrent: chapterCurrent, chapterTotal: chapterTotal)

		return ParsedItem(
			syncServiceID: nil,
			uniqueID: permalink,
			feedURL: feedURL,
			url: permalink,
			externalURL: nil,
			title: title.isEmpty ? nil : title,
			language: nil,
			contentHTML: nil,
			contentText: nil,
			markdown: nil,
			summary: summary,
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: authors.isEmpty ? nil : authors,
			tags: freeformTags.isEmpty ? nil : Set(freeformTags),
			attachments: nil,
			isAmbrosiaItem: false,
			wordCount: wordCount,
			chapterCurrent: chapterCurrent,
			chapterTotal: chapterTotal,
			isComplete: isComplete,
			fandoms: fandoms.isEmpty ? nil : fandoms,
			relationships: relationships.isEmpty ? nil : relationships,
			characters: characters.isEmpty ? nil : characters,
			ratings: ratings.isEmpty ? nil : ratings,
			warnings: warnings.isEmpty ? nil : warnings,
			categories: categories.isEmpty ? nil : categories,
			series: series.isEmpty ? nil : series,
			ao3WorkID: workID
		)
	}

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

// MARK: - Summary

private extension AO3SearchResultsExtractor {

	/// `blockquote.summary` -- serialized as HTML (it's normally a handful
	/// of `<p>` paragraphs), matching the shape `AO3SummaryExtractor`'s
	/// `cleanedSummaryHTML` already produces for the native-feed path, so
	/// `ArticleStringFormatter`'s existing summary handling doesn't need
	/// to distinguish the two sources.
	static func summaryHTML(fromLI li: HTMLLiteElement) -> String? {
		guard let blockquote = firstDescendant(of: li, where: { $0.tag == "blockquote" && classTokens(of: $0).contains("summary") }) else {
			return nil
		}
		let serialized = serializeHTMLLiteNodes(blockquote.children)
		return serialized.isEmpty ? nil : serialized
	}
}

// MARK: - Tag lists (fandoms/warnings/characters/relationships/freeforms)

private extension AO3SearchResultsExtractor {

	/// `<h5 class="fandoms">...<a>...</a></h5>` or
	/// `<li class="warnings">...<a>...</a>...</li>` (and the character/
	/// relationship/freeform siblings of the latter) -- every `<a>`
	/// descendant's flattened, trimmed text, in document order.
	static func tagTexts(in li: HTMLLiteElement, tag: String, classToken: String) -> [String] {
		guard let container = firstDescendant(of: li, where: { $0.tag == tag && classTokens(of: $0).contains(classToken) }) else {
			return []
		}
		return descendants(of: container, where: { $0.tag == "a" })
			.map { flattenedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
	}
}

// MARK: - Symbol row (rating/category/complete-or-WIP)

private extension AO3SearchResultsExtractor {

	/// `span.rating` / `span.category` -- AO3 renders these as one `<span>`
	/// per value (e.g. two `span.category` elements for an "F/M, Other"
	/// work), so this collects every matching span's text rather than
	/// assuming exactly one.
	static func symbolTexts(in li: HTMLLiteElement, classToken: String) -> [String] {
		descendants(of: li, where: { $0.tag == "span" && classTokens(of: $0).contains(classToken) })
			.map { flattenedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
	}
}

// MARK: - Words / chapters / completion

private extension AO3SearchResultsExtractor {

	/// `dd.words` -- digits only, comma stripped (e.g. "116,556").
	static func intValue(fromDD li: HTMLLiteElement, classToken: String) -> Int? {
		guard let dd = firstDescendant(of: li, where: { $0.tag == "dd" && classTokens(of: $0).contains(classToken) }) else {
			return nil
		}
		let digitsOnly = flattenedText(dd).filter(\.isNumber)
		return digitsOnly.isEmpty ? nil : Int(digitsOnly)
	}

	/// `dd.chapters` -- "N/M" (M a literal "?" for an unknown total, same
	/// shape `AO3SummaryExtractor.parseStats` already handles for the
	/// native-feed path).
	static func chapterCounts(fromLI li: HTMLLiteElement) -> (current: Int?, total: Int?) {
		guard let dd = firstDescendant(of: li, where: { $0.tag == "dd" && classTokens(of: $0).contains("chapters") }) else {
			return (nil, nil)
		}
		let text = flattenedText(dd).trimmingCharacters(in: .whitespacesAndNewlines)
		let parts = text.components(separatedBy: "/")
		guard parts.count == 2 else {
			return (nil, nil)
		}
		let current = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines))
		let totalString = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
		guard totalString != "?" else {
			return (current, nil)
		}
		return (current, Int(totalString))
	}

	/// `span.iswip` -- text "Complete Work" marks complete, any other
	/// text (AO3's own copy is "Work in Progress") marks incomplete.
	/// Falls back to comparing `dd.chapters`' own current/total (same
	/// precedent as `AO3SummaryExtractor.parseStats`) only when the
	/// symbol itself isn't present at all.
	static func completionState(fromLI li: HTMLLiteElement, chapterCurrent: Int?, chapterTotal: Int?) -> Bool? {
		if let iswipSpan = firstDescendant(of: li, where: { $0.tag == "span" && classTokens(of: $0).contains("iswip") }) {
			return flattenedText(iswipSpan).trimmingCharacters(in: .whitespacesAndNewlines) == "Complete Work"
		}
		guard let chapterCurrent, let chapterTotal else {
			return nil
		}
		return chapterCurrent == chapterTotal
	}
}

// MARK: - Series membership

private extension AO3SearchResultsExtractor {

	/// `ul[class="series"] li` -- plain rendered text per entry, e.g.
	/// "Part 3 of Some Series Name" with the series name linked. A
	/// genuinely different shape from the work page's own
	/// `dd.series span.series span.position` markup that
	/// `AO3ChapterHTMLExtractor.seriesEntries(fromDD:)` parses (see that
	/// function's own doc comment) -- deliberately not shared with it, per
	/// the plan. Live-fetch confirmation (see file header) found this
	/// exact "Part <N> of <linked name>" text shape, including multiple
	/// `<li>`s back to back for a work in more than one series.
	static func seriesEntries(fromLI li: HTMLLiteElement) -> [ParsedSeriesEntry] {
		// `ul[class="series"]` is an exact-attribute selector in the
		// plan's own notation -- AO3's real element carries only this one
		// class, so a direct string comparison (not a token-membership
		// check) matches it precisely.
		guard let seriesUL = firstDescendant(of: li, where: { $0.tag == "ul" && $0.attributes["class"] == "series" }) else {
			return []
		}
		let entryLIs = descendants(of: seriesUL, where: { $0.tag == "li" })
		return entryLIs.compactMap(parseSeriesEntry)
	}

	static func parseSeriesEntry(_ li: HTMLLiteElement) -> ParsedSeriesEntry? {
		guard let anchor = firstDescendant(of: li, where: { $0.tag == "a" }) else {
			return nil
		}
		let text = flattenedText(li).trimmingCharacters(in: .whitespacesAndNewlines)
		guard text.hasPrefix("Part ") else {
			return nil
		}
		guard let ofRange = text.range(of: " of ") else {
			return nil
		}
		let indexString = text[text.index(text.startIndex, offsetBy: "Part ".count)..<ofRange.lowerBound]
			.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let index = Int(indexString) else {
			return nil
		}
		let name = flattenedText(anchor).trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else {
			return nil
		}
		let ao3ID = seriesID(fromHref: anchor.attributes["href"])
		return ParsedSeriesEntry(name: name, index: index, ao3ID: ao3ID)
	}

	static func seriesID(fromHref href: String?) -> String? {
		guard let href, let range = href.range(of: "/series/") else {
			return nil
		}
		let rest = href[range.upperBound...]
		let digits = rest.prefix { $0.isNumber }
		return digits.isEmpty ? nil : String(digits)
	}
}
