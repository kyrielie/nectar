//
//  Article.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/1/17.
//  Copyright © 2017 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import RSCore

public typealias ArticleSetBlock = (Set<Article>) -> Void

public final class Article: Hashable, Sendable {
	public let articleID: String // Unique database ID (possibly sync service ID)
	public let accountID: String
	public let feedID: String // Likely a URL, but not necessarily
	public let uniqueID: String // Unique per feed (RSS guid, for example)
	public let title: String?
	public let contentHTML: String?
	public let contentText: String?
	public let markdown: String?
	public let rawLink: String? // We store raw source value, but use computed url or link other than where raw value required.
    public let rawExternalLink: String? // We store raw source value, but use computed externalURL or externalLink other than where raw value required.
	public let summary: String?
	public let rawImageLink: String? // We store raw source value, but use computed imageURL or imageLink other than where raw value required.
	public let datePublished: Date?
	public let dateModified: Date?
	public let authors: Set<Author>?
	// MARK: - Ambrosia extension (persisted from ParsedItem's `_ambrosia` fields)
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
	public let series: [ArticleSeriesEntry]?
	// Book-level read-state identity key (see ParsedItem.bookKey). Always
	// resolves to at least uniqueID, so this is non-optional.
	public let bookKey: String
	public let status: ArticleStatus

	public init(accountID: String, articleID: String?, feedID: String, uniqueID: String, title: String?, contentHTML: String?, contentText: String?, markdown: String?, url: String?, externalURL: String?, summary: String?, imageURL: String?, datePublished: Date?, dateModified: Date?, authors: Set<Author>?, wordCount: Int? = nil, chapterCurrent: Int? = nil, chapterTotal: Int? = nil, isComplete: Bool? = nil, fandoms: [String]? = nil, relationships: [String]? = nil, characters: [String]? = nil, ratings: [String]? = nil, warnings: [String]? = nil, categories: [String]? = nil, series: [ArticleSeriesEntry]? = nil, bookKey: String? = nil, status: ArticleStatus) {
		self.accountID = accountID
		self.feedID = feedID
		self.uniqueID = uniqueID
		self.title = title
		self.contentHTML = contentHTML
		self.contentText = contentText
		self.markdown = markdown
		self.rawLink = url
		self.rawExternalLink = externalURL
		self.summary = summary
		self.rawImageLink = imageURL
		self.datePublished = datePublished
		self.dateModified = dateModified
		self.authors = authors
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
		self.bookKey = bookKey ?? uniqueID
		self.status = status

		if let articleID = articleID {
			self.articleID = articleID
		} else {
			self.articleID = Article.calculatedArticleID(feedID: feedID, uniqueID: uniqueID)
		}
	}

	public static func calculatedArticleID(feedID: String, uniqueID: String) -> String {
		return "\(feedID) \(uniqueID)".md5String
	}

	// MARK: - Hashable

	public func hash(into hasher: inout Hasher) {
		hasher.combine(articleID)
	}

	// MARK: - Equatable

	static public func ==(lhs: Article, rhs: Article) -> Bool {
		return lhs.articleID == rhs.articleID && lhs.accountID == rhs.accountID && lhs.feedID == rhs.feedID && lhs.uniqueID == rhs.uniqueID && lhs.title == rhs.title && lhs.contentHTML == rhs.contentHTML && lhs.contentText == rhs.contentText && lhs.rawLink == rhs.rawLink && lhs.rawExternalLink == rhs.rawExternalLink && lhs.summary == rhs.summary && lhs.rawImageLink == rhs.rawImageLink && lhs.datePublished == rhs.datePublished && lhs.dateModified == rhs.dateModified && lhs.authors == rhs.authors && lhs.wordCount == rhs.wordCount && lhs.chapterCurrent == rhs.chapterCurrent && lhs.chapterTotal == rhs.chapterTotal && lhs.isComplete == rhs.isComplete && lhs.fandoms == rhs.fandoms && lhs.relationships == rhs.relationships && lhs.characters == rhs.characters && lhs.ratings == rhs.ratings && lhs.warnings == rhs.warnings && lhs.categories == rhs.categories && lhs.series == rhs.series && lhs.bookKey == rhs.bookKey
	}
}

/// One entry in an article's `_ambrosia.series` array. Mirrors `ParsedSeriesEntry`
/// from RSParser, but lives in Articles so this module doesn't need to depend
/// on RSParser just to store the persisted, already-parsed value.
public struct ArticleSeriesEntry: Codable, Hashable, Sendable {
	public let name: String
	public let index: Int
	public let ao3ID: String?

	public init(name: String, index: Int, ao3ID: String?) {
		self.name = name
		self.index = index
		self.ao3ID = ao3ID
	}
}

public extension Set where Element == Article {

	func articleIDs() -> Set<String> {
		return Set<String>(map { $0.articleID })
	}

	func unreadArticles() -> Set<Article> {
		let articles = self.filter { !$0.status.read }
		return Set(articles)
	}

	func contains(accountID: String, articleID: String) -> Bool {
		return contains(where: { $0.accountID == accountID && $0.articleID == articleID})
	}
}

public extension Array where Element == Article {

	func articleIDs() -> [String] {
		return map { $0.articleID }
	}
}
