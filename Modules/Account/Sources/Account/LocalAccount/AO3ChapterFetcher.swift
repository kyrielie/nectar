//
//  AO3ChapterFetcher.swift
//  Account
//
//  Nectar AO3 direct-reading support, Workstream 2 ("On-demand chapter
//  fetch and storage"). Workstream 3
//  ("optional AO3 login") is layered on top of this file: see
//  attemptAuthenticated(...) below and AO3AuthenticatedFetcher.
//
//  Fetches an AO3 work's live page (`?view_full_work=true&view_adult=true`)
//  on demand and
//  persists the extracted, workskin-preserving contentHTML for any article
//  whose bookKey identifies it as an AO3 work ("ao3-work:<id>"). Modeled
//  directly on HTMLMetadataDownloader: same anti-hammering attemptDates gate, same
//  ActivityLog start/complete/fail calls, same "leave existing content alone
//  on failure, don't retry aggressively" shape. When a session is stored
//  (AO3SessionStore.isSignedIn), the primary fetch is now the authenticated
//  one -- attemptAuthenticated(url:), which deliberately bypasses Downloader
//  (see its doc comment for why) and attaches a Cookie header by hand --
//  falling back to Downloader's anonymous path only on an
//  authentication-shaped failure (a rejected/expired session or a network
//  error on the authenticated attempt). When signed out, behavior is
//  unchanged: straight to the anonymous path, no authenticated attempt at
//  all. Downloader still forces httpShouldSetCookies = false / .never
//  cookie policy app-wide for every anonymous request either way.
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
	private static let ao3WorkIDBookKeyPrefix = "ao3-work:"

	/// bookKey prefixes `ParsedItem.bookKey` uses for an anthology
	/// (`isAnthology == true`) -- see the doc comment on `bookKey` there.
	/// Neither ever resolves to an `ao3WorkID`, and never will: there's no
	/// single AO3 work URL to fetch for a Calibre-merged compilation of
	/// several separate works.
	private static let anthologyBookKeyPrefixes = ["ao3-series:", "calibre-series:"]

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
	private let failureMessages = OSAllocatedUnfairLock(initialState: [String: String]())

	/// The reason the most recent fetch attempt for this article failed, if
	/// any -- `nil` if the article has never had a failed fetch, or if its
	/// last fetch succeeded. Callers needing to react live to a new failure
	/// (rather than polling this after the fact) should observe
	/// `.ao3ChapterFetchDidFail` instead, which carries the same message.
	public func lastFetchFailureMessage(forArticleID articleID: String) -> String? {
		failureMessages.withLock { $0[articleID] }
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
	/// read on a previous visit. `isStale` and the anti-hammering floor in
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
	public func fetchIfNeeded(for article: Article) {
		guard let workID = Self.ao3WorkID(fromBookKey: article.bookKey) else {
			noteAnthologyUnsupportedIfNeeded(for: article)
			return
		}
		guard isStale(article: article) else {
			return
		}
		guard Self.isAO3NetworkRequestAllowed(for: article) else {
			return
		}
		downloadIfNeeded(workID: workID, articleID: article.articleID, accountID: article.accountID, feedID: article.feedID)
	}

	/// True if `article` is a single AO3 work (not an anthology/combined-
	/// series bookKey) that `checkForUpdates(for:)` could actually act on
	/// right now -- i.e. no unresolved pending-update diff is blocking a
	/// re-check. For UI use, to decide whether to show/enable the "Check
	/// for updates" action at all.
	public func canCheckForUpdates(for article: Article) -> Bool {
		guard Self.ao3WorkID(fromBookKey: article.bookKey) != nil else {
			return false
		}
		return article.pendingUpdateContentHTML == nil
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
	/// this does not consult `isStale`'s settled-cadence/regression-flag
	/// checks -- the whole point of an explicit user action is to check
	/// regardless of whether the article "looks" settled.
	public func checkForUpdates(for article: Article) {
		guard let workID = Self.ao3WorkID(fromBookKey: article.bookKey) else {
			noteAnthologyUnsupportedIfNeeded(for: article)
			return
		}
		guard article.pendingUpdateContentHTML == nil else {
			return
		}
		guard Self.isAO3NetworkRequestAllowed(for: article) else {
			return
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
		downloadIfNeeded(workID: workID, articleID: article.articleID, accountID: article.accountID, feedID: article.feedID)
	}

	/// True unless `article` is Ambrosia-sourced and both
	/// `AmbrosiaAO3NetworkPreference` flags are off -- the pre-request guard
	/// for keeping a local-archive-only reader off AO3 servers entirely. A
	/// pre-request guard, not a post-fetch filter: when this is false, no
	/// request is made at all, not just "result discarded." Native
	/// (non-Ambrosia) AO3-RSS-sourced articles always return true here --
	/// they have no other way to get content at all, so they're unaffected
	/// by this flag. Public: WebViewController's checkForUpdatesAction()
	/// uses this to decide whether to render the per-article action as
	/// disabled with an explanatory label.
	public static func isAO3NetworkRequestAllowed(for article: Article) -> Bool {
		guard article.isAmbrosiaItem else {
			return true
		}
		return AmbrosiaAO3NetworkPreference.updatesEnabled
	}

	/// True when the article has no stored content yet, or when it does but
	/// the user's chosen refetch cadence (AO3PrefaceRefetchPreference) says
	/// the last successful fetch through this mechanism is old enough to
	/// check again -- otherwise a work's comments/kudos/hits/formatting
	/// would never update again. Staleness here is cadence-only: this no
	/// longer compares the stored content's chapter count against the
	/// feed-reported `chapterCurrent` (Workstream 1's territory) -- ordinary
	/// AO3 tag/user RSS/Atom feeds have no refresh throttle of their own
	/// (see refresh-throttling.md's "open gap" section), so `chapterCurrent`
	/// could be rewritten by an unrelated feed-summary reparse independent
	/// of, and often out of step with, what this fetcher's own last
	/// download actually wrote -- comparing against it made an unthrottled
	/// feed refresh capable of forcing a content refetch it had no real
	/// evidence for. A content-present article with no recorded
	/// lastPrefaceFetchDate (an Ambrosia import, or any row never fetched
	/// through this mechanism) is now treated as due rather than left
	/// alone, since there's no prior fetch to have been "recent" -- actual
	/// network access is still gated separately by
	/// isAO3NetworkRequestAllowed at the call sites (fetchIfNeeded,
	/// checkForUpdates), unaffected by this function. Exposed internally
	/// for direct testing against fixtures.
	func isStale(article: Article) -> Bool {
		// Task 8: an unresolved pending-update diff or a metadata-level
		// regression flag both mean "leave contentHTML exactly as
		// archived until the person acts" -- skip on-open fetching for
		// either state. checkForUpdates (the explicit per-article action)
		// bypasses this function entirely for the flag case, but still
		// separately blocks on pendingUpdateContentHTML itself -- see its
		// own doc comment.
		guard article.pendingUpdateContentHTML == nil else {
			return false
		}
		guard article.wordCountRegressionFlaggedAt == nil else {
			return false
		}
		// AO3 has confirmed this work is gone or inaccessible (see
		// AO3ChapterFetcher.download's set/clear call sites) -- don't keep
		// retrying it every cadence interval forever. Cleared automatically
		// on a subsequent successful fetch, or when Manage Storage's "Clear
		// Content" action clears contentHTML (see
		// ArticlesTable.clearContentHTML), so this doesn't permanently lock
		// a row out.
		guard article.ao3ConfirmedMissingAt == nil else {
			return false
		}
		guard let contentHTML = article.contentHTML, !contentHTML.isEmpty else {
			return true
		}
		guard let lastPrefaceFetchDate = article.lastPrefaceFetchDate else {
			return true
		}
		return Date().timeIntervalSince(lastPrefaceFetchDate) >= AO3PrefaceRefetchPreference.current.timeInterval
	}
}

// MARK: - Internal, directly testable

extension AO3ChapterFetcher {

	static func ao3WorkID(fromBookKey bookKey: String) -> String? {
		guard bookKey.hasPrefix(ao3WorkIDBookKeyPrefix) else {
			return nil
		}
		let workID = String(bookKey.dropFirst(ao3WorkIDBookKeyPrefix.count))
		return workID.isEmpty ? nil : workID
	}

	/// The reverse of `ao3WorkID(fromBookKey:)` -- `ParsedItem.bookKey`'s
	/// own formula for a bare AO3 work id with no series/anthology
	/// grouping (`ao3SeriesID`/`isAnthology` both nil), which is what
	/// every AO3 series-navigation stub and fetch always is. Exists so
	/// callers that need to go workID -> bookKey (cross-feed lookups, in
	/// particular) don't hand-duplicate `ao3WorkIDBookKeyPrefix`
	/// themselves.
	static func bookKey(forWorkID workID: String) -> String {
		"\(ao3WorkIDBookKeyPrefix)\(workID)"
	}

	/// Logs the anthology/combined-series case to the Activity Log once
	/// per article (reusing `attemptDates` as the "already noted" gate, so
	/// reopening the same article repeatedly doesn't spam the log) instead
	/// of `fetchIfNeeded` silently doing nothing. Also records a
	/// `failureMessages` entry for API consistency with the real-failure
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
			self.fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "Combined AO3 series can't be refreshed individually -- showing imported content")
		}
	}
}

// MARK: - Private

nonisolated extension AO3ChapterFetcher {

	private func downloadIfNeeded(workID: String, articleID: String, accountID: String, feedID: String) {
		let shouldDownload = attemptDates.withLock { dates in
			let currentDate = Date()
			if let attemptDate = dates[articleID], attemptDate > currentDate.addingTimeInterval(-Self.secondsBetweenAttempts) {
				return false
			}
			dates[articleID] = currentDate
			return true
		}

		if shouldDownload {
			download(workID: workID, articleID: articleID, accountID: accountID, feedID: feedID)
		}
	}

	internal func download(workID: String, articleID: String, accountID: String, feedID: String) {
		guard let url = URL(string: "https://archiveofourown.org/works/\(workID)?view_full_work=true&view_adult=true") else {
			return
		}

		Task { @MainActor in
			let activityLog = ActivityLog.shared
			let kind = ActivityKind.fetchAO3Chapter(workID: workID)

			activityLog.createActivity(owner: .ao3ChapterFetcher, kind: kind, detail: nil)
			activityLog.didStart(.ao3ChapterFetcher, kind: kind)

			// Authenticated-first: when a session is stored, try it before
			// ever making an anonymous request. Falls through to the
			// existing anonymous path below only on an authentication-shaped
			// failure (session rejected/expired, or a network-level error on
			// the authenticated attempt itself -- see attemptAuthenticated's
			// own doc comment for why a transient network hiccup here
			// shouldn't block the read). A .rateLimited/timeout on the
			// *anonymous* Downloader path below is unrelated to this and
			// still returned directly, unretried, same as before.
			if AO3SessionStore.isSignedIn {
				switch await attemptAuthenticated(url: url) {
				case .success(let result, let data):
					await self.finishSuccessfulFetch(extraction: result, workID: workID, articleID: articleID, accountID: accountID, feedID: feedID, activityLog: activityLog, kind: kind, dataSizeMessage: ActivityLog.dataSizeMessage(data), returnedFromCache: false)
					return
				case .signedOut:
					// The stored session itself is what's rejected --
					// distinct from never having signed in at all.
					// Clearing it means the next fetch attempt (and the
					// Settings sign-in row) both reflect reality instead
					// of claiming a session that AO3 no longer honors.
					AO3SessionStore.clearSession()
					fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "Signed out of AO3 -- sign in again in Settings to read this work")
					return
				case .notFoundOnRetry:
					// Per the shared authenticated-first/anonymous-fallback
					// policy (docs/ao3-integration.md, "Authenticated-first
					// fetch, anonymous fallback"), a .notFound from the
					// authenticated attempt is treated the same as
					// .registrationRequired: an unsampled restricted-page
					// shape can't be told apart from a real 404 here, so
					// this alone isn't a strong enough signal to confirm
					// the work missing. Fall back to the anonymous path
					// below -- only if *that* also comes back .notFound
					// (dual confirmation) does ao3ConfirmedMissingAt get
					// set, in the anonymous-path .notFound case further
					// down.
					activityLog.updateProgress(.ao3ChapterFetcher, kind: kind, message: "AO3 authenticated fetch found nothing -- retrying anonymously before confirming missing")
				case .otherFailure(let retryMessage):
					// Network-level failure or an unexpected extraction
					// shape on the authenticated attempt -- not a login
					// problem, so the stored session is left alone. Fall
					// back to the anonymous path below rather than failing
					// outright, same as a .rateLimited/timeout fallback
					// would for the anonymous fetch.
					activityLog.updateProgress(.ao3ChapterFetcher, kind: kind, message: "AO3 authenticated fetch failed (\(retryMessage)) -- retrying anonymously")
				case .notSignedIn:
					// Unreachable here (isSignedIn was just checked), but
					// treated the same as .otherFailure would be for
					// exhaustiveness: fall through to the anonymous path,
					// logged the same way for symmetry with the other
					// fallback branches rather than a silent break.
					activityLog.updateProgress(.ao3ChapterFetcher, kind: kind, message: "AO3 authenticated fetch reported no session unexpectedly -- retrying anonymously")
				}
			}

			do {
				let downloadResponse = try await Downloader.shared.download(url)

				guard let data = downloadResponse.data, !data.isEmpty, let response = downloadResponse.response, response.statusIsOK else {
					// Bad response -- leave existing content alone. The
					// attemptDates gate above already prevents
					// hammering a gated/deleted/moved work; no further
					// backoff bookkeeping needed here for this specific
					// article. A 429 specifically also means Downloader
					// itself has now started a per-host cooldown (see
					// Downloader.retryAfterMessages) that holds off every
					// other AO3 fetch, not just this one, until it
					// expires -- called out distinctly here so it isn't
					// read as an ordinary one-off failure.
					let statusCode = downloadResponse.response?.forcedStatusCode ?? -1
					let message = statusCode == HTTPResponseCode.tooManyRequests
						? "AO3 rate limit hit -- backing off before retrying"
						: "Could not reach AO3 (HTTP \(statusCode))"
					fail(articleID: articleID, kind: kind, activityLog: activityLog, message: message)
					return
				}

				guard let html = String(data: data, encoding: .utf8) else {
					fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "No chapter content found (gated or removed work)")
					return
				}

				let extraction: AO3ChapterExtractionResult
				switch AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html) {
				case .success(let result):
					extraction = result
				case .registrationRequired:
					// Only reachable here when signed out (the signed-in
					// case already attempted authenticated-first above and
					// returned), so this is always the "never signed in"
					// message, not a second authenticated retry.
					fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "This work is only available to registered AO3 users")
					return
				case .adultContentGate:
					// Anomalous now that view_adult=true is sent
					// unconditionally -- surfaced distinctly, not folded
					// into .notFound, so it's easy to notice if it starts
					// happening.
					fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "Adult content gate encountered despite view_adult=true (unexpected)")
					return
				case .notFound:
					// Genuinely ambiguous shape -- could be a real
					// deleted/moved work, or a restricted-page shape (a
					// collection- or series-level gate, for instance) this
					// extractor doesn't yet recognize as
					// .registrationRequired -- see
					// AO3ChapterExtractionOutcome.notFound's own doc
					// comment. Only reachable here when signed out (the
					// signed-in case already tried the authenticated
					// attempt above), so there's no session left to retry
					// with -- this is AO3 confirming the work is gone or
					// inaccessible by every means this fetcher has for a
					// signed-out reader, so it sets ao3ConfirmedMissingAt.
					if let account = AccountManager.shared.existingAccount(accountID: accountID) {
						await account.setAO3ConfirmedMissingAsync(forArticleID: articleID)
					}
					fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "No chapter content found (gated or removed work)")
					return
				}

				await self.finishSuccessfulFetch(extraction: extraction, workID: workID, articleID: articleID, accountID: accountID, feedID: feedID, activityLog: activityLog, kind: kind, dataSizeMessage: ActivityLog.dataSizeMessage(data), returnedFromCache: downloadResponse.returnedFromCache)

			} catch {
				// Pre-response failure (DNS, TLS, network) -- same
				// leave-it-alone handling.
				fail(articleID: articleID, kind: kind, activityLog: activityLog, message: error.localizedDescription, error: error)
			}
		}
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
			fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "Account no longer exists")
			return
		}
		let existingArticles = await account.fetchArticlesAsync(.articleIDs([articleID]))
		guard let existingArticle = existingArticles.first else {
			fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "Article no longer exists")
			return
		}

		// Task 8's Ambrosia local-only toggle: gates whether this
		// fetch happened at all (isAO3NetworkRequestAllowed, above
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
		if let regressionDescription = Self.detectRegression(existingArticle: existingArticle, extraction: extraction) {
			await account.setPendingContentUpdateAsync(extraction.contentHTML, forArticleID: articleID)
			activityLog.didComplete(.ao3ChapterFetcher, kind: kind, message: "Possible content regression detected (\(regressionDescription)) -- kept existing content, flagged for review", returnedFromCache: returnedFromCache)
			failureMessages.withLock { $0[articleID] = nil }
			postNotification(name: .ao3ChapterFetchDidComplete, articleID: articleID)
			// The CSRF token this fetch obtained is still good for a
			// kudos attempt even though the content write itself was
			// held back -- see the non-regression path's identical
			// call below for why this is safe/idempotent.
			AO3KudosManager.attemptKudosIfNeeded(article: existingArticle, workID: workID, csrfToken: extraction.csrfToken)
			return
		}

		let parsedItem = Self.rebuildParsedItem(from: existingArticle, workID: workID, extraction: extraction, applyStatsUpdate: applyStatsUpdate)
		_ = await account.updateAsync(feedID: feedID, parsedItems: [parsedItem], deleteOlder: false)

		activityLog.didComplete(.ao3ChapterFetcher, kind: kind, message: dataSizeMessage, returnedFromCache: returnedFromCache)
		failureMessages.withLock { $0[articleID] = nil }
		// A successful fetch means the work is reachable again --
		// either it was a false-positive gate/404, or the author
		// restored it. Clear so isStale can consider this article
		// for auto-fetch again instead of being permanently
		// skipped from a stale confirmed-missing flag.
		await account.clearAO3ConfirmedMissingAsync(forArticleID: articleID)
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

	/// Result of the authenticated attempt -- now the primary path when
	/// signed in, not just a retry on `.registrationRequired`. Distinct
	/// from `AO3ChapterExtractionOutcome` because the failure modes that
	/// matter here -- "session rejected" versus "AO3 confirms the work is
	/// gone" versus "network/unexpected-shape failure" -- have no
	/// counterpart in the anonymous-fetch outcome and need different
	/// handling (only the first clears the stored session; only the
	/// second sets ao3ConfirmedMissingAt).
	enum AuthenticatedRetryResult {
		/// Carries the raw response `Data` alongside the extraction, purely
		/// so the caller can compute the same `ActivityLog.dataSizeMessage`
		/// the anonymous path already logs on success.
		case success(AO3ChapterExtractionResult, data: Data)
		/// No session is stored at all. Unreachable from `download`'s
		/// authenticated-first branch (which already checked
		/// `AO3SessionStore.isSignedIn` before calling this), but kept for
		/// callers that don't pre-check.
		case notSignedIn
		/// A session was stored and sent, and AO3 still returned
		/// `.registrationRequired` -- the session is expired or otherwise
		/// invalid. Caller clears it.
		case signedOut
		/// The authenticated attempt itself came back `.notFound`. Per the
		/// shared authenticated-first/anonymous-fallback policy
		/// (docs/ao3-integration.md), this is treated the same as
		/// `.registrationRequired`/network failure: not strong enough on
		/// its own to confirm deletion, since an unsampled restricted-page
		/// shape can't be told apart from a real 404 here. The caller
		/// falls back to the anonymous path on this outcome, same as
		/// `.otherFailure`; only if the anonymous attempt *also* comes
		/// back `.notFound` (dual confirmation) does `ao3ConfirmedMissingAt`
		/// get set. Kept distinct from `.otherFailure` only so the caller's
		/// progress-log message can be specific, not because it triggers
		/// different fallback behavior.
		case notFoundOnRetry
		/// The attempt reached AO3 but hit a different outcome
		/// (`.adultContentGate`) or a network-level failure -- not a login
		/// problem and not a confirmed deletion, so the stored session is
		/// left alone and no confirmed-missing flag is set. The caller
		/// falls back to the anonymous path on this outcome.
		case otherFailure(message: String)
	}

	/// Attempts `url` once with the stored AO3 session's Cookie header
	/// attached. Called first, before any anonymous request, whenever
	/// `AO3SessionStore.isSignedIn` -- see this file's header comment for
	/// the overall authenticated-first/anonymous-fallback shape.
	///
	/// Deliberately bypasses `Downloader.shared` rather than adding a
	/// Cookie header to a request routed through it: `Downloader`'s cache
	/// is keyed on URL alone, and routing this through it would mean a
	/// later anonymous fetch of the same URL could silently reuse a
	/// cached authenticated (or vice versa) response. `AO3AuthenticatedFetcher`
	/// uses its own cache-free ephemeral session instead. This also means
	/// a `.rateLimited`(429)/timeout on this attempt specifically should
	/// fall back to anonymous the same way `.otherFailure` does below,
	/// since `AO3AuthenticatedFetcher` has no cooldown tracking of its own
	/// and a transient hiccup on its ephemeral session shouldn't block the
	/// read -- both are folded into `.otherFailure` here rather than a
	/// separate case, since the caller's fallback behavior is identical
	/// either way.
	@MainActor
	private func attemptAuthenticated(url: URL) async -> AuthenticatedRetryResult {
		guard AO3SessionStore.isSignedIn else {
			return .notSignedIn
		}

		do {
			guard let (data, response) = try await AO3AuthenticatedFetcher.fetch(url) else {
				return .notSignedIn
			}
			guard response.statusIsOK, !data.isEmpty, let html = String(data: data, encoding: .utf8) else {
				return .otherFailure(message: "Could not reach AO3 (HTTP \(response.statusCode))")
			}
			switch AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html) {
			case .success(let result):
				return .success(result, data: data)
			case .registrationRequired:
				return .signedOut
			case .adultContentGate:
				return .otherFailure(message: "Adult content gate encountered despite view_adult=true (unexpected)")
			case .notFound:
				return .notFoundOnRetry
			}
		} catch {
			// Network-level failure on the retry itself -- not a login
			// problem, so the stored session is left alone; a future fetch
			// attempt gets another chance.
			return .otherFailure(message: error.localizedDescription)
		}
	}

	/// Records `message` as the article's current failure reason, logs it to
	/// the Activity Log (unchanged behavior), and posts
	/// `.ao3ChapterFetchDidFail` so an already-visible article view can
	/// react immediately rather than waiting for the next fetch attempt.
	@MainActor
	private func fail(articleID: String, kind: ActivityKind, activityLog: ActivityLog, message: String, error: Error? = nil) {
		let loggedError = error ?? NSError(domain: "Nectar", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
		activityLog.didFail(.ao3ChapterFetcher, kind: kind, error: loggedError)
		failureMessages.withLock { $0[articleID] = message }
		postNotification(name: .ao3ChapterFetchDidFail, articleID: articleID, message: message)
	}

	/// Copies every field from `existingArticle` unchanged except
	/// `contentHTML` (the freshly fetched, workskin-preserving HTML),
	/// `chapterCurrent` (bumped to the chapter count actually found in this
	/// fetch), and the four AO3 Work Header stats counts (commentCount/
	/// kudosCount/bookmarkCount/hitCount, taken from this fetch's
	/// extraction rather than the existing article, so they refresh on
	/// every successful re-fetch the same way chapterCurrent does).
	/// `chapterTotal`/`isComplete` are left as whatever the article
	/// already has -- those are Workstream 1's (feed-derived) territory, and
	/// a partial chapter fetch shouldn't be used to infer completion.
	///
	/// `tags` and `language` have no persisted home on `Article` at all (see
	/// ParsedItem/Article field lists), so both are passed through as nil --
	/// this doesn't blank anything that was ever actually stored.
	/// Re-derives the currently stored content's chapter/word counts the
	/// same way `isStale` re-derives chapter count -- walking the stored
	/// `contentHTML`'s own `#workskin` wrapper back through
	/// `AO3ChapterHTMLExtractor.extract`, since the stored contentHTML *is*
	/// that wrapper -- and compares against this fetch's counts. Returns a
	/// short human-readable description of what regressed (for the
	/// Activity Log message), or nil if this fetch looks fine to write
	/// through normally.
	///
	/// A fewer-chapters count is always a regression, independent of the
	/// word-count threshold (full deletion is handled fine elsewhere --
	/// `.notFound` leaves existing content alone -- this is specifically
	/// for a legitimate-looking edit that shrinks a work). Word count only
	/// counts as a regression once it clears `AO3RegressionThreshold`'s
	/// 10%-and-300-word bar, using the identical threshold the metadata-
	/// level watch in `Article+Database.changesFrom` uses.
	private static func detectRegression(existingArticle: Article, extraction: AO3ChapterExtractionResult) -> String? {
		guard let storedHTML = existingArticle.contentHTML, !storedHTML.isEmpty,
			  case .success(let storedExtraction) = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: storedHTML) else {
			// Nothing stored yet, or the stored content can't be
			// re-parsed -- nothing to regress against, so the first
			// successful fetch for an article always writes through.
			return nil
		}

		let oldChapterCount = storedExtraction.chapters.count
		let newChapterCount = extraction.chapters.count
		if newChapterCount < oldChapterCount {
			return "chapter count \(oldChapterCount) -> \(newChapterCount)"
		}

		if let oldWordCount = storedExtraction.wordCount, let newWordCount = extraction.wordCount,
		   AO3RegressionThreshold.isRegression(from: oldWordCount, to: newWordCount) {
			return "word count \(oldWordCount) -> \(newWordCount)"
		}

		return nil
	}

	/// `applyStatsUpdate` is Task 8's Ambrosia local-only toggle
	/// (`AmbrosiaAO3NetworkPreference.updatesEnabled`) -- always true for
	/// a non-Ambrosia article, since those have no other way to get
	/// content at all. When false, the stats fields
	/// (comment/kudos/bookmark/hit count) pass `existingArticle`'s own
	/// current values through unchanged instead of this fetch's. There is
	/// no equivalent content-side flag any more: content, chapter count,
	/// and prev/next-work navigation are always taken from `extraction`
	/// once a fetch has been allowed to happen at all, protected instead
	/// by `Self.detectRegression` at the call site, before this function
	/// is ever reached. `internal` rather than the enclosing `private
	/// extension`'s default fileprivate -- AO3ChapterFetcherTests
	/// exercises this directly (`@testable import Account` reaches
	/// `internal`, not `fileprivate`, across file boundaries within the
	/// same module). `detectRegression` above stays fileprivate; only
	/// this one needs the wider access.
	internal static func rebuildParsedItem(from existingArticle: Article, workID: String, extraction: AO3ChapterExtractionResult, applyStatsUpdate: Bool) -> ParsedItem {
		// Metadata fields (author/summary/date/tag-groups): always prefer
		// what this fetch's live page parsed (AO3ChapterHTMLExtractor's
		// AO3WorkPageMetadata), falling back to existingArticle's own
		// stored value only when the live page didn't have that field at
		// all -- the metadata block being absent entirely (gated page, or
		// a shape not yet sampled -- see parseWorkHeader's own doc
		// comment on why it's optional), not merely empty. This is what
		// fixes a series-nav stub (AO3SeriesNavigator.placeholderStub,
		// summary/authors/date/tags all nil) never getting real metadata
		// past the bare stub: previously every one of these fields below
		// passed existingArticle's value straight through unchanged, which
		// for a stub meant "nil forever." An article that already has real
		// metadata (search-results/Ambrosia import) gets the same
		// always-overwrite treatment on every refetch, so a Check-for-
		// updates or open-time refetch can't get stuck on stale metadata
		// either -- the live page is the source of truth, not whatever's
		// already in the database.
		let metadata = extraction.metadata
		let authors: Set<ParsedAuthor>? = metadata.authors.isEmpty
			? existingArticle.authors.map { authorSet in
				Set(authorSet.map { ParsedAuthor(name: $0.name, url: $0.url, avatarURL: $0.avatarURL, emailAddress: $0.emailAddress) })
			}
			: metadata.authors
		let summary = metadata.summary ?? existingArticle.summary
		let datePublished = metadata.datePublished ?? existingArticle.datePublished
		let dateModified = metadata.dateModified ?? existingArticle.dateModified
		let fandoms = metadata.fandoms.isEmpty ? existingArticle.fandoms : metadata.fandoms
		let relationships = metadata.relationships.isEmpty ? existingArticle.relationships : metadata.relationships
		let characters = metadata.characters.isEmpty ? existingArticle.characters : metadata.characters
		let ratings = metadata.ratings.isEmpty ? existingArticle.ratings : metadata.ratings
		let warnings = metadata.warnings.isEmpty ? existingArticle.warnings : metadata.warnings
		let categories = metadata.categories.isEmpty ? existingArticle.categories : metadata.categories
		// Additional Tags (freeform): ParsedItem.tags is the only carrier
		// today -- Article has no persisted field for it yet (see
		// ParsedItem.tags's own doc comment). Passed through regardless,
		// ready for that field once it exists; currently dropped
		// downstream the same way every other source of ParsedItem.tags
		// already is.
		let additionalTags: Set<String>? = metadata.additionalTags.isEmpty ? nil : Set(metadata.additionalTags)

		// Inline series navigation: prefer the existing article's own
		// already-known series membership, carried through unchanged
		// (name/index/ao3ID *and*, now, previousWorkURL/nextWorkURL --
		// dropping the latter two here would silently discard per-series
		// nav data on every refetch). Falls back to this fetch's freshly
		// parsed seriesEntries only when there's no existing series at all
		// to carry forward -- the first-ever fetch of a work reached via
		// Phase 4's bulk series import, whose stub (AO3SeriesNavigator's
		// stub builder) never sets `series`.
		let series: [ParsedSeriesEntry]?
		if let existingSeries = existingArticle.series, !existingSeries.isEmpty {
			series = existingSeries.map { ParsedSeriesEntry(name: $0.name, index: $0.index, ao3ID: $0.ao3ID, previousWorkURL: $0.previousWorkURL, nextWorkURL: $0.nextWorkURL) }
		} else {
			series = extraction.seriesEntries.map(\.entry)
		}

		return ParsedItem(
			syncServiceID: nil,
			uniqueID: existingArticle.uniqueID,
			feedURL: existingArticle.feedID,
			url: existingArticle.rawLink,
			externalURL: existingArticle.rawExternalLink,
			title: extraction.title ?? existingArticle.title,
			language: nil,
			contentHTML: extraction.contentHTML,
			contentText: existingArticle.contentText,
			// existingArticle.markdown is expected nil for every AO3-sourced
			// article (markdown is an Ambrosia/JSON-Feed-only concept, never
			// populated from an AO3 Atom feed) -- passing it through as-is is
			// still correct field-copying, but flag the interaction: if this
			// were ever non-nil, ParsedItem's init would re-render markdown
			// to HTML and discard the contentHTML fetched above entirely.
			markdown: existingArticle.markdown,
			summary: summary,
			imageURL: existingArticle.rawImageLink,
			bannerImageURL: nil,
			datePublished: datePublished,
			dateModified: dateModified,
			authors: authors,
			tags: additionalTags,
			attachments: nil,
			isAmbrosiaItem: existingArticle.isAmbrosiaItem,
			wordCount: existingArticle.wordCount,
			chapterCurrent: extraction.chapters.count,
			chapterTotal: existingArticle.chapterTotal,
			isComplete: existingArticle.isComplete,
			fandoms: fandoms,
			relationships: relationships,
			characters: characters,
			ratings: ratings,
			warnings: warnings,
			categories: categories,
			series: series,
			commentCount: applyStatsUpdate ? extraction.commentCount : existingArticle.commentCount,
			kudosCount: applyStatsUpdate ? extraction.kudosCount : existingArticle.kudosCount,
			bookmarkCount: applyStatsUpdate ? extraction.bookmarkCount : existingArticle.bookmarkCount,
			hitCount: applyStatsUpdate ? extraction.hitCount : existingArticle.hitCount,
			// rebuildParsedItem only runs on a successful extraction (it's
			// handed the extraction.chapters/stats result), so "now" is
			// correct here regardless of caller -- a failed fetch never
			// reaches this function at all.
			lastPrefaceFetchDate: Date(),
			ao3WorkID: workID
		)
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
