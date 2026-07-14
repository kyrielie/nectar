//
//  Article+Database.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/3/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import Foundation
import RSDatabase
import RSDatabaseObjC
import Articles
import RSParser

extension Article {

	convenience init?(accountID: String, row: FMResultSet, status: ArticleStatus) {
		guard let articleID = row.swiftString(forColumn: DatabaseKey.articleID) else {
			assertionFailure("Expected articleID.")
			return nil
		}
		guard let feedID = row.swiftString(forColumn: DatabaseKey.feedID) else {
			assertionFailure("Expected feedID.")
			return nil
		}
		guard let uniqueID = row.swiftString(forColumn: DatabaseKey.uniqueID) else {
			assertionFailure("Expected uniqueID.")
			return nil
		}

		let title = row.swiftString(forColumn: DatabaseKey.title)
		// contentHTML is stored LZFSE-compressed + base64-encoded (Phase 3, see
		// ContentHTMLCompression) -- decompress here, the single choke point
		// every reader of this column goes through via Article.
		let contentHTML = ContentHTMLCompression.decompress(row.swiftString(forColumn: DatabaseKey.contentHTML))
		let contentText = row.swiftString(forColumn: DatabaseKey.contentText)
		let markdown = row.swiftString(forColumn: DatabaseKey.markdown)
		let url = row.swiftString(forColumn: DatabaseKey.url)
		let externalURL = row.swiftString(forColumn: DatabaseKey.externalURL)
		let summary = row.swiftString(forColumn: DatabaseKey.summary)
		let imageURL = row.swiftString(forColumn: DatabaseKey.imageURL)
		let datePublished = row.date(forColumn: DatabaseKey.datePublished)
		let dateModified = row.date(forColumn: DatabaseKey.dateModified)
		let authors = Self.authorsFromRow(row)

		let wordCount = row.columnIsNull(DatabaseKey.wordCount) ? nil : Int(row.longLongInt(forColumn: DatabaseKey.wordCount))
		let chapterCurrent = row.columnIsNull(DatabaseKey.chapterCurrent) ? nil : Int(row.longLongInt(forColumn: DatabaseKey.chapterCurrent))
		let chapterTotal = row.columnIsNull(DatabaseKey.chapterTotal) ? nil : Int(row.longLongInt(forColumn: DatabaseKey.chapterTotal))
		let isComplete = row.columnIsNull(DatabaseKey.isComplete) ? nil : row.bool(forColumn: DatabaseKey.isComplete)
		let fandoms = Self.stringArrayFromRow(row, DatabaseKey.fandoms)
		let relationships = Self.stringArrayFromRow(row, DatabaseKey.relationships)
		let characters = Self.stringArrayFromRow(row, DatabaseKey.characters)
		let ratings = Self.stringArrayFromRow(row, DatabaseKey.ratings)
		let warnings = Self.stringArrayFromRow(row, DatabaseKey.warnings)
		let categories = Self.stringArrayFromRow(row, DatabaseKey.categories)
		let series = Self.seriesFromRow(row)
		let bookKey = row.swiftString(forColumn: DatabaseKey.bookKey)

		self.init(accountID: accountID, articleID: articleID, feedID: feedID, uniqueID: uniqueID, title: title, contentHTML: contentHTML, contentText: contentText, markdown: markdown, url: url, externalURL: externalURL, summary: summary, imageURL: imageURL, datePublished: datePublished, dateModified: dateModified, authors: authors, wordCount: wordCount, chapterCurrent: chapterCurrent, chapterTotal: chapterTotal, isComplete: isComplete, fandoms: fandoms, relationships: relationships, characters: characters, ratings: ratings, warnings: warnings, categories: categories, series: series, bookKey: bookKey, status: status)
	}

	private static func authorsFromRow(_ row: FMResultSet) -> Set<Author>? {
		guard let json = row.swiftString(forColumn: DatabaseKey.authors), !json.isEmpty, let data = json.data(using: .utf8) else {
			return nil
		}
		return Author.authorsWithJSON(data)
	}

	// MARK: - Ambrosia extension (de)serialization
	//
	// String-array and series fields are stored as JSON-encoded TEXT columns,
	// mirroring the existing `authors` column's JSON-in-TEXT approach.

	private static func stringArrayFromRow(_ row: FMResultSet, _ key: String) -> [String]? {
		guard let json = row.swiftString(forColumn: key), !json.isEmpty, let data = json.data(using: .utf8) else {
			return nil
		}
		return try? JSONDecoder().decode([String].self, from: data)
	}

	private static func seriesFromRow(_ row: FMResultSet) -> [ArticleSeriesEntry]? {
		guard let json = row.swiftString(forColumn: DatabaseKey.series), !json.isEmpty, let data = json.data(using: .utf8) else {
			return nil
		}
		return try? JSONDecoder().decode([ArticleSeriesEntry].self, from: data)
	}

	private static func jsonString<T: Encodable>(_ value: T) -> String? {
		guard let data = try? JSONEncoder().encode(value) else {
			return nil
		}
		return String(data: data, encoding: .utf8)
	}

	convenience init(parsedItem: ParsedItem, maximumDateAllowed: Date, accountID: String, feedID: String, status: ArticleStatus) {
		let authors = Author.authorsWithParsedAuthors(parsedItem.authors)

		// Deal with future datePublished and dateModified dates.
		var datePublished = parsedItem.datePublished
		if datePublished == nil {
			datePublished = parsedItem.dateModified
		}
		if datePublished != nil, datePublished! > maximumDateAllowed {
			datePublished = nil
		}

		var dateModified = parsedItem.dateModified
		if dateModified != nil, dateModified! > maximumDateAllowed {
			dateModified = nil
		}

		let series = parsedItem.series?.map { ArticleSeriesEntry(name: $0.name, index: $0.index, ao3ID: $0.ao3ID) }

		self.init(accountID: accountID, articleID: parsedItem.syncServiceID, feedID: feedID, uniqueID: parsedItem.uniqueID, title: parsedItem.title, contentHTML: parsedItem.contentHTML, contentText: parsedItem.contentText, markdown: parsedItem.markdown, url: parsedItem.url, externalURL: parsedItem.externalURL, summary: parsedItem.summary, imageURL: parsedItem.imageURL, datePublished: datePublished, dateModified: dateModified, authors: authors, wordCount: parsedItem.wordCount, chapterCurrent: parsedItem.chapterCurrent, chapterTotal: parsedItem.chapterTotal, isComplete: parsedItem.isComplete, fandoms: parsedItem.fandoms, relationships: parsedItem.relationships, characters: parsedItem.characters, ratings: parsedItem.ratings, warnings: parsedItem.warnings, categories: parsedItem.categories, series: series, bookKey: parsedItem.bookKey, status: status)
	}

	private func addPossibleStringChangeWithKeyPath(_ comparisonKeyPath: KeyPath<Article, String?>, _ otherArticle: Article, _ key: String, _ dictionary: inout DatabaseDictionary) {
		if self[keyPath: comparisonKeyPath] != otherArticle[keyPath: comparisonKeyPath] {
			dictionary[key] = self[keyPath: comparisonKeyPath] ?? ""
		}
	}

	func changesFrom(_ existingArticle: Article) -> DatabaseDictionary? {
		if self == existingArticle {
			return nil
		}

		var d = DatabaseDictionary()
		if uniqueID != existingArticle.uniqueID {
			d[DatabaseKey.uniqueID] = uniqueID
		}

		addPossibleStringChangeWithKeyPath(\Article.title, existingArticle, DatabaseKey.title, &d)
		// contentHTML needs compressing before it lands in the update dictionary --
		// addPossibleStringChangeWithKeyPath would otherwise write the decompressed
		// in-memory string straight to the TEXT column (Phase 3).
		if contentHTML != existingArticle.contentHTML {
			d[DatabaseKey.contentHTML] = ContentHTMLCompression.compress(contentHTML) ?? ""
		}
		addPossibleStringChangeWithKeyPath(\Article.contentText, existingArticle, DatabaseKey.contentText, &d)
		addPossibleStringChangeWithKeyPath(\Article.rawLink, existingArticle, DatabaseKey.url, &d)
		addPossibleStringChangeWithKeyPath(\Article.rawExternalLink, existingArticle, DatabaseKey.externalURL, &d)
		addPossibleStringChangeWithKeyPath(\Article.summary, existingArticle, DatabaseKey.summary, &d)
		addPossibleStringChangeWithKeyPath(\Article.rawImageLink, existingArticle, DatabaseKey.imageURL, &d)

		if authors != existingArticle.authors {
			if let authors, !authors.isEmpty, let json = authors.json() {
				d[DatabaseKey.authors] = json
			} else {
				d[DatabaseKey.authors] = ""
			}
		}

		// If updated versions of dates are nil, and we have existing dates, keep the existing dates.
		// This is data that’s good to have, and it’s likely that a feed removing dates is doing so in error.
		if datePublished != existingArticle.datePublished {
			if let updatedDatePublished = datePublished {
				d[DatabaseKey.datePublished] = updatedDatePublished
			}
		}
		if dateModified != existingArticle.dateModified {
			if let updatedDateModified = dateModified {
				d[DatabaseKey.dateModified] = updatedDateModified
			}
		}

		// Ambrosia extension. Word count/chapter/completion follow the same
		// "only write when a new non-nil value shows up" rule as the dates
		// above — a feed that stops sending `_ambrosia` shouldn't blank out
		// data we already have.
		if wordCount != existingArticle.wordCount, let wordCount {
			d[DatabaseKey.wordCount] = wordCount
		}
		if chapterCurrent != existingArticle.chapterCurrent, let chapterCurrent {
			d[DatabaseKey.chapterCurrent] = chapterCurrent
		}
		if chapterTotal != existingArticle.chapterTotal, let chapterTotal {
			d[DatabaseKey.chapterTotal] = chapterTotal
		}
		if isComplete != existingArticle.isComplete, let isComplete {
			d[DatabaseKey.isComplete] = isComplete
		}

		if fandoms != existingArticle.fandoms, let fandoms, !fandoms.isEmpty, let json = Self.jsonString(fandoms) {
			d[DatabaseKey.fandoms] = json
		}
		if relationships != existingArticle.relationships, let relationships, !relationships.isEmpty, let json = Self.jsonString(relationships) {
			d[DatabaseKey.relationships] = json
		}
		if characters != existingArticle.characters, let characters, !characters.isEmpty, let json = Self.jsonString(characters) {
			d[DatabaseKey.characters] = json
		}
		if ratings != existingArticle.ratings, let ratings, !ratings.isEmpty, let json = Self.jsonString(ratings) {
			d[DatabaseKey.ratings] = json
		}
		if warnings != existingArticle.warnings, let warnings, !warnings.isEmpty, let json = Self.jsonString(warnings) {
			d[DatabaseKey.warnings] = json
		}
		if categories != existingArticle.categories, let categories, !categories.isEmpty, let json = Self.jsonString(categories) {
			d[DatabaseKey.categories] = json
		}
		if series != existingArticle.series, let series, !series.isEmpty, let json = Self.jsonString(series) {
			d[DatabaseKey.series] = json
		}
		if bookKey != existingArticle.bookKey {
			d[DatabaseKey.bookKey] = bookKey
		}

		return d.count < 1 ? nil : d
	}

//	static func articlesWithParsedItems(_ parsedItems: Set<ParsedItem>, _ accountID: String, _ feedID: String, _ statusesDictionary: [String: ArticleStatus]) -> Set<Article> {
//		let maximumDateAllowed = Date().addingTimeInterval(60 * 60 * 24) // Allow dates up to about 24 hours ahead of now
//		return Set(parsedItems.map{ Article(parsedItem: $0, maximumDateAllowed: maximumDateAllowed, accountID: accountID, feedID: feedID, status: statusesDictionary[$0.articleID]!) })
//	}

	private static func _maximumDateAllowed() -> Date {
		return Date().addingTimeInterval(60 * 60 * 24) // Allow dates up to about 24 hours ahead of now
	}

	static func articlesWithFeedIDsAndItems(_ feedIDsAndItems: [String: Set<ParsedItem>], _ accountID: String, _ statusesDictionary: [String: ArticleStatus]) -> Set<Article> {
		let maximumDateAllowed = _maximumDateAllowed()
		var feedArticles = Set<Article>()
		for (feedID, parsedItems) in feedIDsAndItems {
			for parsedItem in parsedItems {
				let status = statusesDictionary[parsedItem.articleID]!
				let article = Article(parsedItem: parsedItem, maximumDateAllowed: maximumDateAllowed, accountID: accountID, feedID: feedID, status: status)
				feedArticles.insert(article)
			}
		}
		return feedArticles
	}

	static func articlesWithParsedItems(_ parsedItems: Set<ParsedItem>, _ feedID: String, _ accountID: String, _ statusesDictionary: [String: ArticleStatus]) -> Set<Article> {
		let maximumDateAllowed = _maximumDateAllowed()
		return Set(parsedItems.map { Article(parsedItem: $0, maximumDateAllowed: maximumDateAllowed, accountID: accountID, feedID: feedID, status: statusesDictionary[$0.articleID]!) })
	}
}

extension Article {

	func databaseDictionary() -> DatabaseDictionary {
		var d = DatabaseDictionary()

		d[DatabaseKey.articleID] = articleID
		d[DatabaseKey.feedID] = feedID
		d[DatabaseKey.uniqueID] = uniqueID

		if let title = title {
			d[DatabaseKey.title] = title
		}
		if let contentHTML = ContentHTMLCompression.compress(contentHTML) {
			d[DatabaseKey.contentHTML] = contentHTML
		}
		if let contentText = contentText {
			d[DatabaseKey.contentText] = contentText
		}
		if let markdown = markdown {
			d[DatabaseKey.markdown] = markdown
		}
		if let rawLink = rawLink {
			d[DatabaseKey.url] = rawLink
		}
		if let rawExternalLink = rawExternalLink {
			d[DatabaseKey.externalURL] = rawExternalLink
		}
		if let summary = summary {
			d[DatabaseKey.summary] = summary
		}
		if let rawImageLink = rawImageLink {
			d[DatabaseKey.imageURL] = rawImageLink
		}
		if let datePublished = datePublished {
			d[DatabaseKey.datePublished] = datePublished
		}
		if let dateModified = dateModified {
			d[DatabaseKey.dateModified] = dateModified
		}
		if let authors, !authors.isEmpty, let json = authors.json() {
			d[DatabaseKey.authors] = json
		}

		if let wordCount {
			d[DatabaseKey.wordCount] = wordCount
		}
		if let chapterCurrent {
			d[DatabaseKey.chapterCurrent] = chapterCurrent
		}
		if let chapterTotal {
			d[DatabaseKey.chapterTotal] = chapterTotal
		}
		if let isComplete {
			d[DatabaseKey.isComplete] = isComplete
		}
		if let fandoms, !fandoms.isEmpty, let json = Self.jsonString(fandoms) {
			d[DatabaseKey.fandoms] = json
		}
		if let relationships, !relationships.isEmpty, let json = Self.jsonString(relationships) {
			d[DatabaseKey.relationships] = json
		}
		if let characters, !characters.isEmpty, let json = Self.jsonString(characters) {
			d[DatabaseKey.characters] = json
		}
		if let ratings, !ratings.isEmpty, let json = Self.jsonString(ratings) {
			d[DatabaseKey.ratings] = json
		}
		if let warnings, !warnings.isEmpty, let json = Self.jsonString(warnings) {
			d[DatabaseKey.warnings] = json
		}
		if let categories, !categories.isEmpty, let json = Self.jsonString(categories) {
			d[DatabaseKey.categories] = json
		}
		if let series, !series.isEmpty, let json = Self.jsonString(series) {
			d[DatabaseKey.series] = json
		}
		d[DatabaseKey.bookKey] = bookKey
		return d
	}
}

extension Set where Element == Article {

	func dictionary() -> [String: Article] {
		var d = [String: Article]()
		for article in self {
			d[article.articleID] = article
		}
		return d
	}

	func databaseDictionaries() -> [DatabaseDictionary] {
		return self.map { $0.databaseDictionary() }
	}
}
