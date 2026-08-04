//
//  AO3IgnoreListTests.swift
//  RSParser
//
//  Nectar AO3 direct-reading support, Task 7 ("Ignore lists") test plan.
//
//  Uses .standard UserDefaults (AO3IgnoreList's own fallback in a test
//  context with no AppIdentifierPrefix Info.plist key -- see its doc
//  comment), so each test clears both keys' state up front rather than
//  relying on test ordering.
//

import Foundation
import Testing
@testable import RSParser

@Suite struct AO3IgnoreListTests {

	init() {
		AO3IgnoreList.ignoredWorkIDs = []
		AO3IgnoreList.ignoredAuthorURLs = []
	}

	// MARK: - Storage

	@Test func ignoreAndUnignoreWork() {
		AO3IgnoreList.ignoreWork(id: "12345")
		#expect(AO3IgnoreList.ignoredWorkIDs.contains("12345"))

		AO3IgnoreList.unignoreWork(id: "12345")
		#expect(!AO3IgnoreList.ignoredWorkIDs.contains("12345"))
	}

	@Test func ignoreAndUnignoreAuthor() {
		let url = "https://archiveofourown.org/users/someone/pseuds/someone"
		AO3IgnoreList.ignoreAuthor(url: url)
		#expect(AO3IgnoreList.ignoredAuthorURLs.contains(url))

		AO3IgnoreList.unignoreAuthor(url: url)
		#expect(!AO3IgnoreList.ignoredAuthorURLs.contains(url))
	}

	// MARK: - shouldExclude(_:) -- by work

	@Test func excludesIgnoredWorkID() {
		AO3IgnoreList.ignoreWork(id: "12345")
		let item = Self.makeItem(ao3WorkID: "12345")
		#expect(AO3IgnoreList.shouldExclude(item))
	}

	@Test func doesNotExcludeNonIgnoredWorkID() {
		AO3IgnoreList.ignoreWork(id: "99999")
		let item = Self.makeItem(ao3WorkID: "12345")
		#expect(!AO3IgnoreList.shouldExclude(item))
	}

	@Test func doesNotExcludeItemWithNoAO3WorkID() {
		AO3IgnoreList.ignoreWork(id: "12345")
		let item = Self.makeItem(ao3WorkID: nil)
		#expect(!AO3IgnoreList.shouldExclude(item))
	}

	// MARK: - shouldExclude(_:) -- by author

	@Test func excludesIgnoredAuthorURL() {
		let url = "https://archiveofourown.org/users/someone/pseuds/someone"
		AO3IgnoreList.ignoreAuthor(url: url)
		let item = Self.makeItem(ao3WorkID: "12345", authorURLs: [url])
		#expect(AO3IgnoreList.shouldExclude(item))
	}

	@Test func excludesWhenAnyCoAuthorIsIgnored() {
		let ignoredURL = "https://archiveofourown.org/users/ignored/pseuds/ignored"
		AO3IgnoreList.ignoreAuthor(url: ignoredURL)
		let item = Self.makeItem(ao3WorkID: "12345", authorURLs: [
			"https://archiveofourown.org/users/fine/pseuds/fine",
			ignoredURL,
		])
		#expect(AO3IgnoreList.shouldExclude(item))
	}

	@Test func doesNotExcludeWhenNoAuthorIsIgnored() {
		AO3IgnoreList.ignoreAuthor(url: "https://archiveofourown.org/users/someone/pseuds/someone")
		let item = Self.makeItem(ao3WorkID: "12345", authorURLs: ["https://archiveofourown.org/users/other/pseuds/other"])
		#expect(!AO3IgnoreList.shouldExclude(item))
	}

	@Test func doesNotExcludeAuthorWithNoURL() {
		AO3IgnoreList.ignoreAuthor(url: "https://archiveofourown.org/users/someone/pseuds/someone")
		let item = Self.makeItem(ao3WorkID: "12345", authors: [ParsedAuthor(name: "Someone", url: nil, avatarURL: nil, emailAddress: nil)])
		#expect(!AO3IgnoreList.shouldExclude(item))
	}
}

private extension AO3IgnoreListTests {

	static func makeItem(ao3WorkID: String?, authorURLs: [String] = []) -> ParsedItem {
		let authors = authorURLs.map { ParsedAuthor(name: nil, url: $0, avatarURL: nil, emailAddress: nil) }
		return makeItem(ao3WorkID: ao3WorkID, authors: Set(authors))
	}

	static func makeItem(ao3WorkID: String?, authors: Set<ParsedAuthor>) -> ParsedItem {
		ParsedItem(
			syncServiceID: nil,
			uniqueID: "test-unique-id-\(UUID().uuidString)",
			feedURL: "https://archiveofourown.org/some/feed",
			url: nil,
			externalURL: nil,
			title: "Test Work",
			language: nil,
			contentHTML: nil,
			contentText: nil,
			markdown: nil,
			summary: nil,
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: authors.isEmpty ? nil : authors,
			tags: nil,
			attachments: nil,
			ao3WorkID: ao3WorkID
		)
	}
}
