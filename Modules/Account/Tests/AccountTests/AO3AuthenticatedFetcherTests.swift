//
//  AO3AuthenticatedFetcherTests.swift
//  AccountTests
//
//  AO3AuthenticatedFetcher shares Downloader's per-host cooldown. Responses
//  come from TestingURLProtocol, which the fetcher's session installs under
//  unit tests. The cases that need a stored session skip when the Keychain
//  refuses the write (an unhosted test bundle can), since they cannot run
//  without one.
//
import XCTest
import RSWeb
import AO3Kit
@testable import Account

@MainActor final class AO3AuthenticatedFetcherTests: XCTestCase {

	private static let host = "archiveofourown.org"
	private static let workURL = URL(string: "https://archiveofourown.org/works/424242")!

	override func setUp() async throws {
		TestingURLProtocol.reset()
		Downloader.shared.clearCooldown(forHost: Self.host)
		AO3SessionStore.clearSession()
	}

	override func tearDown() async throws {
		TestingURLProtocol.reset()
		Downloader.shared.clearCooldown(forHost: Self.host)
		AO3SessionStore.clearSession()
	}

	private func storeSession() throws {
		AO3SessionStore.saveSession(cookieHeaderValue: "_otwarchive_session=test")
		try XCTSkipUnless(AO3SessionStore.isSignedIn, "Keychain unavailable in this test environment")
	}

	func testNoSessionStoredReturnsNoSessionWithoutARequest() async throws {
		let result = try await AO3AuthenticatedFetcher.fetch(Self.workURL)

		guard case .noSession = result else {
			XCTFail("expected .noSession, got \(result)")
			return
		}
		XCTAssertTrue(TestingURLProtocol.requestedURLs.isEmpty)
	}

	func testNonCredentialHostReturnsNoSessionWithoutARequest() async throws {
		try storeSession()

		let result = try await AO3AuthenticatedFetcher.fetch(URL(string: "https://evil.example/works/1")!)

		guard case .noSession = result else {
			XCTFail("expected .noSession, got \(result)")
			return
		}
		XCTAssertTrue(TestingURLProtocol.requestedURLs.isEmpty)
	}

	func testSuccessfulResponseIsReturnedAsIs() async throws {
		try storeSession()
		TestingURLProtocol.responses["/works/424242"] = TestingURLProtocol.Response(statusCode: 200, data: Data("<html>ok</html>".utf8))

		let result = try await AO3AuthenticatedFetcher.fetch(Self.workURL)

		guard case .response(let data, let response) = result else {
			XCTFail("expected .response, got \(result)")
			return
		}
		XCTAssertEqual(response.statusCode, 200)
		XCTAssertEqual(String(data: data, encoding: .utf8), "<html>ok</html>")
	}

	func test429StartsTheSharedCooldownAndIsReturnedAsRateLimited() async throws {
		try storeSession()
		TestingURLProtocol.responses["/works/424242"] = TestingURLProtocol.Response(statusCode: 429, headers: ["Retry-After": "30"])

		let result = try await AO3AuthenticatedFetcher.fetch(Self.workURL)

		guard case .rateLimited(let until) = result else {
			XCTFail("expected .rateLimited, got \(result)")
			return
		}
		XCTAssertEqual(until.timeIntervalSinceNow, 30, accuracy: 5)
		let sharedResume = try XCTUnwrap(Downloader.shared.cooldownResumeDate(forHost: Self.host))
		XCTAssertEqual(sharedResume.timeIntervalSinceNow, 30, accuracy: 5)
	}

	func testActiveCooldownSkipsTheRequest() async throws {
		try storeSession()
		Downloader.shared.recordRateLimit(url: Self.workURL, response: nil)

		let result = try await AO3AuthenticatedFetcher.fetch(Self.workURL)

		guard case .rateLimited = result else {
			XCTFail("expected .rateLimited, got \(result)")
			return
		}
		XCTAssertTrue(TestingURLProtocol.requestedURLs.isEmpty)
	}

	func testCooldownFromADownloaderRequestBlocksTheAuthenticatedPath() async throws {
		try storeSession()
		TestingURLProtocol.responses["/works/424242"] = TestingURLProtocol.Response(statusCode: 429, headers: ["Retry-After": "20"])
		_ = try await Downloader.shared.download(Self.workURL)
		TestingURLProtocol.requestedURLs = []

		let result = try await AO3AuthenticatedFetcher.fetch(Self.workURL)

		guard case .rateLimited = result else {
			XCTFail("expected .rateLimited, got \(result)")
			return
		}
		XCTAssertTrue(TestingURLProtocol.requestedURLs.isEmpty)
	}
}
