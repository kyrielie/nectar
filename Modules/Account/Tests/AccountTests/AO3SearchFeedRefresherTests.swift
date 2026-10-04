//
//  AO3SearchFeedRefresherTests.swift
//  AccountTests
//
//  AO3SearchFeedRefresher through the TestingURLProtocol seam: import,
//  page bookkeeping, and each failure mapping with its English text.
//

import XCTest
import Articles
import ArticlesDatabase
import RSParser
import RSWeb
import AO3Kit
@testable import Account

@MainActor
final class AO3SearchFeedRefresherTests: XCTestCase {

	private final class FakeFeed: AO3SearchFeedPageTracking {
		let feedID = "refresher-feed"
		let url = "https://archiveofourown.org/works?work_search%5Bquery%5D=refresher"
		var ao3SearchFetchedPages: Set<Int>?
		var ao3SearchTotalPages: Int?
	}

	private final class FakeUpdater: AO3ArticleUpdating {
		var updateCount = 0
		var notificationCount = 0
		var lastDeleteOlder: Bool?

		func updateAsync(feedID: String, parsedItems: Set<ParsedItem>, deleteOlder: Bool) async -> ArticleChanges {
			updateCount += 1
			lastDeleteOlder = deleteOlder
			return ArticleChanges()
		}

		func sendNotificationAbout(_ articleChanges: ArticleChanges) {
			notificationCount += 1
		}
	}

	private static let host = "archiveofourown.org"
	private var savedChallengedURL: URL?

	override func setUp() async throws {
		TestingURLProtocol.reset()
		DownloadCache.shared.removeAll()
		Downloader.shared.clearCooldown(forHost: Self.host)
		AO3SessionStore.clearSession()
		savedChallengedURL = AO3ChallengeSessionStore.lastChallengedURL
	}

	override func tearDown() async throws {
		Downloader.shared.clearCooldown(forHost: Self.host)
		AO3ChallengeSessionStore.lastChallengedURL = savedChallengedURL
		TestingURLProtocol.reset()
	}

	private func setBody(_ html: String, statusCode: Int = 200, headers: [String: String] = [:]) {
		TestingURLProtocol.responses["archiveofourown.org/works"] = TestingURLProtocol.Response(statusCode: statusCode, data: Data(html.utf8), headers: headers)
	}

	private func refresh(feed: FakeFeed, updater: FakeUpdater, url: URL? = nil) async -> AO3SearchFeedRefresher.Result {
		await AO3SearchFeedRefresher.refresh(url: url ?? URL(string: feed.url)!, feedURL: feed.url, feedID: feed.feedID, tracker: feed, updater: updater, activity: nil)
	}

	private func resultsHTML(totalPages: Int) -> String {
		"""
		<html><head><title>Some Fandom - Works | Archive of Our Own</title></head><body>
		<li class="work-55555"><h4 class="heading"><a href="/works/55555">A Test Work</a> by <a rel="author" href="/users/author">author</a></h4></li>
		<ol class="pagination"><li><a href="?page=1">1</a></li><li><a href="?page=\(totalPages)">\(totalPages)</a></li></ol>
		</body></html>
		"""
	}

	func testSuccessfulRefreshImportsAndWritesPageOne() async {
		let feed = FakeFeed()
		let updater = FakeUpdater()
		feed.ao3SearchFetchedPages = [1, 2, 3]
		setBody(resultsHTML(totalPages: 7))

		let result = await refresh(feed: feed, updater: updater)

		guard case .imported(let count) = result else {
			return XCTFail("Expected imported, got \(result)")
		}
		XCTAssertEqual(count, 1)
		XCTAssertEqual(updater.updateCount, 1)
		XCTAssertEqual(updater.notificationCount, 1)
		XCTAssertEqual(updater.lastDeleteOlder, false)
		XCTAssertEqual(feed.ao3SearchFetchedPages, [1])
		XCTAssertEqual(feed.ao3SearchTotalPages, 7)
	}

	func testRegistrationWallMapsToListingRegistrationRequired() async {
		let feed = FakeFeed()
		let updater = FakeUpdater()
		setBody("<html><body><div id=\"signin\"><h3 class=\"heading\">Sorry!</h3><p>This work is only available to registered users of the Archive.</p></div></body></html>")

		let result = await refresh(feed: feed, updater: updater)

		guard case .failure(let failure) = result else {
			return XCTFail("Expected failure, got \(result)")
		}
		XCTAssertEqual(failure, .listingRestricted)
		XCTAssertEqual(failure.localizedMessage, "Restricted to registered AO3 users")
		XCTAssertEqual(updater.updateCount, 0)
	}

	func testRateLimitMapsToRateLimited() async {
		let feed = FakeFeed()
		let updater = FakeUpdater()
		setBody("", statusCode: 429, headers: ["Retry-After": "60"])

		let result = await refresh(feed: feed, updater: updater)

		guard case .failure(let failure) = result, case .rateLimited = failure else {
			return XCTFail("Expected rate limited failure, got \(result)")
		}
		XCTAssertEqual(failure.localizedMessage, "AO3 rate limit hit -- backing off before retrying")
		XCTAssertEqual(updater.updateCount, 0)
	}

	func testChallengeMapsToChallengeAndRecordsURL() async {
		let feed = FakeFeed()
		let updater = FakeUpdater()
		AO3ChallengeSessionStore.lastChallengedURL = nil
		setBody("<html><head><title>Just a moment...</title></head><body></body></html>")

		let result = await refresh(feed: feed, updater: updater)

		guard case .failure(let failure) = result else {
			return XCTFail("Expected failure, got \(result)")
		}
		XCTAssertEqual(failure, .challenge)
		XCTAssertEqual(failure.localizedMessage, "Blocked by a Cloudflare challenge -- try again later")
		XCTAssertNotNil(AO3ChallengeSessionStore.lastChallengedURL)
	}

	func testSignedOutSubscriptionsListingMapsToSignInRequired() async {
		let feed = FakeFeed()
		let updater = FakeUpdater()
		let url = URL(string: "https://archiveofourown.org/users/someone/subscriptions")!
		// Signed out, an always-private listing still goes out anonymously
		// (see AO3SearchResultsFetcher.fetchRequiringSignIn); AO3 answers
		// with its registered-users wall, which maps to .notSignedIn.
		TestingURLProtocol.responses["archiveofourown.org/users/someone/subscriptions"] = TestingURLProtocol.Response(statusCode: 200, data: Data("<html><body><div id=\"signin\"><h3 class=\"heading\">Sorry!</h3><p>This work is only available to registered users of the Archive.</p></div></body></html>".utf8))

		let result = await refresh(feed: feed, updater: updater, url: url)

		guard case .failure(let failure) = result else {
			return XCTFail("Expected failure, got \(result)")
		}
		XCTAssertEqual(failure, .signInRequired)
		XCTAssertEqual(updater.updateCount, 0)
	}
}
