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
		// Gives AO3PrefetchQueue a fresh per-refresh-pass budget, alongside
		// newArticlesCount above -- cheap no-op when
		// AO3PrefetchNewWorksPreference is off, since nothing is ever
		// enqueued in that case. Fire-and-forget: this always reaches the
		// actor well before any feed's updateAsync below could possibly
		// complete and try to enqueue against it, so there's no ordering
		// requirement to enforce here.
		Task {
			await AO3PrefetchQueue.shared.resetForNewRefreshCycle()
		}

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

		// Feeds resolved to an Ambrosia `.sqlite` transfer route (per
		// AmbrosiaTransferFormatPreference + Self.url(for:)) never go through
		// DownloadSession at all: DownloadSession's default 15s
		// timeoutIntervalForRequest would kill a multi-minute whole-database
		// transfer outright, which is exactly why
		// AmbrosiaSQLiteTransferFetcher uses its own dedicated URLSession with a
		// 300s timeout instead. Route those feeds to it directly here and only
		// hand the rest to DownloadSession.
		// AO3 listing feeds (search/tag results, author works, bookmarks,
		// marked-for-later, subscriptions, collections, series) are a third
		// bucket alongside sqliteFeeds/downloadFeeds, matched on host + path,
		// not extension -- see Self.isAO3ListingFeed(_:). Like sqliteFeeds,
		// these bypass DownloadSession entirely: they go through
		// Downloader.shared, the same one-shot path AO3ChapterFetcher already
		// uses, since a listing page is a single GET, not something
		// DownloadSession's conditional-GET/feed-parsing machinery is built
		// for. This checkpoint fetches page 1 only -- "load more"
		// pagination is a later checkpoint.
		var downloadFeeds = Set<Feed>()
		var sqliteFeeds = Set<Feed>()
		var ao3SearchResultFeeds = Set<Feed>()
		for feed in filteredFeeds {
			guard let url = Self.url(for: feed) else {
				continue
			}
			if url.pathExtension.lowercased() == "sqlite" {
				sqliteFeeds.insert(feed)
			} else if Self.isAO3ListingFeed(url) {
				ao3SearchResultFeeds.insert(feed)
			} else {
				downloadFeeds.insert(feed)
			}
		}

		urlToFeedDictionary.removeAll()
		for feed in downloadFeeds {
			urlToFeedDictionary[feed.url] = feed
		}

		for feed in sqliteFeeds {
			fetchAndImportAmbrosiaSQLiteTransfer(feed: feed)
		}

		for feed in ao3SearchResultFeeds {
			fetchAndImportAO3SearchResults(feed: feed)
		}

		guard !downloadFeeds.isEmpty else {
			downloadSessionIsComplete = true
			completeRefreshIfReady()
			return
		}

		let urls = downloadFeeds.compactMap { Self.url(for: $0) }

		downloadSession.download(Set(urls))
	}

	/// Fetches and imports every page of an Ambrosia `.sqlite` transfer walk
	/// for `feed`, bypassing DownloadSession entirely (see the routing
	/// comment in refreshFeeds). Tracked the same way a JSON parse Task is
	/// (outstandingParseTasks + completeRefreshIfReady), so the refresh pass
	/// doesn't report itself done while a walk is still in flight.
	///
	/// `.incomplete` is reported via `didComplete`, not
	/// `reportFeedRefreshError` -- it's a distinct, visible state, not a feed
	/// error: the walk is retried automatically starting from wherever it
	/// left off (AmbrosiaSQLiteTransferWalkStateStore) on the next scheduled
	/// refresh, so surfacing it as an "error" would overstate how much
	/// attention it needs while understating that it's already self-healing.
	///
	/// Posts `.AccountDidDownloadArticles` via `account.sendNotificationAbout(_:)`
	/// with the new/updated Article values accumulated across every page of the
	/// walk (see AmbrosiaSQLiteTransferFetcher.fetchAndImportWalk), the same
	/// notification the JSON path's account.updateAsync(feed:parsedFeed:) posts
	/// and the timeline observes to insert new articles -- this import path
	/// previously wrote straight into ArticlesTable/StatusesTable without ever
	/// constructing Article/ArticleChanges values, so the notification never
	/// fired for it.
	///
	/// NOT YET RESOLVED: `.incomplete` is currently surfaced only through the
	/// ActivityLog completion message (visible in Settings > Activity Log).
	/// A distinct status in the feed list itself (not just logs) is also
	/// called for -- wiring that into MainFeedCollectionViewCell/
	/// MainFeedRowIdentifier needs a closer look at how that cell already
	/// surfaces per-feed state (if at all) before adding to it; flagged
	/// rather than guessed at here.
	@MainActor private func fetchAndImportAmbrosiaSQLiteTransfer(feed: Feed) {
		guard let url = Self.url(for: feed), let account = feed.account else {
			return
		}

		let activityKind = ActivityKind.refreshFeedContent(feedURL: feed.url)
		let activityOwner = self.activityOwner

		outstandingParseTasks += 1
		Task { @MainActor in
			defer {
				self.outstandingParseTasks -= 1
				self.completeRefreshIfReady()
			}

			feed.lastCheckDate = Date()

			do {
				let result = try await AmbrosiaSQLiteTransferFetcher.fetchAndImportWalk(baseURL: url, feedID: feed.feedID, into: account.database)
				switch result {
				case .complete(let pagesImported, let rowsImported, let articleChanges):
					account.sendNotificationAbout(articleChanges)
					Self.logger.notice("LocalAccountRefresher: SQLite transfer walk complete for \(feed.url) -- \(rowsImported) rows across \(pagesImported) page(s)")
					if let activityOwner {
						ActivityLog.shared.didComplete(activityOwner, kind: activityKind, message: "SQLite transfer: \(rowsImported) book\(rowsImported == 1 ? "" : "s") across \(pagesImported) page\(pagesImported == 1 ? "" : "s")")
					}
				case .incomplete(let pagesImported, let rowsImported, let expectedTotal, let lastPageAttempted, let articleChanges):
					if articleChanges.new?.isEmpty != false && articleChanges.updated?.isEmpty != false {
						// sendNotificationAbout(_:) is a no-op for an empty ArticleChanges
						// (see Account.sendNotificationAbout), so fall back to the old
						// best-effort nudge for the case where this pass imported nothing
						// at all before giving up (e.g. every attempt for page 1 failed).
						account.updateUnreadCounts(feeds: [feed])
					} else {
						account.sendNotificationAbout(articleChanges)
					}
					Self.logger.notice("LocalAccountRefresher: SQLite transfer walk incomplete for \(feed.url) -- imported \(rowsImported) of \(expectedTotal) rows across \(pagesImported) page(s) this pass, stopped at page \(lastPageAttempted)")
					if let activityOwner {
						let progressDetail = expectedTotal > 0 ? "\(rowsImported) of \(expectedTotal) books" : "\(rowsImported) books"
						ActivityLog.shared.didComplete(activityOwner, kind: activityKind, message: "Sync incomplete — \(progressDetail) imported so far, will resume next refresh", durationIsSignificant: false)
					}
				}
			} catch {
				Self.logger.error("LocalAccountRefresher: Ambrosia SQLite transfer failed for \(url.absoluteString): \(error.localizedDescription)")
				self.reportFeedRefreshError(feed: feed, error: error, activityKind: activityKind)
			}
		}
	}

	/// Fetches page 1 of an AO3 search-results feed and imports whatever
	/// works it lists, via `AO3SearchResultsFetcher` (retry/backoff for 5xx
	/// and timeouts, plus Cloudflare-challenge detection -- see that type's
	/// own doc comments).
	///
	/// `deleteOlder: false` on the `updateAsync` call below, deliberately --
	/// page 1 is a partial view of the search, not the whole feed (pagination
	/// is lazy), so treating it as authoritative for pruning
	/// would delete every work that only shows up on page 2+.
	@MainActor private func fetchAndImportAO3SearchResults(feed: Feed) {
		guard let url = Self.url(for: feed), let account = feed.account else {
			return
		}

		let activityKind = ActivityKind.refreshFeedContent(feedURL: feed.url)

		outstandingParseTasks += 1
		Task { @MainActor in
			defer {
				self.outstandingParseTasks -= 1
				self.completeRefreshIfReady()
			}

			feed.lastCheckDate = Date()

			// Subscriptions and marked-for-later are always-yours,
			// always-private (see isAlwaysAuthenticatedAO3ListingFeed's own
			// doc comment) -- route through the authenticated-then-anonymous
			// fetch here too, mirroring
			// LocalAccountDelegate.createFeed's identical branch, since this
			// function is reachable for those feed types on their add-time
			// fetch (feedShouldBeSkippedForAO3SearchResultsReasons lets
			// lastCheckDate == nil through). Widened beyond
			// isAlwaysAuthenticatedAO3ListingFeed alone: any general
			// search/tag page also routes through fetchRequiringSignIn once
			// a session exists, so a signed-in person gets the
			// authenticated-first attempt there too, not just on the
			// always-private listing types. A subscriptions/marked-for-later
			// page still always routes through it (session or not) to get
			// the correct .notSignedIn surfaced when signed out. Every
			// other listing type, when signed out, keeps using the plain
			// anonymous fetch, unchanged.
			let requiresSignIn = Self.isAlwaysAuthenticatedAO3ListingFeed(url) || AO3SessionStore.isSignedIn

			do {
				let outcome: AO3SearchResultsFetchOutcome
				if requiresSignIn {
					outcome = try await AO3SearchResultsFetcher.fetchRequiringSignIn(url: url, feedURL: feed.url, isAlwaysAuthenticatedListing: Self.isAlwaysAuthenticatedAO3ListingFeed(url), activityContext: activityOwner.map { ($0, activityKind) })
				} else {
					outcome = try await AO3SearchResultsFetcher.fetch(url: url, feedURL: feed.url)
				}

				switch outcome {
				case .success(let parsedItems, let hasNextPage, _, let totalPages):
					// hasNextPage isn't consumed here -- a routine/add-time
					// fetch always writes page 1 (below) regardless; only
					// AO3SearchResultsPaginator's "load more" UI needs the
					// signal, and it calls AO3SearchResultsFetcher directly.
					// pageTitle also unused: this is a routine background
					// refresh of an already-named feed, not the
					// LocalAccountDelegate.createFeed add-time path -- a
					// refresh must never overwrite a name the person may
					// have hand-edited since the feed was created.
					_ = hasNextPage
					let articleChanges = await account.updateAsync(feedID: feed.feedID, parsedItems: Set(parsedItems), deleteOlder: false)
					account.sendNotificationAbout(articleChanges)
					feed.ao3SearchFetchedPages = [1]
					feed.ao3SearchTotalPages = totalPages
					if let activityOwner {
						ActivityLog.shared.didComplete(activityOwner, kind: activityKind, message: "\(parsedItems.count) work\(parsedItems.count == 1 ? "" : "s") found")
					}
				case .noResults(_, let totalPages):
					if let totalPages {
						feed.ao3SearchTotalPages = totalPages
					}
					if let activityOwner {
						ActivityLog.shared.didComplete(activityOwner, kind: activityKind, message: "No results")
					}
				case .registrationRequired:
					self.reportFeedRefreshError(feed: feed, error: NSError(domain: "Nectar", code: -1, userInfo: [NSLocalizedDescriptionKey: "Restricted to registered AO3 users"]), activityKind: activityKind)
				case .rateLimited:
					// Distinct message, not the generic catch-all below --
					// Downloader.shared has already started its own per-host
					// cooldown by the time this returns (see
					// AO3SearchResultsFetcher's doc comment).
					self.reportFeedRefreshError(feed: feed, error: NSError(domain: "Nectar", code: -1, userInfo: [NSLocalizedDescriptionKey: "AO3 rate limit hit -- backing off before retrying"]), activityKind: activityKind)
				case .cloudflareChallenge(let challengedURL):
					// Also distinct: this
					// isn't AO3's own rate limit and shouldn't be read as one,
					// nor folded into the generic parse-failure case, since a
					// real markup change looks identical otherwise.
					//
					// Recorded so Settings' "Verify Browser Access" solver
					// (AO3ChallengeSolverViewController) can default to the
					// actual URL that got challenged, rather than a generic
					// AO3 page that may not exercise the same gate -- see
					// AO3ChallengeSessionStore.lastChallengedURL's doc comment.
					AO3ChallengeSessionStore.lastChallengedURL = challengedURL
					self.reportFeedRefreshError(feed: feed, error: NSError(domain: "Nectar", code: -1, userInfo: [NSLocalizedDescriptionKey: "Blocked by a Cloudflare challenge -- try again later"]), activityKind: activityKind)
				case .notSignedIn:
					// Reachable here on a background/scheduled refresh of an
					// always-authenticated listing feed whose stored AO3
					// session is missing or was rejected -- e.g. signed out
					// in Settings after the feed was added. Distinct
					// messaging from .registrationRequired above, matching
					// AccountError.ao3ListingRequiresSignIn's copy.
					self.reportFeedRefreshError(feed: feed, error: NSError(domain: "Nectar", code: -1, userInfo: [NSLocalizedDescriptionKey: "This feed requires a signed-in AO3 account"]), activityKind: activityKind)
				}
			} catch {
				Self.logger.error("LocalAccountRefresher: AO3 search-results fetch failed for \(url.absoluteString): \(error.localizedDescription)")
				self.reportFeedRefreshError(feed: feed, error: error, activityKind: activityKind)
			}
		}
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

			let (parsedFeed, feedIsPartial, cutoffReason) = await self.mergedParsedFeed(startingWith: firstPageParsedFeed, originalURL: url, owner: activityOwner, activityKind: activityKind)
			let cutoffSuffix = cutoffReason.map { " — \($0.logMessage)" } ?? ""

			guard let account = feed.account else {
				if let activityOwner {
					ActivityLog.shared.didComplete(activityOwner, kind: activityKind, message: dataSizeMessage + cutoffSuffix)
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

			// AO3PrefetchNewWorksPreference's opt-in "fetch new works
			// immediately" path -- deliberately only hooked into this
			// ordinary RSS/Atom updateAsync call, not
			// fetchAndImportAO3SearchResults's own updateAsync call
			// below, so AO3 search-results-feed items keep their existing
			// "no proactive content fetch" treatment unchanged. Filtering
			// on ao3WorkID(fromBookKey:) and isAO3NetworkRequestAllowed
			// here (rather than leaving it to fetchIfNeeded alone) keeps
			// non-AO3 and Ambrosia-network-disabled articles from
			// spending a slot of AO3PrefetchQueue's bounded per-cycle
			// budget on a call that was always going to no-op.
			if AO3PrefetchNewWorksPreference.isEnabled, let newArticles = articleChanges.new, !newArticles.isEmpty {
				// articleChanges.new is a Set<Article> (see ArticleChanges in
				// ArticlesDatabase.swift); AO3PrefetchQueue.enqueue(_:) takes
				// [Article], so this needs an explicit Array(...) conversion
				// rather than relying on filter's return type.
				let candidates: [Article] = Array(newArticles).filter { article in
					AO3ChapterFetcher.ao3WorkID(fromBookKey: article.bookKey) != nil
						&& AO3ChapterFetcher.isAO3NetworkRequestAllowed(for: article)
				}
				if !candidates.isEmpty {
					Task {
						await AO3PrefetchQueue.shared.enqueue(candidates)
					}
				}
			}

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
				ActivityLog.shared.didComplete(activityOwner, kind: activityKind, message: dataSizeMessage + cutoffSuffix)
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

	/// Why pagination stopped short of a `nil` `next_url` -- distinct from
	/// `isPartial`, which only says *that* a feed came back incomplete.
	/// Surfaced in the Activity Log completion message so a cut-off feed
	/// is visible there and not just in `os_log`.
	private enum PaginationCutoffReason {
		case deadlineReached(afterPages: Int)
		case pageFetchFailed(page: Int)
		case pageParseFailed(page: Int)
		case pageLimitReached(limit: Int)

		var logMessage: String {
			switch self {
			case .deadlineReached(let afterPages):
				return "stopped early after \(afterPages) page\(afterPages == 1 ? "" : "s") — background time limit reached"
			case .pageFetchFailed(let page):
				return "stopped — page \(page) fetch failed"
			case .pageParseFailed(let page):
				return "stopped — page \(page) failed to parse"
			case .pageLimitReached(let limit):
				return "stopped — hit \(limit)-page safety limit"
			}
		}
	}

	private func mergedParsedFeed(startingWith parsedFeed: ParsedFeed, originalURL: URL, owner: ActivityOwner?, activityKind: ActivityKind) async -> (feed: ParsedFeed, isPartial: Bool, cutoffReason: PaginationCutoffReason?) {
		var mergedItems = parsedFeed.items
		var currentNextURLString = parsedFeed.nextURL
		var pageCount = 1
		var isPartial = false
		var cutoffReason: PaginationCutoffReason?

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
				cutoffReason = .deadlineReached(afterPages: pageCount)
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
					cutoffReason = .pageFetchFailed(page: pageNumber)
					break
				}
				// Use originalURL (the feed's base URL), not nextURL (this page's
				// URL), as the ParserData url. ParsedItem.feedURL feeds directly
				// into calculatedArticleID(feedID:uniqueID:) for any item without
				// a syncServiceID (all Ambrosia items), while ArticlesTable.update
				// computes the persisted Article's articleID from the constant
				// feedID argument (the base URL) instead. Using nextURL here made
				// every item merged in from page 2 onward hash to a different
				// articleID than its own articles-table row, so the statuses
				// table wrote real rows under an articleID the natural join in
				// fetchArticlesWithWhereClause could never match -- silently
				// dropping every article past page 1 from every fetch with no
				// error anywhere.
				let pageParserData = ParserData(url: originalURL.absoluteString, data: pageData)
				guard let pageParsedFeed = try await FeedParser.parse(pageParserData) else {
					Self.logger.error("LocalAccountRefresher: next_url page \(pageNumber) parse returned nil for \(nextURL.absoluteString)")
					isPartial = true
					cutoffReason = .pageParseFailed(page: pageNumber)
					break
				}
				mergedItems.formUnion(pageParsedFeed.items)
				currentNextURLString = pageParsedFeed.nextURL
				pageCount += 1
				if let owner {
					let detail = ActivityLog.shared.nextTaskNumberString()
					ActivityLog.shared.logCompletedActivity(owner: owner, kind: activityKind, detail: detail, message: "Page \(pageNumber) fetched — \(pageParsedFeed.items.count) item\(pageParsedFeed.items.count == 1 ? "" : "s"), \(mergedItems.count) total so far")
				}
			} catch {
				Self.logger.error("LocalAccountRefresher: next_url page \(pageNumber) fetch error for \(nextURL.absoluteString): \(error.localizedDescription)")
				isPartial = true
				cutoffReason = .pageFetchFailed(page: pageNumber)
				break
			}
		}

		if pageCount >= Self.maxPaginationPages && currentNextURLString != nil {
			Self.logger.error("LocalAccountRefresher: hit maxPaginationPages (\(Self.maxPaginationPages)) for \(originalURL.absoluteString) with more pages remaining -- treating as partial")
			isPartial = true
			cutoffReason = .pageLimitReached(limit: Self.maxPaginationPages)
		}

		guard pageCount > 1 else {
			return (parsedFeed, isPartial, cutoffReason)
		}

		Self.logger.notice("LocalAccountRefresher: merged \(pageCount) next_url pages for \(originalURL.absoluteString), \(mergedItems.count) total items, isPartial: \(isPartial)")

		let mergedFeed = ParsedFeed(type: parsedFeed.type, title: parsedFeed.title, homePageURL: parsedFeed.homePageURL, feedURL: parsedFeed.feedURL, language: parsedFeed.language, feedDescription: parsedFeed.feedDescription, nextURL: nil, iconURL: parsedFeed.iconURL, faviconURL: parsedFeed.faviconURL, authors: parsedFeed.authors, expired: parsedFeed.expired, hubs: parsedFeed.hubs, items: mergedItems)
		return (mergedFeed, isPartial, cutoffReason)
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

extension LocalAccountRefresher {

	/// These hosts will never return a feed.
	///
	/// People may still have feeds pointing to Twitter due to our prior
	/// use of the Twitter API. (Which Twitter took away.)
	private static let badHosts = ["twitter.com", "www.twitter.com", "x.com", "www.x.com"]

	/// Returns whether this feed should be skipped and the reason if so.
	///
	/// Most Nectar feeds are routes on the user's own local Ambrosia server
	/// (this fork restricts account creation to `.onMyMac`), which is why
	/// there is deliberately no general minimum-time-between-checks /
	/// Cache-Control throttle here of the kind upstream NetNewsWire applies
	/// to every feed host: refreshing on demand (pull-to-refresh, or right
	/// after a re-scan on the Mac) must always go through for those feeds.
	///
	/// That reasoning does NOT extend to every feed Nectar fetches, though:
	/// Nectar also subscribes directly to AO3's own tag/user RSS/Atom feeds
	/// (see AO3IgnoreList/AO3SummaryExtractor), which *is* a public site
	/// this app should be polite to. AO3 listing pages (search/tag
	/// results, author works, bookmarks, marked-for-later, subscriptions,
	/// collections, series) get an explicit, narrower throttle below
	/// (feedShouldBeSkippedForAO3SearchResultsReasons); ordinary AO3
	/// tag/user Atom/RSS feed URLs are NOT covered by that check today and
	/// have no proactive throttle here at all, relying only on
	/// Downloader's reactive per-host 429/Cloudflare-challenge handling.
	/// That gap is tracked, not yet resolved either way -- don't assume it
	/// needs fixing; it may be fine as-is given how aggressively AO3 already
	/// rate-limits.
	private static func feedShouldBeSkipped(_ feed: Feed, _ redditURLToRefresh: String?) -> (Bool, String?) {
		let (skipForDisallowedHost, disallowedHostReason) = feedShouldBeSkippedForDisallowedHostReasons(feed)
		if skipForDisallowedHost {
			return (true, disallowedHostReason)
		}
		let (skipForAO3Search, ao3SearchReason) = feedShouldBeSkippedForAO3SearchResultsReasons(feed)
		if skipForAO3Search {
			return (true, ao3SearchReason)
		}
		let (skipForReddit, redditReason) = feedShouldBeSkippedForRedditReasons(feed, redditURLToRefresh)
		if skipForReddit {
			return (true, redditReason)
		}
		return (false, nil)
	}

	/// AO3 listing feeds (search/tag results, author works, bookmarks,
	/// marked-for-later, subscriptions, collections, series -- see
	/// `isAO3ListingFeed(_:)`) are a deliberate, permanent exception to
	/// this file's stated "no minimum time between checks" design (see this
	/// function's siblings below, and the `nectar-import://` scheme's
	/// permanent exclusion in feedShouldBeSkippedForDisallowedHostReasons,
	/// which this cross-references). A normal scheduled/background/
	/// pull-to-refresh pass never re-fetches an AO3 listing feed's page 1 --
	/// only the one-off add-time fetch (lastCheckDate == nil) and the
	/// explicit "load more" / future "check for new results" paths
	/// (AO3SearchResultsPaginator) touch it after that.
	private static func feedShouldBeSkippedForAO3SearchResultsReasons(_ feed: Feed) -> (Bool, String?) {
		guard let url = url(for: feed), Self.isAO3ListingFeed(url) else {
			return (false, nil)
		}
		guard feed.lastCheckDate != nil else {
			return (false, nil) // first fetch (add-time) always goes through
		}
		return (true, "Skipped — AO3 listing pages only refresh when added, checked manually, or paginated")
	}

	/// Reddit rate-limits to one feed per minute, so we
	/// refresh the least recently checked one.
	private static func redditURLToRefresh(in feeds: Set<Feed>) -> String? {
		let redditFeeds = feeds.filter { SpecialCase.urlStringMatchesDomain($0.url, [SpecialCase.redditHostName]) }
		let winner = redditFeeds.min { ($0.lastCheckDate ?? .distantPast) < ($1.lastCheckDate ?? .distantPast) }
		return winner?.url
	}

	private static func feedShouldBeSkippedForRedditReasons(_ feed: Feed, _ redditURLToRefresh: String?) -> (Bool, String?) {
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

	private static func feedShouldBeSkippedForDisallowedHostReasons(_ feed: Feed) -> (Bool, String?) {
		guard let url = url(for: feed) else {
			return (true, "Skipped — invalid URL")
		}

		// The pasted-AO3-link-list import feed (Account.importedLinksFeedURL)
		// has no real server behind it -- its articles are written directly
		// via updateAsync, never fetched. Permanently excluded here, not just
		// this-pass-skipped: unlike badHosts below, a later refresh attempt
		// would never succeed, so there's no reason to keep retrying it.
		if url.scheme?.lowercased() == "nectar-import" {
			return (true, "Skipped — one-time import, no server to refresh from")
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

	/// Resolves the URL actually fetched for `feed`. When the Ambrosia
	/// transfer-format preference is set to `.sqlite` and `feed.url` is a
	/// recognized Ambrosia JSON route (per `AmbrosiaFeedIdentity`), swaps the
	/// `.json` suffix for `.sqlite` -- applies uniformly to every
	/// Ambrosia-paired feed, no per-feed override. Note: this only
	/// affects which URL DownloadSession is asked to fetch; DownloadSession
	/// itself still treats the result as an ordinary feed request; the actual
	/// `.sqlite`-vs-`.json` handling (decompression, import) happens where
	/// callers act on the fetched feed URL for Ambrosia-identified accounts,
	/// not inside DownloadSession.
	/// Any AO3 URL shape whose page AO3 renders with the same "listing"
	/// markup (`.index.group` blurb rows + `ol.pagination` pager) that
	/// `AO3SearchResultsExtractor`/`AO3ListingPagination` already parse
	/// generically -- search/tag results, an author's works, someone's
	/// bookmarks, marked-for-later/reading history, subscriptions, a
	/// public collection's works, or a series. Originally named
	/// `isAO3SearchResultsFeed` when it matched only the first two of
	/// these; renamed once it grew to cover the rest (see
	/// `nectar-toolbar-ao3-listing-feeds.md`'s broadening item) --
	/// `Feed.isAO3SearchResultsFeed`'s public wrapper keeps its old name
	/// for now since it's a public API surface iOS depends on for the
	/// "load more results" footer, which applies identically to every
	/// shape matched here, not just search/tag results.
	///
	/// Matched on host (reusing `AO3LinkListImporter.permittedHosts`, the
	/// same AO3-domain allowlist Task 3's paste-import already trusts,
	/// rather than a fresh single-host check) + path shape, deliberately
	/// not by file extension. Exact shapes, verbatim from
	/// `nectar-toolbar-ao3-listing-feeds.md`'s URL-shape table (sourced
	/// from `ao3downloader`, since AO3 itself documents none of this):
	///
	/// - `/works?work_search[...]` -- requires a `work_search[`-prefixed
	///   query key (matched with `hasPrefix`, not an exact key, since AO3
	///   search URLs carry many distinct bracketed keys).
	/// - `/tags/<tag>/works` -- no such query key; path shape alone
	///   (`/tags/` prefix, `/works` suffix) identifies it.
	/// - `/users/<name>/works` and the pseud-scoped
	///   `/users/<name>/pseuds/<pseud>/works` -- an author's works page.
	/// - `/users/<name>/bookmarks` -- someone's bookmarks (public or, if
	///   private, gated behind login at fetch time -- see item 4 in the
	///   planning doc, not this classifier).
	/// - `/users/<name>/readings` with a `show=to-read` query -- marked
	///   for later / reading history. This exact query string, not a
	///   guess (`ao3downloader`'s `shared.py`,
	///   `marked_for_later_link()`) -- `/users/<name>/readings` alone
	///   (no query, or a different `show=` value) is a different AO3
	///   page (reading history without the to-read filter) and is
	///   deliberately not matched here.
	/// - `/users/<name>/subscriptions` -- subscriptions (query string and
	///   trailing slash ignored, same as `ao3downloader`'s own
	///   `is_subscriptions`).
	/// - `/collections/<name>/works` -- a public collection's works.
	/// - `/series/<digits>` -- a series. Deliberately scoped to *this*
	///   classifier's two call sites (create-feed, refresh-skip) only:
	///   `AO3SeriesListingExtractor`/`AO3SeriesNavigator`'s existing
	///   inline-series-navigation feature (jump-to-first-work, series
	///   walking from a work's own page) never calls this function --
	///   confirmed by grep, not assumed -- so widening the match here
	///   cannot turn an existing series-navigation fetch into an
	///   accidental "subscribe as a feed." See
	///   `LocalAccountRefresherRoutingTests.swift` for the dedicated
	///   non-collision coverage.
	internal static func isAO3ListingFeed(_ url: URL) -> Bool {
		guard let host = url.host()?.lowercased(), AO3LinkListImporter.permittedHosts.contains(host) else {
			return false
		}

		let path = url.path

		if path.hasPrefix("/tags/") && path.hasSuffix("/works") {
			return true
		}

		if path == "/works" {
			guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = components.queryItems else {
				return false
			}
			return queryItems.contains { $0.name.hasPrefix("work_search[") }
		}

		if path.hasPrefix("/users/") && path.hasSuffix("/works") {
			// Covers both `/users/<name>/works` and the pseud-scoped
			// `/users/<name>/pseuds/<pseud>/works` -- both end in
			// `/works` with no further shape distinction needed.
			return true
		}

		if path.hasPrefix("/users/") && path.hasSuffix("/bookmarks") {
			return true
		}

		if path.hasPrefix("/users/") && path.hasSuffix("/readings") {
			guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = components.queryItems else {
				return false
			}
			return queryItems.contains { $0.name == "show" && $0.value == "to-read" }
		}

		// Subscriptions: query string and trailing slash ignored, path
		// shape alone (ends with "/subscriptions") identifies it --
		// mirrors ao3downloader's own is_subscriptions.
		if path.hasPrefix("/users/") {
			let trimmedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
			if trimmedPath.hasSuffix("/subscriptions") {
				return true
			}
		}

		if path.hasPrefix("/collections/") && path.hasSuffix("/works") {
			return true
		}

		if path.hasPrefix("/series/") {
			let digits = path.dropFirst("/series/".count)
			return !digits.isEmpty && digits.allSatisfy(\.isNumber)
		}

		return false
	}

	/// Deprecated name for `isAO3ListingFeed(_:)` -- kept only as a thin
	/// forwarder during the broadening (see that function's doc comment)
	/// so any not-yet-updated call site still compiles; new code should
	/// call `isAO3ListingFeed(_:)` directly. Remove once nothing
	/// references this name.
	@available(*, deprecated, renamed: "isAO3ListingFeed")
	internal static func isAO3SearchResultsFeed(_ url: URL) -> Bool {
		isAO3ListingFeed(url)
	}

	/// Whether `url` is one of the two AO3 listing shapes that are
	/// always-yours and always-private -- subscriptions and
	/// marked-for-later/reading-history -- and therefore must go through
	/// `AO3SearchResultsFetcher.fetchRequiringSignIn(url:feedURL:)`
	/// rather than the plain anonymous `fetch(url:feedURL:)`. A static,
	/// page-type-level property, not something detected from the fetch
	/// response itself (see `nectar-toolbar-ao3-listing-feeds.md`'s "Auth
	/// requirement per listing type" table) -- someone's bookmarks are
	/// only *sometimes* gated (public-vs-private per user) and so are
	/// deliberately not included here; that case is left to the ordinary
	/// anonymous-fetch-then-registration-wall path like any other listing
	/// type, same as today.
	///
	/// Callers must already have confirmed `isAO3ListingFeed(url)` is
	/// true before calling this -- it doesn't re-check the host allowlist
	/// itself, since every existing call site already gates on
	/// `isAO3ListingFeed` first.
	internal static func isAlwaysAuthenticatedAO3ListingFeed(_ url: URL) -> Bool {
		let path = url.path
		guard path.hasPrefix("/users/") else {
			return false
		}
		if path.hasSuffix("/readings") {
			guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = components.queryItems else {
				return false
			}
			return queryItems.contains { $0.name == "show" && $0.value == "to-read" }
		}
		let trimmedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
		return trimmedPath.hasSuffix("/subscriptions")
	}

	private static func url(for feed: Feed) -> URL? {
		guard let url = URL(string: feed.url) else {
			return nil
		}
		guard AmbrosiaTransferFormatPreference.current == .sqlite,
		      AmbrosiaFeedIdentity.collectionKey(for: feed.url) != nil else {
			return url
		}
		let sqliteURLString = String(feed.url.dropLast(".json".count)) + ".sqlite"
		return URL(string: sqliteURLString) ?? url
	}

	/// Whether `error` represents a connection-level failure (couldn't reach the host
	/// at all) as opposed to the host responding with an HTTP-level error. Used to
	/// distinguish "your library's Mac is asleep/off" from an actual feed problem.
	private static func isConnectionLevelError(_ error: NSError) -> Bool {
		guard error.domain == NSURLErrorDomain else {
			return false
		}
		let connectionLevelCodes: Set<Int> = [
			NSURLErrorTimedOut,
			NSURLErrorCannotFindHost,
			NSURLErrorCannotConnectToHost,
			NSURLErrorNetworkConnectionLost,
			NSURLErrorNotConnectedToInternet,
			NSURLErrorDNSLookupFailed
		]
		return connectionLevelCodes.contains(error.code)
	}

	/// Whether `error` is a plain `NSURLErrorCancelled` -- i.e. something (our own
	/// `suspend()`, or the system) cancelled the request rather than the request
	/// failing on its own. Cancellation is not a feed error: it means the feed
	/// simply wasn't fetched this pass and needs retrying, not that anything is
	/// wrong with it.
	private static func isCancellationError(_ error: NSError) -> Bool {
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
