//
//  Keys.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/3/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import Foundation

// MARK: - Database structure

struct DatabaseTableName {
	static let articles = "articles"
	static let statuses = "statuses"
	static let bookState = "bookState"
}

struct DatabaseKey {
	// Shared
	static let articleID = "articleID"
	static let url = "url"
	static let title = "title"

	// Article
	static let feedID = "feedID"
	static let uniqueID = "uniqueID"
	static let contentHTML = "contentHTML"
	static let contentText = "contentText"
	static let markdown = "markdown"
	static let externalURL = "externalURL"
	static let summary = "summary"
	static let imageURL = "imageURL"
	static let datePublished = "datePublished"
	static let dateModified = "dateModified"
	static let authors = "authors"
	static let searchRowID = "searchRowID"

	// Ambrosia extension
	static let wordCount = "wordCount"
	static let chapterCurrent = "chapterCurrent"
	static let chapterTotal = "chapterTotal"
	static let isComplete = "isComplete"
	static let fandoms = "fandoms"
	static let relationships = "relationships"
	static let characters = "characters"
	static let ratings = "ratings"
	static let warnings = "warnings"
	static let categories = "categories"
	static let additionalTags = "additionalTags"
	static let series = "series"
	static let bookKey = "bookKey"

	// AO3 Work Header stats (populated by AO3ChapterFetcher, not part of
	// the `_ambrosia` extension above)
	static let commentCount = "commentCount"
	static let kudosCount = "kudosCount"
	static let bookmarkCount = "bookmarkCount"
	static let hitCount = "hitCount"
	// Task 10 ("Prev/next/first navigation") -- previous/next work in
	// series, read off the same live work-page fetch as the four stats
	// above.
	// Dead: Article no longer has singular previousWorkURL/nextWorkURL
	// fields (superseded by per-series navigation on ArticleSeriesEntry).
	// Kept, unwritten/unread, rather than migrated away -- see
	// nectar-architecture.md's SurfacePalette.HexSet note for the
	// precedent. Do not reuse these column names for anything else.
	static let previousWorkURL = "previousWorkURL"
	static let nextWorkURL = "nextWorkURL"
	static let lastPrefaceFetchDate = "lastPrefaceFetchDate"
	static let isAmbrosiaItem = "isAmbrosiaItem"

	// Task 8 (content archival & destructive-update protection)
	static let pendingUpdateContentHTML = "pendingUpdateContentHTML"
	static let pendingUpdateDetectedAt = "pendingUpdateDetectedAt"
	static let wordCountRegressionFlaggedAt = "wordCountRegressionFlaggedAt"

	// ArticleStatus
	static let read = "read"
	static let starred = "starred"
	static let dateArrived = "dateArrived"

	// Reading behavior (Phase 2 fork addition)
	static let scrollPosition = "scrollPosition"

	// Reading progress, 0...1 fraction (Phase A1 fork addition). Nullable: nil means
	// never computed, distinct from 0 (computed, at the very top).
	static let readingProgress = "readingProgress"

	// Loved status (Phase 5 fork addition). Joins starred in the "never
	// auto-delete" set.
	static let loved = "loved"

	// Last Opened smart feed: bookState-primary, statuses-propagated, same
	// tier as scrollPosition/loved above.
	static let lastOpenedAt = "lastOpenedAt"

	// Kudos-on-like (Task 6 fork addition). kudosAttemptedAt is nil until a
	// kudos POST has actually been attempted for this book;
	// kudosAttemptedAuthenticated only means something once
	// kudosAttemptedAt is non-nil -- it records whether that attempt was a
	// logged-in (permanent, never re-attempted) or guest (retriable once an
	// AO3 account is configured) kudos. bookState-only, no statuses-table
	// mirror -- unlike loved/lastOpenedAt this isn't read per-articleID
	// anywhere, only per-bookKey when deciding whether to fire a kudos
	// attempt.
	static let kudosAttemptedAt = "kudosAttemptedAt"
	static let kudosAttemptedAuthenticated = "kudosAttemptedAuthenticated"

	static let updatedAt = "updatedAt"

	// Author
	static let authorID = "authorID"
	static let name = "name"
	static let avatarURL = "avatarURL"
	static let emailAddress = "emailAddress"

	// Search
	static let body = "body"
	static let rowID = "rowid"
}
