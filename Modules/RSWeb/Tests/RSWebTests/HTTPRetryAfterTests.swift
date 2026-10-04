//
//  HTTPRetryAfterTests.swift
//  RSWebTests
//

import XCTest
@testable import RSWeb

final class HTTPRetryAfterTests: XCTestCase {

	// 1700000000 is 2023-11-14 22:13:20 UTC, a Tuesday.
	private let now = Date(timeIntervalSince1970: 1_700_000_000)

	func testNumericSeconds() {
		XCTAssertEqual(HTTPRetryAfter.seconds(from: "120", now: now), 120)
		XCTAssertEqual(HTTPRetryAfter.seconds(from: " 7 ", now: now), 7)
	}

	func testZeroIsNotPositive() {
		XCTAssertNil(HTTPRetryAfter.seconds(from: "0", now: now))
	}

	func testNegativeAndNonDigitNumbersAreRejected() {
		XCTAssertNil(HTTPRetryAfter.seconds(from: "-5", now: now))
		XCTAssertNil(HTTPRetryAfter.seconds(from: "1e3", now: now))
		XCTAssertNil(HTTPRetryAfter.seconds(from: "inf", now: now))
		XCTAssertNil(HTTPRetryAfter.seconds(from: "nan", now: now))
		XCTAssertNil(HTTPRetryAfter.seconds(from: "1.5", now: now))
	}

	func testHTTPDateInTheFuture() {
		XCTAssertEqual(HTTPRetryAfter.seconds(from: "Tue, 14 Nov 2023 22:15:20 GMT", now: now), 120)
	}

	func testHTTPDateInThePastIsNil() {
		XCTAssertNil(HTTPRetryAfter.seconds(from: "Tue, 14 Nov 2023 22:00:00 GMT", now: now))
	}

	func testGarbageAndEmptyAreNil() {
		XCTAssertNil(HTTPRetryAfter.seconds(from: "", now: now))
		XCTAssertNil(HTTPRetryAfter.seconds(from: "soon", now: now))
		XCTAssertNil(HTTPRetryAfter.seconds(from: "Tuesday", now: now))
	}
}
