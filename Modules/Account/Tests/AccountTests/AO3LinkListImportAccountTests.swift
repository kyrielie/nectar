//
//  AO3LinkListImportAccountTests.swift
//  AccountTests
//
//  Nectar AO3 direct-reading support -- pasted-link-list import (Task 3).
//  Exercises Account.importPastedAO3Links(_:) end-to-end against a real
//  (temp-directory-backed) local account: feed reuse across separate
//  imports, and dedup at the database level (not just within one paste).
//

import XCTest
@testable import Account

@MainActor final class AO3LinkListImportAccountTests: XCTestCase {

	private var account: Account!

	override func setUp() async throws {
		account = TestAccountManager.shared.createAccount(type: .onMyMac)
	}

	override func tearDown() async throws {
		TestAccountManager.shared.deleteAccount(account)
		account = nil
	}

	func testImportCreatesFeedAndArticles() async {
		let newCount = await account.importPastedAO3Links("https://archiveofourown.org/works/111 and https://archiveofourown.org/works/222")
		XCTAssertEqual(newCount, 2)

		let feed = account.existingFeed(withURL: Account.importedLinksFeedURL)
		XCTAssertNotNil(feed)

		let articles = await account.fetchArticlesAsync(.feed(feed!))
		XCTAssertEqual(articles.count, 2)
		XCTAssertEqual(Set(articles.map { $0.uniqueID }), ["111", "222"])
	}

	func testTextWithNoRecognizedLinksImportsNothingAndCreatesNoFeed() async {
		let newCount = await account.importPastedAO3Links("no links in here")
		XCTAssertEqual(newCount, 0)
		XCTAssertNil(account.existingFeed(withURL: Account.importedLinksFeedURL))
	}

	func testSecondImportReusesSameFeed() async {
		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/111")
		let feedAfterFirst = account.existingFeed(withURL: Account.importedLinksFeedURL)
		XCTAssertNotNil(feedAfterFirst)

		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/222")
		let feedAfterSecond = account.existingFeed(withURL: Account.importedLinksFeedURL)

		XCTAssertEqual(feedAfterFirst?.feedID, feedAfterSecond?.feedID)
		XCTAssertEqual(account.flattenedFeeds().filter { $0.url == Account.importedLinksFeedURL }.count, 1)
	}

	func testRePastingSameLinkAcrossSeparateImportsIsANoOp() async {
		let firstCount = await account.importPastedAO3Links("https://archiveofourown.org/works/111")
		XCTAssertEqual(firstCount, 1)

		// Same link pasted again in a completely separate call -- articleID is
		// derived from (feedID, uniqueID), and both are stable across imports,
		// so this must add nothing new.
		let secondCount = await account.importPastedAO3Links("https://archiveofourown.org/works/111")
		XCTAssertEqual(secondCount, 0)

		let feed = account.existingFeed(withURL: Account.importedLinksFeedURL)!
		let articles = await account.fetchArticlesAsync(.feed(feed))
		XCTAssertEqual(articles.count, 1)
	}

	func testEarlierImportedArticleSurvivesALaterUnrelatedImport() async {
		// deleteOlder: false -- a later import must never prune an article
		// from an earlier one, unlike an ordinary feed refresh.
		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/111")
		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/222")

		let feed = account.existingFeed(withURL: Account.importedLinksFeedURL)!
		let articles = await account.fetchArticlesAsync(.feed(feed))
		XCTAssertEqual(Set(articles.map { $0.uniqueID }), ["111", "222"])
	}

	// Not covered here: LocalAccountRefresher.feedShouldBeSkippedForDisallowedHostReasons's
	// nectar-import scheme check. That function lives in a `private extension`
	// in the same file, unreachable even via @testable import, and refreshAll()
	// itself goes through DownloadSession/live network -- same "not mockable,
	// not faked" situation AO3ChapterFetcherTests documents for Downloader.shared.
	// Verified by reading LocalAccountRefresher.swift directly instead: the
	// scheme check is the first branch in feedShouldBeSkippedForDisallowedHostReasons,
	// returning (true, ...) before any host-based logic runs.
}
