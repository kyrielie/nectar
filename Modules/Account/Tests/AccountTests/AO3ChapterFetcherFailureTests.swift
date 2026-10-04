//
//  AO3ChapterFetcherFailureTests.swift
//  AccountTests
//
//  How AO3ChapterFetcher.download reacts to each kind of failed fetch: which
//  failure it records, whether it sets ao3ConfirmedMissingAt, whether it
//  caches or retries, and whether a rate limit or rejected session stops
//  the anonymous fallback. TestingURLProtocol serves both transports, so a
//  fallback shows up as an extra entry in requestedURLs.
//
//  The challenge, 503 and not-found bodies are synthetic (see
//  AO3WorkPageClassifierTests). The cases that need a stored session skip
//  when the Keychain refuses the write.
//
import XCTest
import RSWeb
import Articles
import AO3Kit
@testable import Account

@MainActor final class AO3ChapterFetcherFailureTests: XCTestCase {

	private static let host = "archiveofourown.org"
	private static let challengeHTML = "<html><head><title>Just a moment...</title></head><body></body></html>"
	private static let unavailableHTML = "<html><body><h2>Error 503 - Service unavailable</h2></body></html>"
	private static let notFoundHTML = "<html><body>Sorry, we couldn&#x27;t find the work you were looking for.</body></html>"
	private static let unknownHTML = "<html><body><p>Something nobody has seen before.</p></body></html>"
	private static let registrationHTML = "<html><body><div id=\"signin\"><p>This work is only available to registered users of the Archive.</p></div></body></html>"

	private var account: Account!
	private var feedID: String!
	private var articleID: String!
	private var workID = ""

	override func setUp() async throws {
		TestingURLProtocol.reset()
		DownloadCache.shared.removeAll()
		Downloader.shared.clearCooldown(forHost: Self.host)
		AO3SessionStore.clearSession()

		workID = String(Int.random(in: 70_000_000...79_999_999))
		account = TestAccountManager.shared.createAccount(type: .onMyMac)
		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/\(workID)")
		let feed = try XCTUnwrap(account.existingFeed(withURL: Account.importedLinksFeedURL))
		feedID = feed.feedID
		articleID = Article.calculatedArticleID(feedID: feedID, uniqueID: workID)
	}

	override func tearDown() async throws {
		TestingURLProtocol.reset()
		Downloader.shared.clearCooldown(forHost: Self.host)
		AO3SessionStore.clearSession()
		TestAccountManager.shared.deleteAccount(account)
		account = nil
	}

	// MARK: - Helpers

	private func respond(statusCode: Int = 200, body: String, headers: [String: String] = [:]) {
		TestingURLProtocol.responses["archiveofourown.org/works/\(workID)"] = TestingURLProtocol.Response(statusCode: statusCode, data: Data(body.utf8), headers: headers)
	}

	private func runDownload(priority: AO3ChapterFetcher.Priority = .interactive, timeout: TimeInterval = 8) async {
		let failed = expectation(forNotification: .ao3ChapterFetchDidFail, object: nil)
		AO3ChapterFetcher.shared.download(workID: workID, articleID: articleID, accountID: account.accountID, feedID: feedID, priority: priority)
		await fulfillment(of: [failed], timeout: timeout)
	}

	private var requestCount: Int {
		TestingURLProtocol.requestedURLs.filter { $0.absoluteString.contains("/works/\(workID)") }.count
	}

	private func confirmedMissingAt() async throws -> Date? {
		let articles = await account.fetchArticlesAsync(.articleIDs([articleID]))
		return try XCTUnwrap(articles.first).ao3ConfirmedMissingAt
	}

	private func storeSession() throws {
		AO3SessionStore.saveSession(cookieHeaderValue: "_otwarchive_session=test")
		try XCTSkipUnless(AO3SessionStore.isSignedIn, "Keychain unavailable in this test environment")
	}

	// MARK: - Missing flag (anonymous)

	func testHTTP404SetsMissingFlagWhenSignedOut() async throws {
		respond(statusCode: 404, body: "")

		await runDownload()

		XCTAssertEqual(AO3ChapterFetcher.shared.lastFetchFailure(forArticleID: articleID), .workMissing)
		let flag = try await confirmedMissingAt()
		XCTAssertNotNil(flag)
	}

	func testExplicitNotFoundCopySetsMissingFlag() async throws {
		respond(body: Self.notFoundHTML)

		await runDownload()

		XCTAssertEqual(AO3ChapterFetcher.shared.lastFetchFailure(forArticleID: articleID), .workMissing)
		let flag = try await confirmedMissingAt()
		XCTAssertNotNil(flag)
	}

	func testUnrecognizedPageDoesNotSetMissingFlag() async throws {
		respond(body: Self.unknownHTML)

		await runDownload()

		XCTAssertEqual(AO3ChapterFetcher.shared.lastFetchFailure(forArticleID: articleID), .unrecognizedPage)
		let flag = try await confirmedMissingAt()
		XCTAssertNil(flag)
	}

	func testChallengePageDoesNotSetMissingFlagAndIsNotCached() async throws {
		respond(body: Self.challengeHTML)

		await runDownload()
		XCTAssertEqual(AO3ChapterFetcher.shared.lastFetchFailure(forArticleID: articleID), .challenge)
		let flag = try await confirmedMissingAt()
		XCTAssertNil(flag)
		XCTAssertEqual(requestCount, 1)

		// A cached challenge would be replayed with no new request.
		await runDownload()
		XCTAssertEqual(requestCount, 2)
	}

	func testServiceUnavailablePageDoesNotSetMissingFlagAndIsNotCached() async throws {
		respond(body: Self.unavailableHTML)

		await runDownload()
		XCTAssertEqual(AO3ChapterFetcher.shared.lastFetchFailure(forArticleID: articleID), .serviceUnavailable)
		let flag = try await confirmedMissingAt()
		XCTAssertNil(flag)
		let firstRunRequests = requestCount

		await runDownload()
		XCTAssertGreaterThan(requestCount, firstRunRequests, "the interstitial must not be served from cache")
	}

	// MARK: - Retry

	func testInteractiveFetchRetriesOnce5xx() async {
		respond(statusCode: 502, body: "")

		await runDownload(priority: .interactive)

		XCTAssertEqual(requestCount, 2)
		XCTAssertEqual(AO3ChapterFetcher.shared.lastFetchFailure(forArticleID: articleID), .http(502))
	}

	func testBackgroundFetchDoesNotRetry5xx() async {
		respond(statusCode: 502, body: "")

		await runDownload(priority: .background)

		XCTAssertEqual(requestCount, 1)
		XCTAssertEqual(AO3ChapterFetcher.shared.lastFetchFailure(forArticleID: articleID), .http(502))
	}

	func testNonRetryableStatusIsNotRetried() async {
		respond(statusCode: 403, body: "")

		await runDownload(priority: .interactive)

		XCTAssertEqual(requestCount, 1)
		XCTAssertEqual(AO3ChapterFetcher.shared.lastFetchFailure(forArticleID: articleID), .http(403))
	}

	// MARK: - Failure bookkeeping

	func testFailureMessageMatchesTypedFailure() async {
		respond(statusCode: 502, body: "")

		await runDownload(priority: .background)

		XCTAssertEqual(AO3ChapterFetcher.shared.lastFetchFailureMessage(forArticleID: articleID), "Could not reach AO3 (HTTP 502)")
	}

	// MARK: - Authenticated attempt

	func testRateLimitOnAuthenticatedAttemptDoesNotReachAnonymousTransport() async throws {
		try storeSession()
		respond(statusCode: 429, body: "", headers: ["Retry-After": "30"])

		await runDownload()

		XCTAssertEqual(requestCount, 1, "a 429 must not fall back to an anonymous request")
		guard case .rateLimited = AO3ChapterFetcher.shared.lastFetchFailure(forArticleID: articleID) else {
			XCTFail("expected .rateLimited")
			return
		}
		XCTAssertTrue(AO3SessionStore.isSignedIn, "a rate limit must not end the session")
		let flag = try await confirmedMissingAt()
		XCTAssertNil(flag)
	}

	func testRejectedSessionEndsTheSessionWithoutAnonymousFallback() async throws {
		try storeSession()
		respond(body: Self.registrationHTML)

		await runDownload()

		XCTAssertEqual(AO3ChapterFetcher.shared.lastFetchFailure(forArticleID: articleID), .sessionEnded)
		XCTAssertFalse(AO3SessionStore.isSignedIn)
		XCTAssertEqual(AO3SessionStore.lastEnded?.reason, .rejectedByAO3)
		XCTAssertEqual(requestCount, 1)
	}

	func testMissingSeenByBothAttemptsSetsTheFlag() async throws {
		try storeSession()
		respond(statusCode: 404, body: "")

		await runDownload()

		// Both attempts saw a 404, so the dual-confirmation rule is met.
		XCTAssertEqual(requestCount, 2)
		let flag = try await confirmedMissingAt()
		XCTAssertNotNil(flag)
	}
}
