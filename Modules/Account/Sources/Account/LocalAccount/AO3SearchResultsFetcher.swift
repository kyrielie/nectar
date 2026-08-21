//
//  AO3SearchResultsFetcher.swift
//  Account
//
//  Nectar AO3 direct-reading support, Task 9 checkpoint 2's fetch path
//  ("Feed routing & pagination"): retry/backoff + Cloudflare-challenge
//  detection, wrapping RSParser.AO3SearchResultsExtractor.
//
//  Fetches through Downloader.shared (RSWeb), the same one-shot path
//  AO3ChapterFetcher.download(workID:...) uses, so this inherits that
//  Downloader's existing per-host 429/Retry-After cooldown for free --
//  deliberately not reimplemented here.
//

import Foundation
import os
import RSParser
import RSWeb

/// Outcome of one page fetch + extraction attempt, mirroring
/// `AO3SearchResultsOutcome` (RSParser) plus the fetch-level states that
/// outcome has no way to represent, since it only ever sees HTML AO3 itself
/// already sent:
///
/// - `.rateLimited`: a genuine HTTP 429. Not retried here -- by the time
///   this returns, `Downloader.shared` has already recorded its own
///   per-host cooldown (see `Downloader.retryAfterMessages`), so retrying
///   immediately would just collide with that.
/// - `.cloudflareChallenge`: a Cloudflare block/challenge page, which can
///   arrive as a 200, 403, or overlapping a 429 -- sniffed from the body
///   independently of status code, since it needs its own detection
///   separate from AO3's own 429 handling.
public enum AO3SearchResultsFetchOutcome {
	case success([ParsedItem], hasNextPage: Bool, pageTitle: String?)
	case noResults(pageTitle: String?)
	case registrationRequired
	case rateLimited
	case cloudflareChallenge(challengedURL: URL)
	/// Distinct from `.registrationRequired`: this listing type
	/// (subscriptions, marked-for-later) is always-yours and
	/// always-private, so an anonymous fetch of it is expected to be
	/// gated -- but there is no stored AO3 session to retry with
	/// (`AO3SessionStore.isSignedIn == false`). Surfaced separately so a
	/// caller can show "sign in to AO3 in Settings" rather than the
	/// generic "this work requires registration" copy
	/// `.registrationRequired` implies, which doesn't fit a feed the
	/// person is trying to add for themselves. See
	/// `fetchRequiringSignIn(url:feedURL:)`.
	case notSignedIn
}

public enum AO3SearchResultsFetchError: Error {
	/// A 5xx status or timeout that kept recurring past `maxAttempts`, or a
	/// response with no usable body after every attempt.
	case exhaustedRetries
}

public enum AO3SearchResultsFetcher {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AO3SearchResultsFetcher")

	/// Bounded retry budget for a single page fetch. Covers both 5xx
	/// responses and request timeouts under one counter/backoff -- unlike
	/// `AmbrosiaSQLiteTransferFetcher`'s per-page retry loop (which has a
	/// separate "consecutive-timeout giveup cap"), this is a single
	/// request, not a many-page walk, so one bounded loop covering both
	/// failure kinds is enough: either failure kind still stops retrying
	/// after the same fixed number of attempts rather than continuing
	/// forever.
	private static let maxAttempts = 3
	private static let retryBackoffBaseSeconds: TimeInterval = 2
	private static let maxBackoffSeconds: TimeInterval = 30

	/// Fetches `url` (an AO3 search-results page) with retry/backoff for
	/// 5xx statuses and timeouts, then hands the body to
	/// `AO3SearchResultsExtractor`. A genuine 429 or a detected Cloudflare
	/// challenge returns immediately, unretried (see
	/// `AO3SearchResultsFetchOutcome`'s own doc comment for why).
	///
	/// If AO3ChallengeSessionStore holds a still-fresh clearance cookie
	/// (captured via AO3ChallengeSolverViewController, iOS target), it's
	/// attached by hand as a Cookie header -- the same manual-header
	/// pattern AO3AuthenticatedFetcher uses for the account-gated case,
	/// except this one deliberately does go through Downloader.shared
	/// (see the new URLRequest overload's doc comment for why that's safe
	/// here). If the request still comes back challenged despite carrying
	/// what this store considered a fresh cookie, the cookie is stale
	/// (expired early / revoked) and is cleared so the next attempt
	/// doesn't keep sending it.
	public static func fetch(url: URL, feedURL: String) async throws -> AO3SearchResultsFetchOutcome {
		let clearanceCookieHeaderValue = AO3ChallengeSessionStore.cookieHeaderValueIfFresh

		for attempt in 1...maxAttempts {
			do {
				var request = URLRequest(url: url)
				if let clearanceCookieHeaderValue {
					request.setValue(clearanceCookieHeaderValue, forHTTPHeaderField: "Cookie")
				}
				let downloadResponse = try await Downloader.shared.download(request, shouldCache: { data, _ in
					// See Downloader's own doc comment on the caching check:
					// a Cloudflare challenge page is a 200, so it needs its
					// own veto here on top of Downloader's status-code check,
					// or it gets cached and replayed as a false "success" on
					// every subsequent call to this URL, including the
					// clearance-cookie retry a few lines below on a future
					// attempt.
					guard let data, let html = String(data: data, encoding: .utf8) else {
						return true
					}
					return !isCloudflareChallenge(html)
				})

				guard let response = downloadResponse.response else {
					throw AO3SearchResultsFetchError.exhaustedRetries
				}

				let statusCode = response.forcedStatusCode
				if statusCode == HTTPResponseCode.tooManyRequests {
					return .rateLimited
				}

				if (500...599).contains(statusCode) {
					logger.info("AO3SearchResultsFetcher: attempt \(attempt) got HTTP \(statusCode) for \(url.absoluteString, privacy: .public)")
					try await retryOrGiveUp(attempt: attempt)
					continue
				}

				guard let data = downloadResponse.data, !data.isEmpty, response.statusIsOK else {
					throw AO3SearchResultsFetchError.exhaustedRetries
				}

				guard let html = String(data: data, encoding: .utf8) else {
					throw AO3SearchResultsFetchError.exhaustedRetries
				}

				if isCloudflareChallenge(html) {
					if clearanceCookieHeaderValue != nil {
						logger.info("AO3SearchResultsFetcher: stored clearance cookie didn't satisfy Cloudflare for \(url.absoluteString, privacy: .public) -- clearing it")
						AO3ChallengeSessionStore.clearSession()
					}
					return .cloudflareChallenge(challengedURL: url)
				}

				switch AO3SearchResultsExtractor.extract(fromResultsPageHTML: html, feedURL: feedURL) {
				case .success(let items, let hasNextPage, let pageTitle):
					return .success(items, hasNextPage: hasNextPage, pageTitle: pageTitle)
				case .noResults(let pageTitle):
					return .noResults(pageTitle: pageTitle)
				case .registrationRequired:
					return .registrationRequired
				}
			} catch let error as URLError where error.code == .timedOut {
				logger.info("AO3SearchResultsFetcher: attempt \(attempt) timed out for \(url.absoluteString, privacy: .public)")
				try await retryOrGiveUp(attempt: attempt)
				continue
			}
		}
		throw AO3SearchResultsFetchError.exhaustedRetries
	}

	/// Sleeps with exponential backoff (doubling, capped) if another
	/// attempt remains; throws `.exhaustedRetries` once `maxAttempts` is
	/// used up, ending the caller's loop.
	private static func retryOrGiveUp(attempt: Int) async throws {
		guard attempt < maxAttempts else {
			throw AO3SearchResultsFetchError.exhaustedRetries
		}
		let backoffSeconds = min(retryBackoffBaseSeconds * pow(2, Double(attempt - 1)), maxBackoffSeconds)
		try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
	}
}

// MARK: - Always-authenticated listing types (subscriptions, marked-for-later)

extension AO3SearchResultsFetcher {

	/// Fetches an AO3 listing URL that's always private-to-the-signed-in-
	/// account (subscriptions, marked-for-later -- see
	/// `nectar-toolbar-ao3-listing-feeds.md`'s "Auth requirement per
	/// listing type" table; every other listing shape stays on the plain
	/// `fetch(url:feedURL:)` above, unauthenticated). Tries the ordinary
	/// anonymous path first -- AO3 always challenges these with its
	/// registration wall for a signed-out request, but attempting
	/// anonymously first (rather than skipping straight to
	/// authentication) keeps this consistent with
	/// `AO3ChapterFetcher.retryAuthenticated(url:)`'s existing
	/// anonymous-then-authenticated shape, and still correctly surfaces
	/// `.rateLimited`/`.cloudflareChallenge`/network failures without a
	/// second, redundant authenticated attempt for those cases.
	///
	/// On `.registrationRequired` from the anonymous attempt, retries via
	/// `AO3AuthenticatedFetcher.fetch(_:)` (the same stored-session Cookie
	/// primitive `AO3ChapterFetcher` already uses for a single work page)
	/// against the identical listing-page extraction/pagination path.
	/// Returns `.notSignedIn` rather than `.registrationRequired` when no
	/// session is stored at all, so a caller can distinguish "you need to
	/// sign in" from "AO3 rejected your session" -- callers should treat
	/// `.notSignedIn` as instructing the person to sign in via Settings
	/// (`ao3-authenticated-reading.md`), not as a transient fetch error to
	/// retry.
	///
	/// Callers must check
	/// `AO3ChapterFetcher.isAO3NetworkRequestAllowed(for:)`-equivalent
	/// gating themselves before calling this, same as every other AO3
	/// request path -- this function has no article to gate against, so
	/// it can't check that itself.
	public static func fetchRequiringSignIn(url: URL, feedURL: String) async throws -> AO3SearchResultsFetchOutcome {
		let anonymousOutcome = try await fetch(url: url, feedURL: feedURL)

		guard case .registrationRequired = anonymousOutcome else {
			return anonymousOutcome
		}

		guard AO3SessionStore.isSignedIn else {
			return .notSignedIn
		}

		guard let (data, response) = try await AO3AuthenticatedFetcher.fetch(url) else {
			// No session after all -- AO3SessionStore.isSignedIn and
			// AO3AuthenticatedFetcher.fetch both read the same stored
			// cookie, so this is only reachable if it was cleared
			// between the two checks (e.g. a concurrent sign-out).
			return .notSignedIn
		}

		guard response.statusIsOK, !data.isEmpty, let html = String(data: data, encoding: .utf8) else {
			throw AO3SearchResultsFetchError.exhaustedRetries
		}

		switch AO3SearchResultsExtractor.extract(fromResultsPageHTML: html, feedURL: feedURL) {
		case .success(let items, let hasNextPage, let pageTitle):
			return .success(items, hasNextPage: hasNextPage, pageTitle: pageTitle)
		case .noResults(let pageTitle):
			return .noResults(pageTitle: pageTitle)
		case .registrationRequired:
			// AO3 rejected the stored session itself (expired/revoked),
			// not just "you weren't signed in" -- distinct from
			// .notSignedIn above, but callers currently have no separate
			// UI for "your AO3 session expired, sign in again" on this
			// path, so this folds into the same not-signed-in messaging
			// rather than inventing a fourth outcome case with no
			// consumer yet. Unlike AO3ChapterFetcher.retryAuthenticated,
			// this does NOT clear AO3SessionStore here -- that fetcher's
			// own doc comment notes it's the one call site that owns
			// that decision for a single work-page retry; a listing-page
			// retry duplicating that clear could race a concurrent
			// chapter-fetch retry against the same store. Left to
			// AO3ChapterFetcher's existing call site.
			return .notSignedIn
		}
	}
}

// MARK: - Cloudflare challenge detection

private extension AO3SearchResultsFetcher {

	/// Forwards to `AO3CloudflareChallenge.isChallengePage(_:)` below --
	/// kept as a same-named private method here (rather than calling
	/// `AO3CloudflareChallenge` directly at each call site above) so this
	/// file's own two call sites didn't need to change.
	static func isCloudflareChallenge(_ html: String) -> Bool {
		AO3CloudflareChallenge.isChallengePage(html)
	}
}

/// Public (AO3SearchResultsFetcher itself is internal to this module, so a
/// `public` member on it wouldn't actually be reachable from outside it --
/// this is the standalone equivalent, used by
/// `AO3ChallengeSolverViewController` (iOS target) to sniff the same
/// markers out of a live WKWebView's rendered HTML, to know when an
/// interactive challenge has actually cleared rather than just that the
/// page finished loading (the challenge page itself "finishes loading"
/// too, before its own JS/redirect resolves). `AO3SearchResultsFetcher`'s
/// own `isCloudflareChallenge(_:)` forwards here rather than the reverse,
/// so there's exactly one copy of the marker list.
public enum AO3CloudflareChallenge {

	// "cdn-cgi/challenge-platform" was previously included here but was
	// dropped: it's Cloudflare's routine bot-management/JS-challenge
	// beacon, embedded on ordinary rendered pages under Bot Management,
	// not just interstitials -- it false-positived on real, fully-rendered
	// AO3 search-results pages (confirmed against a captured results page
	// with no "Just a moment..." title and no #signin wall). Both markers
	// below are specific to an actual interstitial: the literal title text
	// Cloudflare's block page uses, and a challenge-bypass link.
	private static let challengeMarkers = [
		"Just a moment...",
		"cf-chl-bypass"
	]

	public static func isChallengePage(_ html: String) -> Bool {
		challengeMarkers.contains { html.contains($0) }
	}
}
