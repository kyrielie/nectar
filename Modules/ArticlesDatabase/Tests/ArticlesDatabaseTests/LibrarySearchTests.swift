//
//  LibrarySearchTests.swift
//  ArticlesDatabaseTests
//

import Testing
import Foundation
import RSParser
import Articles
@testable import ArticlesDatabase

@Suite("Normalized tags and LibrarySearchState queries")
@MainActor
struct LibrarySearchTests {

	private static let feedID = "feed-library-search"
	private static let feedURL = "https://archiveofourown.org/tags/test/works"

	@Test("indexes normalized tags and filters metadata-only and hybrid FTS queries")
	func filtersByTagsCompletionCrossoverWordCountAndFTS() async throws {
		let db = TestFixtures.makeDatabase()

		let matchingWork = ParsedItem(
			syncServiceID: "work-1",
			uniqueID: "work-1",
			feedURL: Self.feedURL,
			url: "https://archiveofourown.org/works/101",
			externalURL: nil,
			title: "Starlight Protocol",
			language: "English",
			contentHTML: "<p>They met beside the observatory lantern at midnight.</p>",
			contentText: nil,
			markdown: nil,
			summary: "Summary 1",
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: Date(timeIntervalSince1970: 1_700_000_000),
			dateModified: Date(timeIntervalSince1970: 1_700_001_000),
			authors: [ParsedAuthor(name: "AuthorA", url: nil, avatarURL: nil, emailAddress: nil)],
			tags: ["Slow Burn", "Observatory"],
			attachments: nil,
			wordCount: 15_000,
			chapterCurrent: 5,
			chapterTotal: 5,
			isComplete: true,
			fandoms: ["Fandom Alpha", "Fandom Beta"],
			relationships: ["Ship X"],
			characters: ["Char One"],
			ratings: ["Teen And Up Audiences"],
			warnings: ["No Archive Warnings Apply"],
			categories: ["Gen"],
			kudosCount: 120,
			ao3Language: "English"
		)

		let excludedWork = ParsedItem(
			syncServiceID: "work-2",
			uniqueID: "work-2",
			feedURL: Self.feedURL,
			url: "https://archiveofourown.org/works/102",
			externalURL: nil,
			title: "Harbor Watch",
			language: "English",
			contentHTML: "<p>Another observatory lantern story.</p>",
			contentText: nil,
			markdown: nil,
			summary: "Summary 2",
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: Date(timeIntervalSince1970: 1_700_000_000),
			dateModified: Date(timeIntervalSince1970: 1_700_002_000),
			authors: [ParsedAuthor(name: "AuthorB", url: nil, avatarURL: nil, emailAddress: nil)],
			tags: ["Angst"],
			attachments: nil,
			wordCount: 4_000,
			chapterCurrent: 2,
			chapterTotal: nil,
			isComplete: false,
			fandoms: ["Fandom Alpha"],
			relationships: ["Ship X"],
			characters: ["Char One"],
			ratings: ["Explicit"],
			warnings: ["Major Character Death"],
			categories: ["Gen"],
			kudosCount: 300,
			ao3Language: "English"
		)

		_ = await db.updateAsync(parsedItems: [matchingWork, excludedWork], feedID: Self.feedID, deleteOlder: false)

		// Metadata-only filter (empty query): include Ship X, exclude Major Character Death, crossover only, complete only, >= 10k words.
		var metadataState = LibrarySearchState()
		metadataState.includeTag("Ship X", category: .relationship)
		metadataState.excludeTag("Major Character Death", category: .warning)
		metadataState.completion = .completeOnly
		metadataState.crossover = .crossoverOnly
		metadataState.wordsFrom = 10_000
		metadataState.language = "english"

		let metadataMatches = await db.fetchArticleSearchMatchesAsync(for: metadataState, feedIDs: [Self.feedID])
		#expect(metadataMatches.map(\.article.uniqueID) == ["work-1"])
		#expect(metadataMatches.first?.snippet == nil)

		// Hybrid FTS + tag filter: query "lantern" + include AuthorA.
		var hybridState = LibrarySearchState(query: "lantern")
		hybridState.includeTag("AuthorA", category: .author)
		let hybridMatches = await db.fetchArticleSearchMatchesAsync(for: hybridState, feedIDs: [Self.feedID])
		#expect(hybridMatches.map(\.article.uniqueID) == ["work-1"])
		let snippet = try #require(hybridMatches.first?.snippet)
		#expect(snippet.contains(ArticleSearchMatch.matchStartDelimiter))

		// Tag suggestions prefix query.
		let fandomSuggestions = await db.fetchTagSuggestionsAsync(category: .fandom, prefix: "Fandom", feedIDs: [Self.feedID])
		#expect(fandomSuggestions.first?.name == "Fandom Alpha")
		#expect(fandomSuggestions.first?.articleCount == 2)

		// Scoped tag suggestions should only include tags co-occurring with the selected fandom.
		let scopedCharacterSuggestions = await db.fetchTagSuggestionsAsync(
			category: .character,
			prefix: "",
			feedIDs: [Self.feedID],
			scopedFandoms: ["Fandom Alpha"]
		)
		#expect(scopedCharacterSuggestions.allSatisfy { $0.category == .character && $0.articleCount > 0 })
		let emptyScopeSuggestions = await db.fetchTagSuggestionsAsync(
			category: .character,
			prefix: "",
			feedIDs: [Self.feedID],
			scopedFandoms: ["Nonexistent Fandom"]
		)
		#expect(emptyScopeSuggestions.isEmpty)

		let languages = await db.fetchAvailableLanguagesAsync(feedIDs: [Self.feedID])
		#expect(languages == ["English"])
	}
}
