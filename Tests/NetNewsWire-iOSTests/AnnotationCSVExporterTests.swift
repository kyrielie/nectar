//
//  AnnotationCSVExporterTests.swift
//  NetNewsWire-iOSTests
//
//  Direct coverage of AnnotationCSVExporter (Shared/Exporters/
//  AnnotationCSVExporter.swift), focused on the hasHighlight/
//  originalText/replacementText columns added alongside schema version
//  5 (see docs/annotations.md, "Storage shape") across the row shapes
//  that column combination produces: pure-highlight, edit-only, and
//  highlight+edit. Escaping and row-count sanity are covered too, same
//  shape as ArticleCSVExporterTests, but this file doesn't re-derive
//  CSVFormatting's own escaping rules -- that's CSVFormattingTests'
//  job -- it only confirms AnnotationCSVExporter actually routes
//  through it.
//

import Testing
import Foundation
import Articles
@testable import Nectar

@MainActor @Suite struct AnnotationCSVExporterTests {

	private static func makeArticle(title: String? = "Test Book", url: String? = "https://archiveofourown.org/works/999") -> Article {
		let articleID = "test-article-id-\(UUID().uuidString)"
		let status = ArticleStatus(articleID: articleID, read: false, starred: false, dateArrived: Date())
		return Article(
			accountID: "test-account-id",
			articleID: articleID,
			feedID: "test-feed-id",
			uniqueID: "test-unique-id",
			title: title,
			contentHTML: nil,
			contentText: nil,
			markdown: nil,
			url: url,
			externalURL: nil,
			summary: nil,
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			status: status
		)
	}

	private static func makeAnnotation(
		quoteExact: String = "he'd still be",
		note: String? = nil,
		chapterTitle: String? = nil,
		hasHighlight: Bool = true,
		originalText: String? = nil,
		replacementText: String? = nil
	) -> Annotation {
		Annotation(
			annotationID: "test-annotation-id-\(UUID().uuidString)",
			articleID: "test-article-id",
			bookKey: "test-book-key",
			quoteExact: quoteExact,
			quotePrefix: "hoping ",
			quoteSuffix: " there",
			startOffset: 10,
			endOffset: 24,
			color: .yellow,
			note: note,
			chapterTitle: chapterTitle,
			hasHighlight: hasHighlight,
			originalText: originalText,
			replacementText: replacementText,
			createdAt: Date(),
			updatedAt: Date()
		)
	}

	// MARK: - Header

	@Test("header row includes the three schema-version-5 columns, in order, at the end")
	func headerRowIncludesNewColumns() {
		let csv = AnnotationCSVExporter.CSVString(with: [])
		let firstLine = csv.split(separator: "\r\n", omittingEmptySubsequences: true).first.map(String.init)
		#expect(firstLine == "book,chapter,quote,note,color,created,link,hasHighlight,originalText,replacementText")
	}

	// MARK: - Row shapes

	@Test("a pure-highlight row has hasHighlight true and empty originalText/replacementText")
	func pureHighlightRow() {
		let article = Self.makeArticle()
		let annotation = Self.makeAnnotation(hasHighlight: true, originalText: nil, replacementText: nil)
		let csv = AnnotationCSVExporter.CSVString(with: [(annotation, article)])
		let dataRow = csv.split(separator: "\r\n", omittingEmptySubsequences: true).dropFirst().first.map(String.init)
		#expect(dataRow?.hasSuffix(",true,,") == true)
	}

	@Test("an edit-only row has hasHighlight false and populated originalText/replacementText")
	func editOnlyRow() {
		let article = Self.makeArticle()
		let annotation = Self.makeAnnotation(hasHighlight: false, originalText: "teh", replacementText: "the")
		let csv = AnnotationCSVExporter.CSVString(with: [(annotation, article)])
		let dataRow = csv.split(separator: "\r\n", omittingEmptySubsequences: true).dropFirst().first.map(String.init)
		#expect(dataRow?.hasSuffix(",false,teh,the") == true)
	}

	@Test("a highlight+edit row has hasHighlight true and populated originalText/replacementText")
	func highlightPlusEditRow() {
		let article = Self.makeArticle()
		let annotation = Self.makeAnnotation(hasHighlight: true, originalText: "he'd stil be", replacementText: "he'd still be")
		let csv = AnnotationCSVExporter.CSVString(with: [(annotation, article)])
		let dataRow = csv.split(separator: "\r\n", omittingEmptySubsequences: true).dropFirst().first.map(String.init)
		#expect(dataRow?.hasSuffix(",true,he'd stil be,he'd still be") == true)
	}

	// MARK: - Escaping

	@Test("a comma inside originalText/replacementText is quoted like any other field")
	func commaInEditFieldsIsQuoted() {
		let article = Self.makeArticle()
		let annotation = Self.makeAnnotation(hasHighlight: false, originalText: "alot, of things", replacementText: "a lot, of things")
		let csv = AnnotationCSVExporter.CSVString(with: [(annotation, article)])
		#expect(csv.contains("\"alot, of things\""))
		#expect(csv.contains("\"a lot, of things\""))
	}

	// MARK: - Chapter fallback (unaffected by this feature, sanity-checked alongside it)

	@Test("chapter column prefers chapterTitle over the book title when both are present")
	func chapterPrefersChapterTitle() {
		let article = Self.makeArticle(title: "Book Title")
		let annotation = Self.makeAnnotation(chapterTitle: "Chapter Two")
		let csv = AnnotationCSVExporter.CSVString(with: [(annotation, article)])
		let dataRow = csv.split(separator: "\r\n", omittingEmptySubsequences: true).dropFirst().first.map(String.init)
		#expect(dataRow?.hasPrefix("Book Title,Chapter Two,") == true)
	}

	// MARK: - Row count sanity

	@Test("row count matches the input count exactly, mixing highlight and edit rows")
	func rowCountMatchesInputCount() {
		let article = Self.makeArticle()
		let rows: [(Annotation, Article?)] = [
			(Self.makeAnnotation(hasHighlight: true), article),
			(Self.makeAnnotation(hasHighlight: false, originalText: "teh", replacementText: "the"), article),
			(Self.makeAnnotation(hasHighlight: true, originalText: "stil", replacementText: "still"), article)
		]
		let csv = AnnotationCSVExporter.CSVString(with: rows)
		let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: true)
		#expect(lines.count == 4)
	}

	@Test("an empty annotation list produces just the header row")
	func emptyListProducesOnlyHeader() {
		let csv = AnnotationCSVExporter.CSVString(with: [])
		let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: true)
		#expect(lines.count == 1)
	}
}
