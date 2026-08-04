//
//  Downloader.swift
//  RSWeb
//
//  Created by Brent Simmons on 8/27/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import os
import RSCore

public typealias DownloadCallback = @MainActor (DownloadResponse, Error?) -> Swift.Void

/// Simple downloader, for a one-shot download like an image
/// or a web page. For a download-feeds session, see DownloadSession.
/// Caches response for a short time for GET requests. May return cached response.
@MainActor public final class Downloader {
	public static let shared = Downloader()
	private let urlSession: URLSession
	private var callbacks = [URL: [(callback: DownloadCallback, fromCache: Bool)]]()
	private let cache = DownloadCache.shared

	// 429 Too Many Requests responses, per host. Mirrors DownloadSession's
	// retryAfterMessages -- that handling previously existed only in
	// DownloadSession (used for feed-refresh sessions), not here, so a
	// one-shot caller like AO3ChapterFetcher had no awareness of a 429 or
	// Cloudflare-style rate limit at all: every non-2xx response, 429
	// included, just failed the caller's own statusIsOK check with no
	// distinct handling, and nothing paused further requests to that host.
	private var retryAfterMessages = [String: HTTPResponse429]()

	// Default for hosts that don't send a Retry-After value. Matches
	// DownloadSession.defaultRetryAfter. Marked nonisolated (rather than
	// implicitly @MainActor via the enclosing class) because it's read
	// from createHTTPResponse429 below, which itself is nonisolated --
	// called from the URLSession dataTask completion handler, off the
	// main actor. Safe: an immutable TimeInterval needs no isolation.
	nonisolated private static let defaultRetryAfter: TimeInterval = 10 * 60

	nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Downloader")

	private init() {
		let sessionConfiguration = URLSessionConfiguration.ephemeral
		sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
		sessionConfiguration.httpShouldSetCookies = false
		sessionConfiguration.httpCookieAcceptPolicy = .never
		sessionConfiguration.httpMaximumConnectionsPerHost = 1
		sessionConfiguration.httpCookieStorage = nil

		if let userAgentHeaders = UserAgent.headers() {
			sessionConfiguration.httpAdditionalHeaders = userAgentHeaders
		}

		urlSession = URLSession(configuration: sessionConfiguration)
	}

	deinit {
		urlSession.invalidateAndCancel()
	}

	public func download(_ url: URL, shouldCache: (@Sendable (Data?, URLResponse?) -> Bool)? = nil) async throws -> DownloadResponse {
		try await withCheckedThrowingContinuation { continuation in
			download(url, shouldCache: shouldCache) { downloadResponse, error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(returning: downloadResponse)
				}
			}
		}
	}

	/// Async wrapper for `download(_ urlRequest:_:)`, mirroring the
	/// URL-only overload above. Needed by callers that must attach a
	/// request header by hand (e.g. AO3SearchResultsFetcher attaching a
	/// captured Cloudflare-clearance Cookie header) while still going
	/// through Downloader.shared -- and so still getting its per-host
	/// 429/Retry-After cooldown and (now-successful-only) response cache --
	/// rather than standing up a second one-shot URLSession the way
	/// AO3AuthenticatedFetcher deliberately does for the account-gated
	/// case. Unlike that case, a passed Cloudflare challenge isn't
	/// per-account -- caching a success under the plain URL key is correct
	/// here, not a leak.
	public func download(_ urlRequest: URLRequest, shouldCache: (@Sendable (Data?, URLResponse?) -> Bool)? = nil) async throws -> DownloadResponse {
		try await withCheckedThrowingContinuation { continuation in
			download(urlRequest, shouldCache: shouldCache) { downloadResponse, error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(returning: downloadResponse)
				}
			}
		}
	}

	public func download(_ url: URL, shouldCache: (@Sendable (Data?, URLResponse?) -> Bool)? = nil, _ callback: @escaping DownloadCallback) {
		assert(Thread.isMainThread)
		download(URLRequest(url: url), shouldCache: shouldCache, callback)
	}

	public func download(_ urlRequest: URLRequest, shouldCache: (@Sendable (Data?, URLResponse?) -> Bool)? = nil, _ callback: @escaping DownloadCallback) {
		assert(Thread.isMainThread)

		guard let url = urlRequest.url else {
			Self.logger.fault("Downloader: skipping download for URLRequest without a URL")
			return
		}

		guard url.isHTTPOrHTTPSURL() else {
			Self.logger.debug("Downloader: skipping download for non-http/https URL: \(url)")
			callback(DownloadResponse(data: nil, response: nil, returnedFromCache: false), nil)
			return
		}

		if let host = url.host()?.lowercased() {
			if let retryAfterMessage = retryAfterMessages[host] {
				if Date() >= retryAfterMessage.resumeDate {
					retryAfterMessages[host] = nil
				} else {
					Self.logger.info("Downloader: skipping \(url) — rate-limited by \(host) until \(retryAfterMessage.resumeDate)")
					let syntheticResponse = HTTPURLResponse(url: url, statusCode: HTTPResponseCode.tooManyRequests, httpVersion: nil, headerFields: nil)
					callback(DownloadResponse(data: nil, response: syntheticResponse, returnedFromCache: false), nil)
					return
				}
			}
		}

		let isCacheableRequest = urlRequest.httpMethod == HTTPMethod.get

		// Return cached record if available.
		if isCacheableRequest {
			if let cachedRecord = cache[url.absoluteString] {
				Self.logger.debug("Downloader: returning cached record for \(url)")
				callback(DownloadResponse(data: cachedRecord.data, response: cachedRecord.response, returnedFromCache: true), nil)
				return
			}
		}

		// Add callback. If there is already a download in progress for this URL, return early.
		if callbacks[url] == nil {
			Self.logger.debug("Downloader: downloading \(url)")
			callbacks[url] = [(callback, false)]
		} else {
			// A download is already in progress for this URL. Don’t start a separate download.
			// Add the callback to the callbacks array for this URL. This caller is coalesced
			// onto the in-progress download, so it makes no network request of its own.
			Self.logger.debug("Downloader: download in progress for \(url) — adding callback")
			callbacks[url]?.append((callback, true))
			return
		}

		var urlRequestToUse = urlRequest
		urlRequestToUse.addSpecialCaseUserAgentIfNeeded()

		let task = urlSession.dataTask(with: urlRequestToUse) { (data, response, error) in

			// Only cache a genuinely successful response. Caching a non-2xx
			// response (a 5xx, a 404, etc.) would mean replaying that failure
			// for the cache's full time-to-live. That alone isn't enough for
			// a Cloudflare challenge page, though -- those come back as an
			// ordinary HTTP 200 (see AO3CloudflareChallenge), so they'd pass
			// the statusIsOK check here and get cached as if they were the
			// real page, then replayed as the same "success" on every later
			// call to this URL for DownloadCache's 3-minute TTL, even after
			// a fresh request would have gotten through -- AO3SearchResultsFetcher's
			// own Cloudflare-challenge detection runs on whatever this hands
			// it, and by the time it decides the body is a challenge page,
			// the caching decision below has already been made. `shouldCache`
			// gives a caller that can recognize its own bad-response bodies
			// (a challenge page, an HTML error page from a normally-JSON
			// endpoint, etc.) the chance to veto caching on top of the
			// status-code check.
			if isCacheableRequest, error == nil, response?.statusIsOK == true, shouldCache?(data, response) ?? true {
				Self.logger.debug("Downloader: caching response for \(url)")
				self.cache.add(url.absoluteString, data: data, response: response)
			}

			let response429 = Self.createHTTPResponse429(url: url, response: response)

			Task { @MainActor in
				if let response429 {
					Self.logger.info("Downloader: recording 429 for \(response429.host), retrying no earlier than \(response429.resumeDate)")
					self.retryAfterMessages[response429.host] = response429
				}
				self.callAndReleaseCallbacks(url, data, response, error)
			}
		}
		task.resume()
	}
}

private extension Downloader {

	// Not actor-isolated -- called from the dataTask completion handler,
	// which doesn't run on the main actor. Reads only its arguments, so
	// this is safe to compute off-actor before hopping back to update
	// retryAfterMessages.
	nonisolated static func createHTTPResponse429(url: URL, response: URLResponse?) -> HTTPResponse429? {
		guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == HTTPResponseCode.tooManyRequests else {
			return nil
		}

		let parsedRetryAfter: TimeInterval? = {
			if let retryAfterValue = httpResponse.value(forHTTPHeaderField: HTTPResponseHeader.retryAfter),
			   let parsed = TimeInterval(retryAfterValue),
			   parsed > 0 {
				return parsed
			}
			return nil
		}()

		return HTTPResponse429(url: url, retryAfter: parsedRetryAfter ?? defaultRetryAfter)
	}
}

private extension Downloader {

	func callAndReleaseCallbacks(_ url: URL, _ data: Data? = nil, _ response: URLResponse? = nil, _ error: Error? = nil) {
		assert(Thread.isMainThread)

		defer {
			callbacks[url] = nil
		}

		guard let callbacksForURL = callbacks[url] else {
			assertionFailure("Downloader: downloaded URL \(url) but no callbacks found")
			Self.logger.fault("Downloader: downloaded URL \(url) but no callbacks found")
			return
		}

		let count = callbacksForURL.count
		if count == 1 {
			Self.logger.debug("Downloader: calling 1 callback for URL \(url)")
		} else {
			Self.logger.debug("Downloader: calling \(count) callbacks for URL \(url)")
		}

		for entry in callbacksForURL {
			let downloadResponse = DownloadResponse(data: data, response: response, returnedFromCache: entry.fromCache)
			entry.callback(downloadResponse, error)
		}
	}
}
