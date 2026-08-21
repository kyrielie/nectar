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
import ActivityLog

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
	/// `totalPages` mirrors `AO3SearchResultsOutcome.success`'s own field
	/// (RSParser, layer 1) -- carried across this fetch wrapper purely so
	/// callers that only see `AO3SearchResultsFetchOutcome` (never the
	/// raw `AO3SearchResultsOutcome`) still get the value.
	case success([ParsedItem], hasNextPage: Bool, pageTitle: String?, totalPages: Int?)
	/// `totalPages` mirrors `AO3SearchResultsOutcome.noResults`'s own
	/// field, same reasoning as `.success` above.
	case noResults(pageTitle: String?, totalPages: Int?)
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
				case .success(let items, let hasNextPage, let pageTitle, let totalPages):
					return .success(items, hasNextPage: hasNextPage, pageTitle: pageTitle, totalPages: totalPages)
				case .noResults(let pageTitle, let totalPages):
					return .noResults(pageTitle: pageTitle, totalPages: totalPages)
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

	/// Fetches an AO3 listing URL. Authenticated-first when a session is
	/// stored, mirroring `AO3ChapterFetcher.download`'s shape: tries
	/// `AO3AuthenticatedFetcher.fetch(_:)` (the same stored-session Cookie
	/// primitive `AO3ChapterFetcher` uses for a single work page) against
	/// this listing-page extraction/pagination path first, before ever
	/// making an anonymous request. Called for every listing page once a
	/// session exists (see the widened `isAlwaysAuthenticatedAO3ListingFeed(_:)
	/// || AO3SessionStore.isSignedIn` gate at each call site), and always
	/// called -- session or not -- for the two listing types that are
	/// always private to the signed-in account (subscriptions,
	/// marked-for-later -- see
	/// `LocalAccountRefresher.isAlwaysAuthenticatedAO3ListingFeed(_:)`'s
	/// own doc comment).
	///
	/// Falls back to the plain anonymous `fetch(url:feedURL:)` above --
	/// with its own retry/backoff/Cloudflare handling, unchanged -- only
	/// on an authentication-shaped failure: the authenticated attempt
	/// comes back `.registrationRequired` (session rejected/expired) or
	/// throws (network error). A `.rateLimited`/Cloudflare-challenge
	/// result from the authenticated attempt is not a login problem and
	/// wouldn't be fixed by falling back anonymously, so those cases
	/// return directly instead. If no session is stored at all
	/// (`AO3SessionStore.isSignedIn == false`), behavior is unchanged:
	/// straight to the anonymous path, no authenticated attempt at all.
	///
	/// Preserves the existing `.notSignedIn` translation, but scoped by
	/// `isAlwaysAuthenticatedListing` (the caller already knows this from
	/// its own `isAlwaysAuthenticatedAO3ListingFeed(_:)` check, so it's
	/// threaded through rather than re-derived here): a
	/// `.registrationRequired` result -- whether from a rejected stored
	/// session or from a signed-out anonymous fetch -- only becomes
	/// `.notSignedIn` when the URL is one of the always-private listing
	/// types. For a general search/tag page routed here only because a
	/// session happens to be stored, a rejected session or a signed-out
	/// registration wall is returned as plain `.registrationRequired`
	/// instead -- the "sign in to see *your* subscriptions" framing
	/// doesn't fit a page that was never gated on identity, only on
	/// AO3's own registration wall for that particular content. Callers
	/// should treat `.notSignedIn` as instructing the person to sign in
	/// via Settings (`ao3-authenticated-reading.md`), not as a transient
	/// fetch error to retry.
	///
	/// `activityContext`, when supplied by a caller that already has a
	/// running Activity Log entry for this fetch (`LocalAccountRefresher`'s
	/// `activityOwner`/`activityKind`), gets a progress note on a
	/// fallback -- a degrade-to-anonymous, not a failure, so
	/// `updateProgress` rather than `didFail`. Callers with no such entry
	/// in scope (`LocalAccountDelegate.createFeed`,
	/// `AO3SearchResultsPaginator.fetchPage`) pass `nil`; the fallback is
	/// still always logged via `os.Logger` below regardless.
	///
	/// Callers must check
	/// `AO3ChapterFetcher.isAO3NetworkRequestAllowed(for:)`-equivalent
	/// gating themselves before calling this, same as every other AO3
	/// request path -- this function has no article to gate against, so
	/// it can't check that itself.
	public static func fetchRequiringSignIn(url: URL, feedURL: String, isAlwaysAuthenticatedListing: Bool, activityContext: (owner: ActivityOwner, kind: ActivityKind)? = nil) async throws -> AO3SearchResultsFetchOutcome {
		func logFallback(_ reason: String) async {
			logger.info("AO3SearchResultsFetcher: authenticated attempt failed (\(reason, privacy: .public)) for \(url.absoluteString, privacy: .public) -- retrying anonymously")
			if let activityContext {
				await ActivityLog.shared.updateProgress(activityContext.owner, kind: activityContext.kind, message: "AO3 authenticated fetch failed (\(reason)) -- retrying anonymously")
			}
		}

		if AO3SessionStore.isSignedIn {
			do {
				if let (data, response) = try await AO3AuthenticatedFetcher.fetch(url) {
					guard response.statusIsOK, !data.isEmpty, let html = String(data: data, encoding: .utf8) else {
						await logFallback("HTTP \(response.statusCode)")
						return try await fetch(url: url, feedURL: feedURL)
					}
					switch AO3SearchResultsExtractor.extract(fromResultsPageHTML: html, feedURL: feedURL) {
					case .success(let items, let hasNextPage, let pageTitle, let totalPages):
						return .success(items, hasNextPage: hasNextPage, pageTitle: pageTitle, totalPages: totalPages)
					case .noResults(let pageTitle, let totalPages):
						return .noResults(pageTitle: pageTitle, totalPages: totalPages)
					case .registrationRequired:
						// The stored session itself is what's rejected --
						// distinct from never having signed in at all. Not
						// cleared here -- see the doc comment above;
						// AO3ChapterFetcher's own call site owns that
						// decision for the single-work-page case, and a
						// listing-page fallback duplicating it here could
						// race a concurrent chapter-fetch retry against the
						// same store. Falls back to the anonymous path,
						// which for an always-authenticated listing type
						// will itself come back .registrationRequired --
						// folded into .notSignedIn just below (matches the
						// previous anonymous-then-authenticated shape's
						// identical fold), since there is no separate UI
						// for "your AO3 session expired, sign in again" on
						// this path. For a general listing page, the plain
						// .registrationRequired is returned as-is instead.
						await logFallback("session rejected")
						let anonymousOutcome = try await fetch(url: url, feedURL: feedURL)
						guard isAlwaysAuthenticatedListing, case .registrationRequired = anonymousOutcome else {
							return anonymousOutcome
						}
						return .notSignedIn
					}
				}
				// No session after all -- AO3SessionStore.isSignedIn and
				// AO3AuthenticatedFetcher.fetch both read the same stored
				// cookie, so this is only reachable if it was cleared
				// between the two checks (e.g. a concurrent sign-out).
				// Fall through to the anonymous path below.
				await logFallback("session cleared mid-fetch")
			} catch {
				// Network-level failure on the authenticated attempt --
				// not a login problem, so the stored session is left
				// alone; fall back to the anonymous path rather than
				// throwing outright.
				await logFallback(error.localizedDescription)
			}
		}

		let anonymousOutcome = try await fetch(url: url, feedURL: feedURL)
		guard case .registrationRequired = anonymousOutcome else {
			return anonymousOutcome
		}
		// Not signed in at all (the signed-in case above already tried
		// the authenticated attempt and handled its own
		// .registrationRequired fold). Same isAlwaysAuthenticatedListing
		// scoping as above: only translate to .notSignedIn for the
		// always-private listing types -- a general search/tag page's
		// registration wall is a content-level gate, not an identity
		// gate, and doesn't mean "you need to sign in."
		guard isAlwaysAuthenticatedListing else {
			return anonymousOutcome
		}
		return .notSignedIn
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
