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

	/// Inline series navigation: per-series-membership previous/next-work
	/// data, read off each `<span class="series">` block's own
	/// `<a class="previous">`/`<a class="next">` -- see
	/// `seriesEntriesWithNavigation(fromDD:)`. Superseded Task 10's single
	/// article-wide `previousWorkURL`/`nextWorkURL` pair, which collapsed
	/// a work's multiple series memberships down to whichever span had a
	/// link first. Empty when the work has no series membership at all;
	/// otherwise one entry per membership, each with its own (possibly
	/// nil, for first/last-in-that-series) previous/next pair.
	public let seriesEntries: [AO3SeriesSpanResult]

	/// The work's own title, from its `<h2 class="title heading">` --
	/// captured at the same site `stripPhantomTitleHeadingClass` already
	/// locates that heading (see that function's own doc comment), before
	/// it's mutated. Separate from `AO3WorkPageMetadata` (which lives in
	/// the Work Header's `dl.stats` block) since the title itself lives in
	/// a different part of the page -- the work-level `div.preface.group`,
	/// not the metadata table. Used by `AO3ChapterFetcher.rebuildParsedItem`
	/// to correct a series-nav stub's placeholder "AO3 Work N" title (or
	/// refresh any existingArticle's title on an ordinary refetch) with
	/// the real one, matching every other field's live-wins policy in that
	/// function.
	public let title: String?

	/// Structured metadata read off the live work page, surfaced here (not
	/// just rendered into `contentHTML`'s preface) so
	/// `AO3ChapterFetcher.rebuildParsedItem` can populate `Article`'s own
	/// summary/authors/date/tag-group fields for a work reached only
	/// through `AO3SeriesNavigator`'s stub-then-fetch flow, whose stub
	/// never has this data (see that type's doc comment on why series-
	/// listing rows are deliberately left bare). Also used for a refetch
	/// of an article that already has real metadata (search-results/
	/// Ambrosia import) -- `rebuildParsedItem` always prefers this fresh
	/// data over whatever's already stored, treating the live page as the
	/// source of truth.
	public let metadata: AO3WorkPageMetadata

	public init(contentHTML: String, chapters: [AO3ExtractedChapter], commentCount: Int? = nil, kudosCount: Int? = nil, bookmarkCount: Int? = nil, hitCount: Int? = nil, wordCount: Int? = nil, csrfToken: String? = nil, seriesEntries: [AO3SeriesSpanResult] = [], title: String? = nil, metadata: AO3WorkPageMetadata = AO3WorkPageMetadata()) {
		self.contentHTML = contentHTML
		self.chapters = chapters
		self.commentCount = commentCount
		self.kudosCount = kudosCount
		self.bookmarkCount = bookmarkCount
		self.hitCount = hitCount
		self.wordCount = wordCount
		self.csrfToken = csrfToken
		self.seriesEntries = seriesEntries
		self.title = title
		self.metadata = metadata
	}
}

/// Structured fields read off a live work page's byline, summary, and
/// `dl.work.meta.group` tag rows/stats -- everything `rebuildParsedItem`
/// needs to fill in what a series-nav stub leaves nil, or to refresh what
/// an already-real article has on a normal "Check for updates" refetch.
/// Every field is nil/empty when the page shape it comes from wasn't
/// found (gated page, or a shape not yet sampled) -- same "optional,
/// absence isn't a hard failure" precedent `parseWorkHeader` already
/// follows for the metadata block as a whole.
public struct AO3WorkPageMetadata: Sendable {
	/// `h3.byline.heading`'s `a[rel=author]` anchors, in `div.preface.group`
	/// (the work-level one, before any chapter's own preface) -- same
	/// row shape `AO3SearchResultsExtractor` reads off a listing row's
	/// heading, just a different container on the full work page.
	public let authors: Set<ParsedAuthor>
	/// `div.summary.module`'s `blockquote.userstuff`, serialized as HTML
	/// the same way `AO3SearchResultsExtractor.summaryHTML` does for a
	/// listing row's `blockquote.summary`, so both sources produce the
	/// same shape `ArticleStringFormatter` already expects.
	public let summary: String?
	/// `dt.published`/`dd.published` inside the meta group's `dl.stats` --
	/// present on every real work page (unlike the search-listing page,
	/// which exposes only "last updated"), so this is the one place
	/// `datePublished` can be recovered for a series-nav stub.
	public let datePublished: Date?
	/// `dt.status`/`dd.status` in the same `dl.stats` -- labeled
	/// "Updated:" or "Completed:" depending on the work's state (same
	/// `dt`/`dd` class either way, see `parseWorkHeader`'s own doc
	/// comment on why class, not label text, is what's keyed on here).
	public let dateModified: Date?
	public let fandoms: [String]
	public let relationships: [String]
	public let characters: [String]
	public let ratings: [String]
	public let warnings: [String]
	public let categories: [String]
	/// Freeform "Additional Tags" -- `dt.freeform.tags`/`dd.freeform.tags`.
	/// Distinct from the other tag groups above in that `Article` has no
	/// persisted field for it yet (see `ParsedItem.tags`'s own doc
	/// comment on why the JSON Feed `tags` field is parsed but dropped
	/// everywhere else in the app) -- kept here regardless, ready for
	/// that field to be added.
	public let additionalTags: [String]

	public init(authors: Set<ParsedAuthor> = [], summary: String? = nil, datePublished: Date? = nil, dateModified: Date? = nil, fandoms: [String] = [], relationships: [String] = [], characters: [String] = [], ratings: [String] = [], warnings: [String] = [], categories: [String] = [], additionalTags: [String] = []) {
		self.authors = authors
		self.summary = summary
		self.datePublished = datePublished
		self.dateModified = dateModified
		self.fandoms = fandoms
		self.relationships = relationships
		self.characters = characters
		self.ratings = ratings
		self.warnings = warnings
		self.categories = categories
		self.additionalTags = additionalTags
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
	/// instance) -- since an unsampled restricted-page shape can't be told
	/// apart from a real 404 here, `AO3ChapterFetcher.download` retries
	/// authenticated on this outcome the same as `.registrationRequired`,
	/// rather than treating it as definitively unretryable.
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
				let title = stripPhantomTitleHeadingClass(inWorkSkin: workSkinDiv)

				let chapters = chapterDivs.compactMap(extractedChapter)
				let assembled = serializedContentHTML(root: root, workSkinParent: workSkinParent, workSkinIndex: workSkinIndex, workSkinDiv: workSkinDiv)

				return .success(AO3ChapterExtractionResult(contentHTML: assembled.contentHTML, chapters: chapters, commentCount: assembled.commentCount, kudosCount: assembled.kudosCount, bookmarkCount: assembled.bookmarkCount, hitCount: assembled.hitCount, wordCount: assembled.wordCount, csrfToken: csrfToken(root: root), seriesEntries: assembled.seriesEntries, title: title, metadata: assembled.metadata))
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
				// Same as the multi-chapter branch: strip the work's own
				// title heading down to a plain, non-heading <h2
				// class="title"> so it isn't double-counted by tocNodes()
				// (main_ios.js: `h1, h2.heading, h2.toc-heading`).
				//
				// A single-chapter work has no per-chapter heading to take
				// its place, but that's fine -- template.html already
				// wraps every article's own title in a top-level <h1>
				// (`<div class="articleTitle"><h1>...`), independent of
				// anything parsed here, and that's what tocNodes() is
				// meant to find for a single-chapter work.
				// TableOfContentsViewController's flat/non-anthology case
				// falls back to that lone <h1> entry when there are no
				// <h2> chapters (see its own comment).
				//
				// This used to call promoteTitleHeadingToH1 to rewrite
				// this heading to <h1> instead of stripping it, on the
				// theory that tocNodes() would otherwise find nothing.
				// That doubled up with template.html's own <h1>: the
				// document had two <h1>s, bookEntries.count became 2,
				// isAnthology went true, and the ToC rendered two
				// un-collapsible rows for a single-chapter work instead of
				// one. Do not reintroduce that without also accounting
				// for template.html's own heading.
				let singleChapterTitle = stripPhantomTitleHeadingClass(inWorkSkin: workSkinDiv)
				stripLandmarkHeading(from: chaptersDiv)

				let chapters = [AO3ExtractedChapter(id: "chapter-1", title: "Chapter 1")]
				let assembled = serializedContentHTML(root: root, workSkinParent: workSkinParent, workSkinIndex: workSkinIndex, workSkinDiv: workSkinDiv)

				return .success(AO3ChapterExtractionResult(contentHTML: assembled.contentHTML, chapters: chapters, commentCount: assembled.commentCount, kudosCount: assembled.kudosCount, bookmarkCount: assembled.bookmarkCount, hitCount: assembled.hitCount, wordCount: assembled.wordCount, csrfToken: csrfToken(root: root), seriesEntries: assembled.seriesEntries, title: singleChapterTitle, metadata: assembled.metadata))
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
	/// request -- see this file's header comment. `nil` if the tag is missing
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

	/// Registration-required login wall -- see `AO3HTMLHelpers.isRegistrationRequired`.
	/// Previously matched on `div#signin`'s bare presence only; reconciled
	/// to the stricter text-matching version also used by
	/// `AO3SearchResultsExtractor`, since a signin div shown for an
	/// unrelated reason (rate limiting, a different notice) shouldn't
	/// read as "registration required" here either.
	static func isRegistrationRequired(_ root: HTMLLiteElement) -> Bool {
		AO3HTMLHelpers.isRegistrationRequired(root)
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
	///
	/// Returns the heading's flattened text (trimmed, nil if empty) before
	/// the `class` attribute rewrite -- the rewrite only touches the class
	/// attribute, never the text node, so this is exactly the title AO3
	/// itself rendered. Callers use this to populate
	/// `AO3ChapterExtractionResult.title`, since nothing else on the page
	/// captures the work's own title into a structured field (see that
	/// property's own doc comment).
	@discardableResult
	static func stripPhantomTitleHeadingClass(inWorkSkin workSkinDiv: HTMLLiteElement) -> String? {
		guard let workPreface = firstDescendant(of: workSkinDiv, where: {
			$0.tag == "div" && $0.attributes["class"] == "preface group"
		}) else {
			return nil
		}
		guard let titleHeading = firstDescendant(of: workPreface, where: { $0.tag == "h2" }) else {
			return nil
		}
		let title = flattenedText(titleHeading).trimmingCharacters(in: .whitespacesAndNewlines)
		titleHeading.attributes["class"] = "title"
		return title.isEmpty ? nil : title
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
	struct SerializedContent {
		let contentHTML: String
		let commentCount: Int?
		let kudosCount: Int?
		let bookmarkCount: Int?
		let hitCount: Int?
		let wordCount: Int?
		let seriesEntries: [AO3SeriesSpanResult]
		let metadata: AO3WorkPageMetadata
	}

	static func serializedContentHTML(root: HTMLLiteElement, workSkinParent: HTMLLiteElement, workSkinIndex: Int, workSkinDiv: HTMLLiteElement) -> SerializedContent {
		var contentHTML = ""
		var counts = (commentCount: Int?.none, kudosCount: Int?.none, bookmarkCount: Int?.none, hitCount: Int?.none, wordCount: Int?.none)
		var seriesEntries: [AO3SeriesSpanResult] = []
		var metadata = AO3WorkPageMetadata()

		if let workHeader = parseWorkHeader(root: root) {
			if let prefaceHTML = AO3PrefaceRenderer.html(id: "ao3Preface", data: workHeader.data) {
				contentHTML += prefaceHTML
			}
			counts = (workHeader.commentCount, workHeader.kudosCount, workHeader.bookmarkCount, workHeader.hitCount, workHeader.wordCount)
			seriesEntries = workHeader.seriesEntries

			// Byline/summary live in the work-level `div.preface.group`
			// (inside `#workskin`), not the `dl.work.meta.group` metadata
			// block `parseWorkHeader` just parsed -- a separate, narrower
			// search scoped to workSkinDiv, same distinction
			// `stripPhantomTitleHeadingClass`'s doc comment already draws
			// between the two.
			let preface = workPreface(workSkinDiv)
			let authors = preface.map(bylineAuthors) ?? []
			let summary = preface.flatMap(summaryHTML)

			metadata = AO3WorkPageMetadata(
				authors: authors,
				summary: summary,
				datePublished: workHeader.datePublished,
				dateModified: workHeader.dateModified,
				fandoms: workHeader.fandoms,
				relationships: workHeader.relationships,
				characters: workHeader.characters,
				ratings: workHeader.ratings,
				warnings: workHeader.warnings,
				categories: workHeader.categories,
				additionalTags: workHeader.additionalTags
			)
		}
		if let styleElement = precedingStyleElement(parent: workSkinParent, beforeIndex: workSkinIndex) {
			contentHTML += serializeHTMLLiteNodes([.element(styleElement)])
		}
		contentHTML += serializeHTMLLiteNodes([.element(workSkinDiv)])
		// Inline series navigation footer: appended immediately after
		// workSkinDiv's own content, from the same per-span data just
		// parsed above, so the top preface links and this bottom "This
		// work is part of" block always agree (same source data, two
		// render calls) instead of drifting. Absent entirely (no
		// #ao3SeriesFooter div at all) when the work has no series
		// membership -- matches the no-fandom/no-warnings "don't render an
		// empty row" precedent elsewhere in this preface pipeline.
		if let footerHTML = AO3PrefaceRenderer.seriesFooterHTML(entries: seriesEntries.map(\.entry)) {
			contentHTML += footerHTML
		}
		return SerializedContent(
			contentHTML: contentHTML,
			commentCount: counts.commentCount,
			kudosCount: counts.kudosCount,
			bookmarkCount: counts.bookmarkCount,
			hitCount: counts.hitCount,
			wordCount: counts.wordCount,
			seriesEntries: seriesEntries,
			metadata: metadata
		)
	}
}

// MARK: - Byline / summary (work-level preface, inside #workskin)

private extension AO3ChapterHTMLExtractor {

	/// The work-level `div.preface.group` -- first one found under
	/// `workSkinDiv`, distinct from each chapter's own
	/// `div.chapter.preface.group` (confirmed: the work-level one has no
	/// `chapter` class token, matching `stripPhantomTitleHeadingClass`'s
	/// existing selector for the same container).
	static func workPreface(_ workSkinDiv: HTMLLiteElement) -> HTMLLiteElement? {
		firstDescendant(of: workSkinDiv, where: {
			$0.tag == "div" && $0.attributes["class"] == "preface group"
		})
	}

	/// `h3.byline.heading`'s `a[rel=author]` anchors -- same selector
	/// `AO3SearchResultsExtractor` uses for a listing row's heading,
	/// scoped here to the work-level byline instead.
	static func bylineAuthors(_ workPreface: HTMLLiteElement) -> Set<ParsedAuthor> {
		guard let bylineH3 = firstDescendant(of: workPreface, where: {
			$0.tag == "h3" && classTokens(of: $0).contains("byline")
		}) else {
			return []
		}
		let authorAnchors = descendants(of: bylineH3, where: { $0.tag == "a" && $0.attributes["rel"] == "author" })
		return Set(authorAnchors.compactMap { anchor -> ParsedAuthor? in
			let name = flattenedText(anchor).trimmingCharacters(in: .whitespacesAndNewlines)
			guard !name.isEmpty else { return nil }
			return ParsedAuthor(name: name, url: absoluteURL(anchor.attributes["href"]), avatarURL: nil, emailAddress: nil)
		})
	}

	/// `div.summary.module`'s `blockquote.userstuff`, serialized as HTML
	/// the same way `AO3SearchResultsExtractor.summaryHTML` serializes a
	/// listing row's `blockquote.summary` -- same downstream shape
	/// (`ArticleStringFormatter`), different source container/class.
	static func summaryHTML(_ workPreface: HTMLLiteElement) -> String? {
		guard let summaryModule = firstDescendant(of: workPreface, where: {
			$0.tag == "div" && classTokens(of: $0).contains("summary") && classTokens(of: $0).contains("module")
		}) else {
			return nil
		}
		guard let blockquote = firstDescendant(of: summaryModule, where: {
			$0.tag == "blockquote"
		}) else {
			return nil
		}
		let serialized = serializeHTMLLiteNodes(blockquote.children)
		return serialized.isEmpty ? nil : serialized
	}

	static func classTokens(of element: HTMLLiteElement) -> [String] {
		AO3HTMLHelpers.classTokens(of: element)
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
	let seriesEntries: [AO3SeriesSpanResult]
	// Tag-group rows, discrete text values (not display-formatted
	// AO3TagEntry) -- for AO3ChapterFetcher.rebuildParsedItem to populate
	// Article's own fandoms/relationships/etc fields, independent of
	// whatever the generic AO3PrefaceRow rendering above does with the
	// same rows.
	let fandoms: [String]
	let relationships: [String]
	let characters: [String]
	let ratings: [String]
	let warnings: [String]
	let categories: [String]
	let additionalTags: [String]
	// dl.stats' Published:/Updated:(or Completed:) rows, parsed as Date --
	// distinct from the four count fields above, which come from the same
	// dl.stats but stay Int.
	let datePublished: Date?
	let dateModified: Date?
}

/// One `<span class="series">` block's full data: `entry` is the
/// persistable/navigable data (name/index/ao3ID/previousWorkURL/
/// nextWorkURL, as a `ParsedSeriesEntry` -- see that type's doc comment
/// for why previous/next live here now instead of as a single article-wide
/// pair). `href`/`prefix` are the display-only fields the top preface's
/// `<dt>Series:</dt><dd>` row needs (the linked series name's own href,
/// and the unlinked "Part N of " prefix text) -- kept alongside `entry`
/// rather than folded into it, since neither is meaningful outside a
/// rendered row.
public struct AO3SeriesSpanResult: Sendable {
	public let entry: ParsedSeriesEntry
	public let href: String?
	public let prefix: String

	public init(entry: ParsedSeriesEntry, href: String?, prefix: String) {
		self.entry = entry
		self.href = href
		self.prefix = prefix
	}
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
		var seriesEntries: [AO3SeriesSpanResult] = []
		var fandoms: [String] = []
		var relationships: [String] = []
		var characters: [String] = []
		var ratings: [String] = []
		var warnings: [String] = []
		var categories: [String] = []
		var additionalTags: [String] = []
		var datePublished: Date?
		var dateModified: Date?

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
				// (rating/category, usually one or two short values).
				// warning is bounded the same way value-count-wise, but
				// each value is a long fixed AO3 phrase (up to "Creator
				// Chose Not To Use Archive Warnings") and works commonly
				// carry two or three at once -- wide for the same reason
				// as the others, just long text instead of many entries.
				let isWide = classTokens.contains("fandom") || classTokens.contains("relationship") || classTokens.contains("character") || classTokens.contains("freeform") || classTokens.contains("warning")
				rows.append(AO3PrefaceRow(label: label, values: entries, isWide: isWide))

				// Same rows, discrete text values -- for
				// AO3ChapterFetcher.rebuildParsedItem, independent of the
				// AO3PrefaceRow rendering above. Keyed on class the same
				// way the row-shape switch above already is, not label
				// text (see parseWorkHeader's own doc comment on "Rating:"
				// vs "Ratings:" etc.).
				let texts = entries.map(\.text)
				if classTokens.contains("fandom") {
					fandoms.append(contentsOf: texts)
				} else if classTokens.contains("relationship") {
					relationships.append(contentsOf: texts)
				} else if classTokens.contains("character") {
					characters.append(contentsOf: texts)
				} else if classTokens.contains("rating") {
					ratings.append(contentsOf: texts)
				} else if classTokens.contains("warning") {
					warnings.append(contentsOf: texts)
				} else if classTokens.contains("category") {
					categories.append(contentsOf: texts)
				} else if classTokens.contains("freeform") {
					additionalTags.append(contentsOf: texts)
				}
			} else if classTokens.contains("language") {
				let text = flattenedText(dd).trimmingCharacters(in: .whitespacesAndNewlines)
				guard !text.isEmpty else { continue }
				rows.append(AO3PrefaceRow(label: label, values: [AO3TagEntry(text: text)]))
			} else if classTokens.contains("series") {
				let spanResults = seriesEntriesWithNavigation(fromDD: dd)
				guard !spanResults.isEmpty else { continue }
				// isSeriesNavigation: true routes this row through
				// AO3PrefaceRenderer.html(id:data:)'s per-entry dt/dd
				// rendering (Phase 3b) instead of the generic
				// comma-joined-into-one-dd path every other row uses --
				// each entry's ao3ID/previousWorkURL/nextWorkURL come
				// straight off the same per-span parse the footer below
				// (seriesEntries) also uses, so the top row's First/
				// Previous/Next links and the bottom "This work is part
				// of" block always agree.
				let displayEntries = spanResults.map { result in
					AO3TagEntry(text: result.entry.name, href: result.href, prefix: result.prefix, ao3ID: result.entry.ao3ID, previousWorkURL: result.entry.previousWorkURL, nextWorkURL: result.entry.nextWorkURL, index: result.entry.index)
				}
				rows.append(AO3PrefaceRow(label: label, values: displayEntries, isSeriesNavigation: true))
				seriesEntries = spanResults
			} else if classTokens.contains("collections") {
				// Plain comma-separated <a> links directly in the dd, no
				// <ul><li> wrapper -- confirmed a different shape from the
				// tag rows above (ao3-work-single-chapter.html). isWide:
				// true for the same reason as fandom/relationship/
				// character/freeform above -- a work in several
				// collections otherwise wraps inside the narrow
				// label-adjacent column instead of using the preface's
				// full width.
				let entries = tagEntries(fromLinksIn: dd)
				guard !entries.isEmpty else { continue }
				rows.append(AO3PrefaceRow(label: label, values: entries, isWide: true))
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
					case "published": datePublished = Self.workPageDate(fromStatValue: statValue)
					// "status" covers both "Updated:" and "Completed:"
					// labels (same dt/dd class either way -- see this
					// function's own doc comment) -- either way it's the
					// work's current dateModified.
					case "status": dateModified = Self.workPageDate(fromStatValue: statValue)
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
			seriesEntries: seriesEntries,
			fandoms: fandoms,
			relationships: relationships,
			characters: characters,
			ratings: ratings,
			warnings: warnings,
			categories: categories,
			additionalTags: additionalTags,
			datePublished: datePublished,
			dateModified: dateModified
		)
	}

	/// AO3's `dl.stats` Published/Updated/Completed values are plain
	/// `YYYY-MM-DD` (confirmed: ao3-work-multi-chapter.html's
	/// `"2026-07-07"`/`"2026-08-01"`) -- no time component, unlike the
	/// search-listing page's `<time datetime="...">` attribute
	/// `AO3SearchResultsExtractor.datetime(fromLI:)` reads instead. A
	/// fixed-format parser rather than ISO8601DateFormatter, which expects
	/// a full date-time and would reject a bare date.
	static func workPageDate(fromStatValue value: String) -> Date? {
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(identifier: "UTC")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter.date(from: value)
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
	/// <a href="/series/<id>">Name</a></span>`.
	///
	/// Merges what used to be two independent walks of the same span list
	/// (`seriesEntries(fromDD:)` for the display name/index/ao3ID,
	/// `previousNextWorkURLs(fromDD:)` for prev/next) into one pass, so
	/// each span's own previous/next pairs with its own series membership
	/// instead of collapsing every membership's navigation down to
	/// whichever span happened to have a link first (Task 10's original,
	/// now-superseded "first span wins" behavior). One `AO3SeriesSpanResult`
	/// per span, in document order; a span this can't parse a position/name
	/// out of is dropped (matches the old `seriesEntries(fromDD:)`'s
	/// `compactMap` behavior).
	static func seriesEntriesWithNavigation(fromDD dd: HTMLLiteElement) -> [AO3SeriesSpanResult] {
		let spans = descendants(of: dd, where: { $0.tag == "span" && $0.attributes["class"] == "series" })
		return spans.compactMap { span -> AO3SeriesSpanResult? in
			guard let positionSpan = firstDescendant(of: span, where: { $0.tag == "span" && $0.attributes["class"] == "position" }) else {
				return nil
			}
			guard let anchor = firstDescendant(of: positionSpan, where: { $0.tag == "a" }) else {
				return nil
			}
			let name = flattenedText(anchor).trimmingCharacters(in: .whitespacesAndNewlines)
			guard !name.isEmpty else {
				return nil
			}
			let fullText = flattenedText(positionSpan).trimmingCharacters(in: .whitespacesAndNewlines)
			// Everything before the linked name -- "Part 6 of " -- stays
			// unlinked, matching Ambrosia's own preface style (confirmed:
			// test2.json's Series row links only the series name, not the
			// "Part 1 of" prefix).
			let prefix: String
			if let nameRange = fullText.range(of: name) {
				prefix = String(fullText[fullText.startIndex..<nameRange.lowerBound])
			} else {
				prefix = ""
			}

			let ao3ID = seriesID(fromHref: anchor.attributes["href"])
			// "Part <N> of " -- same regex-free digit scan as the prefix
			// text itself, since fullText already has it isolated. A work
			// reached only via a refetch of an *existing* article carries
			// its already-known index straight through unchanged
			// (AO3ChapterFetcher.rebuildParsedItem maps existingArticle.series
			// through as-is); this parse only matters for a work with no
			// prior ArticleSeriesEntry to carry forward from (first-ever
			// import via Phase 4's bulk series import) -- treat a failed
			// parse there as 0 rather than silently guessing, since a wrong
			// index would pick the wrong series-listing page in that flow.
			let index = Self.parsedIndex(fromPositionText: fullText) ?? 0

			var previousWorkURL: String?
			var nextWorkURL: String?
			if let previousAnchor = firstDescendant(of: span, where: { $0.tag == "a" && $0.attributes["class"] == "previous" }) {
				previousWorkURL = absoluteURL(previousAnchor.attributes["href"])
			}
			if let nextAnchor = firstDescendant(of: span, where: { $0.tag == "a" && $0.attributes["class"] == "next" }) {
				nextWorkURL = absoluteURL(nextAnchor.attributes["href"])
			}

			let entry = ParsedSeriesEntry(name: name, index: index, ao3ID: ao3ID, previousWorkURL: previousWorkURL, nextWorkURL: nextWorkURL)
			return AO3SeriesSpanResult(entry: entry, href: anchor.attributes["href"], prefix: prefix)
		}
	}

	/// "Part <N> of " -> `N`, reading only the digits between "Part " and
	/// " of " in the span's own flattened text (the same text
	/// `seriesEntriesWithNavigation(fromDD:)` already has in hand -- no
	/// separate DOM walk needed). `nil` if the text doesn't start with
	/// "Part " or the digits between don't parse, so the caller can treat
	/// a genuinely unparseable index as distinct from a real "0".
	static func parsedIndex(fromPositionText text: String) -> Int? {
		guard text.hasPrefix("Part ") else {
			return nil
		}
		guard let ofRange = text.range(of: " of ") else {
			return nil
		}
		let indexString = text[text.index(text.startIndex, offsetBy: "Part ".count)..<ofRange.lowerBound]
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return Int(indexString)
	}

	/// Shared with `AO3SearchResultsExtractor`/`AO3SummaryExtractor` via
	/// `AO3HTMLHelpers.seriesID(fromHref:)`.
	static func seriesID(fromHref href: String?) -> String? {
		AO3HTMLHelpers.seriesID(fromHref: href)
	}

	/// Shared with `AO3SearchResultsExtractor`/`AO3SeriesListingExtractor`
	/// via `AO3HTMLHelpers.absoluteURL(_:)`.
	static func absoluteURL(_ href: String?) -> String? {
		AO3HTMLHelpers.absoluteURL(href)
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
