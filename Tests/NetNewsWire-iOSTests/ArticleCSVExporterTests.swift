//
//  ArticleCSVExporterTests.swift
//  NetNewsWire-iOSTests
//
//  Direct coverage of
//  ArticleCSVExporter (Shared/Exporters/ArticleCSVExporter.swift)'s
//  CSV export, previously untested despite being reachable from Settings
//  and MainFeedCollectionViewController.
//

import Testing
import Foundation
import Articles
@testable import Nectar

@MainActor @Suite struct ArticleCSVExporterTests {

	private static func makeArticle(
		title: String? = "Test Title",
		authors: Set<Author>? = nil,
		summary: String? = nil,
		fandoms: [String]? = nil,
		wordCount: Int? = nil,
		url: String? = "https://archiveofourown.org/works/999"
	) -> Article {
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
			summary: summary,
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: authors,
			wordCount: wordCount,
			fandoms: fandoms,
			status: status
		)
	}

	// 1. Header row matches the documented column list exactly.
	@Test("header row matches the documented 16-column list, in order")
	func headerRow() {
		let csv = ArticleCSVExporter.CSVString(with: [])
		let firstLine = csv.split(separator: "\r\n", omittingEmptySubsequences: true).first.map(String.init)
		#expect(firstLine == "title,author,author_url,summary,fandoms,warnings,characters,relationships,words,rating,chapters,categories,complete,series,updated,link")
	}

	// 2. Comma/quote/newline fields are correctly CSV-escaped -- the most
	// common real-world bug class for hand-rolled CSV writers.
	@Test("a field containing a comma is wrapped in quotes")
	func commaFieldIsQuoted() {
		let article = Self.makeArticle(title: "Title, With A Comma")
		let csv = ArticleCSVExporter.CSVString(with: [article])
		#expect(csv.contains("\"Title, With A Comma\""))
	}

	@Test("a field containing a double quote is wrapped and the quote is doubled")
	func quoteFieldIsEscaped() {
		let article = Self.makeArticle(title: "He said \"hello\"")
		let csv = ArticleCSVExporter.CSVString(with: [article])
		#expect(csv.contains("\"He said \"\"hello\"\"\""))
	}

	@Test("a field containing an embedded newline is wrapped in quotes")
	func newlineFieldIsQuoted() {
		let article = Self.makeArticle(summary: "Line one\nLine two")
		let csv = ArticleCSVExporter.CSVString(with: [article])
		#expect(csv.contains("\"Line one\nLine two\""))
	}

	@Test("a plain field with none of the special characters is left unquoted")
	func plainFieldIsNotQuoted() {
		let article = Self.makeArticle(title: "Plain Title")
		let csv = ArticleCSVExporter.CSVString(with: [article])
		let dataRow = csv.split(separator: "\r\n", omittingEmptySubsequences: true).dropFirst().first
		#expect(dataRow?.hasPrefix("Plain Title,") == true)
	}

	// 3. nil optional fields render as empty cells, not "nil" or a crash.
	@Test("nil optional fields render as empty cells")
	func nilFieldsRenderEmpty() {
		let article = Self.makeArticle(title: nil, authors: nil, summary: nil, fandoms: nil, wordCount: nil, url: nil)
		let csv = ArticleCSVExporter.CSVString(with: [article])
		let dataRow = csv.split(separator: "\r\n", omittingEmptySubsequences: true).dropFirst().first.map(String.init)
		// 16 columns, all empty except nothing -- 15 commas, no other content.
		#expect(dataRow == String(repeating: ",", count: 15))
		#expect(csv.contains("nil") == false)
	}

	// 4. Row count matches input count exactly, no silent drops.
	@Test("row count matches the input article count exactly")
	func rowCountMatchesInputCount() {
		let articles = (0..<5).map { _ in Self.makeArticle() }
		let csv = ArticleCSVExporter.CSVString(with: articles)
		let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: true)
		// One header row plus one row per article.
		#expect(lines.count == 6)
	}

	@Test("an empty article list produces just the header row")
	func emptyArticleListProducesOnlyHeader() {
		let csv = ArticleCSVExporter.CSVString(with: [])
		let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: true)
		#expect(lines.count == 1)
	}

	// Semicolon-joined multi-value fields (fandoms, warnings, etc.) --
	// confirms the documented "; "-join convention actually holds.
	@Test("multi-value fields are semicolon-joined")
	func multiValueFieldsAreSemicolonJoined() {
		let article = Self.makeArticle(fandoms: ["Fandom One", "Fandom Two"])
		let csv = ArticleCSVExporter.CSVString(with: [article])
		#expect(csv.contains("Fandom One; Fandom Two"))
	}
}
