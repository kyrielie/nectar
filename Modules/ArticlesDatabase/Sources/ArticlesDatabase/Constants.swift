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
	static let bookReadState = "bookReadState"
	static let bookStarredState = "bookStarredState"
	static let bookLovedState = "bookLovedState"
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
	static let series = "series"
	static let bookKey = "bookKey"

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

	// BookReadState (Phase 6 fork addition)
	static let state = "state"
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
