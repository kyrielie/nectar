//
//  ArticleCSVExporter.swift
//  NetNewsWire
//
//  Task 4 (CSV export): columns match ao3downloader's
//  parse_soup.get_work_metadata_from_list confirmed column list --
//  title, author, summary, fandoms, warnings, characters, relationships,
//  words, rating, chapters, categories, complete, series, updated, link --
//  with the bookmark-only optional columns (date_bookmarked,
//  bookmarker_tags, bookmarker_notes, last_visited, times_visited) and the
//  freeform `tags` column dropped, since Nectar's Article model has no
//  backing field for any of them and they would be uniformly empty, plus
//  an added `author_url` column (semicolon-joined, same convention as
//  fandoms/warnings/etc.) per Task 4. No `contentHTML`.
//

import Foundation
import Articles

@MainActor struct ArticleCSVExporter {

	private static let columnHeaders = [
		"title", "author", "author_url", "summary", "fandoms", "warnings",
		"characters", "relationships", "words", "rating", "chapters",
		"categories", "complete", "series", "updated", "link"
	]

	static func CSVString(with articles: [Article]) -> String {
		var rows = [rowString(for: columnHeaders)]
		for article in articles {
			rows.append(rowString(for: columns(for: article)))
		}
		return rows.joined(separator: "\r\n") + "\r\n"
	}

	// MARK: - Private

	private static func columns(for article: Article) -> [String] {
		return [
			article.title ?? "",
			joinedAuthorNames(article),
			joinedAuthorURLs(article),
			article.summary ?? "",
			joined(article.fandoms),
			joined(article.warnings),
			joined(article.characters),
			joined(article.relationships),
			article.wordCount.map(String.init) ?? "",
			joined(article.ratings),
			chaptersString(article),
			joined(article.categories),
			completeString(article),
			seriesString(article),
			updatedString(article),
			(article.preferredURL ?? article.url)?.absoluteString ?? ""
		]
	}

	private static func joined(_ values: [String]?) -> String {
		guard let values, !values.isEmpty else { return "" }
		return values.joined(separator: "; ")
	}

	// Article.authors is a Set, so sort by authorID for stable, repeatable
	// CSV output rather than depending on Set's undefined iteration order.
	private static func sortedAuthors(_ article: Article) -> [Author] {
		guard let authors = article.authors, !authors.isEmpty else { return [] }
		return authors.sorted { $0.authorID < $1.authorID }
	}

	private static func joinedAuthorNames(_ article: Article) -> String {
		return sortedAuthors(article).compactMap { $0.name }.joined(separator: "; ")
	}

	private static func joinedAuthorURLs(_ article: Article) -> String {
		return sortedAuthors(article).compactMap { $0.url }.joined(separator: "; ")
	}

	private static func chaptersString(_ article: Article) -> String {
		guard let current = article.chapterCurrent else { return "" }
		let total = article.chapterTotal.map(String.init) ?? "?"
		return "\(current)/\(total)"
	}

	private static func completeString(_ article: Article) -> String {
		guard let isComplete = article.isComplete else { return "" }
		return isComplete ? "true" : "false"
	}

	private static func seriesString(_ article: Article) -> String {
		guard let series = article.series, !series.isEmpty else { return "" }
		return series.map { "\($0.name) (\($0.index))" }.joined(separator: "; ")
	}

	// ISO 8601 rather than ArticleStringFormatter's locale-dependent
	// .medium display style: this is exported data meant to be read back
	// or sorted by a spreadsheet, not UI text.
	private static let dateFormatter: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime]
		return formatter
	}()

	private static func updatedString(_ article: Article) -> String {
		guard let dateModified = article.dateModified else { return "" }
		return dateFormatter.string(from: dateModified)
	}

	private static func rowString(for columns: [String]) -> String {
		return columns.map(escapedCSVField).joined(separator: ",")
	}

	private static func escapedCSVField(_ field: String) -> String {
		guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
			return field
		}
		return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
	}
}
