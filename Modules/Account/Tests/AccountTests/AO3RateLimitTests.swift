//
//  AO3RateLimitTests.swift
//  AccountTests
//

import XCTest
import RSWeb
import AO3Kit
@testable import Account

@MainActor
final class AO3RateLimitTests: XCTestCase {

	override func setUp() async throws {
		for host in AO3Link.recognizedHosts {
			Downloader.shared.clearCooldown(forHost: host)
		}
	}

	override func tearDown() async throws {
		for host in AO3Link.recognizedHosts {
			Downloader.shared.clearCooldown(forHost: host)
		}
	}

	private func response(retryAfter: String, url: URL) -> HTTPURLResponse {
		HTTPURLResponse(url: url, statusCode: 429, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": retryAfter])!
	}

	func testNoCooldownReturnsNil() {
		XCTAssertNil(AO3RateLimit.activeResumeDate())
	}

	func testReturnsLatestResumeDateAcrossHosts() throws {
		let canonical = try XCTUnwrap(URL(string: "https://archiveofourown.org/works/1"))
		let other = try XCTUnwrap(AO3Link.recognizedHosts.first { $0 != AO3Link.canonicalHost && !$0.contains(where: \.isNumber) })
		let otherURL = try XCTUnwrap(URL(string: "https://\(other)/works/1"))

		Downloader.shared.recordRateLimit(url: canonical, response: response(retryAfter: "30", url: canonical))
		Downloader.shared.recordRateLimit(url: otherURL, response: response(retryAfter: "120", url: otherURL))

		let canonicalResume = try XCTUnwrap(Downloader.shared.cooldownResumeDate(forHost: AO3Link.canonicalHost))
		let otherResume = try XCTUnwrap(Downloader.shared.cooldownResumeDate(forHost: other))
		XCTAssertGreaterThan(otherResume, canonicalResume)
		XCTAssertEqual(AO3RateLimit.activeResumeDate(), otherResume)
	}

	func testClearingCooldownClearsActiveDate() throws {
		let url = try XCTUnwrap(URL(string: "https://archiveofourown.org/works/1"))
		Downloader.shared.recordRateLimit(url: url, response: response(retryAfter: "60", url: url))
		XCTAssertNotNil(AO3RateLimit.activeResumeDate())

		Downloader.shared.clearCooldown(forHost: AO3Link.canonicalHost)

		XCTAssertNil(AO3RateLimit.activeResumeDate())
	}
}
