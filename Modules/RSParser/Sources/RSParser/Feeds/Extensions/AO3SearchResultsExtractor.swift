//
//  AO3SearchResultsExtractor.swift
//  RSParser
//
//  Nectar AO3 direct-reading support, Task 9 ("AO3 search-result extractor +
//  pagination + author parsing").
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
//  Date/language/stats selectors (dd.language, p.datetime,
//  dd.comments/kudos/bookmarks/hits) added later, reconciled against a
//  user-supplied real View Source capture of a search-results page rather
//  than a fresh live fetch of this session's own -- on firmer footing
//  than the original ao3downloader-sourced set above, but still not
//  independently confirmed by this session against AO3 directly. Same
//  recheck-against-a-capture advice applies if these specifically start
//  coming back empty on pages that clearly have the data.
//

import Foundation

/// The three ways a fetched AO3 search-results page can come back, as
/// distinguished by document shape alone.
///
/// Deliberately three cases, not four: unlike `AO3ChapterExtractionOutcome`
/// (which mirrors a chapter fetch, where AO3 returns HTTP 200 for a rate
/// limit indistinguishable from a real page), a search-results fetch's rate
/// limiting is a genuine HTTP 429 that `Downloader`'s existing per-host
/// cooldown (see `ao3-preface-rendering.md`)
/// already intercepts before any HTML reaches this extractor. Task 9's
/// checkpoint 2 (fetch path, not yet built) is expected to surface that
/// cooldown as its own `.rateLimited` case on a *fetcher*-level result type
/// that wraps this one -- this extractor only ever sees HTML AO3 actually
/// sent, so it has no rate-limit case of its own. If checkpoint 2 finds a
/// genuine 200-status AO3 rate-limit interstitial (distinct from the 429
/// case), add a case here then, backed by a real captured sample -- not
/// guessed now.
public enum AO3SearchResultsOutcome: Sendable {
	/// At least one recognizable work row was found. `hasNextPage` is
	/// derived from the pagination widget's `li.next` element: true only
	/// when a live `<a href>` is present inside it. Its absence -- whether
	/// `li.next` is missing entirely, or present but only wrapping a
	/// disabled `<span>` the way `li.previous` does on page 1 (only the
	/// disabled-`previous` shape is directly confirmed against a captured
	/// page; the disabled-`next` shape on an actual last page is not, see
	/// `hasNextPage(_:)`'s own doc comment) -- safely resolves to false
	/// either way: worst case "load more" disables one page early, it
	/// never loops past the real last page.
	///
	/// `pageTitle` is the page's own `<title>`, suffix-stripped and
	/// trimmed (see `extractPageTitle(fromResultsPageHTML:)`) -- carried
	/// alongside the items so a create-time caller can name the feed after
	/// the fandom/tag rather than leaving it "Untitled" (see
	/// `LocalAccountDelegate.createFeed`'s AO3 branch). `nil` only if the
	/// page's `<title>` element itself is missing or empty, which
	/// shouldn't happen on a real AO3 page but isn't asserted against.
	case success([ParsedItem], hasNextPage: Bool, pageTitle: String?)
	/// The page parsed as a real AO3 search-results page but listed no
	/// work rows -- a legitimate zero-result search, not a parse failure.
	/// AO3 still serves a real, titled `<title>` on a zero-result page, so
	/// `pageTitle` is carried here too, same reasoning as `.success`.
	case noResults(pageTitle: String?)
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

	public static func extract(fromResultsPageHTML html: String, feedURL: String) -> AO3SearchResultsOutcome {
		let root = parseHTMLLiteTree(html)

		if isRegistrationRequired(root) {
			return .registrationRequired
		}

		let pageTitle = extractPageTitle(fromRoot: root)

		let workLis = descendants(of: root, where: { isWorkRow($0) })
		guard !workLis.isEmpty else {
			return .noResults(pageTitle: pageTitle)
		}

		let items = workLis.compactMap { parsedItem(fromWorkLI: $0, feedURL: feedURL) }
			.filter { !AO3IgnoreList.shouldExclude($0) }
		guard !items.isEmpty else {
			// An ignore-list-filtered-to-empty page has no "next" concept
			// worth reporting -- stays .noResults, same as a genuine
			// zero-result search, rather than carrying a hasNextPage value
			// nothing would use.
			return .noResults(pageTitle: pageTitle)
		}
		return .success(items, hasNextPage: hasNextPage(root), pageTitle: pageTitle)
	}

	/// Parses `<title>Fandom Name - Works | Archive of Our Own</title>`,
	/// stripping the `" - Works | Archive of Our Own"` suffix AO3 renders
	/// on every search/tag-listing page (both the `/works?work_search[...]`
	/// query-search form and the `/tags/<tag>/works` path form), and
	/// trims whitespace. Returns `nil` if no `<title>` element is found or
	/// its text is empty after trimming -- deliberately not further
	/// validated against the suffix actually being present, since a title
	/// that doesn't carry the expected suffix (a future AO3 markup change,
	/// or a page shape this wasn't tested against) is still better passed
	/// through as-is than discarded outright.
	public static func extractPageTitle(fromResultsPageHTML html: String) -> String? {
		extractPageTitle(fromRoot: parseHTMLLiteTree(html))
	}

	private static func extractPageTitle(fromRoot root: HTMLLiteElement) -> String? {
		guard let titleElement = firstDescendant(of: root, where: { $0.tag == "title" }) else {
			return nil
		}
		var text = flattenedText(titleElement).trimmingCharacters(in: .whitespacesAndNewlines)
		let suffix = " - Works | Archive of Our Own"
		if text.hasSuffix(suffix) {
			text.removeLast(suffix.count)
		}
		text = text.trimmingCharacters(in: .whitespacesAndNewlines)
		return text.isEmpty ? nil : text
	}
}

// MARK: - Registration wall

private extension AO3SearchResultsExtractor {

	static func isRegistrationRequired(_ root: HTMLLiteElement) -> Bool {
		AO3HTMLHelpers.isRegistrationRequired(root)
	}
}

// MARK: - Pagination

private extension AO3SearchResultsExtractor {

	/// Hoisted to `AO3ListingPagination.hasNextPage(_:)` (inline-series-
	/// navigation plan, Phase 4a) once `AO3SeriesListingExtractor` needed
	/// the identical `li.next > a[href]` check for the series-listing
	/// walk -- see that type's own doc comment for the confirmation
	/// details this used to carry directly.
	static func hasNextPage(_ root: HTMLLiteElement) -> Bool {
		AO3ListingPagination.hasNextPage(root)
	}
}

// MARK: - Work row identification

private extension AO3SearchResultsExtractor {

	/// `li.work-{worknum}` -- confirmed selector (see header comment).
	static func isWorkRow(_ element: HTMLLiteElement) -> Bool {
		AO3HTMLHelpers.isWorkRow(element)
	}

	static func workID(fromLI element: HTMLLiteElement) -> String? {
		AO3HTMLHelpers.workID(fromLI: element)
	}

	static func classTokens(of element: HTMLLiteElement) -> [String] {
		AO3HTMLHelpers.classTokens(of: element)
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

		let language = stringValue(fromDD: li, classToken: "language")
		let dateModified = datetime(fromLI: li)

		let wordCount = intValue(fromDD: li, classToken: "words")
		let (chapterCurrent, chapterTotal) = chapterCounts(fromLI: li)
		let isComplete = completionState(fromLI: li, chapterCurrent: chapterCurrent, chapterTotal: chapterTotal)

		let commentCount = intValue(fromDD: li, classToken: "comments")
		let kudosCount = intValue(fromDD: li, classToken: "kudos")
		let bookmarkCount = intValue(fromDD: li, classToken: "bookmarks")
		let hitCount = intValue(fromDD: li, classToken: "hits")

		return ParsedItem(
			syncServiceID: nil,
			uniqueID: permalink,
			feedURL: feedURL,
			url: permalink,
			externalURL: nil,
			title: title.isEmpty ? nil : title,
			language: language,
			contentHTML: nil,
			contentText: nil,
			markdown: nil,
			summary: summary,
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: nil,
			dateModified: dateModified,
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
			commentCount: commentCount,
			kudosCount: kudosCount,
			bookmarkCount: bookmarkCount,
			hitCount: hitCount,
			ao3WorkID: workID
		)
	}

	static func absoluteURL(_ href: String?) -> String? {
		AO3HTMLHelpers.absoluteURL(href)
	}
}

// MARK: - Summary

// `internal` (module-default), not `private`: AO3SeriesListingExtractor
// reuses this against the identical "work blurb" row shape (see that
// type's own doc comment) rather than duplicating it -- both files are
// part of the RSParser target, so this stays invisible outside the
// module.
extension AO3SearchResultsExtractor {

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

// `internal`, not `private` -- see the Summary section's access-note above;
// same reuse by AO3SeriesListingExtractor applies here.
extension AO3SearchResultsExtractor {

	/// `<h5 class="fandoms">...<a>...</a></h5>` -- fandoms are grouped in
	/// one container -- or `<li class="warnings">...</li>` (and the
	/// character/relationship/freeform siblings of the latter), which AO3
	/// instead renders as one `<li>` *per tag*, not one container with
	/// multiple `<a>`s inside. Collecting every matching element (not just
	/// the first) handles both shapes: every `<a>` descendant's flattened,
	/// trimmed text, in document order.
	static func tagTexts(in li: HTMLLiteElement, tag: String, classToken: String) -> [String] {
		let containers = descendants(of: li, where: { $0.tag == tag && classTokens(of: $0).contains(classToken) })
		guard !containers.isEmpty else {
			return []
		}
		return containers
			.flatMap { descendants(of: $0, where: { $0.tag == "a" }) }
			.map { flattenedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
	}
}

// MARK: - Symbol row (rating/category/complete-or-WIP)

// `internal`, not `private` -- see the Summary section's access-note above;
// same reuse by AO3SeriesListingExtractor applies here.
extension AO3SearchResultsExtractor {

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

// MARK: - Language

private extension AO3SearchResultsExtractor {

	/// `dd.language` -- plain text (e.g. "English"), same dl.stats block
	/// as words/chapters/comments/kudos/bookmarks/hits below, just not
	/// numeric so it doesn't fit `intValue(fromDD:classToken:)`.
	static func stringValue(fromDD li: HTMLLiteElement, classToken: String) -> String? {
		guard let dd = firstDescendant(of: li, where: { $0.tag == "dd" && classTokens(of: $0).contains(classToken) }) else {
			return nil
		}
		let text = flattenedText(dd).trimmingCharacters(in: .whitespacesAndNewlines)
		return text.isEmpty ? nil : text
	}
}

// MARK: - Date

private extension AO3SearchResultsExtractor {

	/// `dd MMM yyyy`, e.g. "28 Dec 2022" -- fixed `en_US_POSIX` locale
	/// since AO3 renders this in fixed English month abbreviations
	/// regardless of the requesting account's locale, not the device's.
	/// Also fixed to UTC: AO3's page itself renders this date in the
	/// browsing account's own timezone preference (Eastern by default),
	/// not UTC, but with day-only granularity and no timezone indicator
	/// in the text itself, there's no way to know which timezone a given
	/// capture used -- and leaving `timeZone` unset would make
	/// `date(from:)` fall back to the run-time default calendar's
	/// timezone, so the same "01 Jan 2026" string would parse to a
	/// different `Date` on different devices. Fixing to UTC trades
	/// "possibly a day off from AO3's own Eastern-time rendering" for
	/// "deterministic and testable" -- day-granularity display already
	/// tolerates this; nothing in this codebase reads time-of-day off
	/// this value.
	static let datetimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(identifier: "UTC")
		formatter.dateFormat = "dd MMM yyyy"
		return formatter
	}()

	/// `p.datetime` -- this is AO3's "last updated" date for the work
	/// (its own listing label; AO3 doesn't separately expose original
	/// publish date on a search-results row), so it maps to
	/// `dateModified`, not `datePublished` -- consistent with
	/// `Article.logicalDatePublished`'s existing
	/// `datePublished ?? dateModified ?? status.dateArrived` fallback,
	/// which already treats an unset `datePublished` correctly here.
	/// Day-granularity only: AO3 also embeds a second-granularity
	/// `<!-- updated_at=<unix> -->` HTML comment alongside this text, but
	/// `HTMLScanner.consumeComment()` discards all HTML comments during
	/// tokenization -- that data never reaches this parser's tree at
	/// all, so this text node is the only date signal actually available
	/// here.
	static func datetime(fromLI li: HTMLLiteElement) -> Date? {
		guard let p = firstDescendant(of: li, where: { $0.tag == "p" && classTokens(of: $0).contains("datetime") }) else {
			return nil
		}
		let text = flattenedText(p).trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else {
			return nil
		}
		return datetimeFormatter.date(from: text)
	}
}

// MARK: - Words / chapters / completion

// `internal`, not `private` -- see the Summary section's access-note above;
// same reuse by AO3SeriesListingExtractor applies here (only `dd.words`
// is currently reused, but the whole block stays together with its
// `chapterCounts`/`completionState` siblings for cohesion).
extension AO3SearchResultsExtractor {

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
		AO3HTMLHelpers.seriesID(fromHref: href)
	}
}
