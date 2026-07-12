//
//  JSONFeedParser.swift
//  RSParser
//
//  Created by Brent Simmons on 6/25/17.
//  Copyright © 2017 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import os

// See https://jsonfeed.org/version/1.1

public struct JSONFeedParser {

	// Diagnostic only, for tracking down items that go missing between the raw
	// feed JSON and what ends up in the app (e.g. "the feed has N items but only
	// N-1 show up"). Not used for any parsing decision.
	private static let logger = Logger(subsystem: "com.ranchero.NetNewsWire.RSParser", category: "JSONFeedParser")

	struct Key {
		static let version = "version"
		static let items = "items"
		static let title = "title"
		static let homePageURL = "home_page_url"
		static let feedURL = "feed_url"
		static let feedDescription = "description"
		static let nextURL = "next_url"
		static let icon = "icon"
		static let favicon = "favicon"
		static let expired = "expired"
		static let author = "author"
		static let authors = "authors"
		static let name = "name"
		static let url = "url"
		static let avatar = "avatar"
		static let hubs = "hubs"
		static let type = "type"
		static let contentHTML = "content_html"
		static let contentText = "content_text"
		static let externalURL = "external_url"
		static let summary = "summary"
		static let image = "image"
		static let bannerImage = "banner_image"
		static let datePublished = "date_published"
		static let dateModified = "date_modified"
		static let tags = "tags"
		static let uniqueID = "id"
		static let attachments = "attachments"
		static let mimeType = "mime_type"
		static let sizeInBytes = "size_in_bytes"
		static let durationInSeconds = "duration_in_seconds"
		static let language = "language"

		// Ambrosia extension (see LocalFeedServer.swift JSONFeedAmbrosiaExtension).
		// No _ambrosia_schema_version key exists on the wire today — Ambrosia's
		// feed server doesn't send one — so there is nothing to gate on yet.
		static let ambrosia = "_ambrosia"
		static let ambrosiaWordCount = "word_count"
		static let ambrosiaChapterCurrent = "chapter_current"
		static let ambrosiaChapterTotal = "chapter_total"
		static let ambrosiaIsComplete = "is_complete"
		static let ambrosiaFandoms = "fandoms"
		static let ambrosiaRelationships = "relationships"
		static let ambrosiaCharacters = "characters"
		static let ambrosiaRatings = "ratings"
		static let ambrosiaWarnings = "warnings"
		static let ambrosiaCategories = "categories"
		static let ambrosiaSeries = "series"
		static let ambrosiaDateModified = "date_modified"
		static let ambrosiaSeriesName = "name"
		static let ambrosiaSeriesIndex = "index"
		static let ambrosiaSeriesAO3ID = "ao3_id"

		// Read-state identity fields (see LocalFeedServer's JSONFeedAmbrosiaExtension).
		static let ambrosiaAO3WorkID = "ao3_work_id"
		static let ambrosiaIsAnthology = "is_anthology"
		static let ambrosiaAO3SeriesID = "ao3_series_id"
		static let ambrosiaBookSeriesName = "series_name"
	}

	static let jsonFeedVersionMarker = "://jsonfeed.org/version/" // Allow for the mistake of not getting the scheme exactly correct.

	public static func parse(_ parserData: ParserData) throws -> ParsedFeed? {

		guard let d = JSONUtilities.dictionary(with: parserData.data) else {
			throw FeedParserError.invalidJSON
		}

		guard let version = d[Key.version] as? String, version.range(of: JSONFeedParser.jsonFeedVersionMarker) != nil else {
			throw FeedParserError.jsonFeedVersionNotFound
		}
		guard let itemsArray = d[Key.items] as? JSONArray else {
			throw FeedParserError.jsonFeedItemsNotFound
		}
		guard let title = d[Key.title] as? String else {
			throw FeedParserError.jsonFeedTitleNotFound
		}

		let authors = parseAuthors(d)
		let homePageURL = d[Key.homePageURL] as? String
		let feedURL = d[Key.feedURL] as? String ?? parserData.url
		let feedDescription = d[Key.feedDescription] as? String
		let nextURL = d[Key.nextURL] as? String
		let iconURL = d[Key.icon] as? String
		let faviconURL = d[Key.favicon] as? String
		let expired = d[Key.expired] as? Bool ?? false
		let hubs = parseHubs(d)
		let language = d[Key.language] as? String

		let items = parseItems(itemsArray, parserData.url)

		if items.count != itemsArray.count {
			logger.notice("parse: feedURL=\(feedURL, privacy: .public) rawItemCount=\(itemsArray.count, privacy: .public) parsedItemCount=\(items.count, privacy: .public) -- \(itemsArray.count - items.count, privacy: .public) item(s) dropped, see preceding parseItem logs for reasons")
		}

		return ParsedFeed(type: .jsonFeed, title: title, homePageURL: homePageURL, feedURL: feedURL, language: language, feedDescription: feedDescription, nextURL: nextURL, iconURL: iconURL, faviconURL: faviconURL, authors: authors, expired: expired, hubs: hubs, items: items)
	}
}

private extension JSONFeedParser {

	static func parseAuthors(_ dictionary: JSONDictionary) -> Set<ParsedAuthor>? {

		if let authorsArray = dictionary[Key.authors] as? JSONArray {
			var authors = Set<ParsedAuthor>()
			for author in authorsArray {
				if let parsedAuthor = parseAuthor(author) {
					authors.insert(parsedAuthor)
				}
			}
			return authors
		}

		guard let authorDictionary = dictionary[Key.author] as? JSONDictionary,
			  let parsedAuthor = parseAuthor(authorDictionary) else {
			return nil
		}

		return Set([parsedAuthor])
	}

	static func parseAuthor(_ dictionary: JSONDictionary) -> ParsedAuthor? {
		let name = dictionary[Key.name] as? String
		let url = dictionary[Key.url] as? String
		let avatar = dictionary[Key.avatar] as? String
		if name == nil && url == nil && avatar == nil {
			return nil
		}
		return ParsedAuthor(name: name, url: url, avatarURL: avatar, emailAddress: nil)
	}

	static func parseHubs(_ dictionary: JSONDictionary) -> Set<ParsedHub>? {

		guard let hubsArray = dictionary[Key.hubs] as? JSONArray else {
			return nil
		}

		let hubs = hubsArray.compactMap { (hubDictionary) -> ParsedHub? in
			guard let hubURL = hubDictionary[Key.url] as? String, let hubType = hubDictionary[Key.type] as? String else {
				return nil
			}
			return ParsedHub(type: hubType, url: hubURL)
		}
		return hubs.isEmpty ? nil : Set(hubs)
	}

	static func parseItems(_ itemsArray: JSONArray, _ feedURL: String) -> Set<ParsedItem> {

		var seenUniqueIDs = Set<String>()

		let parsedItems = itemsArray.enumerated().compactMap { (index, oneItemDictionary) -> ParsedItem? in
			guard let item = parseItem(oneItemDictionary, feedURL) else {
				let title = oneItemDictionary[Key.title] as? String
				let url = oneItemDictionary[Key.url] as? String
				logger.notice("parseItem: feedURL=\(feedURL, privacy: .public) itemIndex=\(index, privacy: .public) dropped -- title=\(title ?? "nil", privacy: .public) url=\(url ?? "nil", privacy: .public)")
				return nil
			}
			// A same-id collision here won't shrink the Set below (ParsedItem equality
			// is over every field, not just uniqueID), but a downstream by-uniqueID
			// merge/upsert against the article store can still treat these as the same
			// article and keep only one -- log it here, at the source, rather than
			// leaving it to be inferred from a missing article later.
			if !seenUniqueIDs.insert(item.uniqueID).inserted {
				logger.notice("parseItem: feedURL=\(feedURL, privacy: .public) itemIndex=\(index, privacy: .public) duplicate uniqueID=\(item.uniqueID, privacy: .public) title=\(item.title ?? "nil", privacy: .public)")
			}
			return item
		}

		return Set(parsedItems)
	}

	static func parseItem(_ itemDictionary: JSONDictionary, _ feedURL: String) -> ParsedItem? {

		guard let uniqueID = parseUniqueID(itemDictionary) else {
			logger.notice("parseItem: feedURL=\(feedURL, privacy: .public) dropped -- no usable \"\(Key.uniqueID, privacy: .public)\" field")
			return nil
		}

		let contentHTML = itemDictionary[Key.contentHTML] as? String
		let contentText = itemDictionary[Key.contentText] as? String
		if contentHTML == nil && contentText == nil {
			logger.notice("parseItem: feedURL=\(feedURL, privacy: .public) uniqueID=\(uniqueID, privacy: .public) dropped -- neither \(Key.contentHTML, privacy: .public) nor \(Key.contentText, privacy: .public) present")
			return nil
		}

		let url = itemDictionary[Key.url] as? String
		let externalURL = itemDictionary[Key.externalURL] as? String
		let title = parseTitle(itemDictionary, feedURL)
		let language = itemDictionary[Key.language] as? String
		let summary = itemDictionary[Key.summary] as? String
		let imageURL = itemDictionary[Key.image] as? String
		let bannerImageURL = itemDictionary[Key.bannerImage] as? String

		let datePublished = parseDate(itemDictionary[Key.datePublished] as? String)
		var dateModified = parseDate(itemDictionary[Key.dateModified] as? String)

		let authors = parseAuthors(itemDictionary)
		var tags: Set<String>?
		if let tagsArray = itemDictionary[Key.tags] as? [String] {
			tags = Set(tagsArray)
		}
		let attachments = parseAttachments(itemDictionary)

		let ambrosia = itemDictionary[Key.ambrosia] as? JSONDictionary
		if dateModified == nil, let ambrosiaDateModified = ambrosia?[Key.ambrosiaDateModified] as? String {
			dateModified = parseDate(ambrosiaDateModified)
		}

		return ParsedItem(syncServiceID: nil, uniqueID: uniqueID, feedURL: feedURL, url: url, externalURL: externalURL, title: title, language: language, contentHTML: contentHTML, contentText: contentText, markdown: nil, summary: summary, imageURL: imageURL, bannerImageURL: bannerImageURL, datePublished: datePublished, dateModified: dateModified, authors: authors, tags: tags, attachments: attachments, wordCount: ambrosia?[Key.ambrosiaWordCount] as? Int, chapterCurrent: ambrosia?[Key.ambrosiaChapterCurrent] as? Int, chapterTotal: ambrosia?[Key.ambrosiaChapterTotal] as? Int, isComplete: ambrosia?[Key.ambrosiaIsComplete] as? Bool, fandoms: ambrosia?[Key.ambrosiaFandoms] as? [String], relationships: ambrosia?[Key.ambrosiaRelationships] as? [String], characters: ambrosia?[Key.ambrosiaCharacters] as? [String], ratings: ambrosia?[Key.ambrosiaRatings] as? [String], warnings: ambrosia?[Key.ambrosiaWarnings] as? [String], categories: ambrosia?[Key.ambrosiaCategories] as? [String], series: parseAmbrosiaSeries(ambrosia), ao3WorkID: ambrosia?[Key.ambrosiaAO3WorkID] as? String, isAnthology: ambrosia?[Key.ambrosiaIsAnthology] as? Bool, ao3SeriesID: ambrosia?[Key.ambrosiaAO3SeriesID] as? String, seriesName: ambrosia?[Key.ambrosiaBookSeriesName] as? String)
	}

	static func parseAmbrosiaSeries(_ ambrosia: JSONDictionary?) -> [ParsedSeriesEntry]? {
		guard let seriesArray = ambrosia?[Key.ambrosiaSeries] as? JSONArray else {
			return nil
		}
		let entries = seriesArray.compactMap { entry -> ParsedSeriesEntry? in
			guard let name = entry[Key.ambrosiaSeriesName] as? String,
				  let index = entry[Key.ambrosiaSeriesIndex] as? Int else {
				return nil
			}
			let ao3ID = entry[Key.ambrosiaSeriesAO3ID] as? String
			return ParsedSeriesEntry(name: name, index: index, ao3ID: ao3ID)
		}
		return entries.isEmpty ? nil : entries
	}

	static func parseTitle(_ itemDictionary: JSONDictionary, _ feedURL: String) -> String? {

		guard let title = itemDictionary[Key.title] as? String else {
			return nil
		}

		if isSpecialCaseTitleWithEntitiesFeed(feedURL) {
			return title.decodingHTMLEntities()
		}

		return title
	}

	static func isSpecialCaseTitleWithEntitiesFeed(_ feedURL: String) -> Bool {

		// As of 16 Feb. 2018, Kottke’s and Heer’s feeds includes HTML entities in the title elements.
		// If we find more feeds like this, we’ll add them here. If these feeds get fixed, we’ll remove them.

		let lowerFeedURL = feedURL.lowercased()
		let matchStrings = ["kottke.org", "pxlnv.com", "macstories.net", "macobserver.com"]
		for matchString in matchStrings {
			if lowerFeedURL.contains(matchString) {
				return true
			}
		}

		return false
	}

	static func parseUniqueID(_ itemDictionary: JSONDictionary) -> String? {

		if let uniqueID = itemDictionary[Key.uniqueID] as? String {
			return uniqueID // Spec says it must be a string
		}
		// Version 1 spec also says that if it’s a number, even though that’s incorrect, it should be coerced to a string.
		if let uniqueID = itemDictionary[Key.uniqueID] as? Int {
			return "\(uniqueID)"
		}
		if let uniqueID = itemDictionary[Key.uniqueID] as? Double {
			return "\(uniqueID)"
		}
		return nil
	}

	static func parseDate(_ dateString: String?) -> Date? {

		guard let dateString = dateString, !dateString.isEmpty else {
			return nil
		}
		return DateParser.date(from: dateString)
	}

	static func parseAttachments(_ itemDictionary: JSONDictionary) -> Set<ParsedAttachment>? {

		guard let attachmentsArray = itemDictionary[Key.attachments] as? JSONArray else {
			return nil
		}
		return Set(attachmentsArray.compactMap { parseAttachment($0) })
	}

	static func parseAttachment(_ attachmentObject: JSONDictionary) -> ParsedAttachment? {

		guard let url = attachmentObject[Key.url] as? String else {
			return nil
		}
		guard let mimeType = attachmentObject[Key.mimeType] as? String else {
			return nil
		}

		let title = attachmentObject[Key.title] as? String
		let sizeInBytes = attachmentObject[Key.sizeInBytes] as? Int
		let durationInSeconds = attachmentObject[Key.durationInSeconds] as? Int

		return ParsedAttachment(url: url, mimeType: mimeType, title: title, sizeInBytes: sizeInBytes, durationInSeconds: durationInSeconds)
	}
}
