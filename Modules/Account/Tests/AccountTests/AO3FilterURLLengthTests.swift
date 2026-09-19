//
//  AO3FilterURLLengthTests.swift
//  AccountTests
//
//  Boundary coverage for AO3FilterURLLength's three tiers: under the
//  limit nothing happens, exactly at it only the fallback-page check
//  applies, over it the add-feed warning applies too.
//

import XCTest
@testable import Account

final class AO3FilterURLLengthTests: XCTestCase {

	private let filteredPrefix = "https://archiveofourown.org/works?work_search%5Bquery%5D="
	private let unfilteredPrefix = "https://archiveofourown.org/works?query="

	/// A URL whose `absoluteString` is exactly `length` bytes long.
	private func url(prefix: String, length: Int) -> URL {
		let padding = length - prefix.utf8.count
		precondition(padding >= 0)
		let url = URL(string: prefix + String(repeating: "a", count: padding))!
		precondition(url.absoluteString.utf8.count == length)
		return url
	}

	func testLimitIs4096() {
		XCTAssertEqual(AO3FilterURLLength.limit, 4096)
	}

	func testFilteredURLUnderLimitIsNeverChecked() {
		let url = url(prefix: filteredPrefix, length: 4095)
		XCTAssertFalse(AO3FilterURLLength.exceedsLimit(url))
		XCTAssertFalse(AO3FilterURLLength.needsFallbackCheck(url))
	}

	func testFilteredURLExactlyAtLimitIsCheckedButNotWarned() {
		let url = url(prefix: filteredPrefix, length: 4096)
		XCTAssertFalse(AO3FilterURLLength.exceedsLimit(url))
		XCTAssertTrue(AO3FilterURLLength.needsFallbackCheck(url))
	}

	func testFilteredURLOverLimitIsWarnedAndChecked() {
		let url = url(prefix: filteredPrefix, length: 4097)
		XCTAssertTrue(AO3FilterURLLength.exceedsLimit(url))
		XCTAssertTrue(AO3FilterURLLength.needsFallbackCheck(url))
	}

	func testUnfilteredURLIsNeverFlaggedAtAnyLength() {
		for length in [4095, 4096, 4097, 9000] {
			let url = url(prefix: unfilteredPrefix, length: length)
			XCTAssertFalse(AO3FilterURLLength.exceedsLimit(url), "length \(length)")
			XCTAssertFalse(AO3FilterURLLength.needsFallbackCheck(url), "length \(length)")
		}
	}

	/// A later page appends `&page=N`, which can carry a stored page-1
	/// URL that is under the limit over it.
	func testAppendedPageParameterCanCrossTheLimit() {
		let pageOne = url(prefix: filteredPrefix, length: 4090)
		XCTAssertFalse(AO3FilterURLLength.needsFallbackCheck(pageOne))

		var components = URLComponents(url: pageOne, resolvingAgainstBaseURL: false)!
		components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "page", value: "2")]
		let pageTwo = components.url!
		XCTAssertGreaterThanOrEqual(pageTwo.absoluteString.utf8.count, AO3FilterURLLength.limit)
		XCTAssertTrue(AO3FilterURLLength.needsFallbackCheck(pageTwo))
	}
}
