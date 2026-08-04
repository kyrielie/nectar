//
//  AO3SearchResultsFetcher.swift
//  Account
//
//  Nectar AO3 direct-reading support, Task 9 checkpoint 2's fetch path:
//  retry/backoff + Cloudflare-challenge detection, wrapping
//  RSParser.AO3SearchResultsExtractor -- see
//  nectar-ao3-features-plan-FINAL.md, Task 9, "Feed routing & pagination".
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
///   independently of status code, per the plan's explicit call-out that
///   this needs its own detection separate from AO3's own 429 handling.
enum AO3SearchResultsFetchOutcome {
	case success([ParsedItem])
	case noResults
	case registrationRequired
	case rateLimited
	case cloudflareChallenge
}

enum AO3SearchResultsFetchError: Error {
	/// A 5xx status or timeout that kept recurring past `maxAttempts`, or a
	/// response with no usable body after every attempt.
	case exhaustedRetries
}

enum AO3SearchResultsFetcher {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AO3SearchResultsFetcher")

	/// Bounded retry budget for a single page fetch. Covers both 5xx
	/// responses and request timeouts under one counter/backoff -- unlike
	/// `AmbrosiaSQLiteTransferFetcher`'s per-page retry loop (which the plan
	/// separately calls out a "consecutive-timeout giveup cap" for), this is
	/// a single request, not a many-page walk, so one bounded loop covering
	/// both failure kinds is the whole of what the plan's "separate...cap"
	/// requirement needs here: either failure kind still stops retrying
	/// after the same fixed number of attempts rather than continuing
	/// forever, which is the behavior the plan asks for.
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
	static func fetch(url: URL, feedURL: String) async throws -> AO3SearchResultsFetchOutcome {
		let clearanceCookieHeaderValue = AO3ChallengeSessionStore.cookieHeaderValueIfFresh

		for attempt in 1...maxAttempts {
			do {
				var request = URLRequest(url: url)
				if let clearanceCookieHeaderValue {
					request.setValue(clearanceCookieHeaderValue, forHTTPHeaderField: "Cookie")
				}
				let downloadResponse = try await Downloader.shared.download(request)

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
					return .cloudflareChallenge
				}

				switch AO3SearchResultsExtractor.extract(fromResultsPageHTML: html, feedURL: feedURL) {
				case .success(let items):
					return .success(items)
				case .noResults:
					return .noResults
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

	private static let challengeMarkers = [
		"Just a moment...",
		"cdn-cgi/challenge-platform",
		"cf-chl-bypass",
	]

	public static func isChallengePage(_ html: String) -> Bool {
		challengeMarkers.contains { html.contains($0) }
	}
}
