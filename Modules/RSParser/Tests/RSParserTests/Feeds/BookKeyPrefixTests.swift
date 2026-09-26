//
//  BookKeyPrefixTests.swift
//  RSParser
//
//  ParsedItem.bookKey uses BookKeyPrefix's constants for its three
//  prefixed cases. This pins that each case's bookKey actually starts
//  with the matching prefix, so the two can't silently drift apart.
//

import Foundation
import Testing
import RSParser

@Suite struct BookKeyPrefixTests {

	private static func makeItem(ao3WorkID: String? = nil, isAnthology: Bool? = nil, ao3SeriesID: String? = nil, seriesName: String? = nil) -> ParsedItem {
		ParsedItem(
			syncServiceID: nil,
			uniqueID: "test-unique-id",
			feedURL: "https://example.com/feed.json",
			url: nil,
			externalURL: nil,
			title: nil,
			language: nil,
			contentHTML: nil,
			contentText: nil,
			markdown: nil,
			summary: nil,
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			tags: nil,
			attachments: nil,
			ao3WorkID: ao3WorkID,
			isAnthology: isAnthology,
			ao3SeriesID: ao3SeriesID,
			seriesName: seriesName)
	}

	@Test func ao3SeriesBookKeyStartsWithAO3SeriesPrefix() {
		let item = Self.makeItem(ao3SeriesID: "45")
		#expect(item.bookKey.hasPrefix(BookKeyPrefix.ao3Series))
		#expect(item.bookKey == "\(BookKeyPrefix.ao3Series)45")
	}

	@Test func calibreSeriesBookKeyStartsWithCalibreSeriesPrefix() {
		let item = Self.makeItem(isAnthology: true, seriesName: "Some Series")
		#expect(item.bookKey.hasPrefix(BookKeyPrefix.calibreSeries))
		#expect(item.bookKey == "\(BookKeyPrefix.calibreSeries)Some Series")
	}

	@Test func ao3WorkBookKeyStartsWithAO3WorkPrefix() {
		let item = Self.makeItem(ao3WorkID: "12345")
		#expect(item.bookKey.hasPrefix(BookKeyPrefix.ao3Work))
		#expect(item.bookKey == "\(BookKeyPrefix.ao3Work)12345")
	}
}
