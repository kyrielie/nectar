//
//  AO3FetchPolicy.swift
//  AO3Kit
//
//  Pure decisions about whether and how an AO3 work fetch applies to an
//  Article, split out of Account's AO3ChapterFetcher because none of it
//  needs Account types: which articles may touch the network, which are
//  due for a refetch, whether a fetched page looks like a regression
//  against stored content, and how a successful extraction turns back
//  into a ParsedItem. AO3ChapterFetcher (Account) keeps the orchestration:
//  attempt gating, transports, activity logging and database writes.
//
//  `isStale` takes `now` and `interval` as parameters so tests are
//  deterministic; the defaults read the real clock and the user's
//  AO3PrefaceRefetchPreference.
//

import Foundation
import Articles
import RSParser

public enum AO3FetchPolicy {

	/// The AO3 work id for an `ao3-work:<id>` bookKey, nil for anything
	/// else (an anthology/combined-series key, an Ambrosia book key, nil).
	public static func workID(fromBookKey bookKey: String) -> String? {
		AO3Link.workID(fromBookKey: bookKey)
	}

	/// The reverse of `workID(fromBookKey:)` -- `ParsedItem.bookKey`'s own
	/// formula for a bare AO3 work id with no series/anthology grouping
	/// (`ao3SeriesID`/`isAnthology` both nil), which is what every AO3
	/// series-navigation stub and fetch always is. Kept non-optional,
	/// unlike `AO3Link.workBookKey(forWorkID:)`: every caller already
	/// holds a digit-only id validated upstream, so this stays the simple
	/// formula. A caller that needs the optional-id case calls
	/// `AO3Link.workBookKey(forWorkID:)` directly instead.
	public static func bookKey(forWorkID workID: String) -> String {
		"\(BookKeyPrefix.ao3Work)\(workID)"
	}

	/// True unless `article` is Ambrosia-sourced and
	/// `AmbrosiaAO3NetworkPreference.updatesEnabled` is off -- the
	/// pre-request guard for keeping a local-archive-only reader off AO3
	/// servers entirely. A pre-request guard, not a post-fetch filter:
	/// when this is false, no request is made at all, not just "result
	/// discarded." Native (non-Ambrosia) AO3-RSS-sourced articles always
	/// return true here -- they have no other way to get content at all.
	public static func isNetworkRequestAllowed(for article: Article) -> Bool {
		guard article.isAmbrosiaItem else {
			return true
		}
		return AmbrosiaAO3NetworkPreference.updatesEnabled
	}

	/// True if `article` is a single AO3 work (not an anthology/combined-
	/// series bookKey) that an explicit "Check for updates" could act on
	/// right now -- i.e. no unresolved pending-update diff is blocking a
	/// re-check. For UI use, to decide whether to show or enable the
	/// action at all.
	public static func canCheckForUpdates(for article: Article) -> Bool {
		guard workID(fromBookKey: article.bookKey) != nil else {
			return false
		}
		return article.pendingUpdateContentHTML == nil
	}

	/// True when the article has no stored content yet, or when it does
	/// but the user's chosen refetch cadence says the last successful
	/// fetch through this mechanism is old enough to check again --
	/// otherwise a work's comments/kudos/hits/formatting would never
	/// update again. Staleness is cadence-only: it does not compare the
	/// stored content's chapter count against the feed-reported
	/// `chapterCurrent`, because an unthrottled feed refresh can rewrite
	/// that independent of what this fetcher last wrote. A content-present
	/// article with no recorded `lastPrefaceFetchDate` (an Ambrosia
	/// import, or any row never fetched through this mechanism) is due
	/// rather than left alone, since there is no prior fetch to have been
	/// recent. Actual network access is gated separately by
	/// `isNetworkRequestAllowed` at the call sites.
	///
	/// Guard order matters and is part of the contract: pending update,
	/// regression flag, confirmed missing, empty content, no preface
	/// date, cadence.
	public static func isStale(_ article: Article, now: Date = Date(), interval: TimeInterval = AO3PrefaceRefetchPreference.current.timeInterval) -> Bool {
		// An unresolved pending-update diff or a metadata-level
		// regression flag both mean "leave contentHTML exactly as
		// archived until the person acts" -- skip on-open fetching for
		// either state. The explicit per-article "Check for updates"
		// action bypasses this function for the flag case, but still
		// separately blocks on pendingUpdateContentHTML itself.
		guard article.pendingUpdateContentHTML == nil else {
			return false
		}
		guard article.wordCountRegressionFlaggedAt == nil else {
			return false
		}
		// AO3 has confirmed this work is gone or inaccessible -- don't
		// keep retrying it every cadence interval forever. Cleared
		// automatically on a subsequent successful fetch, or when Clear
		// Content clears contentHTML, so this does not permanently lock
		// a row out.
		guard article.ao3ConfirmedMissingAt == nil else {
			return false
		}
		guard let contentHTML = article.contentHTML, !contentHTML.isEmpty else {
			return true
		}
		guard let lastPrefaceFetchDate = article.lastPrefaceFetchDate else {
			return true
		}
		return now.timeIntervalSince(lastPrefaceFetchDate) >= interval
	}

	/// Re-derives the currently stored content's chapter/word counts by
	/// walking the stored `contentHTML`'s own `#workskin` wrapper back
	/// through `AO3ChapterHTMLExtractor.extract` (the stored contentHTML
	/// *is* that wrapper) and compares against this fetch's counts. Returns a
	/// short human-readable description of what regressed (for the
	/// Activity Log message), or nil if this fetch looks fine to write
	/// through normally.
	///
	/// A fewer-chapters count is always a regression, independent of the
	/// word-count threshold (full deletion is handled fine elsewhere --
	/// a missing work leaves existing content alone -- this is specifically
	/// for a legitimate-looking edit that shrinks a work). Word count only
	/// counts as a regression once it clears `AO3RegressionThreshold`'s
	/// 10%-and-300-word bar, using the identical threshold the metadata-
	/// level watch in `Article+Database.changesFrom` uses.
	public static func detectRegression(existingArticle: Article, extraction: AO3ChapterExtractionResult) -> String? {
		guard let storedHTML = existingArticle.contentHTML, !storedHTML.isEmpty,
			  case .success(let storedExtraction) = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: storedHTML) else {
			// Nothing stored yet, or the stored content can't be
			// re-parsed -- nothing to regress against, so the first
			// successful fetch for an article always writes through.
			return nil
		}

		let oldChapterCount = storedExtraction.chapters.count
		let newChapterCount = extraction.chapters.count
		if newChapterCount < oldChapterCount {
			return "chapter count \(oldChapterCount) -> \(newChapterCount)"
		}

		if let oldWordCount = storedExtraction.wordCount, let newWordCount = extraction.wordCount,
		   AO3RegressionThreshold.isRegression(from: oldWordCount, to: newWordCount) {
			return "word count \(oldWordCount) -> \(newWordCount)"
		}

		return nil
	}

	/// Builds the `ParsedItem` that writes a successful fetch back through
	/// `Account.updateAsync`.
	///
	/// Copies every field from `existingArticle` unchanged except
	/// `contentHTML` (the freshly fetched, workskin-preserving HTML),
	/// `chapterCurrent` (bumped to the chapter count actually found in this
	/// fetch), and the four AO3 Work Header stats counts (commentCount/
	/// kudosCount/bookmarkCount/hitCount, taken from this fetch's
	/// extraction rather than the existing article, so they refresh on
	/// every successful re-fetch the same way chapterCurrent does).
	/// `chapterTotal`/`isComplete` are left as whatever the article
	/// already has -- those are Workstream 1's (feed-derived) territory, and
	/// a partial chapter fetch shouldn't be used to infer completion.
	///
	/// `tags` and `language` have no persisted home on `Article` at all (see
	/// ParsedItem/Article field lists), so both are passed through as nil --
	/// this doesn't blank anything that was ever actually stored.
	///
	/// `applyStatsUpdate` is the Ambrosia local-only toggle
	/// (`AmbrosiaAO3NetworkPreference.updatesEnabled`) -- always true for
	/// a non-Ambrosia article, since those have no other way to get
	/// content at all. When false, the stats fields
	/// (comment/kudos/bookmark/hit count) pass `existingArticle`'s own
	/// current values through unchanged instead of this fetch's. There is
	/// no equivalent content-side flag: content, chapter count, and
	/// prev/next-work navigation are always taken from `extraction` once
	/// a fetch has been allowed to happen at all, protected instead by
	/// `detectRegression` at the call site, before this function is ever
	/// reached.
	public static func rebuildParsedItem(from existingArticle: Article, workID: String, extraction: AO3ChapterExtractionResult, applyStatsUpdate: Bool) -> ParsedItem {
		// Metadata fields (author/summary/date/tag-groups): always prefer
		// what this fetch's live page parsed (AO3ChapterHTMLExtractor's
		// AO3WorkPageMetadata), falling back to existingArticle's own
		// stored value only when the live page didn't have that field at
		// all -- the metadata block being absent entirely (gated page, or
		// a shape not yet sampled -- see parseWorkHeader's own doc
		// comment on why it's optional), not merely empty. This is what
		// fixes a series-nav stub (AO3SeriesNavigator.placeholderStub,
		// summary/authors/date/tags all nil) never getting real metadata
		// past the bare stub: previously every one of these fields below
		// passed existingArticle's value straight through unchanged, which
		// for a stub meant "nil forever." An article that already has real
		// metadata (search-results/Ambrosia import) gets the same
		// always-overwrite treatment on every refetch, so a Check-for-
		// updates or open-time refetch can't get stuck on stale metadata
		// either -- the live page is the source of truth, not whatever's
		// already in the database.
		let metadata = extraction.metadata
		let authors: Set<ParsedAuthor>? = metadata.authors.isEmpty
			? existingArticle.authors.map { authorSet in
				Set(authorSet.map { ParsedAuthor(name: $0.name, url: $0.url, avatarURL: $0.avatarURL, emailAddress: $0.emailAddress) })
			}
			: metadata.authors
		let summary = metadata.summary ?? existingArticle.summary
		let datePublished = metadata.datePublished ?? existingArticle.datePublished
		let dateModified = metadata.dateModified ?? existingArticle.dateModified
		let fandoms = metadata.fandoms.isEmpty ? existingArticle.fandoms : metadata.fandoms
		let relationships = metadata.relationships.isEmpty ? existingArticle.relationships : metadata.relationships
		let characters = metadata.characters.isEmpty ? existingArticle.characters : metadata.characters
		let ratings = metadata.ratings.isEmpty ? existingArticle.ratings : metadata.ratings
		let warnings = metadata.warnings.isEmpty ? existingArticle.warnings : metadata.warnings
		let categories = metadata.categories.isEmpty ? existingArticle.categories : metadata.categories
		// Additional Tags (freeform): ParsedItem.tags is the only carrier
		// today -- Article has no persisted field for it yet (see
		// ParsedItem.tags's own doc comment). Passed through regardless,
		// ready for that field once it exists; currently dropped
		// downstream the same way every other source of ParsedItem.tags
		// already is.
		let additionalTags: Set<String>? = metadata.additionalTags.isEmpty ? nil : Set(metadata.additionalTags)

		// Inline series navigation: prefer the existing article's own
		// already-known series membership, carried through unchanged
		// (name/index/ao3ID *and*, now, previousWorkURL/nextWorkURL --
		// dropping the latter two here would silently discard per-series
		// nav data on every refetch). Falls back to this fetch's freshly
		// parsed seriesEntries only when there's no existing series at all
		// to carry forward -- the first-ever fetch of a work reached via
		// Phase 4's bulk series import, whose stub (AO3SeriesNavigator's
		// stub builder) never sets `series`.
		let series: [ParsedSeriesEntry]?
		if let existingSeries = existingArticle.series, !existingSeries.isEmpty {
			series = existingSeries.map { ParsedSeriesEntry(name: $0.name, index: $0.index, ao3ID: $0.ao3ID, previousWorkURL: $0.previousWorkURL, nextWorkURL: $0.nextWorkURL) }
		} else {
			series = extraction.seriesEntries.map(\.entry)
		}

		return ParsedItem(
			syncServiceID: nil,
			uniqueID: existingArticle.uniqueID,
			feedURL: existingArticle.feedID,
			url: existingArticle.rawLink,
			externalURL: existingArticle.rawExternalLink,
			title: extraction.title ?? existingArticle.title,
			language: nil,
			contentHTML: extraction.contentHTML,
			contentText: existingArticle.contentText,
			// existingArticle.markdown is expected nil for every AO3-sourced
			// article (markdown is an Ambrosia/JSON-Feed-only concept, never
			// populated from an AO3 Atom feed) -- passing it through as-is is
			// still correct field-copying, but flag the interaction: if this
			// were ever non-nil, ParsedItem's init would re-render markdown
			// to HTML and discard the contentHTML fetched above entirely.
			markdown: existingArticle.markdown,
			summary: summary,
			imageURL: existingArticle.rawImageLink,
			bannerImageURL: nil,
			datePublished: datePublished,
			dateModified: dateModified,
			authors: authors,
			tags: additionalTags,
			attachments: nil,
			isAmbrosiaItem: existingArticle.isAmbrosiaItem,
			wordCount: existingArticle.wordCount,
			chapterCurrent: extraction.chapters.count,
			chapterTotal: existingArticle.chapterTotal,
			isComplete: existingArticle.isComplete,
			fandoms: fandoms,
			relationships: relationships,
			characters: characters,
			ratings: ratings,
			warnings: warnings,
			categories: categories,
			series: series,
			commentCount: applyStatsUpdate ? extraction.commentCount : existingArticle.commentCount,
			kudosCount: applyStatsUpdate ? extraction.kudosCount : existingArticle.kudosCount,
			bookmarkCount: applyStatsUpdate ? extraction.bookmarkCount : existingArticle.bookmarkCount,
			hitCount: applyStatsUpdate ? extraction.hitCount : existingArticle.hitCount,
			// rebuildParsedItem only runs on a successful extraction (it's
			// handed the extraction.chapters/stats result), so "now" is
			// correct here regardless of caller -- a failed fetch never
			// reaches this function at all.
			lastPrefaceFetchDate: Date(),
			ao3WorkID: workID
		)
	}
}
