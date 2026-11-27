//
//  ArticleTagIndexer.swift
//  ArticlesDatabase
//
//  Maintains normalized `tags` and `article_tags` tables for fast faceted
//  local library filtering and tag prefix autocomplete.
//

import Foundation
import os
import RSDatabase
import RSDatabaseObjC
import Articles

public enum ArticleTagCategory: String, Codable, Sendable, CaseIterable, Hashable {
	case fandom
	case relationship
	case character
	case freeform
	case rating
	case warning
	case category
	case author
}

public struct TagSuggestion: Sendable, Hashable, Identifiable {
	public var id: String { "\(category.rawValue):\(name)" }
	public let name: String
	public let category: ArticleTagCategory
	public let articleCount: Int

	public init(name: String, category: ArticleTagCategory, articleCount: Int) {
		self.name = name
		self.category = category
		self.articleCount = articleCount
	}
}

enum ArticleTagIndexer {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ArticleTagIndexer")

	nonisolated static let tableCreationStatements = """
	CREATE TABLE if not EXISTS tags (tagID INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category TEXT NOT NULL, UNIQUE(name, category));
	CREATE TABLE if not EXISTS article_tags (articleID TEXT NOT NULL, tagID INTEGER NOT NULL, PRIMARY KEY (articleID, tagID), FOREIGN KEY (articleID) REFERENCES articles(articleID) ON DELETE CASCADE, FOREIGN KEY (tagID) REFERENCES tags(tagID) ON DELETE CASCADE);
	CREATE INDEX if not EXISTS article_tags_tagID_index on article_tags(tagID);
	CREATE INDEX if not EXISTS tags_category_name_index on tags(category, name);
	CREATE TRIGGER if not EXISTS articles_after_delete_trigger_delete_article_tags AFTER DELETE ON articles BEGIN DELETE FROM article_tags WHERE articleID = OLD.articleID; END;
	"""

	nonisolated static func syncTags(for article: Article, in database: FMDatabase) {
		syncTags(articleID: article.articleID, pairs: tagPairs(for: article), in: database)
	}

	nonisolated static func syncTags(articleID: String, pairs: [(ArticleTagCategory, String)], in database: FMDatabase) {
		database.executeUpdate("DELETE FROM article_tags WHERE articleID = ?;", withArgumentsIn: [articleID])
		guard !pairs.isEmpty else {
			return
		}
		var seen = Set<String>()
		for (category, rawName) in pairs {
			let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !name.isEmpty else {
				continue
			}
			let dedupKey = "\(category.rawValue)\u{0000}\(name)"
			guard seen.insert(dedupKey).inserted else {
				continue
			}
			database.executeUpdate(
				"INSERT OR IGNORE INTO tags (name, category) VALUES (?, ?);",
				withArgumentsIn: [name, category.rawValue]
			)
			guard let resultSet = database.executeQuery(
				"SELECT tagID FROM tags WHERE name = ? AND category = ? LIMIT 1;",
				withArgumentsIn: [name, category.rawValue]
			) else {
				continue
			}
			defer { resultSet.close() }
			if resultSet.next() {
				let tagID = resultSet.longLongInt(forColumnIndex: 0)
				database.executeUpdate(
					"INSERT OR IGNORE INTO article_tags (articleID, tagID) VALUES (?, ?);",
					withArgumentsIn: [articleID, tagID]
				)
			}
		}
	}

	nonisolated static func backfillAllArticles(in database: FMDatabase) {
		let sql = "SELECT articleID, fandoms, relationships, characters, additionalTags, ratings, warnings, categories, authors FROM articles;"
		guard let resultSet = database.executeQuery(sql, withArgumentsIn: []) else {
			return
		}
		var rows = [(articleID: String, pairs: [(ArticleTagCategory, String)])]()
		while resultSet.next() {
			guard let articleID = resultSet.string(forColumnIndex: 0) else {
				continue
			}
			var pairs = [(ArticleTagCategory, String)]()
			appendJSONStrings(resultSet.string(forColumnIndex: 1), category: .fandom, into: &pairs)
			appendJSONStrings(resultSet.string(forColumnIndex: 2), category: .relationship, into: &pairs)
			appendJSONStrings(resultSet.string(forColumnIndex: 3), category: .character, into: &pairs)
			appendJSONStrings(resultSet.string(forColumnIndex: 4), category: .freeform, into: &pairs)
			appendJSONStrings(resultSet.string(forColumnIndex: 5), category: .rating, into: &pairs)
			appendJSONStrings(resultSet.string(forColumnIndex: 6), category: .warning, into: &pairs)
			appendJSONStrings(resultSet.string(forColumnIndex: 7), category: .category, into: &pairs)
			appendAuthorNames(resultSet.string(forColumnIndex: 8), into: &pairs)
			if !pairs.isEmpty {
				rows.append((articleID: articleID, pairs: pairs))
			}
		}
		resultSet.close()

		let startedTransaction = !database.inTransaction()
		if startedTransaction {
			database.beginTransaction()
		}
		for row in rows {
			syncTags(articleID: row.articleID, pairs: row.pairs, in: database)
		}
		if startedTransaction {
			database.commit()
		}
		logger.info("ArticleTagIndexer: backfilled tags for \(rows.count, privacy: .public) articles")
	}

	nonisolated private static func tagPairs(for article: Article) -> [(ArticleTagCategory, String)] {
		var pairs = [(ArticleTagCategory, String)]()
		if let fandoms = article.fandoms {
			pairs.append(contentsOf: fandoms.map { (.fandom, $0) })
		}
		if let relationships = article.relationships {
			pairs.append(contentsOf: relationships.map { (.relationship, $0) })
		}
		if let characters = article.characters {
			pairs.append(contentsOf: characters.map { (.character, $0) })
		}
		if let additionalTags = article.additionalTags {
			pairs.append(contentsOf: additionalTags.map { (.freeform, $0) })
		}
		if let ratings = article.ratings {
			pairs.append(contentsOf: ratings.map { (.rating, $0) })
		}
		if let warnings = article.warnings {
			pairs.append(contentsOf: warnings.map { (.warning, $0) })
		}
		if let categories = article.categories {
			pairs.append(contentsOf: categories.map { (.category, $0) })
		}
		if let authors = article.authors {
			for author in authors {
				if let name = author.name, !name.isEmpty {
					pairs.append((.author, name))
				}
			}
		}
		return pairs
	}

	nonisolated private static func appendJSONStrings(_ json: String?, category: ArticleTagCategory, into pairs: inout [(ArticleTagCategory, String)]) {
		guard let json, let data = json.data(using: .utf8),
			  let array = try? JSONDecoder().decode([String].self, from: data) else {
			return
		}
		for item in array {
			pairs.append((category, item))
		}
	}

	nonisolated private static func appendAuthorNames(_ json: String?, into pairs: inout [(ArticleTagCategory, String)]) {
		guard let json, let data = json.data(using: .utf8),
			  let authors = try? JSONDecoder().decode([Author].self, from: data) else {
			return
		}
		for author in authors {
			if let name = author.name, !name.isEmpty {
				pairs.append((.author, name))
			}
		}
	}
}
