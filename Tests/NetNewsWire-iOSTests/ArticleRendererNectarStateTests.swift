//
//  ArticleRendererNectarStateTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for the hidden #nectarState marker (see docs/nnwtheme-format.md,
//  "Nectar state hooks"). Tests ArticleRenderer.nectarStateMarkerHTML and the
//  synthetic preface directly, not articleHTML(article:theme:), for the same
//  reason ArticleRendererSeriesNavigationTests does: ArticleTheme() reads
//  bundle resources that do not resolve in the test bundle. The empty-state
//  renderings (multipleSelectionHTML, loadingHTML, and so on) pass
//  article: nil, so ArticleRenderer.init never builds a marker for them.
//

import Testing
import Foundation
import Articles
@testable import Nectar
@testable import ArticleTheming

@MainActor @Suite struct ArticleRendererNectarStateTests {

	private static func makeArticle(
		starred: Bool = false,
		loved: Bool = false,
		isRestricted: Bool? = nil,
		contentHTML: String? = nil,
		fandoms: [String]? = nil
	) -> Article {
		let articleID = "test-article-id-\(UUID().uuidString)"
		let status = ArticleStatus(articleID: articleID, read: false, starred: starred, dateArrived: Date())
		status.loved = loved
		return Article(
			accountID: "test-account-id",
			articleID: articleID,
			feedID: "test-feed-id",
			uniqueID: "test-unique-id",
			title: "Test Title",
			contentHTML: contentHTML,
			contentText: nil,
			markdown: nil,
			url: "https://archiveofourown.org/works/999",
			externalURL: nil,
			summary: nil,
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			fandoms: fandoms,
			isRestricted: isRestricted,
			status: status
		)
	}

	@Test("marker carries the starred and loved booleans")
	func markerCarriesBooleans() {
		let marker = ArticleRenderer.nectarStateMarkerHTML(for: Self.makeArticle(starred: true, loved: false))
		#expect(marker.contains("id=\"nectarState\""))
		#expect(marker.contains("data-starred=\"true\""))
		#expect(marker.contains("data-loved=\"false\""))
	}

	@Test("marker is hidden and has no text node")
	func markerIsHiddenAndEmpty() {
		let marker = ArticleRenderer.nectarStateMarkerHTML(for: Self.makeArticle())
		#expect(marker.contains(" hidden "))
		#expect(marker.contains("aria-hidden=\"true\""))
		#expect(marker.hasPrefix("<span "))
		#expect(marker.hasSuffix("></span>"))
	}

	@Test("data-restricted is omitted when isRestricted is nil")
	func restrictedOmittedForNil() {
		let marker = ArticleRenderer.nectarStateMarkerHTML(for: Self.makeArticle(isRestricted: nil))
		#expect(!marker.contains("data-restricted"))
	}

	@Test("data-restricted reflects a known value")
	func restrictedReflectsValue() {
		#expect(ArticleRenderer.nectarStateMarkerHTML(for: Self.makeArticle(isRestricted: true)).contains("data-restricted=\"true\""))
		#expect(ArticleRenderer.nectarStateMarkerHTML(for: Self.makeArticle(isRestricted: false)).contains("data-restricted=\"false\""))
	}

	@Test("status written after construction is what the marker reads")
	func markerReadsCurrentStatus() {
		let article = Self.makeArticle(starred: false)
		article.status.starred = true
		#expect(ArticleRenderer.nectarStateMarkerHTML(for: article).contains("data-starred=\"true\""))
	}

	@Test("synthetic preface rows carry data-kind")
	func syntheticPrefaceCarriesKinds() throws {
		let originalStatsVisible = AppDefaults.shared.statsVisible
		AppDefaults.shared.statsVisible = true
		defer { AppDefaults.shared.statsVisible = originalStatsVisible }

		let status = ArticleStatus(articleID: "kinds", read: false, starred: false, dateArrived: Date())
		let article = Article(accountID: "a", articleID: "kinds", feedID: "f", uniqueID: "u", title: "T", contentHTML: nil, contentText: nil, markdown: nil, url: nil, externalURL: nil, summary: nil, imageURL: nil, datePublished: nil, dateModified: nil, authors: nil, fandoms: ["Fandom"], relationships: ["A/B"], characters: ["A"], ratings: ["General Audiences"], warnings: ["No Archive Warnings Apply"], categories: ["Gen"], status: status)
		let preface = try #require(ArticleRenderer.ao3SyntheticPrefaceHTML(for: article))
		for kind in ["rating", "warning", "category", "fandom", "relationship", "character"] {
			#expect(preface.contains("data-kind='\(kind)'"), "missing \(kind)")
		}
		#expect(preface.contains("<span data-value='gen'>Gen</span>"))
	}
}
