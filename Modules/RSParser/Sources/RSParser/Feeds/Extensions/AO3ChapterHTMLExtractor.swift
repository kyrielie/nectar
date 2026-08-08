//
//  AO3ChapterHTMLExtractor.swift
//  RSParser
//
//  Created for the Nectar fork.
//

import Foundation

/// One posted chapter found in a fetched AO3 work page, in document order.
/// Used only to drive the table-of-contents UI -- the chapter's actual
/// rendered content lives in `AO3ChapterExtractionResult.contentHTML`, not
/// here (see that type's doc comment).
public struct AO3ExtractedChapter: Sendable {
	public let id: String       // e.g. "chapter-1", from the source div's own id
	public let title: String    // flattened text of the chapter's h3.title, e.g. "Chapter 2: Livermore, California"
}

public struct AO3ChapterExtractionResult: Sendable {

	/// The Work Header metadata block (rating/warning/category/fandom/
	/// relationships/characters/tags/language/series/collections/stats),
	/// when found, followed by the `#workskin` wrapper (plus its preceding
	/// `<style>` block, when the work has a custom skin), re-serialized as a
	/// single unit. This is what actually gets rendered -- metadata, title,
	/// work-level summary, and every posted chapter concatenated, exactly
	/// as the live page groups them (except the metadata block, which is
	/// relocated here from elsewhere on the page -- see
	/// `AO3ChapterHTMLExtractor`'s header comment). Splitting the
	/// style+workskin portion into per-chapter HTML and discarding the
	/// wrapper would break the workskin's styling, since every one of its
	/// rules is scoped under `#workskin`.
	public let contentHTML: String

	/// Per-chapter boundaries/titles, in document order, for the TOC only.
	public let chapters: [AO3ExtractedChapter]

	/// Structured counts read off the Work Header's `dl.stats` block (see
	/// `AO3PrefaceRenderer`/`parseWorkHeader` below), for persisting to the
	/// database independent of however the preface itself ends up
	/// displayed. Nil when the metadata block itself was absent (gated
	/// pages) or didn't include that particular stat -- Comments and
	/// Bookmarks are both known to be sometimes absent even on a normal
	/// work page (confirmed: ao3-work-single-chapter.html's fixture has no
	/// Comments row).
	public let commentCount: Int?
	public let kudosCount: Int?
	public let bookmarkCount: Int?
	public let hitCount: Int?

	/// The Work Header stats block's Words count, read the same way as the
	/// four counts above. Distinct from `Article.wordCount`, which stays
	/// Workstream 1's (feed-derived) territory and is never overwritten by
	/// a chapter fetch (see `AO3ChapterFetcher.rebuildParsedItem`, which
	/// always passes `existingArticle.wordCount` through unchanged) --
	/// this field exists purely for Task 8's content-regression guard
	/// (`AO3ChapterFetcher.detectRegression`), which needs the fetched
	/// page's own word count to compare against the stored content's
	/// re-derived one, independent of whatever the feed last reported.
	public let wordCount: Int?

	/// The page's Rails CSRF token (`<meta name="csrf-token" content="...">`,
	/// present on every AO3 page regardless of sign-in state), scraped for
	/// Task 6 (kudos-on-like) -- see `AO3KudosManager`. `nil` only if the
	/// meta tag itself was missing, which shouldn't happen on a real AO3
	/// page but isn't treated as an extraction failure by itself, since
	/// everything else in `AO3ChapterExtractionResult` is still valid
	/// without it.
	public let csrfToken: String?

	/// Task 10 (prev/next/first navigation): the AO3-absolute URL of the
	/// previous/next work in whichever series membership carries one,
	/// read off `<a class="previous">`/`<a class="next">` inside the same
	/// `<span class="series">` block `seriesEntries(fromDD:)` already
	/// reads the position text out of -- see
	/// `previousNextWorkURLs(fromDD:)`. Page-navigation chrome AO3 renders
	/// on every work page regardless of whether the reader has series
	/// grouping enabled; capturing it costs no additional request. `nil`
	/// when the work has no series membership, or is the first/last work
	/// in every series it belongs to (for that respective direction).
	public let previousWorkURL: String?
	public let nextWorkURL: String?

	public init(contentHTML: String, chapters: [AO3ExtractedChapter], commentCount: Int? = nil, kudosCount: Int? = nil, bookmarkCount: Int? = nil, hitCount: Int? = nil, wordCount: Int? = nil, csrfToken: String? = nil, previousWorkURL: String? = nil, nextWorkURL: String? = nil) {
		self.contentHTML = contentHTML
		self.chapters = chapters
		self.commentCount = commentCount
		self.kudosCount = kudosCount
		self.bookmarkCount = bookmarkCount
		self.hitCount = hitCount
		self.wordCount = wordCount
		self.csrfToken = csrfToken
		self.previousWorkURL = previousWorkURL
		self.nextWorkURL = nextWorkURL
	}
}

/// The four ways a fetched AO3 work page can come back, distinguished by
/// document shape alone -- there is no HTTP-status-level signal for any of
/// the three failure cases; AO3 returns 200 for all of them.
public enum AO3ChapterExtractionOutcome: Sendable {
	/// `#workskin` plus at least one `.chapter` div were found -- the normal
	/// case.
	case success(AO3ChapterExtractionResult)
	/// The Adult Content Warning interstitial -- expected to be unreachable
	/// now that every fetch sends `view_adult=true` unconditionally, so
	/// seeing this outcome in practice means that parameter didn't do its
	/// job (redirect stripping it, an AO3 behavior change, or a gate this
	/// hasn't been sampled against yet).
	case adultContentGate
	/// AO3's "restricted to registered users" login wall
	/// (`div#signin`, "This work is only available to registered users of
	/// the Archive."). Distinct from `.notFound` -- Workstream 3's
	/// authenticated retry fires specifically on this outcome.
	case registrationRequired
	/// Neither `#workskin`+`.chapter` divs, nor either known gate page, was
	/// found. Catch-all for a genuinely deleted/moved work, or any other
	/// shape not yet sampled (a collection- or series-level gate, for
	/// instance).
	case notFound
}

/// Extracts storable article content from a fetched AO3 work page
/// (`GET .../works/<id>?view_full_work=true&view_adult=true`).
///
/// AO3 wraps a work's title, its own summary, and every concatenated posted
/// chapter in a single `<div id="workskin">`, unconditionally -- present and
/// non-empty even for works with no custom skin. Immediately before it, still
/// outside `#workskin`, sits the work's own `<style>` block when (and only
/// when) the work has a custom skin; every one of that stylesheet's rules is
/// scoped `#workskin .classname { ... }`, so it and the wrapper have to be
/// captured and stored together as one unit -- neither means anything to a
/// renderer without the other.
///
/// Separately, the work's rating/warning/category/fandom/relationships/
/// characters/tags/language/series/collections/stats live in their own
/// `<dl class="work meta group">`, entirely outside `#workskin` (a sibling
/// of `#work-skin` under `#main`) -- AO3's own live page renders this table
/// as the "Work Header" landmark. Parsed into structured data (see
/// `parseWorkHeader`/`AO3PrefaceRenderer`), re-rendered in this app's own
/// preface style, and prepended to `contentHTML` as its own unit, unrelated
/// positionally to the style+workskin capture.
public enum AO3ChapterHTMLExtractor {

	/// See `AO3ChapterExtractionOutcome` for what each case means and when
	/// callers should treat it as retryable (`.registrationRequired`, via
	/// Workstream 3) versus not (`.adultContentGate`, `.notFound`).
	public static func extract(fromWorkPageHTML html: String) -> AO3ChapterExtractionOutcome {
		let root = parseHTMLLiteTree(html)

		if let (workSkinParent, workSkinIndex, workSkinDiv) = firstDescendantWithParent(of: root, where: {
			$0.tag == "div" && $0.attributes["id"] == "workskin"
		}) {
			let chapterDivs = descendants(of: workSkinDiv, where: {
				$0.tag == "div" && $0.attributes["class"] == "chapter" && ($0.attributes["id"]?.hasPrefix("chapter-") ?? false)
			})
			if !chapterDivs.isEmpty {
				stripPhantomTitleHeadingClass(inWorkSkin: workSkinDiv)

				let chapters = chapterDivs.compactMap(extractedChapter)
				let assembled = serializedContentHTML(root: root, workSkinParent: workSkinParent, workSkinIndex: workSkinIndex, workSkinDiv: workSkinDiv)

				return .success(AO3ChapterExtractionResult(contentHTML: assembled.contentHTML, chapters: chapters, commentCount: assembled.commentCount, kudosCount: assembled.kudosCount, bookmarkCount: assembled.bookmarkCount, hitCount: assembled.hitCount, wordCount: assembled.wordCount, csrfToken: csrfToken(root: root), previousWorkURL: assembled.previousWorkURL, nextWorkURL: assembled.nextWorkURL))
			}

			// Single-chapter works carry no per-chapter <div class="chapter">
			// wrapper at all -- confirmed against a real work (87955346,
			// "Chapters: 1/1"): the body sits directly inside
			// <div id="chapters" role="article">, with no h3.title chapter
			// heading either, since there's only ever one implicit chapter.
			// Without this branch, every single-chapter AO3 work was
			// misreported as gated/removed.
			if let chaptersDiv = firstDescendant(of: workSkinDiv, where: {
				$0.tag == "div" && $0.attributes["id"] == "chapters"
			}) {
				// Unlike the multi-chapter branch, there's no per-chapter
				// heading to rewrite into an h2.heading here -- a
				// single-chapter work has exactly one heading in the whole
				// document, the work's own title. Stripping its "heading"
				// class (as stripPhantomTitleHeadingClass does for the
				// multi-chapter branch, where real h2.heading chapter
				// entries exist to take its place) would leave tocNodes()
				// (main_ios.js: `h1, h2.heading, h2.toc-heading`) with
				// nothing to find at all, and TableOfContentsViewController
				// would render an empty screen. Promoting it to <h1>
				// instead mirrors Calibre's own convention (a lone <h1> is
				// the book's own title, not a selectable chapter row --
				// see tocNodes()'s doc comment in main_ios.js), which keeps
				// TableOfContentsViewController's flat/non-anthology
				// handling of a single-<h1>-only entries array correct.
				promoteTitleHeadingToH1(inWorkSkin: workSkinDiv)
				stripLandmarkHeading(from: chaptersDiv)

				let chapters = [AO3ExtractedChapter(id: "chapter-1", title: "Chapter 1")]
				let assembled = serializedContentHTML(root: root, workSkinParent: workSkinParent, workSkinIndex: workSkinIndex, workSkinDiv: workSkinDiv)

				return .success(AO3ChapterExtractionResult(contentHTML: assembled.contentHTML, chapters: chapters, commentCount: assembled.commentCount, kudosCount: assembled.kudosCount, bookmarkCount: assembled.bookmarkCount, hitCount: assembled.hitCount, wordCount: assembled.wordCount, csrfToken: csrfToken(root: root), previousWorkURL: assembled.previousWorkURL, nextWorkURL: assembled.nextWorkURL))
			}
		}

		if isAdultContentGate(root) {
			return .adultContentGate
		}
		if isRegistrationRequired(root) {
			return .registrationRequired
		}
		return .notFound
	}
}

// MARK: - CSRF token (Task 6: kudos-on-like)

private extension AO3ChapterHTMLExtractor {

	/// Scrapes the Rails CSRF token AO3 embeds on every page (gated or not,
	/// signed in or not) as `<meta name="csrf-token" content="...">` --
	/// confirmed against `ArmindoFlores/ao3_api`'s (MIT) `Work.authenticity_token`,
	/// which reads the identical tag. Used by `AO3KudosManager` to leave a
	/// kudos off the back of this same fetch rather than a dedicated
	/// request -- see this file's header comment and the licensing note in
	/// nectar-ao3-features-plan-FINAL.md. `nil` if the tag is missing
	/// (shouldn't happen on a real page, but not fatal to the rest of the
	/// extraction).
	static func csrfToken(root: HTMLLiteElement) -> String? {
		firstDescendant(of: root, where: { $0.tag == "meta" && $0.attributes["name"] == "csrf-token" })?.attributes["content"]
	}
}

// MARK: - Gate page detection

private extension AO3ChapterHTMLExtractor {

	/// Adult Content Warning interstitial: anchored on the heading text --
	/// the simplest reliable signal, and it doesn't depend on the per-work
	/// "Yes, Continue" link's exact `view_adult=true`-suffixed href.
	static func isAdultContentGate(_ root: HTMLLiteElement) -> Bool {
		firstDescendant(of: root, where: {
			$0.tag == "h2" && $0.attributes["class"] == "landmark heading" && flattenedText($0).trimmingCharacters(in: .whitespacesAndNewlines) == "Adult Content Warning"
		}) != nil
	}

	/// Registration-required login wall: matched on `div#signin`'s
	/// presence -- an id, so cheaper and more specific than matching the
	/// "Sorry! This work is only available to registered users of the
	/// Archive." prose.
	static func isRegistrationRequired(_ root: HTMLLiteElement) -> Bool {
		firstDescendant(of: root, where: {
			$0.tag == "div" && $0.attributes["id"] == "signin"
		}) != nil
	}
}

// MARK: - Per-chapter extraction

private extension AO3ChapterHTMLExtractor {

	/// Mutates `chapterDiv` in place (title heading rewrite, landmark strip)
	/// and returns the TOC-facing summary of it. `nil` only for a
	/// structurally malformed chapter div (missing title), which shouldn't
	/// happen against real AO3 output but shouldn't crash if it did.
	static func extractedChapter(_ chapterDiv: HTMLLiteElement) -> AO3ExtractedChapter? {
		guard let id = chapterDiv.attributes["id"] else {
			return nil
		}

		guard let prefaceGroup = firstDescendant(of: chapterDiv, where: {
			$0.tag == "div" && $0.attributes["class"] == "chapter preface group"
		}) else {
			return nil
		}
		guard let titleHeading = firstDescendant(of: prefaceGroup, where: {
			$0.tag == "h3" && $0.attributes["class"] == "title"
		}) else {
			return nil
		}

		// Flattened text of the whole heading, not just its <a> child --
		// a chapter with its own title (e.g. "Chapter 2: Livermore,
		// California", confirmed in workskinentire.html) has that title as
		// a text node trailing the anchor, sibling to it inside the same
		// h3. Reading only the anchor's text would silently drop it.
		let title = flattenedText(titleHeading).trimmingCharacters(in: .whitespacesAndNewlines)

		// `iOS/Resources/main_ios.js`'s tocNodes() only collects
		// `h1, h2.heading, h2.toc-heading` -- invisible to h3. Rewrite so
		// this chapter lands on the existing flat TOC branch with no
		// Swift/JS changes on that side.
		titleHeading.tag = "h2"
		titleHeading.attributes["class"] = "heading"

		if let body = firstDescendant(of: chapterDiv, where: {
			$0.tag == "div" && $0.attributes["class"] == "userstuff module" && $0.attributes["role"] == "article"
		}) {
			stripLandmarkHeading(from: body)
		}

		return AO3ExtractedChapter(id: id, title: title)
	}
}

// MARK: - Landmark heading strip

private extension AO3ChapterHTMLExtractor {

	/// Strips the "Chapter Text" / "Work Text:" landmark heading -- matched
	/// by id="work", not by its English text, so a locale variant isn't
	/// silently missed (untested against a non-English work). Shared by
	/// both the multi-chapter body (`div.userstuff.module[role="article"]`)
	/// and the single-chapter body (`div#chapters[role="article"]`
	/// directly) -- the heading's id is the same either way.
	static func stripLandmarkHeading(from body: HTMLLiteElement) {
		body.children.removeAll {
			if case .element(let el) = $0, el.attributes["id"] == "work" {
				return true
			}
			return false
		}
	}
}

// MARK: - Phantom TOC entry from the work title

private extension AO3ChapterHTMLExtractor {

	/// The work's own title -- `<h2 class="title heading">`, first h2 inside
	/// the work-level `div.preface.group` (distinct from each chapter's own
	/// `div.chapter.preface.group`), before the byline h3 -- carries the
	/// class `heading` and so matches `tocNodes()`'s `h2.heading` selector
	/// exactly like a rewritten chapter title does. Left alone, every AO3
	/// article's TOC would show this as a phantom entry above "Chapter 1".
	/// Confirmed harmless against the one workskin sample in hand, whose
	/// rules target paragraph-level classes, not `.title`/`.heading` --
	/// flagged as unverified against a workskin that does style that chrome.
	static func stripPhantomTitleHeadingClass(inWorkSkin workSkinDiv: HTMLLiteElement) {
		guard let workPreface = firstDescendant(of: workSkinDiv, where: {
			$0.tag == "div" && $0.attributes["class"] == "preface group"
		}) else {
			return
		}
		guard let titleHeading = firstDescendant(of: workPreface, where: { $0.tag == "h2" }) else {
			return
		}
		titleHeading.attributes["class"] = "title"
	}

	/// Single-chapter counterpart to `stripPhantomTitleHeadingClass` above:
	/// same element (`<h2 class="title heading">`, first h2 inside
	/// `div.preface.group`), but rewritten to `<h1>` instead of stripped
	/// bare, since a single-chapter work has no per-chapter heading to
	/// leave behind as tocNodes()'s sole match. See the call site's comment
	/// for why this needs to remain a real tocNodes() match rather than
	/// disappearing entirely.
	static func promoteTitleHeadingToH1(inWorkSkin workSkinDiv: HTMLLiteElement) {
		guard let workPreface = firstDescendant(of: workSkinDiv, where: {
			$0.tag == "div" && $0.attributes["class"] == "preface group"
		}) else {
			return
		}
		guard let titleHeading = firstDescendant(of: workPreface, where: { $0.tag == "h2" }) else {
			return
		}
		titleHeading.tag = "h1"
		titleHeading.attributes["class"] = "title"
	}
}

// MARK: - Content assembly

private extension AO3ChapterHTMLExtractor {

	/// The metadata block (rating/warning/category/fandom/relationships/
	/// characters/additional tags/language/series/collections/stats),
	/// rendered ahead of the style+workskin unit. Found by a plain
	/// descendant search on `<dl class="work meta group">` -- confirmed
	/// unique per page across every fixture in hand, and unlike the
	/// `<style>` block, not positionally coupled to `#workskin` at all (it
	/// lives entirely outside `#work-skin`, as a sibling under `#main`), so
	/// no sibling-adjacency logic is needed to find it.
	///
	/// Absent on the two known gate pages (confirmed: 0 occurrences in
	/// ao3-work-adult-content-gate.html) and, more importantly, on any
	/// future page shape this hasn't been sampled against either -- so this
	/// is optional. A work extracting successfully without its metadata
	/// block is a smaller loss than the whole extraction failing over it.
	///
	/// Previously (patch 0006) this block was captured whole rather than
	/// parsed field-by-field, specifically to get AO3's own real,
	/// correctly-encoded tag links (e.g. "M/M" -> "M*s*M") and to pick up
	/// any row not yet sampled (Series, at the time) for free. Parsing into
	/// `AO3PrefaceData` via `parseWorkHeader` below keeps both of those --
	/// real hrefs are read directly off each `<a>`, and Series is now
	/// confirmed and handled (see `seriesEntries(fromDD:)`) -- while also
	/// re-rendering through `AO3PrefaceRenderer`, the same renderer
	/// `ArticleRenderer` uses for the pre-fetch synthetic preface. That's
	/// what makes both prefaces look alike (Ambrosia-style comma-joined
	/// tags, inline stats) instead of this one carrying AO3's own
	/// `<ul class="commas"><li>` markup, and it's what turns
	/// Comments/Kudos/Bookmarks/Hits into structured data this function can
	/// hand back to callers instead of leaving them buried in an opaque
	/// HTML blob.
	static func serializedContentHTML(root: HTMLLiteElement, workSkinParent: HTMLLiteElement, workSkinIndex: Int, workSkinDiv: HTMLLiteElement) -> (contentHTML: String, commentCount: Int?, kudosCount: Int?, bookmarkCount: Int?, hitCount: Int?, wordCount: Int?, previousWorkURL: String?, nextWorkURL: String?) {
		var contentHTML = ""
		var counts = (commentCount: Int?.none, kudosCount: Int?.none, bookmarkCount: Int?.none, hitCount: Int?.none, wordCount: Int?.none)
		var navigation = (previousWorkURL: String?.none, nextWorkURL: String?.none)

		if let workHeader = parseWorkHeader(root: root) {
			if let prefaceHTML = AO3PrefaceRenderer.html(id: "ao3Preface", data: workHeader.data) {
				contentHTML += prefaceHTML
			}
			counts = (workHeader.commentCount, workHeader.kudosCount, workHeader.bookmarkCount, workHeader.hitCount, workHeader.wordCount)
			navigation = (workHeader.previousWorkURL, workHeader.nextWorkURL)
		}
		if let styleElement = precedingStyleElement(parent: workSkinParent, beforeIndex: workSkinIndex) {
			contentHTML += serializeHTMLLiteNodes([.element(styleElement)])
		}
		contentHTML += serializeHTMLLiteNodes([.element(workSkinDiv)])
		return (contentHTML, counts.commentCount, counts.kudosCount, counts.bookmarkCount, counts.hitCount, counts.wordCount, navigation.previousWorkURL, navigation.nextWorkURL)
	}
}

// MARK: - Work Header parsing

/// Result of parsing `<dl class="work meta group">` into structured data:
/// the renderable preface rows, plus the four stats counts worth
/// persisting to the database separately from however the preface itself
/// is displayed.
struct AO3WorkHeaderExtraction {
	let data: AO3PrefaceData
	let commentCount: Int?
	let kudosCount: Int?
	let bookmarkCount: Int?
	let hitCount: Int?
	let wordCount: Int?
	let previousWorkURL: String?
	let nextWorkURL: String?
}

private extension AO3ChapterHTMLExtractor {

	/// Parses AO3's real `<dl class="work meta group">` -- confirmed against
	/// six independent fetched-page fixtures (entire.html,
	/// ao3-work-single-chapter.html, plus fullworkseries.html,
	/// twoauthors.html, and twoseries.html, all sampled specifically to
	/// confirm the Series row's real shape) -- into row/stats data ready for
	/// `AO3PrefaceRenderer`.
	///
	/// Row identification is by each `<dt>`'s class token, not its label
	/// text: label text varies by row content in ways that don't affect
	/// meaning ("Category:" vs "Categories:" depending on count, confirmed
	/// in twoseries.html; "Updated:" vs "Completed:" for the same `dt
	/// class="status"`, confirmed comparing fullworkseries.html against
	/// twoauthors.html) -- keying on class is what AO3's own site CSS does
	/// too, and is stable across both variations.
	static func parseWorkHeader(root: HTMLLiteElement) -> AO3WorkHeaderExtraction? {
		guard let metaGroup = firstDescendant(of: root, where: {
			$0.tag == "dl" && $0.attributes["class"] == "work meta group"
		}) else {
			return nil
		}

		var rows: [AO3PrefaceRow] = []
		var statsRows: [AO3PrefaceStatsRow] = []
		var commentCount: Int?
		var kudosCount: Int?
		var bookmarkCount: Int?
		var hitCount: Int?
		var wordCount: Int?
		var previousWorkURL: String?
		var nextWorkURL: String?

		var pendingDT: HTMLLiteElement?
		for element in directChildElements(of: metaGroup) {
			if element.tag == "dt" {
				pendingDT = element
				continue
			}
			guard element.tag == "dd", let dt = pendingDT else {
				continue
			}
			let dd = element
			pendingDT = nil

			let classTokens = Set((dt.attributes["class"] ?? "").split(separator: " ").map(String.init))
			let label = flattenedText(dt).trimmingCharacters(in: .whitespacesAndNewlines)

			if classTokens.contains("tags") {
				// rating / warning / category / fandom / relationship /
				// character / freeform -- each a <ul class="commas"><li>
				// of <a class="tag" href="...">.
				let entries = tagEntries(fromLinksIn: dd)
				guard !entries.isEmpty else { continue }
				// fandom/relationship/character/freeform can carry dozens
				// or hundreds of tags on a heavily-tagged work -- rendered
				// wide (full preface width, own line) rather than confined
				// to the label-adjacent column like the bounded rows
				// (rating/warning/category, usually one or two values).
				let isWide = classTokens.contains("fandom") || classTokens.contains("relationship") || classTokens.contains("character") || classTokens.contains("freeform")
				rows.append(AO3PrefaceRow(label: label, values: entries, isWide: isWide))
			} else if classTokens.contains("language") {
				let text = flattenedText(dd).trimmingCharacters(in: .whitespacesAndNewlines)
				guard !text.isEmpty else { continue }
				rows.append(AO3PrefaceRow(label: label, values: [AO3TagEntry(text: text)]))
			} else if classTokens.contains("series") {
				let entries = seriesEntries(fromDD: dd)
				guard !entries.isEmpty else { continue }
				rows.append(AO3PrefaceRow(label: label, values: entries))
				(previousWorkURL, nextWorkURL) = previousNextWorkURLs(fromDD: dd)
			} else if classTokens.contains("collections") {
				// Plain comma-separated <a> links directly in the dd, no
				// <ul><li> wrapper -- confirmed a different shape from the
				// tag rows above (ao3-work-single-chapter.html).
				let entries = tagEntries(fromLinksIn: dd)
				guard !entries.isEmpty else { continue }
				rows.append(AO3PrefaceRow(label: label, values: entries))
			} else if classTokens.contains("stats") {
				guard let statsDL = firstDescendant(of: dd, where: { $0.tag == "dl" && $0.attributes["class"] == "stats" }) else {
					continue
				}
				var pendingStatDT: HTMLLiteElement?
				for statElement in directChildElements(of: statsDL) {
					if statElement.tag == "dt" {
						pendingStatDT = statElement
						continue
					}
					guard statElement.tag == "dd", let statDT = pendingStatDT else {
						continue
					}
					pendingStatDT = nil

					let statLabel = flattenedText(statDT).trimmingCharacters(in: .whitespacesAndNewlines)
					// flattenedText, not just the dd's own text, since
					// Bookmarks wraps its number in an <a href=".../bookmarks">
					// (confirmed: entire.html) -- reading only direct text
					// would silently drop it.
					let statValue = flattenedText(statElement).trimmingCharacters(in: .whitespacesAndNewlines)
					guard !statValue.isEmpty else { continue }
					statsRows.append(AO3PrefaceStatsRow(label: statLabel, value: statValue))

					let numeric = Int(statValue.replacingOccurrences(of: ",", with: ""))
					switch statDT.attributes["class"] {
					case "comments": commentCount = numeric
					case "kudos": kudosCount = numeric
					case "bookmarks": bookmarkCount = numeric
					case "hits": hitCount = numeric
					case "words": wordCount = numeric
					default: break
					}
				}
			}
		}

		// Words is still part of statsRows' display text regardless (nothing
		// is lost visually), and Article.wordCount itself stays Workstream
		// 1's (feed-derived) territory, same as chapterTotal/isComplete --
		// AO3ChapterFetcher.rebuildParsedItem always passes
		// existingArticle.wordCount through unchanged, so this parsed value
		// never silently overrides what the feed parser already owns. It's
		// surfaced on AO3WorkHeaderExtraction/AO3ChapterExtractionResult
		// purely for Task 8's content-regression guard to compare a fresh
		// fetch's word count against the stored content's re-derived one.

		guard !rows.isEmpty || !statsRows.isEmpty else {
			return nil
		}
		return AO3WorkHeaderExtraction(
			data: AO3PrefaceData(rows: rows, statsRows: statsRows),
			commentCount: commentCount,
			kudosCount: kudosCount,
			bookmarkCount: bookmarkCount,
			hitCount: hitCount,
			wordCount: wordCount,
			previousWorkURL: previousWorkURL,
			nextWorkURL: nextWorkURL
		)
	}

	/// `<a class="tag" href="...">Name</a>` entries, wherever they sit
	/// (inside `ul.commas > li`, or directly in the dd for
	/// language/collections rows) -- descendant search finds either shape
	/// without needing to special-case the wrapper.
	static func tagEntries(fromLinksIn dd: HTMLLiteElement) -> [AO3TagEntry] {
		descendants(of: dd, where: { $0.tag == "a" }).map {
			AO3TagEntry(text: flattenedText($0).trimmingCharacters(in: .whitespacesAndNewlines), href: $0.attributes["href"])
		}
	}

	/// `<dd class="series">` holds one or more `<span class="series">`
	/// entries (comma-separated in the source when a work belongs to more
	/// than one series -- confirmed in twoseries.html), each wrapping
	/// optional Previous/Next Work navigation links around the one that
	/// actually matters: `<span class="position">Part <N> of
	/// <a href="/series/<id>">Name</a></span>`. Only that inner span is
	/// read; the Previous/Next links are page-navigation chrome, not
	/// metadata about the work itself.
	static func seriesEntries(fromDD dd: HTMLLiteElement) -> [AO3TagEntry] {
		let spans = descendants(of: dd, where: { $0.tag == "span" && $0.attributes["class"] == "series" })
		return spans.compactMap { span in
			guard let positionSpan = firstDescendant(of: span, where: { $0.tag == "span" && $0.attributes["class"] == "position" }) else {
				return nil
			}
			guard let anchor = firstDescendant(of: positionSpan, where: { $0.tag == "a" }) else {
				return nil
			}
			let name = flattenedText(anchor).trimmingCharacters(in: .whitespacesAndNewlines)
			let fullText = flattenedText(positionSpan).trimmingCharacters(in: .whitespacesAndNewlines)
			guard !name.isEmpty, let nameRange = fullText.range(of: name) else {
				return AO3TagEntry(text: name, href: anchor.attributes["href"])
			}
			// Everything before the linked name -- "Part 6 of " -- stays
			// unlinked, matching Ambrosia's own preface style (confirmed:
			// test2.json's Series row links only the series name, not the
			// "Part 1 of" prefix).
			let prefix = String(fullText[fullText.startIndex..<nameRange.lowerBound])
			return AO3TagEntry(text: name, href: anchor.attributes["href"], prefix: prefix)
		}
	}

	/// Task 10 (prev/next/first navigation): the same `<span class="series">`
	/// blocks `seriesEntries(fromDD:)` reads the position text out of also
	/// carry optional `<a class="previous">`/`<a class="next">` Work
	/// navigation links -- previously discarded entirely (see
	/// `seriesEntries(fromDD:)`'s own doc comment); now captured here.
	///
	/// A work in more than one series (confirmed: twoseries.html) gets one
	/// `span.series` block per membership, each with its own
	/// previous/next pair. The reader's prev/next buttons are singular,
	/// though, so the first block that has a link for a given direction
	/// wins for that direction -- in practice a work is almost always in
	/// at most one series, so this only matters for the rare multi-series
	/// case.
	static func previousNextWorkURLs(fromDD dd: HTMLLiteElement) -> (previous: String?, next: String?) {
		let spans = descendants(of: dd, where: { $0.tag == "span" && $0.attributes["class"] == "series" })
		var previous: String?
		var next: String?
		for span in spans {
			if previous == nil, let previousAnchor = firstDescendant(of: span, where: { $0.tag == "a" && $0.attributes["class"] == "previous" }) {
				previous = absoluteURL(previousAnchor.attributes["href"])
			}
			if next == nil, let nextAnchor = firstDescendant(of: span, where: { $0.tag == "a" && $0.attributes["class"] == "next" }) {
				next = absoluteURL(nextAnchor.attributes["href"])
			}
			if previous != nil && next != nil {
				break
			}
		}
		return (previous, next)
	}

	private static let baseURL = "https://archiveofourown.org"

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

	/// `element.children` filtered down to just the `.element` nodes, in
	/// order -- `dl.work.meta.group`'s and the inner `dl.stats`' direct
	/// children alternate dt/dd with only whitespace text nodes between
	/// them, so this is enough to pair them up sequentially without needing
	/// a "next sibling" lookup.
	static func directChildElements(of element: HTMLLiteElement) -> [HTMLLiteElement] {
		element.children.compactMap {
			if case .element(let el) = $0 {
				return el
			}
			return nil
		}
	}
}

// MARK: - Preceding <style> block

private extension AO3ChapterHTMLExtractor {

	/// The workskin `<style>` block, when present, sits immediately before
	/// `#workskin` in document order (separated only by whitespace text --
	/// the comments AO3 emits in between are silently consumed by
	/// `HTMLScanner`, never reaching this tree as nodes). Anything else
	/// found while walking backward past whitespace means there's no skin,
	/// same as `entire.html`'s no-skin sample.
	static func precedingStyleElement(parent: HTMLLiteElement, beforeIndex index: Int) -> HTMLLiteElement? {
		var i = index - 1
		while i >= 0 {
			switch parent.children[i] {
			case .text(let text):
				guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
					return nil
				}
				i -= 1
			case .element(let element):
				return element.tag == "style" ? element : nil
			}
		}
		return nil
	}
}
