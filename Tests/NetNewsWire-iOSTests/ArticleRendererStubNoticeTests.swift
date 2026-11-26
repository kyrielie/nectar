//
//  ArticleRendererStubNoticeTests.swift
//  NetNewsWire-iOSTests
//

import Testing
import Foundation
import Articles
import AO3Kit
@testable import Nectar

@MainActor @Suite struct ArticleRendererStubNoticeTests {

	private static func makeArticle(
		contentHTML: String? = nil,
		bookKey: String = "ao3-work:999",
		isAmbrosiaItem: Bool = false,
		ao3ConfirmedMissingAt: Date? = nil
	) -> Article {
		let articleID = "test-article-\(UUID().uuidString)"
		return Article(
			accountID: "test-account",
			articleID: articleID,
			feedID: "test-feed",
			uniqueID: "test-unique",
			title: "Test Work",
			contentHTML: contentHTML,
			contentText: nil,
			markdown: nil,
			url: "https://archiveofourown.org/works/999",
			externalURL: nil,
			summary: "<p>Summary</p>",
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			ao3ConfirmedMissingAt: ao3ConfirmedMissingAt,
			isAmbrosiaItem: isAmbrosiaItem,
			bookKey: bookKey,
			status: ArticleStatus(articleID: articleID, read: false, starred: false, dateArrived: Date())
		)
	}

	@Test("non-AO3 article with nil contentHTML produces no stub notice")
	func nonAO3ArticleReturnsNil() {
		let article = Self.makeArticle(contentHTML: nil, bookKey: "non-ao3-unique-id")
		#expect(ArticleRenderer.ao3StubNoticeHTML(for: article, isFetching: false) == nil)
	}

	@Test("populated AO3 article produces no stub notice")
	func populatedAO3ArticleReturnsNil() {
		let article = Self.makeArticle(contentHTML: "<p>Chapter 1</p>")
		#expect(ArticleRenderer.ao3StubNoticeHTML(for: article, isFetching: false) == nil)
	}

	@Test("in-flight stub shows fetching message without retry button")
	func inFlightStubNotice() {
		let article = Self.makeArticle()
		let html = ArticleRenderer.ao3StubNoticeHTML(for: article, isFetching: true)
		#expect(html?.contains("Fetching full work from AO3") == true)
		#expect(html?.contains("nectar-ao3-fetch://") == false)
	}

	@Test("failed stub shows error reason and retry button")
	func failedStubNotice() {
		let article = Self.makeArticle()
		let html = ArticleRenderer.ao3StubNoticeHTML(for: article, isFetching: false, lastFailureMessage: "HTTP 503")
		#expect(html?.contains("Full text unavailable: HTTP 503") == true)
		#expect(html?.contains("href='nectar-ao3-fetch://retry'") == true)
	}

	@Test("confirmed-missing stub shows missing message and retry button")
	func confirmedMissingStubNotice() {
		let article = Self.makeArticle(ao3ConfirmedMissingAt: Date())
		let html = ArticleRenderer.ao3StubNoticeHTML(for: article, isFetching: false)
		#expect(html?.contains("missing or inaccessible") == true)
		#expect(html?.contains("href='nectar-ao3-fetch://retry'") == true)
	}

	@Test("idle stub shows summary notice and Fetch Full Work button")
	func idleStubNotice() {
		let article = Self.makeArticle()
		let html = ArticleRenderer.ao3StubNoticeHTML(for: article, isFetching: false)
		#expect(html?.contains("Showing feed summary stub") == true)
		#expect(html?.contains("href='nectar-ao3-fetch://fetch'") == true)
	}
}
