//
//  DownloaderCooldownTests.swift
//  RSWebTests
//
//  Downloader.shared is a process-wide singleton whose cooldown state is
//  keyed by host, so every test uses its own unique host. Responses come
//  from TestingURLProtocol, which Downloader installs under unit tests.
//

import XCTest
@testable import RSWeb

@MainActor final class DownloaderCooldownTests: XCTestCase {

	override func setUp() async throws {
		TestingURLProtocol.reset()
	}

	override func tearDown() async throws {
		TestingURLProtocol.reset()
	}

	private func makeHost() -> String {
		"h\(UUID().uuidString.lowercased()).example.test"
	}

	private func make429(host: String, retryAfter: String?) -> URL {
		let headers = retryAfter.map { ["Retry-After": $0] } ?? [:]
		TestingURLProtocol.responses[host] = TestingURLProtocol.Response(statusCode: 429, data: nil, headers: headers)
		return URL(string: "https://\(host)/page")!
	}

	private func assertResume(_ date: Date?, about seconds: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
		guard let date else {
			XCTFail("expected an active cooldown", file: file, line: line)
			return
		}
		XCTAssertEqual(date.timeIntervalSinceNow, seconds, accuracy: 5, file: file, line: line)
	}

	func testNoCooldownForUnknownHost() {
		XCTAssertNil(Downloader.shared.cooldownResumeDate(forHost: makeHost()))
	}

	func testSecondsRetryAfterSetsCooldown() async throws {
		let host = makeHost()
		let url = make429(host: host, retryAfter: "120")

		_ = try await Downloader.shared.download(url)

		assertResume(Downloader.shared.cooldownResumeDate(forHost: host), about: 120)
	}

	func testCooldownLookupIsCaseInsensitive() async throws {
		let host = makeHost()
		let url = make429(host: host, retryAfter: "120")

		_ = try await Downloader.shared.download(url)

		assertResume(Downloader.shared.cooldownResumeDate(forHost: host.uppercased()), about: 120)
	}

	func testHTTPDateRetryAfterSetsCooldown() async throws {
		let host = makeHost()
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
		let url = make429(host: host, retryAfter: formatter.string(from: Date().addingTimeInterval(300)))

		_ = try await Downloader.shared.download(url)

		assertResume(Downloader.shared.cooldownResumeDate(forHost: host), about: 300)
	}

	func testHugeRetryAfterIsClampedToOneHour() async throws {
		let host = makeHost()
		let url = make429(host: host, retryAfter: "999999")

		_ = try await Downloader.shared.download(url)

		assertResume(Downloader.shared.cooldownResumeDate(forHost: host), about: 3600)
	}

	func testMissingOrGarbageRetryAfterDefaultsToTenMinutes() async throws {
		let missingHost = makeHost()
		_ = try await Downloader.shared.download(make429(host: missingHost, retryAfter: nil))
		assertResume(Downloader.shared.cooldownResumeDate(forHost: missingHost), about: 600)

		let garbageHost = makeHost()
		_ = try await Downloader.shared.download(make429(host: garbageHost, retryAfter: "soon"))
		assertResume(Downloader.shared.cooldownResumeDate(forHost: garbageHost), about: 600)
	}

	func testActiveCooldownShortCircuitsFurtherDownloads() async throws {
		let host = makeHost()
		let url = make429(host: host, retryAfter: "120")
		_ = try await Downloader.shared.download(url)
		let requestsAfterFirst = TestingURLProtocol.requestedURLs.filter { $0.host() == host }.count
		XCTAssertEqual(requestsAfterFirst, 1)

		let second = try await Downloader.shared.download(URL(string: "https://\(host)/other")!)

		XCTAssertEqual((second.response as? HTTPURLResponse)?.statusCode, 429)
		XCTAssertEqual(TestingURLProtocol.requestedURLs.filter { $0.host() == host }.count, requestsAfterFirst)
	}

	func testRecordRateLimitUsesRetryAfterHeader() throws {
		let host = makeHost()
		let url = URL(string: "https://\(host)/page")!
		let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "45"]))

		Downloader.shared.recordRateLimit(url: url, response: response)

		assertResume(Downloader.shared.cooldownResumeDate(forHost: host), about: 45)
	}

	func testClearCooldownEndsItAndAnnouncesTheChange() throws {
		let host = makeHost()
		let url = URL(string: "https://\(host)/page")!
		Downloader.shared.recordRateLimit(url: url, response: nil)
		XCTAssertNotNil(Downloader.shared.cooldownResumeDate(forHost: host))

		let cleared = expectation(forNotification: .hostRateLimitDidChange, object: nil) { note in
			note.userInfo?[HostRateLimitUserInfoKey.host] as? String == host
				&& note.userInfo?[HostRateLimitUserInfoKey.resumeDate] == nil
		}
		Downloader.shared.clearCooldown(forHost: host.uppercased())

		XCTAssertNil(Downloader.shared.cooldownResumeDate(forHost: host))
		wait(for: [cleared], timeout: 1.0)
	}

	func testRecordRateLimitWithoutResponseDefaultsToTenMinutes() {
		let host = makeHost()

		Downloader.shared.recordRateLimit(url: URL(string: "https://\(host)/page")!, response: nil)

		assertResume(Downloader.shared.cooldownResumeDate(forHost: host), about: 600)
	}

	func testRecordingPostsNotificationWithHostAndResumeDate() throws {
		let host = makeHost()
		let posted = expectation(forNotification: .hostRateLimitDidChange, object: nil) { note in
			note.userInfo?[HostRateLimitUserInfoKey.host] as? String == host
				&& note.userInfo?[HostRateLimitUserInfoKey.resumeDate] is Date
		}

		Downloader.shared.recordRateLimit(url: URL(string: "https://\(host)/page")!, response: nil)

		wait(for: [posted], timeout: 1.0)
	}

	func testExpiredCooldownIsPurgedAndAnnounced() async throws {
		let host = makeHost()
		let url = URL(string: "https://\(host)/page")!
		let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "1"]))
		Downloader.shared.recordRateLimit(url: url, response: response)
		XCTAssertNotNil(Downloader.shared.cooldownResumeDate(forHost: host))

		let cleared = expectation(forNotification: .hostRateLimitDidChange, object: nil) { note in
			note.userInfo?[HostRateLimitUserInfoKey.host] as? String == host
				&& note.userInfo?[HostRateLimitUserInfoKey.resumeDate] == nil
		}
		try await Task.sleep(for: .seconds(1.2))

		XCTAssertNil(Downloader.shared.cooldownResumeDate(forHost: host))
		await fulfillment(of: [cleared], timeout: 1.0)
	}
}
