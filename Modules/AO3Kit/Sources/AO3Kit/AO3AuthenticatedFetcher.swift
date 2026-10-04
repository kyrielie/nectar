//
//  AO3AuthenticatedFetcher.swift
//  AO3Kit
//
//  Nectar AO3 direct-reading support, Workstream 3 ("optional AO3 login").
//
//  A single plain fetch with the stored AO3 session's Cookie header
//  manually attached -- not a second cookie-jar URLSession.
//  Used by every AO3 HTML page-fetch call site that has a stored session:
//  AO3ChapterFetcher.download (work/chapter pages, tried first when signed
//  in, falling back to Downloader on some failures), AO3SearchResultsFetcher.fetchRequiringSignIn
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
//  Shares Downloader's per-host rate-limit cooldown (see AO3RateLimit): a
//  request made while a cooldown is active is not sent, and a 429 received
//  here starts the same cooldown Downloader would have started. Requests go
//  through one long-lived session capped at one connection per host, so
//  they queue instead of fanning out.
//

import Foundation
import RSCore
import RSWeb
import os

/// What an authenticated fetch produced, with the "no usable session" and
/// "rate limited" cases kept distinct from a real HTTP response so callers
/// cannot confuse a 429 with an ordinary failure and fall back to an
/// anonymous request.
public enum AO3AuthenticatedFetchResult {
	/// No session is stored, or `url` is not a host that may receive it.
	case noSession
	/// A cooldown is active (from an earlier 429 on any AO3 transport) or
	/// this request just received a 429. No anonymous fallback should
	/// follow.
	case rateLimited(until: Date)
	case response(Data, HTTPURLResponse)
}

public enum AO3AuthenticatedFetcher {

	// Also bypasses Downloader.shared (see header comment) and so was also
	// unlogged. This one is reached only after AO3ChapterFetcher's own
	// isAO3NetworkRequestAllowed gate already let the original (now-gated)
	// request through, so it's not a leak path -- logged for the same
	// "every request to AO3 is visible in one place" reason as the others.
	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nectar", category: "AO3AuthenticatedFetcher")

	/// One long-lived session: ephemeral, cache-free, no cookie jar, and one
	/// connection per host so authenticated requests queue behind each other
	/// the way Downloader's do. Uses
	/// `URLSession(configuration:delegate:delegateQueue:)` so
	/// `AO3CredentialRedirectGuard` can block a redirect off an AO3
	/// credential host from resending the hand-attached Cookie header (D6)
	/// -- see that type's own header comment. Under unit tests and the
	/// seeded UI-test mode it routes through `TestingURLProtocol`, exactly
	/// as Downloader does.
	private static let session: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.httpShouldSetCookies = false
		configuration.httpCookieAcceptPolicy = .never
		configuration.httpCookieStorage = nil
		configuration.httpMaximumConnectionsPerHost = 1
		if let userAgentHeaders = UserAgent.headers() {
			configuration.httpAdditionalHeaders = userAgentHeaders
		}
		if Platform.isRunningUnitTests || Platform.isUITestingWithSeedDemoData {
			configuration.protocolClasses = [TestingURLProtocol.self]
		}
		return URLSession(configuration: configuration, delegate: AO3CredentialRedirectGuard(), delegateQueue: nil)
	}()

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
	/// `.noSession` means no session is stored or the host may not receive
	/// it -- callers should treat that the same as any other unsatisfied
	/// `.registrationRequired`, not as an error. `.rateLimited` means do
	/// not retry, and do not fall back to an anonymous request either.
	public static func fetch(_ url: URL) async throws -> AO3AuthenticatedFetchResult {
		guard shouldSendSession(to: url) else {
			logger.debug("Refusing to send AO3 session cookie: \(url.absoluteString, privacy: .public) is not a credential host")
			return .noSession
		}
		guard let cookieHeaderValue = AO3SessionStore.cookieHeaderValue else {
			return .noSession
		}

		if let resumeDate = await AO3RateLimit.resumeDate(for: url) {
			logger.info("Not requesting AO3: \(url.absoluteString, privacy: .public) is rate-limited until \(resumeDate, privacy: .public)")
			return .rateLimited(until: resumeDate)
		}

		var request = URLRequest(url: url)
		request.setValue(cookieHeaderValue, forHTTPHeaderField: "Cookie")

		logger.debug("Requesting AO3: GET \(url.absoluteString, privacy: .public) (authenticated)")

		let (data, response) = try await session.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw URLError(.badServerResponse)
		}

		if httpResponse.statusCode == HTTPResponseCode.tooManyRequests {
			let resumeDate = await AO3RateLimit.record(url: url, response: httpResponse) ?? Date()
			return .rateLimited(until: resumeDate)
		}
		return .response(data, httpResponse)
	}
}
