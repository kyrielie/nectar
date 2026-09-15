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
	// itself goes through DownloadSession, which (unlike Downloader.shared,
	// now stubbable -- see AO3SeriesNavigatorTests.swift) still has no
	// TestingURLProtocol seam of its own. Verified by reading
	// LocalAccountRefresher.swift directly instead: the scheme check is the
	// first branch in feedShouldBeSkippedForDisallowedHostReasons, returning
	// (true, ...) before any host-based logic runs.

	// MARK: - destination: .newFolder

	func testNewFolderDestinationCreatesFolderAndFeedInsideIt() async {
		let newCount = await account.importPastedAO3Links("https://archiveofourown.org/works/111", destination: .newFolder(name: "09-13-26"))
		XCTAssertEqual(newCount, 1)

		let folder = account.existingFolder(withDisplayName: "09-13-26")
		XCTAssertNotNil(folder, "Destination folder should be created if it doesn't already exist")

		// The shared top-level feed must be untouched by a folder import.
		XCTAssertNil(account.existingFeed(withURL: Account.importedLinksFeedURL))

		let feed = folder?.topLevelFeeds.first
		XCTAssertNotNil(feed)
		let articles = await account.fetchArticlesAsync(.feed(feed!))
		XCTAssertEqual(articles.map(\.uniqueID), ["111"])
	}

	func testNewFolderDestinationReusesExistingFolderOfTheSameName() async {
		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/111", destination: .newFolder(name: "09-13-26"))
		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/222", destination: .newFolder(name: "09-13-26"))

		// One folder, not two, and both links land in its one feed --
		// this is the "same name reused... appends to the same feed"
		// behavior the destination picker's own design review flagged
		// as an open question.
		XCTAssertEqual(account.folders?.count, 1)
		let folder = account.existingFolder(withDisplayName: "09-13-26")!
		XCTAssertEqual(folder.topLevelFeeds.count, 1)

		let articles = await account.fetchArticlesAsync(.feed(folder.topLevelFeeds.first!))
		XCTAssertEqual(Set(articles.map(\.uniqueID)), ["111", "222"])
	}

	func testDifferentNewFolderNamesGetSeparateFeeds() async {
		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/111", destination: .newFolder(name: "09-13-26"))
		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/222", destination: .newFolder(name: "09-14-26"))

		XCTAssertEqual(account.folders?.count, 2)
		let firstFeed = account.existingFolder(withDisplayName: "09-13-26")?.topLevelFeeds.first
		let secondFeed = account.existingFolder(withDisplayName: "09-14-26")?.topLevelFeeds.first
		XCTAssertNotNil(firstFeed)
		XCTAssertNotNil(secondFeed)
		XCTAssertNotEqual(firstFeed?.feedID, secondFeed?.feedID)
	}

	// MARK: - destination: .existingContainer

	func testExistingContainerDestinationImportsIntoThatFolder() async {
		let folder = account.ensureFolder(with: "Fandom")!

		let newCount = await account.importPastedAO3Links("https://archiveofourown.org/works/111", destination: .existingContainer(folder))
		XCTAssertEqual(newCount, 1)

		let feed = folder.topLevelFeeds.first
		XCTAssertNotNil(feed)
		XCTAssertNil(account.existingFeed(withURL: Account.importedLinksFeedURL), "Shared top-level feed should be untouched")

		let articles = await account.fetchArticlesAsync(.feed(feed!))
		XCTAssertEqual(articles.map(\.uniqueID), ["111"])
	}

	func testExistingContainerDestinationIntoNestedFolderReusesItsFeedOnReimport() async {
		let nested = account.ensureFolder(withFolderNames: ["Parent", "Child"])!

		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/111", destination: .existingContainer(nested))
		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/222", destination: .existingContainer(nested))

		XCTAssertEqual(nested.topLevelFeeds.count, 1, "Re-importing into the same nested folder must reuse its feed, not duplicate it")
		let articles = await account.fetchArticlesAsync(.feed(nested.topLevelFeeds.first!))
		XCTAssertEqual(Set(articles.map(\.uniqueID)), ["111", "222"])
	}
}
