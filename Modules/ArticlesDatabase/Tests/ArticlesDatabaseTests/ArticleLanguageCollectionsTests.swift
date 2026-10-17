//
//  ArticleLanguageCollectionsTests.swift
//  ArticlesDatabaseTests
//
//  `language` (AO3 display text) and `collections` (JSON array of
//  {name, slug}). Both NULL = unknown; collections "[]" = known to be in none.
//

import Testing
import Foundation
import RSParser
import Articles
import RSDatabaseObjC
@testable import ArticlesDatabase

@Suite("language and collections storage")
@MainActor
struct ArticleLanguageCollectionsTests {

	private static let feedID = "feed-1"
	private static let feedURL = "https://example.com/feed"
	private static let articleID = Article.calculatedArticleID(feedID: feedID, uniqueID: "u1")

	private let a = ParsedCollectionEntry(name: "Voiceteam 2025", slug: "Voiceteam2025")
	private let b = ParsedCollectionEntry(name: "Dapper Dormice", slug: "VT2025_Dapper")

	private func item(language: String? = nil, collections: [ParsedCollectionEntry]? = nil) -> ParsedItem {
		TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: Self.feedURL, ao3Language: language, collections: collections)
	}

	private func stored(_ db: ArticlesDatabase) async throws -> Article {
		try #require(await db.fetchArticlesAsync(articleIDs: [Self.articleID]).first)
	}

	private func write(_ db: ArticlesDatabase, _ parsed: ParsedItem) async {
		_ = await db.updateAsync(parsedItems: [parsed], feedID: Self.feedID, deleteOlder: false)
	}

	// MARK: language

	@Test("language round trips, nil included", arguments: [nil, "English"] as [String?])
	func languageRoundTrip(value: String?) async throws {
		let db = TestFixtures.makeDatabase()
		await write(db, item(language: value))
		#expect(try await stored(db).language == value)
	}

	@Test("a nil language refresh never blanks a stored value")
	func nilLanguageDoesNotBlank() async throws {
		let db = TestFixtures.makeDatabase()
		await write(db, item(language: "English"))
		await write(db, item(language: nil))
		#expect(try await stored(db).language == "English")
	}

	@Test("a different language is written")
	func languageChangeWrites() async throws {
		let db = TestFixtures.makeDatabase()
		await write(db, item(language: "English"))
		await write(db, item(language: "Deutsch"))
		#expect(try await stored(db).language == "Deutsch")
	}

	@Test("the feed-level ParsedItem.language code is not persisted")
	func feedLevelLanguageIsNotStored() async throws {
		let db = TestFixtures.makeDatabase()
		await write(db, TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: Self.feedURL, language: "en-us"))
		#expect(try await stored(db).language == nil)
	}

	// MARK: collections

	@Test("collections round trip with name and slug")
	func collectionsRoundTrip() async throws {
		let db = TestFixtures.makeDatabase()
		await write(db, item(collections: [a, b]))
		#expect(try await stored(db).collections == [
			ArticleCollectionEntry(name: a.name, slug: a.slug),
			ArticleCollectionEntry(name: b.name, slug: b.slug)
		])
	}

	@Test("nil collections stay nil (unknown)")
	func nilCollectionsStayNil() async throws {
		let db = TestFixtures.makeDatabase()
		await write(db, item(collections: nil))
		#expect(try await stored(db).collections == nil)
	}

	@Test("an empty collections array round trips as empty, distinct from nil")
	func emptyCollectionsRoundTrip() async throws {
		let db = TestFixtures.makeDatabase()
		await write(db, item(collections: []))
		#expect(try await stored(db).collections == [])
	}

	@Test("a nil collections refresh never blanks stored collections")
	func nilCollectionsDoNotBlank() async throws {
		let db = TestFixtures.makeDatabase()
		await write(db, item(collections: [a]))
		await write(db, item(collections: nil))
		#expect(try await stored(db).collections?.count == 1)
	}

	@Test("an empty collections array clears a stored membership")
	func emptyCollectionsClear() async throws {
		let db = TestFixtures.makeDatabase()
		await write(db, item(collections: [a, b]))
		await write(db, item(collections: []))
		#expect(try await stored(db).collections == [])
	}

	@Test("a changed collections list is written")
	func collectionsChangeWrites() async throws {
		let db = TestFixtures.makeDatabase()
		await write(db, item(collections: [a]))
		await write(db, item(collections: [b]))
		#expect(try await stored(db).collections == [ArticleCollectionEntry(name: b.name, slug: b.slug)])
	}
}
