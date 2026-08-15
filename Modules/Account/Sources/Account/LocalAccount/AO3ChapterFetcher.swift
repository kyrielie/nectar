//
//  AO3ChapterFetcher.swift
//  Account
//
//  Nectar AO3 direct-reading support, Workstream 2 ("On-demand chapter
//  fetch and storage"). Workstream 3
//  ("optional AO3 login") is layered on top of this file: see
//  retryAuthenticated(...) below and AO3AuthenticatedFetcher.
//
//  Fetches an AO3 work's live page (`?view_full_work=true&view_adult=true`)
//  on demand and
//  persists the extracted, workskin-preserving contentHTML for any article
//  whose bookKey identifies it as an AO3 work ("ao3-work:<id>"). Modeled
//  directly on HTMLMetadataDownloader: same anti-hammering attemptDates gate, same
//  ActivityLog start/complete/fail calls, same "leave existing content alone
//  on failure, don't retry aggressively" shape. The primary fetch is
//  anonymous -- Downloader already forces httpShouldSetCookies = false /
//  .never cookie policy app-wide, so no change was needed to get that
//  behavior here. The one exception is the single authenticated retry on
//  .registrationRequired, which deliberately bypasses Downloader (see
//  retryAuthenticated's doc comment for why) and attaches a Cookie header
//  by hand.
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
	/// There is deliberately no bulk "check all" equivalent (per the plan).
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
					switch await retryAuthenticated(url: url) {
					case .success(let result):
						extraction = result
					case .signedOut:
						// The stored session itself is what's rejected --
						// distinct from never having signed in at all.
						// Clearing it means the next fetch attempt (and the
						// Settings sign-in row) both reflect reality instead
						// of claiming a session that AO3 no longer honors.
						AO3SessionStore.clearSession()
						fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "Signed out of AO3 -- sign in again in Settings to read this work")
						return
					case .notSignedIn:
						fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "This work is only available to registered AO3 users")
						return
					case .notFoundOnRetry:
						// Anonymous fetch said .registrationRequired, and the
						// authenticated retry came back .notFound -- same
						// "AO3 confirms gone" signal as the .notFound
						// branch's identical case below, just reached from
						// the other anonymous-fetch outcome. Both agree the
						// work isn't there, so this sets ao3ConfirmedMissingAt
						// too rather than being folded into .otherFailure.
						if let account = AccountManager.shared.existingAccount(accountID: accountID) {
							await account.setAO3ConfirmedMissingAsync(forArticleID: articleID)
						}
						fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "No chapter content found (gated or removed work)")
						return
					case .otherFailure(let retryMessage):
						fail(articleID: articleID, kind: kind, activityLog: activityLog, message: retryMessage)
						return
					}
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
					// comment. Retried authenticated the same way
					// .registrationRequired is above, so a signed-in
					// reader who actually has access still gets the
					// cookie'd fetch instead of this silently never
					// retrying. A truly deleted/moved work still comes
					// back .notFound on the retry too, surfaced as its own
					// .notFoundOnRetry case below (not folded into
					// .notSignedIn -- the two are reached under different
					// conditions, one with no session and one with a
					// session that still can't see the work) -- and
					// retryAuthenticated only ever clears the stored
					// session on .signedOut, never on .notFound, so this
					// doesn't risk logging a valid session out over an
					// unrelated 404. Both .notSignedIn and .notFoundOnRetry
					// are AO3 confirming the work is gone or inaccessible
					// by every means this fetcher has, so both set
					// ao3ConfirmedMissingAt.
					switch await retryAuthenticated(url: url) {
					case .success(let result):
						extraction = result
					case .signedOut:
						AO3SessionStore.clearSession()
						fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "Signed out of AO3 -- sign in again in Settings to read this work")
						return
					case .notSignedIn:
						// Existing contentHTML (nil, on first fetch) is left
						// alone; ArticleRenderer's contentHTML ?? contentText
						// ?? summary chain already falls back to Workstream
						// 1's blurb.
						if let account = AccountManager.shared.existingAccount(accountID: accountID) {
							await account.setAO3ConfirmedMissingAsync(forArticleID: articleID)
						}
						fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "No chapter content found (gated or removed work)")
						return
					case .notFoundOnRetry:
						if let account = AccountManager.shared.existingAccount(accountID: accountID) {
							await account.setAO3ConfirmedMissingAsync(forArticleID: articleID)
						}
						fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "No chapter content found (gated or removed work)")
						return
					case .otherFailure(let retryMessage):
						fail(articleID: articleID, kind: kind, activityLog: activityLog, message: retryMessage)
						return
					}
				}

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
					activityLog.didComplete(.ao3ChapterFetcher, kind: kind, message: "Possible content regression detected (\(regressionDescription)) -- kept existing content, flagged for review", returnedFromCache: downloadResponse.returnedFromCache)
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

				activityLog.didComplete(.ao3ChapterFetcher, kind: kind, message: ActivityLog.dataSizeMessage(data), returnedFromCache: downloadResponse.returnedFromCache)
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

			} catch {
				// Pre-response failure (DNS, TLS, network) -- same
				// leave-it-alone handling.
				fail(articleID: articleID, kind: kind, activityLog: activityLog, message: error.localizedDescription, error: error)
			}
		}
	}

	/// Result of the single authenticated retry attempted on
	/// `.registrationRequired`. Distinct from `AO3ChapterExtractionOutcome`
	/// because the two failure modes that matter here -- "never signed in"
	/// versus "signed in, but AO3 rejected the session" -- have no
	/// counterpart in the anonymous-fetch outcome and need different
	/// handling (only the latter clears the stored session).
	enum AuthenticatedRetryResult {
		case success(AO3ChapterExtractionResult)
		/// No session is stored at all -- login was never completed, or was
		/// signed out. Not itself an error; the caller falls back to the
		/// ordinary "registered users only" message.
		case notSignedIn
		/// A session was stored and sent, and AO3 still returned
		/// `.registrationRequired` -- the session is expired or otherwise
		/// invalid. Caller clears it.
		case signedOut
		/// The authenticated retry itself came back `.notFound` -- i.e.
		/// both the anonymous fetch and the authenticated retry agree the
		/// work is gone, which is the strongest signal available that this
		/// is a confirmed deletion rather than a transient failure. Kept
		/// distinct from `.otherFailure` (network error on the retry,
		/// unexpected adult-content-gate shape) specifically so the caller
		/// can set `ao3ConfirmedMissingAt` only for this case, without
		/// having to pattern-match on `.otherFailure`'s message string.
		case notFoundOnRetry
		/// The retry reached AO3 but hit a different outcome
		/// (`.adultContentGate`) or a network-level failure -- not a login
		/// problem and not a confirmed deletion, so the stored session is
		/// left alone and no confirmed-missing flag is set.
		case otherFailure(message: String)
	}

	/// Retries `url` once with the stored AO3 session's Cookie header
	/// attached, on `.registrationRequired` and `.notFound` -- `.notFound`
	/// is AO3ChapterHTMLExtractor's catch-all for a restricted-page shape
	/// it doesn't recognize as `.registrationRequired` specifically (see
	/// `AO3ChapterExtractionOutcome.notFound`'s doc comment), so it gets
	/// the same authenticated retry. `.adultContentGate` is excluded: it's
	/// not a login problem and a login retry wouldn't fix it (per the
	/// plan).
	///
	/// Deliberately bypasses `Downloader.shared` rather than adding a
	/// Cookie header to a request routed through it: `Downloader`'s cache
	/// is keyed on URL alone, and the anonymous fetch that got
	/// `.registrationRequired` just cached a response at this exact URL --
	/// reusing `Downloader` here would silently hand back that cached
	/// gate-page response instead of ever making the authenticated
	/// request. `AO3AuthenticatedFetcher` uses its own cache-free ephemeral
	/// session instead.
	@MainActor
	private func retryAuthenticated(url: URL) async -> AuthenticatedRetryResult {
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
				return .success(result)
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
