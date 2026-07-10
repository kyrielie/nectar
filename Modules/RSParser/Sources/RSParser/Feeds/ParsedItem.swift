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
	            series: [ParsedSeriesEntry]? = nil) {
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
}
