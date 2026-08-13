//
//  AO3KudosFetcher.swift
//  Account
//
//  Nectar AO3 direct-reading support, Task 6 ("kudos-on-like").
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
import os

enum AO3KudosFetcher {

	// Doesn't go through Downloader.shared (see this file's header comment for
	// why), so this is the only place that request gets logged -- kept in the
	// same "Requesting AO3:" format as AO3KudosManager's CSRF fetch and
	// Downloader's own "Downloader: downloading" lines so every actual
	// outbound request to archiveofourown.org shows up under one greppable
	// pattern in the console, regardless of which code path fired it.
	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nectar", category: "AO3KudosFetcher")

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

		logger.debug("Requesting AO3: POST \(AO3KudosRequest.url.absoluteString, privacy: .public) for workID=\(workID, privacy: .public) authenticated=\(cookieHeaderValue != nil, privacy: .public)")

		let session = makeSession()
		defer { session.invalidateAndCancel() }

		let (data, response) = try await session.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw URLError(.badServerResponse)
		}
		return AO3KudosRequest.outcome(statusCode: httpResponse.statusCode, data: data)
	}
}
