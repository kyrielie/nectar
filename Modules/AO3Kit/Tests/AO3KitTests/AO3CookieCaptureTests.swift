//
//  AO3CookieCaptureTests.swift
//  AO3Kit
//

import Foundation
import Testing
@testable import AO3Kit

@Suite struct AO3CookieCaptureTests {

	private func cookie(_ name: String, _ value: String, domain: String) throws -> HTTPCookie {
		try #require(HTTPCookie(properties: [
			.name: name,
			.value: value,
			.domain: domain,
			.path: "/"
		]))
	}

	@Test func joinsAO3CookiesInOrder() throws {
		let cookies = [
			try cookie("_otwarchive_session", "abc", domain: ".archiveofourown.org"),
			try cookie("user_credentials", "1", domain: "archiveofourown.org")
		]
		#expect(AO3CookieCapture.headerValue(from: cookies) == "_otwarchive_session=abc; user_credentials=1")
	}

	@Test func excludesNonAO3Cookies() throws {
		let cookies = [
			try cookie("tracker", "x", domain: ".example.com"),
			try cookie("lookalike", "y", domain: "archiveofourown.org.evil.example"),
			try cookie("_otwarchive_session", "abc", domain: ".archiveofourown.org")
		]
		#expect(AO3CookieCapture.headerValue(from: cookies) == "_otwarchive_session=abc")
	}

	@Test func nilWhenNoAO3Cookies() throws {
		#expect(AO3CookieCapture.headerValue(from: []) == nil)
		#expect(AO3CookieCapture.headerValue(from: [try cookie("tracker", "x", domain: ".example.com")]) == nil)
	}

	@Test func urlConstants() {
		#expect(AO3Link.loginURL.absoluteString == "https://archiveofourown.org/users/login")
		#expect(AO3Link.worksURL.absoluteString == "https://archiveofourown.org/works")
		#expect(AO3Link.isAO3Host(AO3Link.loginURL))
	}
}
