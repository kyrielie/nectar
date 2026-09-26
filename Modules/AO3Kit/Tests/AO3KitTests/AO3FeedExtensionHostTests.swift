//
//  AO3FeedExtensionHostTests.swift
//  AO3Kit
//
//  A feed entry only gets an AO3 work id (and so an `ao3-work:` bookKey and a
//  live AO3 fetch) when its permalink is on one of AO3's own hosts.
//

import Foundation
import RSParser
import Testing
@testable import AO3Kit

@Suite struct AO3FeedExtensionHostTests {

	/// Minimal summary that `AO3SummaryExtractor` accepts as AO3-shaped.
	private static let summaryHTML = "<p>Words: 500, Chapters: 1/1</p>"

	private func extraction(forPermalink permalink: String?) -> AO3SummaryExtractionResult? {
		AO3FeedExtension().extractedItem(fromSummaryHTML: Self.summaryHTML, permalink: permalink, language: nil)
	}

	@Test(arguments: [
		"https://archiveofourown.org/works/123",
		"https://www.archiveofourown.org/works/123",
		"https://archiveofourown.com/works/123",
		"https://archiveofourown.net/works/123",
		"https://archiveofourown.gay/works/123",
		"https://ao3.org/works/123",
		"https://archive.transformativeworks.org/works/123",
		"http://insecure.archiveofourown.org/works/123"
	])
	func officialHostsYieldWorkID(permalink: String) {
		#expect(extraction(forPermalink: permalink)?.ao3WorkID == "123")
	}

	@Test(arguments: [
		"https://starlog-archive.invalid/works/123",
		"https://example.com/works/123",
		"https://archiveofourown.org.some-mirror.example/works/123",
		"https://notarchiveofourown.org/works/123"
	])
	func otherHostsYieldNoWorkID(permalink: String) {
		#expect(extraction(forPermalink: permalink)?.ao3WorkID == nil)
	}

	@Test func missingOrRelativePermalinkYieldsNoWorkID() {
		#expect(extraction(forPermalink: nil)?.ao3WorkID == nil)
		#expect(extraction(forPermalink: "/works/123")?.ao3WorkID == nil)
	}

	/// Only the work id is gated. The summary metadata still comes through, so
	/// a non-AO3-host entry keeps its badges and stats.
	@Test func otherHostStillExtractsSummaryMetadata() throws {
		let result = try #require(extraction(forPermalink: "https://starlog-archive.invalid/works/123"))
		#expect(result.wordCount == 500)
		#expect(result.chapterCurrent == 1)
		#expect(result.ao3WorkID == nil)
	}
}
