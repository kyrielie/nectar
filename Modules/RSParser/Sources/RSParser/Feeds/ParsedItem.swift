//
//  ParsedItem.swift
//  RSParser
//
//  Created by Brent Simmons on 6/20/17.
//  Copyright © 2017 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import Tidemark

public struct ParsedItem: Hashable, Sendable {
	public let syncServiceID: String? // Nil when not syncing
	public let uniqueID: String // RSS guid, for instance; may be calculated
	public let feedURL: String
	public let url: String?
	public let externalURL: String?
	public let title: String?
	public let language: String?
	public let contentHTML: String?
	public let contentText: String?
	public let markdown: String?
	public let summary: String?
	public let imageURL: String?
	public let bannerImageURL: String?
	public let datePublished: Date?
	public let dateModified: Date?
	public let authors: Set<ParsedAuthor>?
	public let tags: Set<String>?
	public let attachments: Set<ParsedAttachment>?

	// True when the item carries an `_ambrosia` extension object on the wire
	// (a book), regardless of whether any field inside it is populated --
	// a book with zero AO3 metadata is still a book, not a blog post.
	// Not persisted; consulted only by ArticlesTable.update for the
	// unread-on-import default.
	public let isAmbrosiaItem: Bool

	// MARK: - Ambrosia extension (`_ambrosia` in JSON Feed 1.1 items)
	//
	// Ambrosia's LocalFeedServer sends no `_ambrosia_schema_version` field
	// (confirmed by reading LocalFeedServer.swift directly) so there is
	// nothing to gate parsing on yet; these fields are simply nil for any
	// feed that doesn't include `_ambrosia`. `_ambrosia.date_modified` is
	// folded into the top-level `dateModified` above rather than kept as a
	// separate property, since JSON Feed 1.1 already has a `date_modified`
	// concept and Ambrosia only puts it under `_ambrosia` because nothing
	// else in the item is populating it.
	public let wordCount: Int?
	public let chapterCurrent: Int?
	public let chapterTotal: Int?
	public let isComplete: Bool?
	public let fandoms: [String]?
	public let relationships: [String]?
	public let characters: [String]?
	public let ratings: [String]?
	public let warnings: [String]?
	public let categories: [String]?
	public let series: [ParsedSeriesEntry]?

	// AO3 Work Header stats (Comments/Kudos/Bookmarks/Hits), read off AO3's
	// live dl.stats block -- not part of the `_ambrosia` extension object
	// above (Ambrosia's own JSON Feed has no equivalent field), and never
	// set from an ordinary feed refresh. Populated only by
	// AO3ChapterFetcher.rebuildParsedItem, from AO3ChapterExtractionResult,
	// on each successful chapter fetch.
	public let commentCount: Int?
	public let kudosCount: Int?
	public let bookmarkCount: Int?
	public let hitCount: Int?
	// Task 10 (prev/next/first navigation): AO3-absolute URLs of the
	// previous/next work in series, read off the work page's own
	// Previous/Next Work navigation chrome -- same "fetcher-only, never
	// feed-derived" precedent as the four stats above. Populated only by
	// AO3ChapterFetcher.rebuildParsedItem, from
	// AO3ChapterExtractionResult.previousWorkURL/nextWorkURL, on each
	// successful chapter fetch. Independent of series grouping being
	// enabled -- see AO3ChapterExtractionResult's own doc comment.
	public let previousWorkURL: String?
	public let nextWorkURL: String?
	// Completion time of the AO3ChapterFetcher fetch that produced this
	// ParsedItem, for the refetch-cadence setting. Same "fetcher-only,
	// never feed-derived" precedent as the stats above: set only by
	// AO3ChapterFetcher.rebuildParsedItem on success, nil otherwise, and
	// threaded straight through to Article.lastPrefaceFetchDate.
	public let lastPrefaceFetchDate: Date?

	// Read-state identity fields (see LocalFeedServer's JSONFeedAmbrosiaExtension
	// on the Ambrosia side). Deliberately separate from `uniqueID`, which stays
	// "ambrosia-book-<calibre_id>" forever -- ao3WorkID may only become known
	// after a later re-extraction.
	public let ao3WorkID: String?
	// True only when this Calibre book's own description is a merge-plugin
	// "Anthology containing:" comment -- this book IS an entire compiled
	// series, not a normal work that happens to belong to one.
	public let isAnthology: Bool?
	// Populated when isAnthology is true (an anthology's own AO3 series id),
	// and also on series-group items (Ambrosia's own runtime grouping of
	// multiple Calibre books sharing an AO3 series), which set ao3SeriesID
	// from the group's series key without setting isAnthology at all.
	// seriesName is the Calibre-derived fallback for an anthology with no
	// AO3 series id -- series-group items never need it, since they always
	// carry ao3SeriesID.
	public let ao3SeriesID: String?
	public let seriesName: String?

	/// Book-level identity key for read-state dedup across feeds/re-subscriptions.
	/// Precedence: AO3 series id (anthology or series-group), then anthology
	/// series name, then AO3 work id, then the bare stable `uniqueID`
	/// ("ambrosia-book-<calibre_id>") as last resort. Mirrors the client-side
	/// `book_key()` precedence finalized against Ambrosia's LocalFeedServer
	/// output -- do not reorder without re-checking that source, since the
	/// precedence exists specifically to survive Calibre re-imports and late
	/// AO3 extraction without treating either as a new article.
	public var bookKey: String {
		// Routes on ao3SeriesID's presence, not isAnthology -- an
		// Ambrosia series-group item (multiple Calibre books sharing an
		// AO3 series, merged at request time) sets ao3SeriesID but never
		// isAnthology, and needs the same single-pre-merged-row keying an
		// anthology-with-a-series-id gets. seriesName stays anthology-gated:
		// it's the Calibre-derived fallback for an anthology with no AO3
		// series id, not a fallback series-group items ever need, since a
		// series group always has ao3SeriesID set from group.seriesKey.
		if let sid = ao3SeriesID, !sid.isEmpty {
			return "ao3-series:\(sid)"
		}
		if isAnthology == true, let name = seriesName {
			return "calibre-series:\(name)"
		}
		if let wid = ao3WorkID, !wid.isEmpty {
			return "ao3-work:\(wid)"
		}
		return uniqueID
	}

	public init(syncServiceID: String?,
	            uniqueID: String,
	            feedURL: String,
	            url: String?,
	            externalURL: String?,
	            title: String?,
	            language: String?,
	            contentHTML: String?,
	            contentText: String?,
	            markdown: String?,
	            summary: String?,
	            imageURL: String?,
	            bannerImageURL: String?,
	            datePublished: Date?,
	            dateModified: Date?,
	            authors: Set<ParsedAuthor>?,
	            tags: Set<String>?,
	            attachments: Set<ParsedAttachment>?,
	            isAmbrosiaItem: Bool = false,
	            wordCount: Int? = nil,
	            chapterCurrent: Int? = nil,
	            chapterTotal: Int? = nil,
	            isComplete: Bool? = nil,
	            fandoms: [String]? = nil,
	            relationships: [String]? = nil,
	            characters: [String]? = nil,
	            ratings: [String]? = nil,
	            warnings: [String]? = nil,
	            categories: [String]? = nil,
	            series: [ParsedSeriesEntry]? = nil,
	            commentCount: Int? = nil,
	            kudosCount: Int? = nil,
	            bookmarkCount: Int? = nil,
	            hitCount: Int? = nil,
	            previousWorkURL: String? = nil,
	            nextWorkURL: String? = nil,
	            lastPrefaceFetchDate: Date? = nil,
	            ao3WorkID: String? = nil,
	            isAnthology: Bool? = nil,
	            ao3SeriesID: String? = nil,
	            seriesName: String? = nil) {
		self.syncServiceID = syncServiceID
		self.uniqueID = uniqueID
		self.feedURL = feedURL
		self.url = url
		self.externalURL = externalURL
		self.title = title
		self.language = language
		self.contentText = contentText
		self.markdown = markdown
		self.summary = summary
		self.imageURL = imageURL
		self.bannerImageURL = bannerImageURL
		self.datePublished = datePublished
		self.dateModified = dateModified
		self.authors = authors
		self.tags = tags
		self.attachments = attachments
		self.isAmbrosiaItem = isAmbrosiaItem
		self.wordCount = wordCount
		self.chapterCurrent = chapterCurrent
		self.chapterTotal = chapterTotal
		self.isComplete = isComplete
		self.fandoms = fandoms
		self.relationships = relationships
		self.characters = characters
		self.ratings = ratings
		self.warnings = warnings
		self.categories = categories
		self.series = series
		self.commentCount = commentCount
		self.kudosCount = kudosCount
		self.bookmarkCount = bookmarkCount
		self.hitCount = hitCount
		self.previousWorkURL = previousWorkURL
		self.nextWorkURL = nextWorkURL
		self.lastPrefaceFetchDate = lastPrefaceFetchDate
		self.ao3WorkID = ao3WorkID
		self.isAnthology = isAnthology
		self.ao3SeriesID = ao3SeriesID
		self.seriesName = seriesName

		// Render Markdown when present, else use contentHTML
		if let markdown {
			let rendered = Tidemark.markdownToHTML(markdown)
			self.contentHTML = rendered.isEmpty ? contentHTML : rendered
		} else {
			self.contentHTML = contentHTML
		}
	}

	// MARK: - Hashable

	public func hash(into hasher: inout Hasher) {
		if let syncServiceID = syncServiceID {
			hasher.combine(syncServiceID)
		} else {
			hasher.combine(uniqueID)
			hasher.combine(feedURL)
		}
	}

	/// Returns a copy with the four AO3 Work Header stats
	/// (comment/kudos/bookmark/hit count) cleared, everything else
	/// unchanged. Used by callers that need to respect a "don't apply
	/// AO3-derived stats" preference for feed-supplied values (as opposed
	/// to the fetcher-only stats this type's own doc comment describes) --
	/// see AmbrosiaAO3NetworkPreference.statsUpdatesEnabled in the Account
	/// module, which this type can't reference directly (RSParser doesn't
	/// depend on Account), so the decision of *when* to call this lives
	/// with the caller. `markdown` is passed as `nil` here rather than
	/// `self.markdown` so the designated init doesn't re-render it from
	/// scratch -- `contentHTML` below is already the final rendered value.
	public func strippingAO3Stats() -> ParsedItem {
		ParsedItem(syncServiceID: syncServiceID, uniqueID: uniqueID, feedURL: feedURL, url: url, externalURL: externalURL, title: title, language: language, contentHTML: contentHTML, contentText: contentText, markdown: nil, summary: summary, imageURL: imageURL, bannerImageURL: bannerImageURL, datePublished: datePublished, dateModified: dateModified, authors: authors, tags: tags, attachments: attachments, isAmbrosiaItem: isAmbrosiaItem, wordCount: wordCount, chapterCurrent: chapterCurrent, chapterTotal: chapterTotal, isComplete: isComplete, fandoms: fandoms, relationships: relationships, characters: characters, ratings: ratings, warnings: warnings, categories: categories, series: series, commentCount: nil, kudosCount: nil, bookmarkCount: nil, hitCount: nil, previousWorkURL: previousWorkURL, nextWorkURL: nextWorkURL, lastPrefaceFetchDate: lastPrefaceFetchDate, ao3WorkID: ao3WorkID, isAnthology: isAnthology, ao3SeriesID: ao3SeriesID, seriesName: seriesName)
	}
}
