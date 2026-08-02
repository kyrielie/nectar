//
//  AO3SummaryExtractorTests.swift
//  RSParser
//
//  Created for the Nectar fork.
//

import Foundation
import Testing
@testable import RSParser

@Suite struct AO3SummaryExtractorTests {

	@Test func nonAO3SummaryReturnsNil() {
		let result = AO3SummaryExtractor.extract(fromSummaryHTML: "<p>Just a regular blog post.</p>")
		#expect(result == nil)
	}

	@Test func fullTagListEntry() throws {
		let feed = try #require(try FeedParser.parse(parserData("testfeed", "atom", "https://archiveofourown.org/tags/1147379/feed.atom")))
		let item = try #require(feed.items.first { $0.title == "I've Looked at Life From Both Sides Now" })

		#expect(item.contentHTML == nil)
		#expect(item.wordCount == 5643)
		#expect(item.chapterCurrent == 1)
		#expect(item.chapterTotal == 4)
		#expect(item.isComplete == false)
		#expect(item.fandoms == ["Check Please! (Webcomic)"])
		#expect(item.ratings == ["Teen And Up Audiences"])
		#expect(item.warnings == ["No Archive Warnings Apply"])
		#expect(item.categories == ["M/M"])
		#expect(item.ao3WorkID == "88675176")
	}

	@Test func chaptersUnknownTotalIsNil() throws {
		let feed = try #require(try FeedParser.parse(parserData("testfeed", "atom", "https://archiveofourown.org/tags/1147379/feed.atom")))
		let itemsWithUnknownTotal = feed.items.filter { $0.chapterCurrent != nil && $0.chapterTotal == nil }
		#expect(itemsWithUnknownTotal.count == 4)
		for item in itemsWithUnknownTotal {
			#expect(item.isComplete == nil)
		}
	}

	@Test func seriesEntries() throws {
		let feed = try #require(try FeedParser.parse(parserData("testfeed", "atom", "https://archiveofourown.org/tags/1147379/feed.atom")))
		let itemsWithSeries = feed.items.filter { ($0.series?.isEmpty ?? true) == false }
		#expect(itemsWithSeries.count == 2)

		let partTwo = itemsWithSeries.first { $0.series?.first?.index == 2 }
		#expect(partTwo?.series?.first?.name == "Vivienne 'verse")
		#expect(partTwo?.series?.first?.ao3ID == "6313756")

		let partOne = itemsWithSeries.first { $0.series?.first?.index == 1 }
		#expect(partOne?.series?.first?.name == "birthday ficlets 2026")
		#expect(partOne?.series?.first?.ao3ID == "6092166")
	}

	@Test func anonymousEntryDoesNotLeakBylineIntoSummary() throws {
		let feed = try #require(try FeedParser.parse(parserData("testfeed", "atom", "https://archiveofourown.org/tags/1147379/feed.atom")))
		let item = try #require(feed.items.first { $0.title == "anyway you slice it" })
		#expect(item.summary?.contains("by Anonymous") != true)
		#expect(item.wordCount != nil)
	}

	@Test func endToEnd25Items() throws {
		let feed = try #require(try FeedParser.parse(parserData("testfeed", "atom", "https://archiveofourown.org/tags/1147379/feed.atom")))
		#expect(feed.items.count == 25)
		for item in feed.items {
			#expect(item.contentHTML == nil)
			#expect(item.wordCount != nil)
		}
	}
}
