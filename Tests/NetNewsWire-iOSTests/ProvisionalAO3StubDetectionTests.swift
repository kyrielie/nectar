//
//  ProvisionalAO3StubDetectionTests.swift
//  NetNewsWire-iOSTests
//
//  Regression coverage for WebViewController.isProvisionalAO3Stub(_:), the
//  seam introduced by the Reading Stats/Screen Time fix plan's Phase 2 to
//  stop the reader from recording scroll progress, page-counter state, or
//  Reading Stats credit against an unfetched AO3 stub. WebViewController
//  itself can't be instantiated here -- see
//  WebViewControllerAppearanceToggleTests.swift's header comment -- so this
//  targets the pure, internal helper directly.
//

import Testing
import Foundation
import Articles
@testable import Nectar

@MainActor @Suite struct ProvisionalAO3StubDetectionTests {

	private static func makeArticle(bookKey: String, contentHTML: String?) -> Article {
		let articleID = "test-article-id-\(UUID().uuidString)"
		let dateArrived = Date(timeIntervalSince1970: 1_500_000_000)
		let status = ArticleStatus(articleID: articleID, read: false, starred: false, dateArrived: dateArrived)
		return Article(
			accountID: "test-account-id",
			articleID: articleID,
			feedID: "test-feed-id",
			uniqueID: "test-unique-id",
			title: "Test Title",
			contentHTML: contentHTML,
			contentText: nil,
			markdown: nil,
			url: nil,
			externalURL: nil,
			summary: nil,
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			bookKey: bookKey,
			status: status
		)
	}

	@Test func nilArticle_isNotProvisional() {
		#expect(WebViewController.isProvisionalAO3Stub(nil) == false)
	}

	@Test func nonAO3Article_isNotProvisional_evenWithNoContent() {
		let article = Self.makeArticle(bookKey: "some-other-book-key", contentHTML: nil)
		#expect(WebViewController.isProvisionalAO3Stub(article) == false)
	}

	@Test func ao3ArticleWithNoContent_isProvisional() {
		let article = Self.makeArticle(bookKey: "ao3-work:12345", contentHTML: nil)
		#expect(WebViewController.isProvisionalAO3Stub(article) == true)
	}

	/// Documents a deliberate D7 behavior difference: the bare prefix with
	/// no id is no longer treated as an AO3 bookKey (`AO3Link.workID(fromBookKey:)`
	/// requires a non-empty id, unlike the old `hasPrefix("ao3-work:")`
	/// check). `ParsedItem.bookKey` can never produce a bare prefix (it
	/// requires a non-empty id to take the `ao3-work:` branch at all), so
	/// no live article is expected to hit this case.
	@Test func ao3ArticleWithBarePrefixAndNoID_isNotProvisional() {
		let article = Self.makeArticle(bookKey: "ao3-work:", contentHTML: nil)
		#expect(WebViewController.isProvisionalAO3Stub(article) == false)
	}

	@Test func ao3ArticleWithEmptyContent_isProvisional() {
		let article = Self.makeArticle(bookKey: "ao3-work:12345", contentHTML: "")
		#expect(WebViewController.isProvisionalAO3Stub(article) == true)
	}

	@Test func ao3ArticleWithFetchedContent_isNotProvisional() {
		let article = Self.makeArticle(bookKey: "ao3-work:12345", contentHTML: "<p>Real chapter text.</p>")
		#expect(WebViewController.isProvisionalAO3Stub(article) == false)
	}
}
