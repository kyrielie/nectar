//
//  AO3AuthenticatedFetcher.swift
//  AO3Kit
//
//  Nectar AO3 direct-reading support, Workstream 3 ("optional AO3 login").
//
//  A single plain fetch with the stored AO3 session's Cookie header
//  manually attached -- not a second cookie-jar URLSession.
//  Used by every AO3 HTML page-fetch call site that has a stored session:
//  AO3ChapterFetcher.attemptAuthenticated(url:) (work/chapter pages, now
//  tried first when signed in, falling back to Downloader on an
//  authentication-shaped failure), AO3SearchResultsFetcher.fetchRequiringSignIn
//  (search/tag/listing pages), and AO3SeriesNavigator.fetchListingPage
//  (series listing pages).
//
//  Deliberately doesn't reuse Downloader.shared: Downloader's response
//  cache is keyed on URL alone, and mixing authenticated and anonymous
//  responses for the same URL through one cache would risk silently
//  handing back the wrong one on a later request. This uses its own
//  ephemeral, cache-free session instead, mirroring Downloader's own
//  cookie-disabling configuration (see Downloader.swift) so the only
//  cookie ever sent is the one attached by hand here.
//

import Foundation
import RSWeb
import os

public enum AO3AuthenticatedFetcher {

	// Also bypasses Downloader.shared (see header comment) and so was also
	// unlogged. This one is reached only after AO3ChapterFetcher's own
	// isAO3NetworkRequestAllowed gate already let the original (now-gated)
	// request through, so it's not a leak path -- logged for the same
	// "every request to AO3 is visible in one place" reason as the others.
	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nectar", category: "AO3AuthenticatedFetcher")

	/// Not a stored singleton -- this fetcher is used at most once per
	/// AO3ChapterFetcher retry, so there's no benefit to keeping a
	/// long-lived URLSession around between calls, unlike Downloader.
	/// Uses `URLSession(configuration:delegate:delegateQueue:)`, not the
	/// plain `URLSession(configuration:)` this had before, so
	/// `AO3CredentialRedirectGuard` can block a redirect off an AO3
	/// credential host from resending the hand-attached Cookie header
	/// (D6) -- see that type's own header comment.
	private static func makeSession() -> URLSession {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.httpShouldSetCookies = false
		configuration.httpCookieAcceptPolicy = .never
		configuration.httpCookieStorage = nil
		if let userAgentHeaders = UserAgent.headers() {
			configuration.httpAdditionalHeaders = userAgentHeaders
		}
		return URLSession(configuration: configuration, delegate: AO3CredentialRedirectGuard(), delegateQueue: nil)
	}

	/// Whether `url` may be sent the stored AO3 session's Cookie header --
	/// the host/scheme gate half of D6, checked first in `fetch` so a
	/// caller-supplied URL that somehow isn't a credential host never gets
	/// this far. Separate, unit-testable function (no network needed) so
	/// this and `AO3CredentialRedirectGuard`'s later per-redirect check are
	/// provably the same decision.
	public static func shouldSendSession(to url: URL) -> Bool {
		AO3Link.mayReceiveSession(url)
	}

	/// Fetches `url` with the stored AO3 session's Cookie header attached.
	/// Returns `nil` if no session is stored -- callers should treat that
	/// the same as any other unsatisfied `.registrationRequired`, not as an
	/// error.
	public static func fetch(_ url: URL) async throws -> (data: Data, response: HTTPURLResponse)? {
		guard shouldSendSession(to: url) else {
			logger.debug("Refusing to send AO3 session cookie: \(url.absoluteString, privacy: .public) is not a credential host")
			return nil
		}
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
