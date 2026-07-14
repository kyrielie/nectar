//
//  LocalAccountRefresher.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/6/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import ErrorLog
import RSCore
import RSParser
import RSWeb
import Articles
import ArticlesDatabase
import ActivityLog
import os

@MainActor protocol LocalAccountRefresherDelegate {
	func localAccountRefresher(_ refresher: LocalAccountRefresher, articleChanges: ArticleChanges)
}

@MainActor final class LocalAccountRefresher: ProgressInfoReporter {
	var delegate: LocalAccountRefresherDelegate?

	var progressInfo = ProgressInfo() {
		didSet {
			if progressInfo != oldValue {
				postProgressInfoDidChangeNotification()
			}
		}
	}

	/// Settable by the caller (LocalAccountDelegate / CloudKitAccountDelegate) so
	/// per-refresh activities can be scoped to the right account.
	var accountID: String?

	/// When false, refreshFeeds does not create its own `.refreshAll` activity.
	var publishesRefreshActivity = true

	/// Feed URLs whose refresh was cut short this pass, either because the
	/// background deadline (`AccountManager.shared.backgroundRefreshDeadline`)
	/// was hit or because `suspend()` cancelled the request out from under it.
	/// The caller (`LocalAccountDelegate.refreshAll()`) uses this to make sure
	/// those specific feeds get flagged for a prompt retry instead of silently
	/// staying exactly as stale as they were before this refresh.
	private(set) var interruptedFeedURLs = Set<String>()

	/// Human-readable stats summary for the most recent (or in-progress) refresh.
	var refreshStatsMessage: String {
		var parts = [String]()
		parts.append("\(feedsTotal) \(feedsTotal == 1 ? "feed" : "feeds")")
		if feedsSkipped > 0 {
			parts.append("\(feedsSkipped) skipped")
		}
		if feedsErrored > 0 {
			parts.append("\(feedsErrored) \(feedsErrored == 1 ? "error" : "errors")")
		}
		parts.append("\(newArticlesCount) new \(newArticlesCount == 1 ? "article" : "articles")")
		parts.append("\(updatedArticlesCount) updated \(updatedArticlesCount == 1 ? "article" : "articles")")
		return parts.joined(separator: ", ")
	}

	private var refreshActivityID: Int?
	private var feedsTotal = 0
	private var feedsSkipped = 0
	private var feedsErrored = 0
	private var newArticlesCount = 0
	private var updatedArticlesCount = 0
	private var outstandingParseTasks = 0
	private var downloadSessionIsComplete = false

	private var completions: [() -> Void] = []
	private var isSuspended = false

	/// Guards against a second refreshFeeds pass starting while one is still
	/// in flight. Previously, a call to refreshFeeds while a prior call's
	/// DownloadSession tasks and next_url pagination were still running would
	/// reset outstandingParseTasks/downloadSessionIsComplete/paginationProgress
	/// out from under the in-flight pass and overwrite the stored completion
	/// closure -- silently hanging the first caller's await forever and
	/// causing a second DownloadSession batch to fire against the same feed
	/// URLs the first pass was still fetching (observed as broken-pipe socket
	/// errors on the server side). Feeds requested while a pass is running are
	/// queued in pendingFeeds/pendingCompletions and folded into a follow-up
	/// pass started the moment the current one finishes, instead of colliding
	/// with it.
	private var isRefreshing = false
	private var pendingFeeds: Set<Feed> = []
	private var pendingCompletions: [() -> Void] = []

	private lazy var downloadSession: DownloadSession = {
		let session = DownloadSession(delegate: self)
		NotificationCenter.default.addObserver(self, selector: #selector(progressInfoDidChange(_:)), name: .progressInfoDidChange, object: session)
		return session
	}()

	/// Tracks next_url pagination fetches, which happen outside DownloadSession
	/// (via a bare URLSession.shared.data(from:) in mergedParsedFeed) and so
	/// were previously invisible to progressInfo entirely: the refresh progress
	/// bar reflected only the initial per-feed requests and disappeared while
	/// pagination kept fetching and parsing pages in the background.
	private lazy var paginationProgress: RSProgress = {
		let progress = RSProgress()
		NotificationCenter.default.addObserver(self, selector: #selector(progressInfoDidChange(_:)), name: .progressInfoDidChange, object: progress)
		return progress
	}()

	private var urlToFeedDictionary = [String: Feed]()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "LocalAccountRefresher")

	@MainActor public func refreshFeeds(_ feeds: Set<Feed>) async {
		await withCheckedContinuation { continuation in
			Task { @MainActor in
				refreshFeeds(feeds) {
					continuation.resume()
				}
			}
		}
	}

	@MainActor private func refreshFeeds(_ feeds: Set<Feed>, completion: (() -> Void)? = nil) {
		guard !isRefreshing else {
			pendingFeeds.formUnion(feeds)
			if let completion {
				pendingCompletions.append(completion)
			}
			return
		}
		isRefreshing = true
		if let completion {
			completions.append(completion)
		}

		let redditURLToRefresh = Self.redditURLToRefresh(in: feeds)

		var filteredFeeds = Set<Feed>()
		var skippedFeeds = [(Feed, String)]() // feed and skip reason

		for feed in feeds {
			let (shouldSkip, reason) = Self.feedShouldBeSkipped(feed, redditURLToRefresh)
			if shouldSkip, let reason {
				skippedFeeds.append((feed, reason))
			} else {
				filteredFeeds.insert(feed)
			}
		}

		feedsTotal = feeds.count
		feedsSkipped = skippedFeeds.count
		feedsErrored = 0
		newArticlesCount = 0
		updatedArticlesCount = 0
		outstandingParseTasks = 0
		downloadSessionIsComplete = false
		interruptedFeedURLs.removeAll()
		paginationProgress.reset()

		// Create a pending activity for each feed that will be fetched,
		// to be completed later by the DownloadSessionDelegate callbacks.
		// Log skipped feeds as already completed with their reason.
		if let owner = activityOwner {
			let activityLog = ActivityLog.shared
			if publishesRefreshActivity {
				refreshActivityID = activityLog.createActivity(owner: owner, kind: .refreshAll)
				activityLog.didStart(id: refreshActivityID!)
			}
			for feed in filteredFeeds {
				activityLog.createActivity(owner: owner, kind: .refreshFeedContent(feedURL: feed.url), detail: feed.nameForDisplay)
			}
			for (feed, reason) in skippedFeeds {
				activityLog.logCompletedActivity(owner: owner, kind: .refreshFeedContent(feedURL: feed.url), detail: feed.nameForDisplay, message: reason)
			}
		}

		guard !filteredFeeds.isEmpty else {
			// All feeds were skipped. Still need to complete the parent activity.
			downloadSessionIsComplete = true
			completeRefreshIfReady()
			return
		}

		urlToFeedDictionary.removeAll()
		for feed in filteredFeeds {
			urlToFeedDictionary[feed.url] = feed
		}

		let urls = filteredFeeds.compactMap { Self.url(for: $0) }

		downloadSession.download(Set(urls))
	}

	private var activityOwner: ActivityOwner? {
		guard let accountID else {
			return nil
		}
		let displayName = AccountManager.shared.existingAccount(accountID: accountID)?.nameForDisplay ?? accountID
		return .account(accountID: accountID, displayName: displayName)
	}

	@MainActor public func suspend() {
		downloadSession.cancelAll()
		isSuspended = true
	}

	@MainActor public func resume() {
		isSuspended = false
	}

	// MARK: - Notifications

	@objc func progressInfoDidChange(_ notification: Notification) {
		progressInfo = ProgressInfo.combined([downloadSession.progressInfo, paginationProgress.progressInfo])
	}
}

// MARK: - DownloadSessionDelegate

@MainActor extension LocalAccountRefresher: DownloadSessionDelegate {

	func downloadSession(_ downloadSession: DownloadSession, conditionalGetInfoFor url: URL) -> HTTPConditionalGetInfo? {

		guard let feed = urlToFeedDictionary[url.absoluteString] else {
			assertionFailure("LocalAccountRefresher: expected feed for \(url)")
			Self.logger.debug("LocalAccountRefresher: expected feed for \(url)")
			return nil
		}

		// A nil contentHash means we've never confirmed this feed is single-page
		// (see LocalAccountRefresher's downloadDidComplete: contentHash is only set
		// after a non-partial, non-paginated refresh). Sending conditional GET
		// headers here risks a 304 that skips page-1 parsing -- and therefore
		// pagination -- entirely, for a feed we don't yet know is safe to shortcut.
		guard feed.contentHash != nil else {
			Self.logger.notice("LocalAccountRefresher: skipping conditional GET for \(url) -- feed not confirmed single-page")
			return nil
		}
		guard let conditionalGetInfo = feed.conditionalGetInfo else {
			Self.logger.debug("LocalAccountRefresher: no conditional GET info for \(url)")
			return nil
		}

		// Conditional GET info is dropped every 8 days, because some servers just always
		// respond with a 304 when *any* conditional GET info is sent, which means
		// those feeds don’t get updated. By dropping conditional GET info periodically,
		// we make sure those feeds get updated.
		if let conditionalGetInfoDate = feed.conditionalGetInfoDate {
			let eightDaysAgo = Date().bySubtracting(days: 8)
			if conditionalGetInfoDate < eightDaysAgo {
				if !SpecialCase.urlStringContainSpecialCase( url.absoluteString, [SpecialCase.openRSSOrgHostName, SpecialCase.rachelByTheBayHostName]) {
					Self.logger.info("LocalAccountRefresher: dropping conditional GET info for \(url) — more than 8 days old")
					feed.conditionalGetInfo = nil
					return nil
				}
			}
		}

		return conditionalGetInfo
	}

	func downloadSession(_ downloadSession: DownloadSession, didReceiveResponse url: URL) {
		guard let feed = urlToFeedDictionary[url.absoluteString], let owner = activityOwner else {
			return
		}
		ActivityLog.shared.didStart(owner, kind: .refreshFeedContent(feedURL: feed.url))
	}

	func downloadSession(_ downloadSession: DownloadSession, didFollowRedirectFor url: URL, from fromURL: URL, to toURL: URL, statusCode: Int) {
		guard let owner = activityOwner else {
			return
		}
		let detail = urlToFeedDictionary[url.absoluteString]?.nameForDisplay
		ActivityLog.shared.logCompletedActivity(owner: owner, kind: .followFeedRedirect, detail: detail, message: "\(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode)): \(fromURL.absoluteString) → \(toURL.absoluteString)")
	}

	func downloadSession(_ downloadSession: DownloadSession, didSkip url: URL, reason: String) {
		guard let owner = activityOwner else {
			return
		}
		let kind = ActivityKind.refreshFeedContent(feedURL: url.absoluteString)
		ActivityLog.shared.startIfNeeded(owner, kind: kind)
		ActivityLog.shared.didComplete(owner, kind: kind, message: reason, durationIsSignificant: false)
	}

	func downloadSession(_ downloadSession: DownloadSession, downloadDidComplete url: URL, response: URLResponse?, data: Data, error: NSError?) {

		guard let feed = urlToFeedDictionary[url.absoluteString] else {
			return
		}
		feed.lastCheckDate = Date()

		let activityKind = ActivityKind.refreshFeedContent(feedURL: feed.url)

		if let error {
			// A connection-level failure (host asleep, closed, or otherwise unreachable
			// on the network) for a feed belonging to a paired-library account is treated
			// as "can't reach your library right now," not a per-feed error dialog — the
			// Mac's feed server has no auto-restart by default, so this is an expected,
			// recoverable state rather than a genuine feed problem.
			if Self.isConnectionLevelError(error), let account = feed.account, account.endpointURL != nil {
				account.isLibraryReachable = false
				if let activityOwner {
					ActivityLog.shared.didComplete(activityOwner, kind: activityKind, message: "Library unreachable", durationIsSignificant: false)
				}
				return
			}
			if Self.isCancellationError(error) {
				// Either `suspend()` cancelled this request (app backgrounded /
				// low on background time) or the caller cancelled it directly.
				// This is not a feed problem -- don't count it as an error or
				// surface an error dialog -- but the feed still needs retrying,
				// since it silently ended up with none of this pass's data.
				Self.logger.notice("LocalAccountRefresher: \(url.absoluteString) cancelled mid-refresh -- will retry next pass")
				interruptedFeedURLs.insert(url.absoluteString)
				return
			}
			reportFeedRefreshError(feed: feed, error: error, activityKind: activityKind)
			return
		}
		guard let httpResponse = response as? HTTPURLResponse else {
			let error = NSError(domain: "LocalAccountRefresher", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unexpected response (not HTTP)"])
			reportFeedRefreshError(feed: feed, error: error, activityKind: activityKind)
			return
		}

		// Any real HTTP response means the server itself was reachable, even if this
		// particular request then errored at the HTTP level (handled below).
		feed.account?.isLibraryReachable = true

		feed.lastResponseCode = httpResponse.statusCode

		let statusIsOK = httpResponse.statusIsOK
		let statusIsOKOrNotModified = statusIsOK || httpResponse.statusCode == HTTPResponseCode.notModified
		guard statusIsOKOrNotModified else {
			let statusCode = httpResponse.statusCode
			let error = NSError(domain: "LocalAccountRefresher", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"])
			reportFeedRefreshError(feed: feed, error: error, activityKind: activityKind)
			return
		}

		let activityOwner = self.activityOwner

		let conditionalGetInfo = HTTPConditionalGetInfo(urlResponse: httpResponse)
		if conditionalGetInfo != feed.conditionalGetInfo {
			Self.logger.debug("LocalAccountRefresher: setting conditionalGetInfo for \(url.absoluteString)")
			feed.conditionalGetInfo = conditionalGetInfo
		}

		guard statusIsOK else {
			// 304 Not Modified
			if let activityOwner {
				ActivityLog.shared.didComplete(activityOwner, kind: activityKind, message: "304 Not Modified", durationIsSignificant: false)
			}
			return
		}

		if let cacheControlInfo = CacheControlInfo(urlResponse: httpResponse) {
			Self.logger.debug("LocalAccountRefresher: setting cacheControlInfo maxAge: \(cacheControlInfo.maxAge) url: \(url.absoluteString)")
			feed.cacheControlInfo = cacheControlInfo
		}

		let dataHash = data.md5String
		let dataSizeMessage = ActivityLog.dataSizeMessage(data)

		outstandingParseTasks += 1
		Task { @MainActor in
			defer {
				self.outstandingParseTasks -= 1
				self.completeRefreshIfReady()
			}

			Self.logger.notice("LocalAccountRefresher: parsing feed for \(url.absoluteString)")

			let parserData = ParserData(url: feed.url, data: data)
			let firstPageParsedFeed: ParsedFeed
			do {
				guard let result = try await FeedParser.parse(parserData) else {
					if let activityOwner {
						ActivityLog.shared.didComplete(activityOwner, kind: activityKind, message: dataSizeMessage)
					}
					return
				}
				firstPageParsedFeed = result
			} catch {
				Self.logger.error("LocalAccountRefresher: feed parse error for \(url.absoluteString): \(error.localizedDescription)")
				if let activityOwner {
					ActivityLog.shared.didFail(activityOwner, kind: activityKind, error: error)
				}
				self.feedsErrored += 1
				if let account = feed.account {
					let errorLogUserInfo = ErrorLogUserInfoKey.userInfo(sourceName: account.nameForDisplay, sourceID: account.type.rawValue, operation: "Parsing feed", errorMessage: "\(error.localizedDescription): \(url.absoluteString)")
					NotificationCenter.default.post(name: .appDidEncounterError, object: self, userInfo: errorLogUserInfo)
				}
				return
			}

			// Only single-page feeds can safely use the "unchanged" shortcut: a paginated
			// feed's page-1 body is a stable slice of a much larger feed, so hashing it
			// alone would short-circuit every subsequent refresh before pagination ever runs.
			let isPaginated = firstPageParsedFeed.nextURL != nil
			let hashMatch = dataHash == feed.contentHash
			Self.logger.notice("LocalAccountRefresher: page 1 decision for \(url.absoluteString) -- items=\(firstPageParsedFeed.items.count) nextURL=\(firstPageParsedFeed.nextURL ?? "nil") isPaginated=\(isPaginated) hashMatch=\(hashMatch) storedHash=\(feed.contentHash ?? "nil")")
			if !isPaginated, dataHash == feed.contentHash {
				if let activityOwner {
					ActivityLog.shared.didComplete(activityOwner, kind: activityKind, message: "\(dataSizeMessage), content unchanged")
				}
				return
			}

			let (parsedFeed, feedIsPartial) = await self.mergedParsedFeed(startingWith: firstPageParsedFeed, originalURL: url, owner: activityOwner, activityKind: activityKind)

			guard let account = feed.account else {
				if let activityOwner {
					ActivityLog.shared.didComplete(activityOwner, kind: activityKind, message: dataSizeMessage)
				}
				return
			}

			assert(Thread.isMainThread)
			if feedIsPartial {
				Self.logger.error("LocalAccountRefresher: \(url.absoluteString) fetched partially -- skipping deleteOlder for this refresh")
			}
			let articleChanges = await account.updateAsync(feed: feed, parsedFeed: parsedFeed, isPartial: feedIsPartial)

			Self.logger.notice("LocalAccountRefresher: update complete for \(url.absoluteString) -- mergedItems=\(parsedFeed.items.count) new=\(articleChanges.new?.count ?? 0) updated=\(articleChanges.updated?.count ?? 0) isPartial=\(feedIsPartial)")

			self.newArticlesCount += articleChanges.new?.count ?? 0
			self.updatedArticlesCount += articleChanges.updated?.count ?? 0

			// contentHash is only meaningful for single-page feeds: a merged multi-page
			// feed has no single "page body" to compare against on the next refresh, and
			// storing one here would silently re-trigger the pagination short-circuit bug.
			if !feedIsPartial, !isPaginated {
				Self.logger.notice("LocalAccountRefresher: setting contentHash for \(url.absoluteString)")
				feed.contentHash = dataHash
			} else {
				feed.contentHash = nil
			}

			if let activityOwner {
				ActivityLog.shared.didComplete(activityOwner, kind: activityKind, message: dataSizeMessage)
			}

			self.delegate?.localAccountRefresher(self, articleChanges: articleChanges)
		}
	}

	func downloadSession(_ downloadSession: DownloadSession, httpError statusCode: Int, url: URL) {
		guard let feed = urlToFeedDictionary[url.absoluteString] else {
			return
		}

		feed.lastCheckDate = Date()
		feed.lastResponseCode = statusCode

		let webserviceError = WebserviceError.httpError(status: statusCode)
		let statusDescription = webserviceError.localizedDescription
		let errorMessage = "HTTP \(statusCode) \(statusDescription): \(url.absoluteString)"
		let error = NSError(domain: "Nectar", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])

		reportFeedRefreshError(feed: feed, error: error, activityKind: .refreshFeedContent(feedURL: feed.url))
	}

	private func reportFeedRefreshError(feed: Feed, error: Error, activityKind: ActivityKind) {
		Self.logger.error("LocalAccountRefresher: error refreshing \(feed.url): \(error.localizedDescription)")
		if let activityOwner {
			ActivityLog.shared.didFail(activityOwner, kind: activityKind, error: error)
		}
		feedsErrored += 1
		guard let account = feed.account else {
			return
		}
		let errorLogUserInfo = ErrorLogUserInfoKey.userInfo(sourceName: account.nameForDisplay, sourceID: account.type.rawValue, operation: "Downloading feed: \(feed.url)", errorMessage: AccountError.detailedErrorMessage(error))
		NotificationCenter.default.post(name: .appDidEncounterError, object: self, userInfo: errorLogUserInfo)
	}

	func downloadSession(_ downloadSession: DownloadSession, shouldContinueAfterReceivingData data: Data, url: URL) -> Bool {

		guard !data.isDefinitelyNotFeed(), !isSuspended else {
			return false
		}
		return true
	}

	func downloadSessionDidComplete(_ downloadSession: DownloadSession) {

		if let accountID {
			completeRemainingActivities(accountID: accountID)
		}

		downloadSessionIsComplete = true
		completeRefreshIfReady()
	}

	/// JSON Feed pagination: if the first page has a `next_url`, fetch and
	/// parse each subsequent page directly, merging items into a single
	/// ParsedFeed. Most JSON Feed servers (including Ambrosia's) paginate by
	/// default, and nothing before this consumed `next_url`, so any feed
	/// with more items than one page's worth was silently truncated.
	///
	/// Stops when `next_url` is absent, a page fails to fetch or parse, or
	/// `maxPaginationPages` is hit -- a safety net against a misbehaving
	/// server whose `next_url` never terminates. This is a page-count cap,
	/// not an item-count cap: Ambrosia's per-page item count varies with
	/// series/collection grouping, so raise this if libraries grow past
	/// what 200 pages covers at the page sizes seen in practice.
	///
	/// A page that fails to fetch or parse makes the merged result partial:
	/// the caller must not run `deleteOlder` pruning against a feed that
	/// wasn't fetched in full, since the items on the failed page would
	/// look like they'd disappeared from the feed and get deleted from
	/// the local database.
	private static let maxPaginationPages = 200

	private func mergedParsedFeed(startingWith parsedFeed: ParsedFeed, originalURL: URL, owner: ActivityOwner?, activityKind: ActivityKind) async -> (feed: ParsedFeed, isPartial: Bool) {
		var mergedItems = parsedFeed.items
		var currentNextURLString = parsedFeed.nextURL
		var pageCount = 1
		var isPartial = false

		while let nextURLString = currentNextURLString,
			  let nextURL = URL(string: nextURLString),
			  pageCount < Self.maxPaginationPages {

			if let deadline = AccountManager.shared.backgroundRefreshDeadline, Date() >= deadline {
				// Running out of background execution time. Stop fetching more
				// pages now, on our own terms, rather than letting `suspend()`
				// cancel the in-flight request later and lose this page's data
				// with no explanation in the log. What's merged so far is kept
				// and reported as partial so `deleteOlder` pruning is skipped.
				// Read live (not copied at refresh start) so this also takes
				// effect for a refresh that began in the foreground and got
				// backgrounded mid-pagination -- exactly the case that produced
				// the two silently-dropped feeds this fix addresses.
				Self.logger.notice("LocalAccountRefresher: page fetch deadline reached for \(originalURL.absoluteString) after \(pageCount) page(s) -- stopping early")
				interruptedFeedURLs.insert(originalURL.absoluteString)
				isPartial = true
				break
			}

			let pageNumber = pageCount + 1
			Self.logger.notice("LocalAccountRefresher: following next_url page \(pageNumber) for \(originalURL.absoluteString): \(nextURL.absoluteString)")
			if let owner {
				ActivityLog.shared.updateProgress(owner, kind: activityKind, message: "Fetching page \(pageNumber)… (\(mergedItems.count) so far)")
			}
			paginationProgress.addTask()
			defer { paginationProgress.completeTask() }
			do {
				let (pageData, response) = try await URLSession.shared.data(from: nextURL)
				guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusIsOK else {
					let statusCode = (response as? HTTPURLResponse)?.statusCode
					let bodyPreview = String(data: pageData.prefix(500), encoding: .utf8) ?? "<non-UTF8 body, \(pageData.count) bytes>"
					Self.logger.error("LocalAccountRefresher: next_url page \(pageNumber) fetch failed for \(nextURL.absoluteString) -- status: \(statusCode.map(String.init) ?? "none"), body: \(bodyPreview)")
					isPartial = true
					break
				}
				let pageParserData = ParserData(url: nextURL.absoluteString, data: pageData)
				guard let pageParsedFeed = try await FeedParser.parse(pageParserData) else {
					Self.logger.error("LocalAccountRefresher: next_url page \(pageNumber) parse returned nil for \(nextURL.absoluteString)")
					isPartial = true
					break
				}
				mergedItems.formUnion(pageParsedFeed.items)
				currentNextURLString = pageParsedFeed.nextURL
				pageCount += 1
			} catch {
				Self.logger.error("LocalAccountRefresher: next_url page \(pageNumber) fetch error for \(nextURL.absoluteString): \(error.localizedDescription)")
				isPartial = true
				break
			}
		}

		if pageCount >= Self.maxPaginationPages && currentNextURLString != nil {
			Self.logger.error("LocalAccountRefresher: hit maxPaginationPages (\(Self.maxPaginationPages)) for \(originalURL.absoluteString) with more pages remaining -- treating as partial")
			isPartial = true
		}

		guard pageCount > 1 else {
			return (parsedFeed, isPartial)
		}

		Self.logger.notice("LocalAccountRefresher: merged \(pageCount) next_url pages for \(originalURL.absoluteString), \(mergedItems.count) total items, isPartial: \(isPartial)")

		let mergedFeed = ParsedFeed(type: parsedFeed.type, title: parsedFeed.title, homePageURL: parsedFeed.homePageURL, feedURL: parsedFeed.feedURL, language: parsedFeed.language, feedDescription: parsedFeed.feedDescription, nextURL: nil, iconURL: parsedFeed.iconURL, faviconURL: parsedFeed.faviconURL, authors: parsedFeed.authors, expired: parsedFeed.expired, hubs: parsedFeed.hubs, items: mergedItems)
		return (mergedFeed, isPartial)
	}
}

// MARK: - Activity Helpers

@MainActor private extension LocalAccountRefresher {

	func completeRefreshActivityIfReady() {
		guard downloadSessionIsComplete && outstandingParseTasks == 0 else {
			return
		}
		guard let refreshActivityID else {
			return
		}

		ActivityLog.shared.didComplete(id: refreshActivityID, message: refreshStatsMessage)
		self.refreshActivityID = nil
	}

	/// Fires every completion queued for the pass that just finished --
	/// resuming their `await refreshFeeds(_:)` callers -- only once every
	/// initial DownloadSession request *and* every next_url pagination/parse
	/// Task it spawned has finished. Previously `downloadSessionDidComplete`
	/// called `completion?()` directly as soon as the initial batch of
	/// requests came back, which meant callers (e.g.
	/// `LocalAccountDelegate.refreshAll()`, which sets
	/// `lastRefreshCompletedDate` right after awaiting this) believed the
	/// refresh had finished while next_url pagination was still silently
	/// running in the background -- the actual mechanism behind items never
	/// arriving even though the individual page fetches were succeeding.
	///
	/// If feeds were queued in `pendingFeeds` while this pass was running
	/// (see the re-entrancy guard in `refreshFeeds`), start a follow-up pass
	/// for them now instead of leaving `isRefreshing` set or dropping the
	/// request.
	func completeRefreshIfReady() {
		completeRefreshActivityIfReady()
		guard downloadSessionIsComplete, outstandingParseTasks == 0 else {
			return
		}

		let finishedCompletions = completions
		completions = []

		if !pendingFeeds.isEmpty {
			// Feeds were requested (e.g. a manual refresh, or a single-feed
			// repair) while this pass was still running. Start a follow-up
			// pass for them now that this one has actually finished, rather
			// than dropping the request or letting it collide with the
			// still-finishing pass -- the latter is what previously caused a
			// second DownloadSession batch to fire against feed URLs the
			// first pass was still fetching.
			let nextFeeds = pendingFeeds
			pendingFeeds = []
			let queuedCompletions = pendingCompletions
			pendingCompletions = []
			isRefreshing = false
			refreshFeeds(nextFeeds) {
				for queuedCompletion in queuedCompletions {
					queuedCompletion()
				}
			}
		} else {
			isRefreshing = false
		}

		Task { @MainActor in
			for finishedCompletion in finishedCompletions {
				finishedCompletion()
			}
		}
	}

	/// Cleans up any leftover per-feed activities at the end of a refresh.
	/// Defense-in-depth for paths we didn’t explicitly cover (e.g. a feed
	/// the DownloadSession dropped without a `didSkip` callback).
	func completeRemainingActivities(accountID: String) {
		let displayName = AccountManager.shared.existingAccount(accountID: accountID)?.nameForDisplay ?? accountID
		let owner = ActivityOwner.account(accountID: accountID, displayName: displayName)
		let activityLog = ActivityLog.shared

		for activity in activityLog.pendingActivities(for: owner) where activity.kind != .refreshAll {
			activityLog.startIfNeeded(owner, kind: activity.kind)
			activityLog.didComplete(owner, kind: activity.kind)
		}
		for activity in activityLog.runningActivities(for: owner) where activity.kind != .refreshAll {
			activityLog.didComplete(owner, kind: activity.kind)
		}
	}

}

// MARK: - Private

private extension LocalAccountRefresher {

	/// These hosts will never return a feed.
	///
	/// People may still have feeds pointing to Twitter due to our prior
	/// use of the Twitter API. (Which Twitter took away.)
	static let badHosts = ["twitter.com", "www.twitter.com", "x.com", "www.x.com"]

	/// Returns whether this feed should be skipped and the reason if so.
	///
	/// Nectar only ever refreshes feeds from the user's own local Ambrosia
	/// server (this fork restricts account creation to `.onMyMac`, and every
	/// feed URL is a route on that account's paired server) -- never a public
	/// site the app needs to be polite to. There is deliberately no minimum
	/// time between checks and no Cache-Control throttle here: refreshing on
	/// demand (pull-to-refresh, or right after a re-scan on the Mac) must
	/// always go through.
	static func feedShouldBeSkipped(_ feed: Feed, _ redditURLToRefresh: String?) -> (Bool, String?) {
		let (skipForDisallowedHost, disallowedHostReason) = feedShouldBeSkippedForDisallowedHostReasons(feed)
		if skipForDisallowedHost {
			return (true, disallowedHostReason)
		}
		let (skipForReddit, redditReason) = feedShouldBeSkippedForRedditReasons(feed, redditURLToRefresh)
		if skipForReddit {
			return (true, redditReason)
		}
		return (false, nil)
	}

	/// Reddit rate-limits to one feed per minute, so we
	/// refresh the least recently checked one.
	static func redditURLToRefresh(in feeds: Set<Feed>) -> String? {
		let redditFeeds = feeds.filter { SpecialCase.urlStringMatchesDomain($0.url, [SpecialCase.redditHostName]) }
		let winner = redditFeeds.min { ($0.lastCheckDate ?? .distantPast) < ($1.lastCheckDate ?? .distantPast) }
		return winner?.url
	}

	static func feedShouldBeSkippedForRedditReasons(_ feed: Feed, _ redditURLToRefresh: String?) -> (Bool, String?) {
		guard SpecialCase.urlStringMatchesDomain(feed.url, [SpecialCase.redditHostName]) else {
			return (false, nil)
		}
		if feed.url == redditURLToRefresh {
			return (false, nil)
		}
		var reason = "Skipped — Reddit allows only one feed per minute"
		if let redditURLToRefresh {
			reason += " — refreshing \(redditURLToRefresh) this time"
		}
		return (true, reason)
	}

	static func feedShouldBeSkippedForDisallowedHostReasons(_ feed: Feed) -> (Bool, String?) {
		guard let url = url(for: feed) else {
			return (true, "Skipped — invalid URL")
		}
		guard let lowercaseHost = url.host()?.lowercased() else {
			return (true, "Skipped — no host")
		}

		for badHost in badHosts {
			if lowercaseHost == badHost {
				Self.logger.info("LocalAccountRefresher: Dropping request because it’s X/Twitter, which doesn’t provide feeds: \(feed.url)")
				return (true, "Skipped — host does not provide feeds")
			}
		}

		return (false, nil)
	}

	static func url(for feed: Feed) -> URL? {
		URL(string: feed.url)
	}

	/// Whether `error` represents a connection-level failure (couldn't reach the host
	/// at all) as opposed to the host responding with an HTTP-level error. Used to
	/// distinguish "your library's Mac is asleep/off" from an actual feed problem.
	static func isConnectionLevelError(_ error: NSError) -> Bool {
		guard error.domain == NSURLErrorDomain else {
			return false
		}
		let connectionLevelCodes: Set<Int> = [
			NSURLErrorTimedOut,
			NSURLErrorCannotFindHost,
			NSURLErrorCannotConnectToHost,
			NSURLErrorNetworkConnectionLost,
			NSURLErrorNotConnectedToInternet,
			NSURLErrorDNSLookupFailed,
		]
		return connectionLevelCodes.contains(error.code)
	}

	/// Whether `error` is a plain `NSURLErrorCancelled` -- i.e. something (our own
	/// `suspend()`, or the system) cancelled the request rather than the request
	/// failing on its own. Cancellation is not a feed error: it means the feed
	/// simply wasn't fetched this pass and needs retrying, not that anything is
	/// wrong with it.
	static func isCancellationError(_ error: NSError) -> Bool {
		error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
	}
}

// MARK: - Utility

private extension Data {

	func isDefinitelyNotFeed() -> Bool {
		// We only detect a few image types for now. This should get fleshed-out at some later date.
		return self.isImage
	}
}
