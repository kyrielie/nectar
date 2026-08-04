//
//  AO3KudosFetcher.swift
//  Account
//
//  Nectar AO3 direct-reading support, Task 6 ("kudos-on-like") -- see
//  nectar-ao3-features-plan-FINAL.md.
//
//  The actual networking half of the kudos POST -- AO3KudosRequest (RSParser
//  -- no, Account, pure) builds the request and parses the response; this
//  just sends it. Same ephemeral, cache-free, cookie-jar-free URLSession
//  shape as AO3AuthenticatedFetcher, and for the same reason: this needs
//  full manual control over which Cookie header (if any) goes out, and
//  Downloader.shared's cache is keyed on URL alone, which would be wrong
//  for a POST endpoint anyway.
//

import Foundation
import RSWeb

enum AO3KudosFetcher {

	private static func makeSession() -> URLSession {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.httpShouldSetCookies = false
		configuration.httpCookieAcceptPolicy = .never
		configuration.httpCookieStorage = nil
		if let userAgentHeaders = UserAgent.headers() {
			configuration.httpAdditionalHeaders = userAgentHeaders
		}
		return URLSession(configuration: configuration)
	}

	/// Posts a kudos for `workID` using `csrfToken`, attaching
	/// `cookieHeaderValue` (nil for a guest attempt) -- see
	/// AO3KudosRequest.makeRequest. Throws on a pre-response network
	/// failure; a non-2xx/non-recognized HTTP response is represented in
	/// the returned AO3KudosOutcome instead, not as a thrown error.
	static func leaveKudos(workID: String, csrfToken: String, cookieHeaderValue: String?) async throws -> AO3KudosOutcome {
		let request = AO3KudosRequest.makeRequest(workID: workID, csrfToken: csrfToken, cookieHeaderValue: cookieHeaderValue)

		let session = makeSession()
		defer { session.invalidateAndCancel() }

		let (data, response) = try await session.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw URLError(.badServerResponse)
		}
		return AO3KudosRequest.outcome(statusCode: httpResponse.statusCode, data: data)
	}
}
