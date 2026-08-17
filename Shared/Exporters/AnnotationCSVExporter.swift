//
//  AnnotationCSVExporter.swift
//  NetNewsWire
//
//  Same shape as ArticleCSVExporter: a columnHeaders array and a
//  CSVString(with:) static function. Paired with each annotation's
//  owning Article (not just the Annotation itself), since the CSV needs
//  the book/chapter title and link, which live on Article, not on
//  Annotation.
//

import Foundation
import Articles

@MainActor struct AnnotationCSVExporter {

	private static let columnHeaders = [
		"book", "chapter", "quote", "note", "color", "created", "link"
	]

	static func CSVString(with rows: [(Annotation, Article?)]) -> String {
		var lines = [CSVFormatting.rowString(for: columnHeaders)]
		for (annotation, article) in rows {
			lines.append(CSVFormatting.rowString(for: columns(for: annotation, article: article)))
		}
		return lines.joined(separator: "\r\n") + "\r\n"
	}

	// MARK: - Private

	private static func columns(for annotation: Annotation, article: Article?) -> [String] {
		return [
			bookString(article),
			chapterString(annotation, article),
			annotation.quoteExact,
			annotation.note ?? "",
			annotation.color.rawValue,
			dateFormatter.string(from: annotation.createdAt),
			(article?.preferredURL ?? article?.url)?.absoluteString ?? ""
		]
	}

	// Falls back to the chapter title when the article has no series/book
	// name of its own -- an annotation whose owning article couldn't be
	// found (deleted since the highlight was made) still exports with
	// whatever it has rather than dropping the row.
	private static func bookString(_ article: Article?) -> String {
		guard let article else { return "" }
		if let series = article.series, !series.isEmpty {
			return series.map { $0.name }.joined(separator: "; ")
		}
		return article.title ?? ""
	}

	// Prefers the real per-annotation chapterTitle (see Annotation.chapterTitle)
	// now that one exists; falls back to the book title for annotations made
	// before chapterTitle existed and not yet re-anchored (nil until then --
	// self-heals, see docs/annotations.md), or for genuinely single-heading
	// books where there's no distinct chapter to report. Previously this
	// column was always article?.title -- i.e. the book title mislabeled as
	// "chapter" -- since no per-annotation chapter data existed yet.
	private static func chapterString(_ annotation: Annotation, _ article: Article?) -> String {
		annotation.chapterTitle ?? article?.title ?? ""
	}

	// ISO 8601, same reasoning as ArticleCSVExporter.updatedString: this is
	// exported data meant to be read back or sorted by a spreadsheet, not
	// UI text.
	private static let dateFormatter: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime]
		return formatter
	}()
}
