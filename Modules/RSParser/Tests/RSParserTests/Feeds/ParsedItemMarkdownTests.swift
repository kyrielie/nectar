//
//  ParsedItemMarkdownTests.swift
//  RSParser
//
//  `ParsedItem.markdown` is carried and persisted but no longer rendered
//  (Tidemark was removed so the package builds for an iOS 16 target).
//  These tests pin that `contentHTML` is never derived from `markdown`.
//

import Foundation
import Testing
import RSParser

@Suite struct ParsedItemMarkdownTests {

	private static func makeItem(contentHTML: String?, markdown: String?) -> ParsedItem {
		ParsedItem(
			syncServiceID: nil,
			uniqueID: "test-unique-id",
			feedURL: "https://example.com/feed.xml",
			url: nil,
			externalURL: nil,
			title: nil,
			language: nil,
			contentHTML: contentHTML,
			contentText: nil,
			markdown: markdown,
			summary: nil,
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			tags: nil,
			attachments: nil)
	}

	@Test func contentHTMLWinsAndMarkdownIsRetained() {
		let item = Self.makeItem(contentHTML: "<p>x</p>", markdown: "# Hi")
		#expect(item.contentHTML == "<p>x</p>")
		#expect(item.markdown == "# Hi")
	}

	@Test func markdownOnlyYieldsNilContentHTML() {
		let item = Self.makeItem(contentHTML: nil, markdown: "# Hi")
		#expect(item.contentHTML == nil)
		#expect(item.markdown == "# Hi")
	}

	@Test func rssSourceMarkdownIsCapturedButNotRendered() throws {
		let d = parserData("markdown2", "rss", "https://wordland.social/scripting/246529703/rss.xml")
		let parsedFeed = try #require(try FeedParser.parse(d))
		let item = try #require(parsedFeed.items.first)
		let markdown = try #require(item.markdown)
		let contentHTML = try #require(item.contentHTML)

		// The item's <description> (HTML) is promoted to contentHTML; the
		// <source:markdown> text is kept only in `markdown`.
		#expect(contentHTML.hasPrefix("<p>"))
		#expect(contentHTML != markdown)
		#expect(!markdown.contains("<p>"))
	}
}
