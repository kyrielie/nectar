//
//  DownloadCache.swift
//  RSWeb
//
//  Created by Brent Simmons on 10/16/25.
//

import Foundation
import RSCore

struct DownloadCacheRecord: CacheRecord, Sendable {
	let dateCreated = Date()
	let data: Data?
	let response: URLResponse?

	init(data: Data?, response: URLResponse?) {
		self.data = data
		self.response = response
	}
}

public nonisolated final class DownloadCache: Sendable {
	public static let shared = DownloadCache()

	private let cache = Cache<DownloadCacheRecord>(timeToLive: 60 * 3, timeBetweenCleanups: 60)

	init() {
		NotificationCenter.default.addObserver(self, selector: #selector(handleAppDidGoToBackground(_:)), name: .appDidGoToBackground, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(handleLowMemory(_:)), name: .lowMemory, object: nil)
	}

	@objc func handleAppDidGoToBackground(_ notification: Notification) {
		cache.removeAll()
	}

	@objc func handleLowMemory(_ notification: Notification) {
		cache.removeAll()
	}

	subscript(_ key: String) -> DownloadCacheRecord? {
		get {
			cache[key]
		}
		set {
			cache[key] = newValue
		}
	}

	func add(_ urlString: String, data: Data?, response: URLResponse?) {
		let cacheRecord = DownloadCacheRecord(data: data, response: response)
		cache[urlString] = cacheRecord
	}

	/// Clears every cached response. `Downloader.shared` caches successful
	/// GET responses for `Cache`'s 3-minute time-to-live, keyed only by URL
	/// -- with no seam of its own, a test that registers a new
	/// `TestingURLProtocol` response for a URL some earlier test already
	/// fetched (a common pattern: several `AO3SeriesNavigatorTests` cases
	/// reuse the same work-page URL against different fixtures) silently
	/// gets the earlier test's cached response back instead of ever
	/// reaching `TestingURLProtocol` again. `TestingURLProtocol.reset()`
	/// alone doesn't cover this, since that only clears the *registered*
	/// responses/requested-URL log, not what `Downloader` already cached
	/// from a prior request. Call this alongside `TestingURLProtocol.reset()`
	/// in any test `setUp()` that exercises `Downloader.shared`.
	public func removeAll() {
		cache.removeAll()
	}
}
