//
//  AO3AuthenticatedFetcher.swift
//  Account
//
//  Nectar AO3 direct-reading support, Workstream 3 ("optional AO3 login").
//
//  A single plain fetch with the stored AO3 session's Cookie header
//  manually attached -- not a second cookie-jar URLSession.
//  Used exactly once, by AO3ChapterFetcher.retryAuthenticated(url:), on
//  AO3ChapterExtractionOutcome.registrationRequired only.
//
//  Deliberately doesn't reuse Downloader.shared: Downloader's response
//  cache is keyed on URL alone, and the anonymous fetch that produced
//  .registrationRequired for this exact URL will already have cached that
//  gate-page response by the time a retry is attempted -- routing the
//  authenticated retry through Downloader would silently hand back that
//  stale, unauthenticated response instead of ever sending the Cookie
//  header. This uses its own ephemeral, cache-free session instead, mirroring
//  Downloader's own cookie-disabling configuration (see Downloader.swift) so
//  the only cookie ever sent is the one attached by hand here.
//

import Foundation
import RSWeb
import os

enum AO3AuthenticatedFetcher {

	// Also bypasses Downloader.shared (see header comment) and so was also
	// unlogged. This one is reached only after AO3ChapterFetcher's own
	// isAO3NetworkRequestAllowed gate already let the original (now-gated)
	// request through, so it's not a leak path -- logged for the same
	// "every request to AO3 is visible in one place" reason as the others.
	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nectar", category: "AO3AuthenticatedFetcher")

	/// Not a stored singleton -- this fetcher is used at most once per
	/// AO3ChapterFetcher retry, so there's no benefit to keeping a
	/// long-lived URLSession around between calls, unlike Downloader.
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

	/// Fetches `url` with the stored AO3 session's Cookie header attached.
	/// Returns `nil` if no session is stored -- callers should treat that
	/// the same as any other unsatisfied `.registrationRequired`, not as an
	/// error.
	static func fetch(_ url: URL) async throws -> (data: Data, response: HTTPURLResponse)? {
		guard let cookieHeaderValue = AO3SessionStore.cookieHeaderValue else {
			return nil
		}

		var request = URLRequest(url: url)
		request.setValue(cookieHeaderValue, forHTTPHeaderField: "Cookie")

		logger.debug("Requesting AO3: GET \(url.absoluteString, privacy: .public) (authenticated retry)")

		let session = makeSession()
		defer { session.invalidateAndCancel() }

		let (data, response) = try await session.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw URLError(.badServerResponse)
		}
		return (data, httpResponse)
	}
}
