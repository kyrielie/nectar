//
//  AO3KudosRequestTests.swift
//  AccountTests
//
//  Nectar AO3 direct-reading support, Task 6 ("kudos-on-like") test plan.
//
//  Pure -- no network. Covers makeRequest's header/body shape and every
//  outcome(statusCode:data:) branch against constructed responses, mirroring
//  AO3ChapterFetcherTests' fixture-based approach.
//

import XCTest
@testable import Account

final class AO3KudosRequestTests: XCTestCase {

	// MARK: - makeRequest

	func testMakeRequestGuestShape() {
		let request = AO3KudosRequest.makeRequest(workID: "12345", csrfToken: "the-token", cookieHeaderValue: nil)

		XCTAssertEqual(request.httpMethod, "POST")
		XCTAssertEqual(request.url, URL(string: "https://archiveofourown.org/kudos.js"))
		XCTAssertEqual(request.value(forHTTPHeaderField: "x-csrf-token"), "the-token")
		XCTAssertEqual(request.value(forHTTPHeaderField: "x-requested-with"), "XMLHttpRequest")
		XCTAssertEqual(request.value(forHTTPHeaderField: "referer"), "https://archiveofourown.org/works/12345")
		XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))

		let body = try? XCTUnwrap(request.httpBody)
		let bodyString = String(data: body ?? Data(), encoding: .utf8) ?? ""
		XCTAssertTrue(bodyString.contains("authenticity_token=the-token"))
		XCTAssertTrue(bodyString.contains("kudo%5Bcommentable_id%5D=12345"))
		XCTAssertTrue(bodyString.contains("kudo%5Bcommentable_type%5D=Work"))
	}

	func testMakeRequestAuthenticatedShapeIncludesCookie() {
		let request = AO3KudosRequest.makeRequest(workID: "12345", csrfToken: "the-token", cookieHeaderValue: "_otwarchive_session=abc")
		XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "_otwarchive_session=abc")
	}

	// MARK: - outcome(statusCode:data:)

	func testOutcomeSuccess() {
		XCTAssertEqual(AO3KudosRequest.outcome(statusCode: 201, data: nil), .success)
	}

	func testOutcomeRateLimited() {
		XCTAssertEqual(AO3KudosRequest.outcome(statusCode: 429, data: nil), .rateLimited)
	}

	func testOutcomeAlreadyKudosedByUserID() {
		let json = #"{"errors":{"user_id":["already left kudos"]}}"#
		XCTAssertEqual(AO3KudosRequest.outcome(statusCode: 422, data: json.data(using: .utf8)), .alreadyKudosed)
	}

	func testOutcomeAlreadyKudosedByIPAddress() {
		let json = #"{"errors":{"ip_address":["already left kudos"]}}"#
		XCTAssertEqual(AO3KudosRequest.outcome(statusCode: 422, data: json.data(using: .utf8)), .alreadyKudosed)
	}

	func testOutcomeAuthError() {
		let json = #"{"errors":{"auth_error":["invalid token"]}}"#
		XCTAssertEqual(AO3KudosRequest.outcome(statusCode: 422, data: json.data(using: .utf8)), .authError)
	}

	func testOutcomeInvalidWork() {
		let json = #"{"errors":{"no_commentable":["work not found"]}}"#
		XCTAssertEqual(AO3KudosRequest.outcome(statusCode: 422, data: json.data(using: .utf8)), .invalidWork)
	}

	func testOutcomeUnrecognized422Shape() {
		let json = #"{"errors":{"something_else":["huh"]}}"#
		guard case .otherFailure = AO3KudosRequest.outcome(statusCode: 422, data: json.data(using: .utf8)) else {
			XCTFail("Expected .otherFailure")
			return
		}
	}

	func testOutcomeMissingBodyOn422() {
		guard case .otherFailure = AO3KudosRequest.outcome(statusCode: 422, data: nil) else {
			XCTFail("Expected .otherFailure")
			return
		}
	}

	func testOutcomeUnexpectedStatusCode() {
		guard case .otherFailure = AO3KudosRequest.outcome(statusCode: 500, data: nil) else {
			XCTFail("Expected .otherFailure")
			return
		}
	}
}
