//
//  AO3ChapterFetcher.swift
//  Account
//
//  Nectar AO3 direct-reading support, Workstream 2 ("On-demand chapter
//  fetch and storage") -- see docs/ao3-merged-plan-nectar.md. Workstream 3
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

	/// Upper bound on how many articles one background sweep (see
	/// `sweepStaleUnreadArticles`) fetches, and the delay between each --
	/// deliberately conservative. The sweep is the one place in this file
	/// capable of firing several AO3 requests back-to-back with no user
	/// action in between (fetchIfNeeded's other caller,
	/// WebViewController.setArticle, is naturally paced by how fast a
	/// person can open articles); keeping it slow and bounded is the
	/// actual mitigation here, not just Downloader's reactive 429 backoff.
	private static let maxArticlesPerSweep = 5
	private static let secondsBetweenSweepRequests: TimeInterval = 5

	private let attemptDates = OSAllocatedUnfairLock(initialState: [String: Date]())

	/// Human-readable reason the most recent fetch for an article didn't
	/// persist new content, keyed by articleID. Cleared on a subsequent
	/// success. Exists so a view showing the article can explain why full
	/// text isn't loading (see `lastFetchFailureMessage(forArticleID:)`)
	/// instead of the failure being visible only in the Activity Log.
	private let failureMessages = OSAllocatedUnfairLock(initialState: [String: String]())

	/// Account IDs a background sweep is currently running for -- guards
	/// against two AccountRefreshDidFinish notifications in quick
	/// succession starting overlapping sweeps for the same account.
	private let sweepingAccountIDs = OSAllocatedUnfairLock(initialState: Set<String>())

	init() {
		// Complements the open-time trigger in fetchIfNeeded: without
		// this, an AO3-work article that's never opened never picks up a
		// formatting change or a settled work's new comments/kudos/hits,
		// no matter how long it sits unread. Scoped to unread articles
		// only (see sweepStaleUnreadArticles) and throttled (see
		// maxArticlesPerSweep/secondsBetweenSweepRequests above).
		NotificationCenter.default.addObserver(forName: .AccountRefreshDidFinish, object: nil, queue: .main) { [weak self] note in
			guard let self, let account = note.object as? Account else { return }
			Task { @MainActor in
				await self.sweepStaleUnreadArticles(in: account)
			}
		}
	}

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
	/// An anthology/combined-series bookKey (`ao3-series:`/
	/// `calibre-series:` -- see `ParsedItem.bookKey`) never resolves to an
	/// `ao3WorkID` at all: a Calibre-merged anthology isn't one AO3 work,
	/// so there's no single live page to refetch from (fetching and
	/// merging every member work was scoped out of Workstream 2 -- see
	/// ao3-merged-plan.md's "Deferred" section). That's out of scope to
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
		downloadIfNeeded(workID: workID, articleID: article.articleID, accountID: article.accountID, feedID: article.feedID)
	}

	/// True when the article has no stored content yet, when the stored
	/// content's own chapter count -- re-derived by walking the same
	/// `#workskin` wrapper AO3ChapterHTMLExtractor produced, since the stored
	/// contentHTML *is* that wrapper -- is behind `chapterCurrent` (the
	/// feed-reported total, Workstream 1's territory), or when the chapter
	/// count matches ("settled") but the user's chosen refetch cadence
	/// (AO3PrefaceRefetchPreference) says the last successful fetch is old
	/// enough to check again anyway -- otherwise a settled work's
	/// comments/kudos/hits/formatting would never update again. A settled
	/// article with no recorded lastPrefaceFetchDate (never fetched through
	/// this mechanism) is left alone by the cadence check rather than being
	/// treated as overdue, since there's no fetch time to measure the
	/// interval from. Exposed internally for direct testing against
	/// fixtures.
	func isStale(article: Article) -> Bool {
		guard let contentHTML = article.contentHTML, !contentHTML.isEmpty else {
			return true
		}
		guard let chapterCurrent = article.chapterCurrent else {
			// No chapter-count metadata at all -- shouldn't happen for an
			// article whose bookKey resolved to ao3-work: (Workstream 1
			// always sets chapterCurrent for AO3 items), but with nothing to
			// compare against, don't treat that as stale on every call.
			return false
		}
		let storedChapterCount: Int
		if case .success(let result) = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: contentHTML) {
			storedChapterCount = result.chapters.count
		} else {
			storedChapterCount = 0
		}
		if storedChapterCount < chapterCurrent {
			return true
		}
		guard let lastPrefaceFetchDate = article.lastPrefaceFetchDate else {
			return false
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

	/// Checks the account's unread articles for stale AO3-work content and
	/// calls `fetchIfNeeded` for a bounded, throttled batch -- see
	/// `maxArticlesPerSweep`/`secondsBetweenSweepRequests`. Scoped to
	/// unread rather than every article in the account: unread is both
	/// what someone's actually about to read and, for any account with a
	/// real archive, a small fraction of total stored articles, so this
	/// doesn't turn into an unbounded full-account crawl on every refresh.
	@MainActor
	func sweepStaleUnreadArticles(in account: Account) async {
		let alreadySweeping = sweepingAccountIDs.withLock { ids in
			if ids.contains(account.accountID) {
				return true
			}
			ids.insert(account.accountID)
			return false
		}
		guard !alreadySweeping else {
			return
		}
		defer {
			_ = sweepingAccountIDs.withLock { $0.remove(account.accountID) }
		}

		let unread = await account.fetchArticlesAsync(.unread(nil))
		let eligible = unread
			.filter { Self.ao3WorkID(fromBookKey: $0.bookKey) != nil }
			.filter { isStale(article: $0) }
			.prefix(Self.maxArticlesPerSweep)

		for article in eligible {
			fetchIfNeeded(for: article)
			try? await Task.sleep(nanoseconds: UInt64(Self.secondsBetweenSweepRequests * 1_000_000_000))
		}
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

nonisolated private extension AO3ChapterFetcher {

	func downloadIfNeeded(workID: String, articleID: String, accountID: String, feedID: String) {
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

	func download(workID: String, articleID: String, accountID: String, feedID: String) {
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
					// Genuinely ambiguous remainder -- deleted/moved work,
					// or a gate shape not yet sampled. Existing
					// contentHTML (nil, on first fetch) is left alone;
					// ArticleRenderer's contentHTML ?? contentText ??
					// summary chain already falls back to Workstream 1's
					// blurb.
					fail(articleID: articleID, kind: kind, activityLog: activityLog, message: "No chapter content found (gated or removed work)")
					return
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

				let parsedItem = Self.rebuildParsedItem(from: existingArticle, workID: workID, extraction: extraction)
				_ = await account.updateAsync(feedID: feedID, parsedItems: [parsedItem], deleteOlder: false)

				activityLog.didComplete(.ao3ChapterFetcher, kind: kind, message: ActivityLog.dataSizeMessage(data), returnedFromCache: downloadResponse.returnedFromCache)
				failureMessages.withLock { $0[articleID] = nil }
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
		/// The retry reached AO3 but hit a different outcome
		/// (`.adultContentGate`, `.notFound`) or a network-level failure --
		/// not a login problem, so the stored session is left alone.
		case otherFailure(message: String)
	}

	/// Retries `url` once with the stored AO3 session's Cookie header
	/// attached, on `.registrationRequired` only -- `.adultContentGate` and
	/// `.notFound` aren't login problems and a login retry wouldn't fix
	/// either (per the plan).
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
	func retryAuthenticated(url: URL) async -> AuthenticatedRetryResult {
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
				return .otherFailure(message: "No chapter content found (gated or removed work)")
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
	func fail(articleID: String, kind: ActivityKind, activityLog: ActivityLog, message: String, error: Error? = nil) {
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
	static func rebuildParsedItem(from existingArticle: Article, workID: String, extraction: AO3ChapterExtractionResult) -> ParsedItem {
		let authors: Set<ParsedAuthor>? = existingArticle.authors.map { authorSet in
			Set(authorSet.map { ParsedAuthor(name: $0.name, url: $0.url, avatarURL: $0.avatarURL, emailAddress: $0.emailAddress) })
		}
		let series: [ParsedSeriesEntry]? = existingArticle.series?.map { ParsedSeriesEntry(name: $0.name, index: $0.index, ao3ID: $0.ao3ID) }

		return ParsedItem(
			syncServiceID: nil,
			uniqueID: existingArticle.uniqueID,
			feedURL: existingArticle.feedID,
			url: existingArticle.rawLink,
			externalURL: existingArticle.rawExternalLink,
			title: existingArticle.title,
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
			summary: existingArticle.summary,
			imageURL: existingArticle.rawImageLink,
			bannerImageURL: nil,
			datePublished: existingArticle.datePublished,
			dateModified: existingArticle.dateModified,
			authors: authors,
			tags: nil,
			attachments: nil,
			isAmbrosiaItem: existingArticle.isAmbrosiaItem,
			wordCount: existingArticle.wordCount,
			chapterCurrent: extraction.chapters.count,
			chapterTotal: existingArticle.chapterTotal,
			isComplete: existingArticle.isComplete,
			fandoms: existingArticle.fandoms,
			relationships: existingArticle.relationships,
			characters: existingArticle.characters,
			ratings: existingArticle.ratings,
			warnings: existingArticle.warnings,
			categories: existingArticle.categories,
			series: series,
			commentCount: extraction.commentCount,
			kudosCount: extraction.kudosCount,
			bookmarkCount: extraction.bookmarkCount,
			hitCount: extraction.hitCount,
			// rebuildParsedItem only runs on a successful extraction (it's
			// handed the extraction.chapters/stats result), so "now" is
			// correct here regardless of caller -- a failed fetch never
			// reaches this function at all.
			lastPrefaceFetchDate: Date(),
			ao3WorkID: workID
		)
	}

	func postNotification(name: Notification.Name, articleID: String, message: String? = nil) {
		var userInfo: [String: Any] = [AO3ChapterFetchUserInfoKey.articleID: articleID]
		if let message {
			userInfo[AO3ChapterFetchUserInfoKey.message] = message
		}
		NotificationCenter.default.postOnMainThread(
			name: name, object: self, userInfo: userInfo
		)
	}
}
