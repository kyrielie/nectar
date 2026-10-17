//
//  ArticleIsRestrictedTests.swift
//  ArticlesDatabaseTests
//
//  isRestricted (AO3 archive lock). Nullable BOOL, nil = unknown.
//

import Testing
import Foundation
import RSParser
import Articles
@testable import ArticlesDatabase

@Suite("isRestricted storage")
@MainActor
struct ArticleIsRestrictedTests {

	private static let feedID = "feed-1"
	private static let feedURL = "https://example.com/feed"
	private static let articleID = Article.calculatedArticleID(feedID: feedID, uniqueID: "u1")

	private func item(isRestricted: Bool?) -> ParsedItem {
		TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: Self.feedURL, isRestricted: isRestricted)
	}

	private func stored(_ db: ArticlesDatabase) async throws -> Article {
		try #require(await db.fetchArticlesAsync(articleIDs: [Self.articleID]).first)
	}

	// MARK: Round trip and diff rules

	@Test("nil, true and false each round trip through the database", arguments: [nil, true, false] as [Bool?])
	func roundTrip(value: Bool?) async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [item(isRestricted: value)], feedID: Self.feedID, deleteOlder: false)
		#expect(try await stored(db).isRestricted == value)
	}

	@Test("a nil refresh never blanks a stored true")
	func nilDoesNotBlankTrue() async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [item(isRestricted: true)], feedID: Self.feedID, deleteOlder: false)
		_ = await db.updateAsync(parsedItems: [item(isRestricted: nil)], feedID: Self.feedID, deleteOlder: false)
		#expect(try await stored(db).isRestricted == true)
	}

	@Test("true to false is written, for a work its author unlocked")
	func trueToFalseWrites() async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [item(isRestricted: true)], feedID: Self.feedID, deleteOlder: false)
		_ = await db.updateAsync(parsedItems: [item(isRestricted: false)], feedID: Self.feedID, deleteOlder: false)
		#expect(try await stored(db).isRestricted == false)
	}

	@Test("false to true is written")
	func falseToTrueWrites() async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [item(isRestricted: false)], feedID: Self.feedID, deleteOlder: false)
		_ = await db.updateAsync(parsedItems: [item(isRestricted: true)], feedID: Self.feedID, deleteOlder: false)
		#expect(try await stored(db).isRestricted == true)
	}
}
