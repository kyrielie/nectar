//
//  ArticlesTable+LibrarySearch.swift
//  ArticlesDatabase
//
//  SQL compilation for persistent AO3-style LibrarySearchState queries and
//  indexed tag prefix autocomplete.
//

import Foundation
import RSDatabase
import RSDatabaseObjC
import Articles

extension ArticlesTable {

	func fetchArticleSearchMatchesAsync(
		for state: LibrarySearchState,
		feedIDs: Set<String>,
		cancellationToken: SQLiteCancellationToken? = nil,
		_ completion: @escaping @Sendable ([ArticleSearchMatch]) -> Void
	) {
		queue.runInDatabase { database in
			let matches = database.withProgressCancellation(cancellationToken) {
				self.fetchArticleSearchMatches(for: state, feedIDs: feedIDs, database)
			}
			DispatchQueue.main.async {
				completion(matches)
			}
		}
	}

	func fetchTagSuggestionsAsync(
		category: ArticleTagCategory?,
		prefix: String,
		limit: Int,
		feedIDs: Set<String>,
		scopedFandoms: Set<String> = [],
		_ completion: @escaping @Sendable ([TagSuggestion]) -> Void
	) {
		queue.runInDatabase { database in
			let suggestions = self.fetchTagSuggestions(
				category: category,
				prefix: prefix,
				limit: limit,
				feedIDs: feedIDs,
				scopedFandoms: scopedFandoms,
				database
			)
			DispatchQueue.main.async {
				completion(suggestions)
			}
		}
	}

	func fetchAvailableLanguagesAsync(
		feedIDs: Set<String>,
		_ completion: @escaping @Sendable ([String]) -> Void
	) {
		queue.runInDatabase { database in
			let languages = self.fetchAvailableLanguages(feedIDs: feedIDs, database)
			DispatchQueue.main.async {
				completion(languages)
			}
		}
	}

	func fetchArticleSearchMatches(for state: LibrarySearchState, feedIDs: Set<String>, _ database: FMDatabase) -> [ArticleSearchMatch] {
		guard state.hasExecutableCriteria,
			  let feedFilter = SQLiteIDList.clause(column: "articles.feedID", strings: feedIDs) else {
			return []
		}

		let trimmedQuery = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
		let sqlSearchString = trimmedQuery.count >= 3 ? sqliteSearchString(with: trimmedQuery) : nil
		let useFTS = sqlSearchString != nil

		// If the user typed >= 3 characters that collapsed to an empty FTS query (e.g. punctuation only)
		// and no structured filters are active, return empty rather than scanning everything.
		if !useFTS && !state.hasActiveFilters {
			return []
		}

		var whereClauses = [String]()
		var parameters = [AnyObject]()

		if let sqlSearchString {
			whereClauses.append("search match ?")
			parameters.append(sqlSearchString as AnyObject)
		}

		whereClauses.append(feedFilter.sql)
		parameters.append(feedFilter.parameter as AnyObject)

		appendTagFilterClauses(for: state, whereClauses: &whereClauses, parameters: &parameters)
		appendScalarFilterClauses(for: state, whereClauses: &whereClauses, parameters: &parameters)

		let selectColumns = useFTS
			? "articles.articleID, snippet(search, 1, char(30), char(31), '…', 24), snippet(search, 0, char(30), char(31), '…', 24)"
			: "articles.articleID"
		let fromClause = useFTS
			? "search join articles on articles.searchRowID = search.rowid"
			: "articles"
		let orderByClause = Self.orderBySQL(for: state.sort, useFTS: useFTS)
		let sql = "select \(selectColumns) from \(fromClause) where \(whereClauses.joined(separator: " and ")) order by \(orderByClause) limit 500;"

		guard let resultSet = database.executeQuery(sql, withArgumentsIn: parameters) else {
			if useFTS {
				let baseErrorCode = database.lastErrorCode() & 0xFF
				if baseErrorCode == 11 || baseErrorCode == 26 {
					Self.logger.error("ArticlesTable: FTS5 search index corrupted (code=\(baseErrorCode, privacy: .public)); resetting search table")
					resetCorruptSearchIndex(in: database)
				}
			}
			return []
		}

		var orderedRows = [(articleID: String, snippet: String?)]()
		while resultSet.next() {
			guard let articleID = resultSet.string(forColumnIndex: 0) else {
				continue
			}
			let snippet = useFTS
				? Self.preferredSnippet(bodySnippet: resultSet.string(forColumnIndex: 1), titleSnippet: resultSet.string(forColumnIndex: 2))
				: nil
			orderedRows.append((articleID: articleID, snippet: snippet))
		}
		resultSet.close()

		guard let articleIDFilter = SQLiteIDList.clause(column: "articleID", strings: Set(orderedRows.map(\.articleID))) else {
			return []
		}
		let fetchedArticles = fetchArticlesWithWhereClause(database, whereClause: articleIDFilter.sql, parameters: [articleIDFilter.parameter as AnyObject])
		let articlesByID = Dictionary(uniqueKeysWithValues: fetchedArticles.map { ($0.articleID, $0) })
		return orderedRows.compactMap { row in
			guard let article = articlesByID[row.articleID] else {
				return nil
			}
			return ArticleSearchMatch(article: article, snippet: row.snippet)
		}
	}

	func fetchTagSuggestions(
		category: ArticleTagCategory?,
		prefix: String,
		limit: Int,
		feedIDs: Set<String>,
		scopedFandoms: Set<String> = [],
		_ database: FMDatabase
	) -> [TagSuggestion] {
		guard limit > 0,
			  let feedFilter = SQLiteIDList.clause(column: "articles.feedID", strings: feedIDs) else {
			return []
		}

		var whereClauses = [feedFilter.sql]
		var parameters: [AnyObject] = [feedFilter.parameter as AnyObject]

		if let category {
			whereClauses.append("t.category = ?")
			parameters.append(category.rawValue as AnyObject)
		}

		if category != .fandom && !scopedFandoms.isEmpty {
			for fandom in scopedFandoms.sorted() {
				whereClauses.append("exists (select 1 from article_tags af join tags tf on tf.tagID = af.tagID where af.articleID = articles.articleID and tf.category = 'fandom' and tf.name = ?)")
				parameters.append(fandom as AnyObject)
			}
		}

		let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
		if !trimmedPrefix.isEmpty {
			let escaped = trimmedPrefix
				.replacingOccurrences(of: "\\", with: "\\\\")
				.replacingOccurrences(of: "%", with: "\\%")
				.replacingOccurrences(of: "_", with: "\\_")
			whereClauses.append("t.name like ? escape '\\'")
			parameters.append("%\(escaped)%" as AnyObject)
		}

		parameters.append(NSNumber(value: limit))

		let sql = """
		select t.name, t.category, count(distinct at.articleID) as articleCount
		from tags t
		join article_tags at on at.tagID = t.tagID
		join articles on articles.articleID = at.articleID
		where \(whereClauses.joined(separator: " and "))
		group by t.tagID
		order by articleCount desc, t.name asc
		limit ?;
		"""

		guard let resultSet = database.executeQuery(sql, withArgumentsIn: parameters) else {
			return []
		}
		defer { resultSet.close() }

		var suggestions = [TagSuggestion]()
		while resultSet.next() {
			guard let name = resultSet.string(forColumnIndex: 0),
				  let rawCategory = resultSet.string(forColumnIndex: 1),
				  let resolvedCategory = ArticleTagCategory(rawValue: rawCategory) else {
				continue
			}
			let count = Int(resultSet.int(forColumnIndex: 2))
			suggestions.append(TagSuggestion(name: name, category: resolvedCategory, articleCount: count))
		}
		return suggestions
	}

	func fetchAvailableLanguages(feedIDs: Set<String>, _ database: FMDatabase) -> [String] {
		guard let feedFilter = SQLiteIDList.clause(column: "feedID", strings: feedIDs) else {
			return []
		}
		let sql = "select distinct language from articles where \(feedFilter.sql) and language is not null and trim(language) != '' order by language collate nocase asc;"
		guard let resultSet = database.executeQuery(sql, withArgumentsIn: [feedFilter.parameter as AnyObject]) else {
			return []
		}
		defer { resultSet.close() }

		var languages = [String]()
		while resultSet.next() {
			if let lang = resultSet.string(forColumnIndex: 0) {
				languages.append(lang)
			}
		}
		return languages
	}

	private func appendTagFilterClauses(
		for state: LibrarySearchState,
		whereClauses: inout [String],
		parameters: inout [AnyObject]
	) {
		for category in ArticleTagCategory.allCases {
			if let included = state.includedTags[category] {
				for name in included.sorted() {
					whereClauses.append("exists (select 1 from article_tags at join tags t on t.tagID = at.tagID where at.articleID = articles.articleID and t.category = ? and t.name = ?)")
					parameters.append(category.rawValue as AnyObject)
					parameters.append(name as AnyObject)
				}
			}
			if let excluded = state.excludedTags[category] {
				for name in excluded.sorted() {
					whereClauses.append("not exists (select 1 from article_tags at join tags t on t.tagID = at.tagID where at.articleID = articles.articleID and t.category = ? and t.name = ?)")
					parameters.append(category.rawValue as AnyObject)
					parameters.append(name as AnyObject)
				}
			}
		}
	}

	private func appendScalarFilterClauses(
		for state: LibrarySearchState,
		whereClauses: inout [String],
		parameters: inout [AnyObject]
	) {
		switch state.completion {
		case .any:
			break
		case .completeOnly:
			whereClauses.append("articles.isComplete = 1")
		case .wipOnly:
			whereClauses.append("articles.isComplete = 0")
		}

		switch state.crossover {
		case .any:
			break
		case .crossoverOnly:
			whereClauses.append("(select count(*) from article_tags at join tags t on t.tagID = at.tagID where at.articleID = articles.articleID and t.category = 'fandom') > 1")
		case .singleFandomOnly:
			whereClauses.append("(select count(*) from article_tags at join tags t on t.tagID = at.tagID where at.articleID = articles.articleID and t.category = 'fandom') = 1")
		}

		if let language = state.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
			whereClauses.append("lower(articles.language) = lower(?)")
			parameters.append(language as AnyObject)
		}

		if let wordsFrom = state.wordsFrom {
			whereClauses.append("coalesce(articles.wordCount, 0) >= ?")
			parameters.append(NSNumber(value: wordsFrom))
		}

		if let wordsTo = state.wordsTo {
			whereClauses.append("articles.wordCount is not null and articles.wordCount <= ?")
			parameters.append(NSNumber(value: wordsTo))
		}
	}

	private static func orderBySQL(for sort: LibrarySearchSort, useFTS: Bool) -> String {
		switch sort {
		case .relevance:
			return useFTS ? "bm25(search)" : "coalesce(articles.dateModified, articles.datePublished) desc"
		case .datePublished:
			return "articles.datePublished desc"
		case .dateModified:
			return "coalesce(articles.dateModified, articles.datePublished) desc"
		case .wordCount:
			return "coalesce(articles.wordCount, 0) desc"
		case .kudosCount:
			return "coalesce(articles.kudosCount, 0) desc"
		case .bookmarkCount:
			return "coalesce(articles.bookmarkCount, 0) desc"
		case .hitCount:
			return "coalesce(articles.hitCount, 0) desc"
		case .dateBookmarked:
			return "coalesce(articles.dateBookmarked, articles.datePublished) desc"
		}
	}
}
