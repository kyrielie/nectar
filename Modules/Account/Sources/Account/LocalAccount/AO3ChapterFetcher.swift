import AO3Kit
//
//  AO3ChapterFetcher.swift
//  Account
//
//  Nectar AO3 direct-reading support, Workstream 2 ("On-demand chapter
//  fetch and storage"). Workstream 3
//  ("optional AO3 login") is layered on top of this file: see
//  the authenticated attempt in download(...) below and
//  AO3AuthenticatedFetcher.
//
//  Fetches an AO3 work's live page (`?view_full_work=true&view_adult=true`)
//  on demand and
//  persists the extracted, workskin-preserving contentHTML for any article
//  whose bookKey identifies it as an AO3 work ("ao3-work:<id>"). Modeled
//  directly on HTMLMetadataDownloader: same anti-hammering attemptDates gate, same
//  ActivityLog start/complete/fail calls, same "leave existing content alone
//  on failure, don't retry aggressively" shape. When a session is stored
//  (AO3SessionStore.isSignedIn), the primary fetch is the authenticated
//  one (AO3AuthenticatedFetcher, which attaches a Cookie header by hand and
//  shares Downloader's rate-limit cooldown), falling back to Downloader's
//  anonymous path only for a network error, an unexpected HTTP status, an
//  unrecognized page or a possibly-missing work. A rate limit, challenge,
//  AO3 503 page, unrevealed work, permission wall or adult gate ends the
//  fetch with no fallback, and a rejected session ends the session. Both
//  attempts are classified by AO3WorkPageClassifier and, when interactive,
//  retried once (AO3RetryPolicy). When signed out, the fetch goes straight
//  to the anonymous path. Downloader still forces httpShouldSetCookies =
//  false / .never cookie policy app-wide for every anonymous request.
//
//  ParsedItem reconstruction: Account.updateAsync(feedID:parsedItems:...) is
//  the only write path for contentHTML (no single-field "update just this"
//  API exists), and Article+Database.changesFrom diffs the incoming
//  ParsedItem against the existing Article field by field. That means every
//  field the existing Article already has must be copied into the rebuilt
//  ParsedItem unchanged -- only contentHTML and chapterCurrent actually
//  change here -- or an otherwise-ordinary "just update the content" fetch
//  would blank title/summary/fandoms/etc. on that article.
//
//  ao3WorkID for the refetch URL is recovered directly from the existing
//  article's own bookKey (stripping the "ao3-work:" prefix) rather than
//  needing isAnthology/ao3SeriesID/seriesName carried through the rebuild:
//  bookKey only resolves to "ao3-work:<id>" when isAnthology wasn't true to
//  begin with (anthology series id/name takes precedence -- see
//  ParsedItem.bookKey), so reconstructing with isAnthology left nil
//  reproduces the identical bookKey.
//

import Foundation
import os
import RSCore
import RSParser
import RSWeb
import Articles
import ActivityLog

nonisolated public final class AO3ChapterFetcher: Sendable {

	public static let shared = AO3ChapterFetcher()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AO3ChapterFetcher")

	// Was a flat 3-hour anti-hammering floor on retry attempts. Lowered to 1
	// minute once AO3PrefaceRefetchPreference's .always cadence existed --
	// 3 hours would have silently defeated "always" for any article reopened
	// sooner than that, and this floor's job is only to stop rapid re-opens
	// from firing the same request twice, not to pace legitimate refetches
	// (that's the cadence preference's job now).
	private static let secondsBetweenAttempts: TimeInterval = 60

	/// bookKey prefixes `ParsedItem.bookKey` uses for an anthology
	/// (`isAnthology == true`) -- see the doc comment on `bookKey` there.
	/// Neither ever resolves to an `ao3WorkID`, and never will: there's no
	/// single AO3 work URL to fetch for a Calibre-merged compilation of
	/// several separate works.
	private static let anthologyBookKeyPrefixes = [BookKeyPrefix.ao3Series, BookKeyPrefix.calibreSeries]

	// internal, not private -- AO3SeriesNavigator's bounded two-fetch
	// series-listing walk (Phase 4c of the inline series navigation plan)
	// reuses this exact pacing value between its page-1 and second-page
	// fetches, rather than inventing a second "don't hammer AO3" constant
	// for the same concern.
	static let secondsBetweenAO3PagedRequests: TimeInterval = 5

	private let attemptDates = OSAllocatedUnfairLock(initialState: [String: Date]())

	/// Human-readable reason the most recent fetch for an article didn't
	/// persist new content, keyed by articleID. Cleared on a subsequent
	/// success. Exists so a view showing the article can explain why full
	/// text isn't loading (see `lastFetchFailureMessage(forArticleID:)`)
	/// instead of the failure being visible only in the Activity Log.
	private let failures = OSAllocatedUnfairLock(initialState: [String: AO3FetchFailure]())

	/// The reason the most recent fetch attempt for this article failed, if
	/// any -- `nil` if the article has never had a failed fetch, or if its
	/// last fetch succeeded. Callers needing to react live to a new failure
	/// (rather than polling this after the fact) should observe
	/// `.ao3ChapterFetchDidFail` instead, which carries the same message.
	public func lastFetchFailureMessage(forArticleID articleID: String) -> String? {
		lastFetchFailure(forArticleID: articleID)?.localizedMessage
	}

	/// The typed reason the most recent fetch attempt for this article
	/// failed, or nil under the same conditions as
	/// `lastFetchFailureMessage(forArticleID:)`.
	public func lastFetchFailure(forArticleID articleID: String) -> AO3FetchFailure? {
		failures.withLock { $0[articleID] }
	}

	/// Who is waiting on a fetch. Only `.interactive` fetches retry (see
	/// `AO3RetryPolicy`).
	public enum Priority: Sendable {
		case interactive
		case background
	}

	/// Kicks off a fetch if `article` is an AO3-sourced article (per its
	/// bookKey) whose stored content looks stale or missing, and enough time
	/// has passed since the last attempt for this article. No-op for any
	/// other article -- including one with no resolvable ao3WorkID at all.
	/// Fire-and-forget; callers observe `.ao3ChapterFetchDidComplete` to know
	/// when to reload.
	///
	/// Read state is irrelevant here by design: this only ever runs from
	/// WebViewController.setArticle, i.e. the user has this article open
	/// right now, which is reason enough to honor the refetch cadence
	/// (AO3PrefaceRefetchPreference) regardless of whether it was marked
	/// read on a previous visit. `AO3FetchPolicy.isStale` and the anti-hammering floor in
	/// downloadIfNeeded are what actually decide whether a request goes out
	/// -- this function's only job is "the user opened this."
	///
	/// An anthology/combined-series bookKey (`ao3-series:`/
	/// `calibre-series:` -- see `ParsedItem.bookKey`) never resolves to an
	/// `ao3WorkID` at all: a Calibre-merged anthology isn't one AO3 work,
	/// so there's no single live page to refetch from (fetching and
	/// merging every member work was scoped out of Workstream 2 -- see
	/// docs/ao3-preface-rendering.md, "Anthology/combined-series
	/// articles"). That's out of scope to
	/// fix here, but leaving it a bare no-op made it indistinguishable
	/// from "nothing needed checking" -- `noteAnthologyUnsupportedIfNeeded`
	/// logs it once per article instead, so it shows up in the Activity
	/// Log rather than silently doing nothing forever.
	public func fetchIfNeeded(for article: Article, priority: Priority = .interactive) {
		guard let workID = AO3FetchPolicy.workID(fromBookKey: article.bookKey) else {
			noteAnthologyUnsupportedIfNeeded(for: article)
			return
		}
		guard AO3FetchPolicy.isStale(article) else {
			return
		}
		guard AO3FetchPolicy.isNetworkRequestAllowed(for: article) else {
			return
		}
		downloadIfNeeded(workID: workID, articleID: article.articleID, accountID: article.accountID, feedID: article.feedID, priority: priority)
	}

	/// Explicit "Check for updates" action -- always available per-article
	/// regardless of read state, unlike `fetchIfNeeded`'s automatic paths.
	/// There is deliberately no bulk "check all" equivalent: an unbounded
	/// bulk refetch across every subscribed AO3 work would be exactly the
	/// kind of unthrottled, server-unfriendly bulk fetch this fetcher's
	/// cadence-only staleness check (see docs/ao3-preface-rendering.md)
	/// exists to avoid; per-article is deliberate, not an oversight.
	/// Still a no-op for an anthology/combined-series bookKey (same as
	/// `fetchIfNeeded`), and still blocked while an unresolved
	/// `pendingUpdateContentHTML` diff exists for this article -- a second
	/// edit landing before the first pending diff is resolved must not
	/// silently overwrite the pending slot, so re-checking is blocked
	/// entirely until the person resolves it (see
	/// `Account.resolvePendingContentUpdateAsync`). Unlike `fetchIfNeeded`,
	/// this does not consult `AO3FetchPolicy.isStale`'s settled-cadence/regression-flag
	/// checks -- the whole point of an explicit user action is to check
	/// regardless of whether the article "looks" settled.
	/// Returns whether a request started: false when the article is not an
	/// individually refreshable AO3 work, a pending update is unresolved,
	/// the network gate refused, or the 60-second floor swallowed it.
	@discardableResult
	public func checkForUpdates(for article: Article) -> Bool {
		guard let workID = AO3FetchPolicy.workID(fromBookKey: article.bookKey) else {
			noteAnthologyUnsupportedIfNeeded(for: article)
			return false
		}
		guard article.pendingUpdateContentHTML == nil else {
			return false
		}
		guard AO3FetchPolicy.isNetworkRequestAllowed(for: article) else {
			return false
		}
		// This fetch is about to potentially change article's own chapter
		// content, which can shift its position within any series it
		// belongs to (a newly posted chapter can itself land as a new
		// series entry) -- invalidate any cached walk for those series so
		// AO3SeriesNavigator's .first shortcut (Fix 4) and Step 2 pagination
		// cache (Fix 5) don't keep trusting listing data this fetch may be
		// about to make stale. Called before downloadIfNeeded rather than
		// after, since the download itself is fire-and-forget from here
		// (Task { @MainActor in ... } inside download(...)) and there's no
		// completion point at this call site to hook a post-fetch
		// invalidation into instead.
		let ao3SeriesIDs = article.series?.compactMap(\.ao3ID) ?? []
		if !ao3SeriesIDs.isEmpty {
			AO3SeriesNavigator.invalidateWalk(feedID: article.feedID, ao3SeriesIDs: ao3SeriesIDs)
		}
		return downloadIfNeeded(workID: workID, articleID: article.articleID, accountID: article.accountID, feedID: article.feedID, priority: .interactive)
	}

}

// MARK: - Internal, directly testable

extension AO3ChapterFetcher {

	/// Logs the anthology/combined-series case to the Activity Log once
	/// per article (reusing `attemptDates` as the "already noted" gate, so
	/// reopening the same article repeatedly doesn't spam the log) instead
	/// of `fetchIfNeeded` silently doing nothing. Also records a
	/// `failures` entry for API consistency with the real-failure
	/// path, though it currently has nowhere to surface in the reader:
	/// `ArticleRenderer`'s inline notice only shows when `contentHTML ==
	/// nil`, which is never true for an Ambrosia-sourced article (see
	/// `ao3SyntheticPrefaceHTML`'s doc comment).
	///
	/// Nonisolated, like `fetchIfNeeded` itself -- the "already noted"
	/// check runs synchronously against the lock-protected `attemptDates`
	/// dictionary, and only the actual ActivityLog/notification work hops
	/// to the main actor, mirroring `downloadIfNeeded`/`download` below.
	func noteAnthologyUnsupportedIfNeeded(for article: Article) {
		guard Self.anthologyBookKeyPrefixes.contains(where: { article.bookKey.hasPrefix($0) }) else {
			return
		}
		let alreadyNoted = attemptDates.withLock { dates in
			if dates[article.articleID] != nil {
				return true
			}
			dates[article.articleID] = .distantPast
			return false
		}
		guard !alreadyNoted else {
			return
		}

		let articleID = article.articleID
		let bookKey = article.bookKey
		Task { @MainActor in
			let activityLog = ActivityLog.shared
			let kind = ActivityKind.skipAO3SeriesFetch(bookKey: bookKey)
			activityLog.createActivity(owner: .ao3ChapterFetcher, kind: kind, detail: nil)
			activityLog.didStart(.ao3ChapterFetcher, kind: kind)
			self.fail(articleID: articleID, kind: kind, activityLog: activityLog, failure: .anthologyNotRefreshable)
		}
	}
}

// MARK: - Private

nonisolated extension AO3ChapterFetcher {

	/// Returns whether a request actually started: false when the 60-second
	/// floor swallowed the attempt.
	@discardableResult
	private func downloadIfNeeded(workID: String, articleID: String, accountID: String, feedID: String, priority: Priority) -> Bool {
		let shouldDownload = attemptDates.withLock { dates in
			let currentDate = Date()
			if let attemptDate = dates[articleID], attemptDate > currentDate.addingTimeInterval(-Self.secondsBetweenAttempts) {
				return false
			}
			dates[articleID] = currentDate
			return true
		}

		if shouldDownload {
			download(workID: workID, articleID: articleID, accountID: accountID, feedID: feedID, priority: priority)
		}
		return shouldDownload
	}

	/// The shared fetch flow. Signed in: an authenticated attempt first,
	/// classified by `AO3WorkPageClassifier`. A rate limit, a Cloudflare
	/// challenge, AO3's 503 page, an unrevealed work, a permission wall and
	/// the adult gate end the fetch with no anonymous fallback; a rejected
	/// session ends the session; anything else falls back to one anonymous
	/// attempt. The missing flag is set only on positive evidence from the
	/// anonymous attempt, plus the same evidence from the authenticated one
	/// when signed in. Each attempt gets one retry when interactive.
	internal func download(workID: String, articleID: String, accountID: String, feedID: String, priority: Priority = .interactive) {
		guard let url = AO3Link.workURL(id: workID, fullWork: true, adultView: true) else {
			return
		}

		Task { @MainActor in
			let activityLog = ActivityLog.shared
			let kind = ActivityKind.fetchAO3Chapter(workID: workID)
			let interactive = priority == .interactive

			activityLog.createActivity(owner: .ao3ChapterFetcher, kind: kind, detail: nil)
			activityLog.didStart(.ao3ChapterFetcher, kind: kind)

			let signedIn = AO3SessionStore.isSignedIn
			// True once an authenticated request actually went out. A
			// signed-in fetch that found no session to send (concurrent
			// sign-out) made no attempt, so it cannot be required to
			// confirm a missing work.
			var authenticatedAttemptMade = signedIn
			var authenticatedAttemptSawMissing = false

			if signedIn {
				let attempt = await AO3RetryPolicy.perform(interactive: interactive, url: url) {
					try await Self.authenticatedFetch(url: url)
				}
				switch attempt.result {
				case .success(let extraction):
					await self.finishSuccessfulFetch(extraction: extraction, workID: workID, articleID: articleID, accountID: accountID, feedID: feedID, activityLog: activityLog, kind: kind, dataSizeMessage: ActivityLog.dataSizeMessage(attempt.data ?? Data()), returnedFromCache: false)
					return
				case .failure(let failure):
					switch failure {
					case .registrationRequired:
						// The stored session itself is what AO3 rejected,
						// which is distinct from never having signed in.
						// Ending it makes the next fetch and the Settings
						// sign-in row reflect reality, and records why.
						AO3SessionStore.endSession(reason: .rejectedByAO3)
						fail(articleID: articleID, kind: kind, activityLog: activityLog, failure: .sessionEnded)
						return
					case .rateLimited, .challenge, .serviceUnavailable, .hiddenUntilRevealed, .permissionDenied, .adultGate:
						// Terminal: an anonymous request would meet the
						// same limit, challenge or wall.
						fail(articleID: articleID, kind: kind, activityLog: activityLog, failure: failure)
						return
					case .workMissing:
						// Not enough alone to confirm the work is gone;
						// remembered for the dual-confirmation rule below.
						authenticatedAttemptSawMissing = true
						activityLog.updateProgress(.ao3ChapterFetcher, kind: kind, message: "AO3 authenticated fetch found nothing -- retrying anonymously before confirming missing")
					case .signInRequired:
						// The session was cleared between the isSignedIn
						// check and the request.
						authenticatedAttemptMade = false
						activityLog.updateProgress(.ao3ChapterFetcher, kind: kind, message: "AO3 authenticated fetch reported no session unexpectedly -- retrying anonymously")
					default:
						// Network error, unexpected HTTP status or an
						// unrecognized page: not a login problem, so the
						// session is left alone.
						activityLog.updateProgress(.ao3ChapterFetcher, kind: kind, message: "AO3 authenticated fetch failed (\(failure.localizedMessage)) -- retrying anonymously")
					}
				}
			}

			let anonymous = await AO3RetryPolicy.perform(interactive: interactive, url: url) {
				try await Self.anonymousFetch(url: url)
			}
			switch anonymous.result {
			case .success(let extraction):
				await self.finishSuccessfulFetch(extraction: extraction, workID: workID, articleID: articleID, accountID: accountID, feedID: feedID, activityLog: activityLog, kind: kind, dataSizeMessage: ActivityLog.dataSizeMessage(anonymous.data ?? Data()), returnedFromCache: anonymous.returnedFromCache)
			case .failure(let failure):
				// Only positive evidence (HTTP 404/410 or AO3's explicit
				// not-found copy) sets ao3ConfirmedMissingAt, and when an
				// authenticated attempt was made it must have seen the same
				// evidence. Every other failure is transient.
				if failure.evidencesMissing, !authenticatedAttemptMade || authenticatedAttemptSawMissing,
				   let account = AccountManager.shared.existingAccount(accountID: accountID) {
					await account.setAO3ConfirmedMissingAsync(forArticleID: articleID)
				}
				if failure == .unrecognizedPage {
					// Logged on its own so real deleted-work page shapes
					// can be learned from the Activity Log.
					activityLog.updateProgress(.ao3ChapterFetcher, kind: kind, message: "AO3 returned a page Nectar does not recognize -- not treating the work as missing")
				}
				fail(articleID: articleID, kind: kind, activityLog: activityLog, failure: failure)
			}
		}
	}

	private static func authenticatedFetch(url: URL) async throws -> AO3WorkPageFetch {
		switch try await AO3AuthenticatedFetcher.fetch(url) {
		case .noSession:
			return .failure(.signInRequired)
		case .rateLimited(let until):
			return .failure(.rateLimited(until: until))
		case .response(let data, let response):
			return AO3WorkPageFetch(result: AO3WorkPageClassifier.classify(data: data, statusCode: response.statusCode), data: data)
		}
	}

	/// Goes through `Downloader`, which holds the shared per-host cooldown. An
	/// interstitial body (Cloudflare challenge, AO3's 503 page) is vetoed from
	/// its cache so a transient block is never replayed.
	private static func anonymousFetch(url: URL) async throws -> AO3WorkPageFetch {
		let downloadResponse = try await Downloader.shared.download(url, shouldCache: { data, _ in
			guard let data, let html = String(data: data, encoding: .utf8) else {
				return true
			}
			return !AO3WorkPageClassifier.isInterstitial(html)
		})
		let statusCode = downloadResponse.response?.forcedStatusCode
		return AO3WorkPageFetch(result: AO3WorkPageClassifier.classify(data: downloadResponse.data, statusCode: statusCode), data: downloadResponse.data, returnedFromCache: downloadResponse.returnedFromCache)
	}

	/// Shared success tail for both the authenticated-first path and the
	/// anonymous fallback path in `download` -- persists `extraction`,
	/// completes the Activity Log entry, clears any stale failure/missing
	/// state, and fires the kudos-on-like piggyback. Factored out so the
	/// two call sites (authenticated success, anonymous success) can't
	/// drift apart; `dataSizeMessage`/`returnedFromCache` are threaded
	/// through rather than recomputed here since each path's underlying
	/// `Data`/cache-hit info comes from a different fetch primitive
	/// (`Downloader.shared` vs. `AO3AuthenticatedFetcher`, the latter never
	/// cached).
	@MainActor
	private func finishSuccessfulFetch(extraction: AO3ChapterExtractionResult, workID: String, articleID: String, accountID: String, feedID: String, activityLog: ActivityLog, kind: ActivityKind, dataSizeMessage: String, returnedFromCache: Bool) async {
		guard let account = AccountManager.shared.existingAccount(accountID: accountID) else {
			fail(articleID: articleID, kind: kind, activityLog: activityLog, failure: .accountMissing)
			return
		}
		let existingArticles = await account.fetchArticlesAsync(.articleIDs([articleID]))
		guard let existingArticle = existingArticles.first else {
			fail(articleID: articleID, kind: kind, activityLog: activityLog, failure: .articleMissing)
			return
		}

		// Task 8's Ambrosia local-only toggle: gates whether this
		// fetch happened at all (AO3FetchPolicy.isNetworkRequestAllowed, above
		// download), not what gets applied from it -- content and
		// stats are always applied together from a fetch that was
		// allowed to happen. Always true for a non-Ambrosia
		// article. Content is still protected independently by the
		// regression guard directly below, same as before this
		// flag was collapsed to one.
		let applyStatsUpdate = !existingArticle.isAmbrosiaItem || AmbrosiaAO3NetworkPreference.updatesEnabled

		// Task 8's content-level regression guard: don't overwrite
		// silently, and don't discard the new fetch either -- keep
		// the currently-stored content as canonical and stash the
		// new fetch as a pending update for the reader to review.
		if let regressionDescription = AO3FetchPolicy.detectRegression(existingArticle: existingArticle, extraction: extraction) {
			await account.setPendingContentUpdateAsync(extraction.contentHTML, forArticleID: articleID)
			activityLog.didComplete(.ao3ChapterFetcher, kind: kind, message: "Possible content regression detected (\(regressionDescription)) -- kept existing content, flagged for review", returnedFromCache: returnedFromCache)
			failures.withLock { $0[articleID] = nil }
			postNotification(name: .ao3ChapterFetchDidComplete, articleID: articleID)
			// The CSRF token this fetch obtained is still good for a
			// kudos attempt even though the content write itself was
			// held back -- see the non-regression path's identical
			// call below for why this is safe/idempotent.
			AO3KudosManager.attemptKudosIfNeeded(article: existingArticle, workID: workID, csrfToken: extraction.csrfToken)
			return
		}

		let parsedItem = AO3FetchPolicy.rebuildParsedItem(from: existingArticle, workID: workID, extraction: extraction, applyStatsUpdate: applyStatsUpdate)
		_ = await account.updateAsync(feedID: feedID, parsedItems: [parsedItem], deleteOlder: false)

		activityLog.didComplete(.ao3ChapterFetcher, kind: kind, message: dataSizeMessage, returnedFromCache: returnedFromCache)
		failures.withLock { $0[articleID] = nil }
		// A successful fetch means the work is reachable again --
		// either it was a false-positive gate/404, or the author
		// restored it. Clear so AO3FetchPolicy.isStale can consider this article
		// for auto-fetch again instead of being permanently
		// skipped from a stale confirmed-missing flag.
		await account.clearAO3ConfirmedMissingAsync(forArticleID: articleID)
		// Same reasoning for the feed-derived regression flag: this
		// fetch passed the content-level guard, so the flag no longer
		// has a reason to block auto-fetch. Not cleared on the
		// regression path above -- that path stashes a pending update
		// and the flag clears when the reader resolves it.
		await account.clearWordCountRegressionFlagAsync(forArticleID: articleID)
		postNotification(name: .ao3ChapterFetchDidComplete, articleID: articleID)

		// Task 6 (kudos-on-like), piggyback path: this fetch's
		// response already carried a CSRF token (extraction.csrfToken),
		// so if this book is loved and hasn't had a kudos landed
		// for it yet, leave one now instead of firing a second,
		// dedicated request. existingArticle.status.loved is read
		// before rebuildParsedItem/updateAsync above, but loved
		// isn't a field either of those touch, so it still
		// reflects the book's current state. No-op (including
		// when the feature is off) -- see
		// AO3KudosManager.attemptKudosIfNeeded's own eligibility
		// checks.
		AO3KudosManager.attemptKudosIfNeeded(article: existingArticle, workID: workID, csrfToken: extraction.csrfToken)
	}

	/// Records `failure` as the article's current failure reason, logs it to
	/// the Activity Log, and posts `.ao3ChapterFetchDidFail` (whose `message`
	/// is the failure's localized text) so an already-visible article view can
	/// react immediately rather than waiting for the next fetch attempt.
	@MainActor
	private func fail(articleID: String, kind: ActivityKind, activityLog: ActivityLog, failure: AO3FetchFailure) {
		let message = failure.localizedMessage
		let loggedError = NSError(domain: "Nectar", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
		activityLog.didFail(.ao3ChapterFetcher, kind: kind, error: loggedError)
		failures.withLock { $0[articleID] = failure }
		postNotification(name: .ao3ChapterFetchDidFail, articleID: articleID, message: message)
	}

	private func postNotification(name: Notification.Name, articleID: String, message: String? = nil) {
		var userInfo: [String: Any] = [AO3ChapterFetchUserInfoKey.articleID: articleID]
		if let message {
			userInfo[AO3ChapterFetchUserInfoKey.message] = message
		}
		NotificationCenter.default.postOnMainThread(
			name: name, object: self, userInfo: userInfo
		)
	}
}
