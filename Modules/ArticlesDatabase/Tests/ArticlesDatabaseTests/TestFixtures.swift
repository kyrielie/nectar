//
//  TestFixtures.swift
//  ArticlesDatabaseTests
//
//  Phase 0.2: a real in-memory ArticlesDatabase per test (SQLite's ":memory:"
//  path, same pattern RSDatabaseTests uses for FMDatabase directly), plus a
//  ParsedItem builder that fills in every required field with an inert
//  default so each test only has to specify what it's actually exercising.
//

import Foundation
import Testing
import RSParser
import Articles
@testable import ArticlesDatabase

@MainActor
enum TestFixtures {

	static func makeDatabase(accountID: String = "test-account") -> ArticlesDatabase {
		ArticlesDatabase(databaseFilePath: ":memory:", accountID: accountID, retentionStyle: .feedBased)
	}

	/// `uniqueID` and `feedURL` default to caller-supplied values because
	/// `ParsedItem.articleID` (and therefore `Article.articleID`) is derived
	/// from `Article.calculatedArticleID(feedID: feedURL, uniqueID:)` -- two
	/// items that are meant to be "the same article" across two different
	/// test calls must share both, and two items meant to be siblings on
	/// different feeds must differ on `feedURL` even while sharing whatever
	/// makes their `bookKey`s equal.
	static func makeParsedItem(
		uniqueID: String,
		feedURL: String,
		title: String? = "Test Title",
		contentHTML: String? = "<p>content</p>",
		summary: String? = nil,
		isAmbrosiaItem: Bool = true,
		wordCount: Int? = nil,
		fandoms: [String]? = nil,
		ao3WorkID: String? = nil,
		isAnthology: Bool? = nil,
		ao3SeriesID: String? = nil,
		seriesName: String? = nil
	) -> ParsedItem {
		ParsedItem(
			syncServiceID: nil,
			uniqueID: uniqueID,
			feedURL: feedURL,
			url: nil,
			externalURL: nil,
			title: title,
			language: nil,
			contentHTML: contentHTML,
			contentText: nil,
			markdown: nil,
			summary: summary,
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			tags: nil,
			attachments: nil,
			isAmbrosiaItem: isAmbrosiaItem,
			wordCount: wordCount,
			fandoms: fandoms,
			ao3WorkID: ao3WorkID,
			isAnthology: isAnthology,
			ao3SeriesID: ao3SeriesID,
			seriesName: seriesName
		)
	}
}
