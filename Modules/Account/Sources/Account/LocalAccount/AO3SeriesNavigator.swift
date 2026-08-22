//
//  AO3SeriesNavigator.swift
//  NetNewsWire
//
//  Nectar AO3 direct-reading support. Originally Task 10 ("Prev/next/
//  first navigation -- independent of the grouping toggle"), now
//  inline-series-navigation Phase 4: `openSeriesWork` below
//  replaces every "first membership wins" per-article entry point this
//  file used to expose (`fetchAdjacentWork`/`fetchFirstWorkInSeries`,
//  deleted this pass) -- those collapsed a work's multiple series
//  memberships to one, which per-series inline links (Phase 3) no
//  longer do, so the navigator underneath them can't either.
//
//  `openSeriesWork` adds and fetches a series member the same way the
//  old entry points did (stub-then-fetch, mirroring
//  Account.importPastedAO3Links(_:), under existingArticle.feedID
//  rather than the "Imported Links" feed) but is bounded to at most two
//  series-listing page fetches regardless of series length -- see the
//  function's own doc comment.
//

import Foundation
import os
import Articles
import RSParser
import RSWeb

// File-scope, not a member of AO3SeriesNavigator below: a `nonisolated static
// let` inside a `@MainActor`-isolated type is still treated by the compiler
// as main-actor-isolated when referenced from a non-isolated context (the
// `@Sendable` NotificationCenter closure in downloadAndAwait(workID:...)
// below needs it) -- moving it to file scope, outside the actor-isolated
// type entirely, is the reliable fix rather than fighting the isolation
// checker with `nonisolated`/`Self.`/concrete-type-name spelling tricks.
private let ao3SeriesNavigatorLogger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AO3SeriesNavigator")

/// A recorded page-1 walk for one series: when it happened, and the
/// pagination shape observed at the time (`pageSize` == the listing's
/// per-page work count, `totalPages` == AO3SeriesListingExtractor's parsed
/// total, `nil` if that page's listing didn't expose one -- mirrors
/// `page1TotalPages`'s existing optionality in Step 2/3 below). Read back
/// by `walkedPagination(feedID:ao3SeriesID:)` to let `.previous`/`.next`
/// skip Step 2's page-1 fetch when the cached shape already answers the
/// "which page is the target on" question (Fix 5) -- see that function's
/// own doc comment for the recency/safety reasoning.
private struct SeriesWalkRecord {
	let date: Date
	let pageSize: Int
	let totalPages: Int?
}

// Same file-scope-not-a-member reasoning as ao3SeriesNavigatorLogger above:
// AO3ChapterFetcher.checkForUpdates(for:) is itself `nonisolated` (it's a
// member of the `nonisolated` Sendable AO3ChapterFetcher class) and needs
// to invalidate this cache when an article's series content changes (see
// invalidateWalk below) -- routing that through a `Task { @MainActor in
// ... }` hop would make an otherwise-synchronous call site asynchronous
// just to touch this one piece of state. Lock-protected at file scope
// instead, mirroring the pattern AO3ChapterFetcher.attemptDates already
// uses for its own cross-call anti-hammering state, rather than changing
// AO3SeriesNavigator's own actor isolation (openSeriesWork's UI-facing
// call sites are unaffected either way).
private let seriesWalkedRecords = OSAllocatedUnfairLock(initialState: [String: SeriesWalkRecord]())

public enum AO3SeriesNavigationError: Error, Sendable, Equatable {
	/// The tapped link carried no usable target -- a `.previous`/`.next`
	/// tap with no `workurl`, or an unparseable one.
	case noAdjacentWork
	/// The series-listing page loaded but no work row was found on it
	/// (see `AO3SeriesListingExtractor.workPermalinks`).
	case emptySeriesListing
	/// The known target work id didn't appear on the page(s) actually
	/// fetched -- either the computed page number (position math assuming
	/// a contiguous, gap-free "Part N" listing) was wrong, or the listing
	/// changed between when the tapped link's data was captured and now.
	/// A hard stop, not a retry-with-a-third-page case -- see
	/// `openSeriesWork`'s Step 3.
	case seriesListingMismatch
	/// Couldn't reach AO3, or its response couldn't be read.
	case networkError(String)
	/// AO3ChapterFetcher's own fetch of the target work failed --
	/// message is the same one `.ao3ChapterFetchDidFail` carries
	/// (Cloudflare challenge, registration required, rate limit, etc.).
	case fetchFailed(String)

	public var displayMessage: String {
		switch self {
		case .noAdjacentWork:
			return NSLocalizedString("No adjacent work in this series", comment: "AO3 series navigation error")
		case .emptySeriesListing:
			return NSLocalizedString("Couldn't find that work in the series", comment: "AO3 series navigation error")
		case .seriesListingMismatch:
			return NSLocalizedString("Couldn't locate that work in the series listing", comment: "AO3 series navigation error")
		case .networkError(let message), .fetchFailed(let message):
			return message
		}
	}
}

@MainActor
public enum AO3SeriesNavigator {

	public enum Direction: Sendable, Hashable {
		case first
		case previous
		case next
	}

	#if DEBUG
	static func resetWalkedStateForTesting() {
		seriesWalkedRecords.withLock { $0 = [:] }
	}

	static func markWalkedForTesting(feedID: String, ao3SeriesID: String, pageSize: Int = 1, totalPages: Int? = 1) {
		markWalked(feedID: feedID, ao3SeriesID: ao3SeriesID, pageSize: pageSize, totalPages: totalPages)
	}
	#endif

	/// Adds (if needed) and fetches one work in the series identified by
	/// `ao3SeriesID`, returning the new/existing article's `articleID`
	/// once its content is available, so the caller can navigate the
	/// reader straight to it.
	///
	/// - Parameters:
	///   - direction: which work to open. `.first` always resolves
	///     against page 1 of the listing (AO3's work page carries no
	///     "first work in series" link of its own -- see
	///     `AO3SeriesListingExtractor`'s header comment -- so First's
	///     target is discovered from the listing, not known up front).
	///   - targetWorkURL: the adjacent work's own permalink, already known
	///     from `ArticleSeriesEntry.previousWorkURL`/`nextWorkURL` (the
	///     per-series field the tapped inline link carries in its
	///     `workurl` query item). Required for `.previous`/`.next`; unused
	///     for `.first`.
	///   - targetIndex: the target's expected 1-based "Part N" position in
	///     the series listing -- `existingArticle`'s own matching series
	///     entry's `index`, minus/plus one. Used only to compute which
	///     listing page the target should be on if it isn't found on page
	///     1; not trusted blindly (see Step 3's verification). Unused for
	///     `.first`.
	///   - existingArticle: the article the tap originated from, for its
	///     `feedID` (every stubbed/fetched work lands in this same feed)
	///     and as the cache-check scope.
	///   - account: the account `existingArticle` belongs to.
	///
	/// Bounded to at most two series-listing page fetches, regardless of
	/// series length:
	///
	/// 1. **Cache check** (`.previous`/`.next` only -- `.first`'s target
	///    id isn't known yet). If a row already exists under
	///    `existingArticle.feedID` for the target work id with content
	///    already fetched, it's returned directly. If it is only a stub,
	///    the listing shortcut is trusted only when this feed/series pair
	///    has been walked recently per `AO3PrefaceRefetchPreference`;
	///    otherwise page 1 is backfilled before the target content fetch.
	/// 1b. **Cross-feed cache check** (`.previous`/`.next` only, on a
	///    Step 1 miss): the same work may already be fetched under a
	///    *different* feed -- another series' stub-import, an
	///    Ambrosia-synced copy, a direct-URL import. When found (with
	///    content), its content/metadata is copied into a new row under
	///    `existingArticle.feedID` rather than the reader being sent to
	///    the other feed -- see `copiedParsedItem`'s own doc comment. An
	///    unfetched cross-feed stub doesn't qualify here (see that
	///    step's own comment for why); it still gets found and reused
	///    normally if/when it turns up again as a same-feed row via
	///    Steps 2/3 below.
	/// 2. **Fetch page 1**, always. This is the only fetch `.first` ever
	///    needs -- series list works in ascending Part order, so #1 is
	///    never on a later page. Every work found is batch-stubbed into
	///    the feed (one `account.updateAsync` call, not one per work).
	///    `.previous`/`.next` whose target is on this page resolve here
	///    too, no second fetch.
	/// 3. **Fetch the computed page** (`.previous`/`.next` only, when the
	///    target isn't on page 1) -- the single allowed second fetch,
	///    paced by `AO3ChapterFetcher.secondsBetweenAO3PagedRequests` before
	///    issuing it. The target's presence on this page is verified
	///    against the actually-parsed listing, not assumed from the index
	///    math alone -- if it's missing, this returns
	///    `.seriesListingMismatch` rather than trying a third page. That
	///    verification is what makes "two pages maximum" a structural
	///    guarantee.
	/// 4. **Fetch the target's real content**, via the same
	///    `AO3ChapterFetcher.shared.download` + notification-wait shape
	///    this file has always used.
	///
	/// **Accepted gap:** only page 1 and (when needed) one other computed
	/// page ever get stubbed. Works strictly between them are never
	/// pre-imported by this flow -- they still work correctly if opened
	/// directly later (`bookKey`/`BookStateTable` sharing doesn't depend
	/// on having been pre-stubbed), they just don't appear as rows in the
	/// timeline until then. Deliberate cost of the two-page cap, not an
	/// incomplete-import bug.
	///
	/// **Dedup:** every listing page includes whatever work the user is
	/// currently reading (that's how they got here), so a naive stub-
	/// every-row pass would create a second row for it whenever its
	/// existing `uniqueID` doesn't happen to equal its bare AO3 work id --
	/// the normal case for an Ambrosia-synced article. `Article.bookKey`
	/// (routed through `AO3ChapterFetcher.ao3WorkID(fromBookKey:)`) is a
	/// reliable, already-existing cross-scheme identity key for "is this
	/// AO3 work already in this feed," independent of whichever `uniqueID`
	/// scheme produced the row -- see `existingArticlesByWorkID` below,
	/// computed once per call and used both to skip re-stubbing an
	/// already-present work and to resolve the real `articleID` a target
	/// should be refetched under, rather than always computing a fresh
	/// one from a bare `workID`.
	public static func openSeriesWork(
		ao3SeriesID: String,
		direction: Direction,
		targetWorkURL: String?,
		targetIndex: Int?,
		existingArticle: Article,
		account: Account
	) async -> Result<String, AO3SeriesNavigationError> {

		ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork ao3SeriesID=\(ao3SeriesID, privacy: .public) direction=\(String(describing: direction), privacy: .public) targetWorkURL=\(targetWorkURL ?? "nil", privacy: .public) targetIndex=\(targetIndex.map(String.init) ?? "nil", privacy: .public) existingArticleID=\(existingArticle.articleID, privacy: .public)")

		let knownTargetWorkID: String?
		switch direction {
		case .first:
			knownTargetWorkID = nil
		case .previous, .next:
			guard let targetWorkURL, let workID = AO3SummaryExtractor.ao3WorkID(fromPermalink: targetWorkURL) else {
				return .failure(.noAdjacentWork)
			}
			knownTargetWorkID = workID
		}

		// Fetched once, reused by the cache check below, target
		// resolution (all three directions, including .first), and both
		// stub-import passes -- see existingArticlesByWorkID's own doc
		// comment for why this is what actually prevents the
		// currently-open work from getting stubbed as a duplicate.
		let existingByWorkID = await existingArticlesByWorkID(feedID: existingArticle.feedID, account: account)

		// Step 0.5: .first's own equivalent of Step 1 -- Step 1 itself is
		// skipped entirely for .first below, since its target id isn't
		// known without a listing fetch. But if this feed/series pair was
		// walked recently, the index-1 work is already sitting in
		// existingByWorkID from that walk's stub-import, so .first doesn't
		// need a fresh page-1 fetch just to re-learn what it already
		// knows. Falls through to Step 1/2 below (page 1 fetch) when no
		// recent walk exists or no index-1 entry is found in it.
		if direction == .first, isWalkRecent(feedID: existingArticle.feedID, ao3SeriesID: ao3SeriesID),
		   let firstEntry = existingByWorkID.values.first(where: { article in
			   article.series?.contains(where: { $0.ao3ID == ao3SeriesID && $0.index == 1 }) ?? false
		   }) {
			ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork .first satisfied from recent walk, workID=\(firstEntry.bookKey, privacy: .public)")
			let workID = AO3ChapterFetcher.ao3WorkID(fromBookKey: firstEntry.bookKey) ?? firstEntry.uniqueID
			return await downloadAndAwait(workID: workID, existingArticleID: firstEntry.articleID, feedID: existingArticle.feedID, account: account)
		}

		// Step 1: cache check -- skipped entirely for .first, whose
		// target id isn't known until page 1 is parsed below (except for
		// the recent-walk shortcut just above, .first's own equivalent of
		// this step).
		//
		// A previously-fetched article (contentHTML != nil) returns
		// immediately, no network activity at all. A previously-stubbed-
		// but-never-opened row (contentHTML == nil) only skips the listing
		// fetch when this feed/series pair has a recent page-1 walk on
		// file. Otherwise the stub may have arrived from unrelated search
		// or import work, so do a one-page backfill before fetching the
		// target's content.
		if let knownTargetWorkID, let existing = existingByWorkID[knownTargetWorkID] {
			if existing.contentHTML != nil {
				ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork cache hit with content, workID=\(knownTargetWorkID, privacy: .public) articleID=\(existing.articleID, privacy: .public)")
				return .success(existing.articleID)
			}
			if isWalkRecent(feedID: existingArticle.feedID, ao3SeriesID: ao3SeriesID) {
				ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork cache hit as stub with recent walk, workID=\(knownTargetWorkID, privacy: .public) articleID=\(existing.articleID, privacy: .public), fetching directly")
				return await downloadAndAwait(workID: knownTargetWorkID, existingArticleID: existing.articleID, feedID: existingArticle.feedID, account: account)
			}

			ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork cache hit as stub without recent walk, attempting page-1 backfill, workID=\(knownTargetWorkID, privacy: .public) articleID=\(existing.articleID, privacy: .public)")
			if let page1HTML = await fetchListingPage(ao3SeriesID: ao3SeriesID, page: 1) {
				let (page1Works, _, page1TotalPages) = AO3SeriesListingExtractor.workPermalinks(fromSeriesListingHTML: page1HTML)
				let newPage1Works = page1Works.filter { existingByWorkID[$0.workID] == nil }
				await stubImport(newPage1Works, feedID: existingArticle.feedID, account: account)
				markWalked(feedID: existingArticle.feedID, ao3SeriesID: ao3SeriesID, pageSize: page1Works.count, totalPages: page1TotalPages)
				ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork stub-hit backfill parsed workCount=\(page1Works.count, privacy: .public) newStubs=\(newPage1Works.count, privacy: .public)")
			} else {
				ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork stub-hit backfill page-1 fetch failed, proceeding to target workID=\(knownTargetWorkID, privacy: .public)")
			}
			return await downloadAndAwait(workID: knownTargetWorkID, existingArticleID: existing.articleID, feedID: existingArticle.feedID, account: account)
		}

		// Step 1b (Bug 3b): cross-feed reuse. Same idea as Step 1, but
		// looking account-wide rather than only under existingArticle's
		// own feed -- the work may already be sitting, fully fetched, in
		// a different feed (a different series' stub-import pass, an
		// Ambrosia-synced copy elsewhere, a direct-URL import, etc.).
		// Only a *fetched* cross-feed copy (contentHTML != nil) is worth
		// this: an unfetched cross-feed stub carries no more information
		// than page 1 is about to give us for free, and copying it in
		// would still need a listing-page-equivalent position lookup
		// this function doesn't have another way to get. Copies the
		// other feed's content into a *new* row under
		// existingArticle.feedID (per product decision: reuse-in-place
		// was rejected because every other row this navigator produces
		// lives under existingArticle.feedID, and the reader's "which
		// feed is this series in" model assumes that) rather than
		// navigating the reader to the other feed directly.
		if let knownTargetWorkID, existingByWorkID[knownTargetWorkID] == nil {
			let crossFeedMatches = await account.fetchArticlesAsync(bookKeys: [AO3ChapterFetcher.bookKey(forWorkID: knownTargetWorkID)])
			// Prefer whichever cross-feed copy actually has content, same
			// self-healing precedent existingArticlesByWorkID's own dedup
			// already uses for an in-feed duplicate.
			if let sourceArticle = crossFeedMatches.first(where: { $0.contentHTML != nil }) {
				ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork cross-feed cache hit, workID=\(knownTargetWorkID, privacy: .public) sourceArticleID=\(sourceArticle.articleID, privacy: .public), copying into feedID=\(existingArticle.feedID, privacy: .public)")
				let copiedItem = copiedParsedItem(from: sourceArticle, feedID: existingArticle.feedID)
				_ = await account.updateAsync(feedID: existingArticle.feedID, parsedItems: [copiedItem], deleteOlder: false)
				return .success(Article.calculatedArticleID(feedID: existingArticle.feedID, uniqueID: knownTargetWorkID))
			}
		}

		ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork no cache hit (same-feed or cross-feed), fetching page 1")

		// Fix 5: for .previous/.next only (.first is already routed around
		// Step 2 by the recent-walk shortcut above when it applies), skip
		// this unconditional page-1 fetch when a recent walk's cached
		// pagination already answers "which page is the target on" and
		// that page isn't page 1. fetchTargetOnComputedPage's own
		// membership check below is what keeps this safe if the series
		// shifted since the cached walk -- worst case is a
		// .seriesListingMismatch, not wrong content written anywhere. If
		// the cached math instead says the target should be on page 1, or
		// the cached totalPages can't support the computed page (a
		// shrunk/stale series), there's no cached listing content to
		// check membership against -- fall through to the ordinary fresh
		// fetch below, which also refreshes the cached pagination for
		// next time.
		if direction != .first, let knownTargetWorkID, let targetIndex,
		   let cachedPagination = walkedPagination(feedID: existingArticle.feedID, ao3SeriesID: ao3SeriesID) {
			let cachedTargetPage = Int((Double(targetIndex) / Double(cachedPagination.pageSize)).rounded(.up))
			if cachedTargetPage > 1, let cachedTotalPages = cachedPagination.totalPages, cachedTargetPage <= cachedTotalPages {
				ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork skipping page-1 fetch via cached pagination, going straight to page \(cachedTargetPage, privacy: .public), workID=\(knownTargetWorkID, privacy: .public) targetIndex=\(targetIndex, privacy: .public) cachedPageSize=\(cachedPagination.pageSize, privacy: .public)")
				return await fetchTargetOnComputedPage(cachedTargetPage, targetWorkID: knownTargetWorkID, ao3SeriesID: ao3SeriesID, existingByWorkID: existingByWorkID, existingArticle: existingArticle, account: account)
			}
		}

		// Step 2: page 1, always (unless the shortcut above already returned).
		guard let page1HTML = await fetchListingPage(ao3SeriesID: ao3SeriesID, page: 1) else {
			ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork page 1 fetch failed, ao3SeriesID=\(ao3SeriesID, privacy: .public)")
			return .failure(.networkError(NSLocalizedString("Couldn't load the series page", comment: "AO3 series navigation error")))
		}
		let (page1Works, _, page1TotalPages) = AO3SeriesListingExtractor.workPermalinks(fromSeriesListingHTML: page1HTML)
		guard !page1Works.isEmpty else {
			ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork page 1 parsed but empty, ao3SeriesID=\(ao3SeriesID, privacy: .public)")
			return .failure(.emptySeriesListing)
		}
		// The currently-open work (always present on page 1) is filtered
		// out here instead of being handed to stubImport/updateAsync as a
		// competing row under a fresh uniqueID -- this is what actually
		// kills the duplicate.
		let newPage1Works = page1Works.filter { existingByWorkID[$0.workID] == nil }
		ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork page 1 parsed, workCount=\(page1Works.count, privacy: .public) newStubs=\(newPage1Works.count, privacy: .public)")
		await stubImport(newPage1Works, feedID: existingArticle.feedID, account: account)
		markWalked(feedID: existingArticle.feedID, ao3SeriesID: ao3SeriesID, pageSize: page1Works.count, totalPages: page1TotalPages)

		let targetWorkID: String
		switch direction {
		case .first:
			targetWorkID = page1Works[0].workID
		case .previous, .next:
			guard let knownTargetWorkID else {
				return .failure(.noAdjacentWork)
			}
			targetWorkID = knownTargetWorkID
		}

		if page1Works.contains(where: { $0.workID == targetWorkID }) {
			ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork target found on page 1, workID=\(targetWorkID, privacy: .public)")
			// existingByWorkID is a snapshot taken before stubImport above
			// ran, so it never has an entry for a work that only just got
			// stubbed by *this* call -- the normal case, since a
			// pre-existing entry would have already returned via Step 1's
			// cache check. Falling back to the deterministic
			// calculatedArticleID (same feedID/uniqueID stubImport just
			// wrote under) means downloadAndAwait treats this as an
			// existing row instead of taking its own no-existing-row
			// fallback branch, which would otherwise immediately
			// overwrite the listing-derived title stubImport just wrote
			// with its own generic "AO3 Work %@" placeholder.
			let targetArticleID = existingByWorkID[targetWorkID]?.articleID ?? Article.calculatedArticleID(feedID: existingArticle.feedID, uniqueID: targetWorkID)
			return await downloadAndAwait(workID: targetWorkID, existingArticleID: targetArticleID, feedID: existingArticle.feedID, account: account)
		}

		// .first's target is always page1Works[0], so it can never reach
		// here -- only .previous/.next fall through to the second fetch.

		// Step 3: the single allowed second fetch, only when the target's
		// position math says it isn't on page 1.
		guard let targetIndex else {
			ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork target not on page 1 and no targetIndex to compute a second page, workID=\(targetWorkID, privacy: .public)")
			return .failure(.seriesListingMismatch)
		}
		let pageSize = page1Works.count
		let targetPage = Int((Double(targetIndex) / Double(pageSize)).rounded(.up))
		guard targetPage > 1 else {
			// The index math says the target should have been on page 1,
			// but it wasn't found there -- treat as a mismatch rather
			// than silently fetching page 1 again.
			ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork targetIndex math says page 1 but target wasn't there, workID=\(targetWorkID, privacy: .public) targetIndex=\(targetIndex, privacy: .public)")
			return .failure(.seriesListingMismatch)
		}
		guard let page1TotalPages, targetPage <= page1TotalPages else {
			ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork computed page \(targetPage, privacy: .public) exceeds known total pages \(page1TotalPages.map(String.init) ?? "nil", privacy: .public), workID=\(targetWorkID, privacy: .public)")
			return .failure(.seriesListingMismatch)
		}

		ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork fetching computed page \(targetPage, privacy: .public) for workID=\(targetWorkID, privacy: .public) targetIndex=\(targetIndex, privacy: .public) pageSize=\(pageSize, privacy: .public)")
		return await fetchTargetOnComputedPage(targetPage, targetWorkID: targetWorkID, ao3SeriesID: ao3SeriesID, existingByWorkID: existingByWorkID, existingArticle: existingArticle, account: account)
	}
}

private extension AO3SeriesNavigator {

	nonisolated static func walkKey(feedID: String, ao3SeriesID: String) -> String {
		"\(feedID)|\(ao3SeriesID)"
	}

	static func isWalkRecent(feedID: String, ao3SeriesID: String) -> Bool {
		let key = walkKey(feedID: feedID, ao3SeriesID: ao3SeriesID)
		guard let record = seriesWalkedRecords.withLock({ $0[key] }) else {
			return false
		}
		return Date().timeIntervalSince(record.date) < AO3PrefaceRefetchPreference.current.timeInterval
	}

	static func markWalked(feedID: String, ao3SeriesID: String, pageSize: Int, totalPages: Int?) {
		let key = walkKey(feedID: feedID, ao3SeriesID: ao3SeriesID)
		let record = SeriesWalkRecord(date: Date(), pageSize: pageSize, totalPages: totalPages)
		seriesWalkedRecords.withLock { $0[key] = record }
	}

	/// The cached pagination shape from the most recent walk, only when
	/// that walk is still recent by the same cadence `isWalkRecent` checks
	/// -- a stale walk's pagination is exactly as untrustworthy as a stale
	/// walk's target-membership assumption, so this deliberately reuses
	/// the same recency gate rather than having its own. `nil` whenever
	/// `isWalkRecent` would also be `nil`/`false`, or when no walk has
	/// happened at all for this feed/series pair.
	static func walkedPagination(feedID: String, ao3SeriesID: String) -> (pageSize: Int, totalPages: Int?)? {
		let key = walkKey(feedID: feedID, ao3SeriesID: ao3SeriesID)
		guard let record = seriesWalkedRecords.withLock({ $0[key] }) else {
			return nil
		}
		guard Date().timeIntervalSince(record.date) < AO3PrefaceRefetchPreference.current.timeInterval else {
			return nil
		}
		return (record.pageSize, record.totalPages)
	}

	/// Existing articles under `feedID`, keyed by AO3 work id (recovered
	/// from `bookKey` -- always present for AO3-sourced articles per
	/// every producer in this codebase: `JSONFeedParser` for
	/// Ambrosia-synced items, `AO3ChapterFetcher.rebuildParsedItem` for
	/// real-fetch refetches, and this navigator's own stubs). Fetched
	/// once per `openSeriesWork` call and reused by the cache check,
	/// `.first`'s target resolution, and both stub-import passes, so
	/// nothing this function does ever creates a second row for a work
	/// that's already in the feed under some other `uniqueID` scheme
	/// (Ambrosia sync being the common case, since the currently-open
	/// article is always a member of the series page(s) this function
	/// fetches).
	static func existingArticlesByWorkID(feedID: String, account: Account) async -> [String: Article] {
		guard let feed = account.existingFeed(withFeedID: feedID) else {
			return [:]
		}
		let articles = await account.fetchArticlesAsync(.feed(feed))
		var result: [String: Article] = [:]
		for article in articles {
			guard let workID = AO3ChapterFetcher.ao3WorkID(fromBookKey: article.bookKey) else { continue }
			// If a pre-fix duplicate already exists for this workID,
			// prefer whichever copy actually has content, self-healing
			// old dupes rather than picking one arbitrarily.
			if let existing = result[workID], existing.contentHTML != nil { continue }
			result[workID] = article
		}
		return result
	}

	/// The single allowed second listing-page fetch (Step 3), shared
	/// between the ordinary page-1-then-computed-page fallback and Fix 5's
	/// cached-pagination shortcut that skips straight here without ever
	/// fetching page 1 this round. Paced by
	/// `AO3ChapterFetcher.secondsBetweenAO3PagedRequests` before issuing the
	/// request, same anti-hammering precedent the original inline Step 3
	/// used. Every work found on `targetPage` is stubbed (same dedup
	/// against `existingByWorkID` Step 2 uses) before the membership check
	/// below, so a work stubbed here is still picked up if the person
	/// navigates to it directly later even if this call's own target
	/// verification fails. `pageNWorks.contains(where:)` is the actual
	/// safety net for both callers: a stale cached `pageSize`/`totalPages`
	/// (Fix 5's shortcut) or a series that simply changed shape between
	/// page-1 parse and now both fail here as `.seriesListingMismatch`
	/// rather than ever writing wrong content.
	static func fetchTargetOnComputedPage(_ targetPage: Int, targetWorkID: String, ao3SeriesID: String, existingByWorkID: [String: Article], existingArticle: Article, account: Account) async -> Result<String, AO3SeriesNavigationError> {
		ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork fetching computed page \(targetPage, privacy: .public) for workID=\(targetWorkID, privacy: .public)")
		try? await Task.sleep(nanoseconds: UInt64(AO3ChapterFetcher.secondsBetweenAO3PagedRequests * 1_000_000_000))

		guard let pageNHTML = await fetchListingPage(ao3SeriesID: ao3SeriesID, page: targetPage) else {
			ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork page \(targetPage, privacy: .public) fetch failed, ao3SeriesID=\(ao3SeriesID, privacy: .public)")
			return .failure(.networkError(NSLocalizedString("Couldn't load the series page", comment: "AO3 series navigation error")))
		}
		let (pageNWorks, _, _) = AO3SeriesListingExtractor.workPermalinks(fromSeriesListingHTML: pageNHTML)
		// Same filter as Step 2, against the same shared map -- page N is
		// very unlikely to contain the current article, but a target
		// reached via .previous/.next from a different session could
		// already be present as a stub from an earlier tap.
		let newPageNWorks = pageNWorks.filter { existingByWorkID[$0.workID] == nil }
		ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork page \(targetPage, privacy: .public) parsed, workCount=\(pageNWorks.count, privacy: .public) newStubs=\(newPageNWorks.count, privacy: .public)")
		await stubImport(newPageNWorks, feedID: existingArticle.feedID, account: account)

		guard pageNWorks.contains(where: { $0.workID == targetWorkID }) else {
			ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork target not found on computed page \(targetPage, privacy: .public), workID=\(targetWorkID, privacy: .public) -- mismatch")
			return .failure(.seriesListingMismatch)
		}

		ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: openSeriesWork target found on computed page \(targetPage, privacy: .public), workID=\(targetWorkID, privacy: .public)")
		// Same stale-snapshot fallback as the page-1 branch in
		// openSeriesWork -- existingByWorkID predates this page's
		// stubImport call (and, for the fresh-fetch caller, page 1's too),
		// so a work stubbed by either still needs the deterministic-ID
		// fallback here.
		let targetArticleID = existingByWorkID[targetWorkID]?.articleID ?? Article.calculatedArticleID(feedID: existingArticle.feedID, uniqueID: targetWorkID)
		return await downloadAndAwait(workID: targetWorkID, existingArticleID: targetArticleID, feedID: existingArticle.feedID, account: account)
	}

	/// `GET https://archiveofourown.org/series/<id>` for page 1 (bare, no
	/// query string -- AO3's own page-1-is-bare-URL convention), or
	/// `.../series/<id>?page=<n>` for `n >= 2`. Authenticated-first when a
	/// session is stored, mirroring `AO3ChapterFetcher.download`'s shape
	/// -- a real gap otherwise for a restricted work in a series, since
	/// this function previously had no authenticated path at all. Falls
	/// back to the existing anonymous `Downloader.shared` path only on an
	/// authentication-shaped failure (a non-OK/empty authenticated
	/// response, a detected Cloudflare challenge, or a thrown network
	/// error) -- callers only ever see the resulting HTML (or nil), so
	/// which path succeeded is logged here, not surfaced through the
	/// return type. Both the authenticated and anonymous branches check
	/// for a Cloudflare interstitial (`AO3CloudflareChallenge`, same
	/// marker list `AO3SearchResultsFetcher` uses) before handing HTML
	/// back to a caller -- this function has no result type to represent
	/// "challenged" separately (unlike `AO3SearchResultsFetchOutcome`),
	/// so a detected challenge is treated as a failed attempt: the
	/// authenticated branch falls back to anonymous, and the anonymous
	/// branch returns nil rather than returning interstitial HTML as if
	/// it were real series-listing content for
	/// `AO3SeriesListingExtractor` to misparse.
	static func fetchListingPage(ao3SeriesID: String, page: Int) async -> String? {
		var urlString = "https://archiveofourown.org/series/\(ao3SeriesID)"
		if page > 1 {
			urlString += "?page=\(page)"
		}
		guard let url = URL(string: urlString) else {
			return nil
		}

		if AO3SessionStore.isSignedIn {
			do {
				if let (data, response) = try await AO3AuthenticatedFetcher.fetch(url) {
					if response.statusIsOK, !data.isEmpty, let html = String(data: data, encoding: .utf8) {
						if AO3CloudflareChallenge.isChallengePage(html) {
							ao3SeriesNavigatorLogger.info("AO3SeriesNavigator: fetchListingPage authenticated attempt hit a Cloudflare challenge for \(url.absoluteString, privacy: .public) -- retrying anonymously")
						} else {
							return html
						}
					} else {
						ao3SeriesNavigatorLogger.info("AO3SeriesNavigator: fetchListingPage authenticated attempt got bad response for \(url.absoluteString, privacy: .public) -- retrying anonymously")
					}
				}
				// A nil result means the session was cleared between the
				// isSignedIn check and the fetch (concurrent sign-out) --
				// fall through to the anonymous path below either way.
			} catch {
				// Network-level failure on the authenticated attempt --
				// not a login problem, so the stored session is left
				// alone; fall back to the anonymous path rather than
				// returning nil outright.
				ao3SeriesNavigatorLogger.info("AO3SeriesNavigator: fetchListingPage authenticated attempt threw (\(error.localizedDescription, privacy: .public)) for \(url.absoluteString, privacy: .public) -- retrying anonymously")
			}
		}

		guard let downloadResponse = try? await Downloader.shared.download(url) else {
			return nil
		}
		guard let data = downloadResponse.data, !data.isEmpty,
		      let response = downloadResponse.response, response.statusIsOK,
		      let html = String(data: data, encoding: .utf8) else {
			return nil
		}
		guard !AO3CloudflareChallenge.isChallengePage(html) else {
			ao3SeriesNavigatorLogger.info("AO3SeriesNavigator: fetchListingPage anonymous attempt hit a Cloudflare challenge for \(url.absoluteString, privacy: .public)")
			return nil
		}
		return html
	}

	/// Bug 3b (cross-feed reuse): builds a `ParsedItem` for
	/// `existingArticle.feedID` that copies `sourceArticle`'s already-
	/// fetched content and metadata wholesale, under this file's own
	/// bare-`workID` `uniqueID` convention (not `sourceArticle`'s own
	/// `uniqueID`, which may use a different scheme -- Ambrosia sync
	/// being the common case). `workID` is threaded through separately
	/// rather than recovered from `sourceArticle.bookKey` at the call
	/// site, since the caller already has it as `knownTargetWorkID`.
	///
	/// Authors/series need their own `Article` -> `Parsed*` conversions
	/// (the reverse of `Article+Database.swift`'s `ParsedItem` -> ...
	/// mapping) -- same shape `AO3ChapterFetcher.rebuildParsedItem`
	/// already uses for its own existingArticle-carries-forward cases.
	/// `lastPrefaceFetchDate` is carried forward too: the copy is exactly
	/// as fresh as the source fetch was, not "just fetched now," so
	/// `AO3ChapterFetcher.isStale` shouldn't treat it as newly-stale on
	/// the next open.
	static func copiedParsedItem(from sourceArticle: Article, feedID: String) -> ParsedItem {
		let workID = AO3ChapterFetcher.ao3WorkID(fromBookKey: sourceArticle.bookKey) ?? sourceArticle.uniqueID
		let authors: Set<ParsedAuthor>? = sourceArticle.authors.map { authorSet in
			Set(authorSet.map { ParsedAuthor(name: $0.name, url: $0.url, avatarURL: $0.avatarURL, emailAddress: $0.emailAddress) })
		}
		let series: [ParsedSeriesEntry]? = sourceArticle.series?.map {
			ParsedSeriesEntry(name: $0.name, index: $0.index, ao3ID: $0.ao3ID, previousWorkURL: $0.previousWorkURL, nextWorkURL: $0.nextWorkURL)
		}
		return ParsedItem(
			syncServiceID: nil,
			uniqueID: workID,
			feedURL: feedID,
			url: sourceArticle.rawLink,
			externalURL: sourceArticle.rawExternalLink,
			title: sourceArticle.title,
			language: nil,
			contentHTML: sourceArticle.contentHTML,
			contentText: sourceArticle.contentText,
			markdown: sourceArticle.markdown,
			summary: sourceArticle.summary,
			imageURL: sourceArticle.rawImageLink,
			bannerImageURL: nil,
			datePublished: sourceArticle.datePublished,
			dateModified: sourceArticle.dateModified,
			authors: authors,
			tags: sourceArticle.additionalTags.map { Set($0) },
			attachments: nil,
			isAmbrosiaItem: sourceArticle.isAmbrosiaItem,
			wordCount: sourceArticle.wordCount,
			chapterCurrent: sourceArticle.chapterCurrent,
			chapterTotal: sourceArticle.chapterTotal,
			isComplete: sourceArticle.isComplete,
			fandoms: sourceArticle.fandoms,
			relationships: sourceArticle.relationships,
			characters: sourceArticle.characters,
			ratings: sourceArticle.ratings,
			warnings: sourceArticle.warnings,
			categories: sourceArticle.categories,
			series: series,
			commentCount: sourceArticle.commentCount,
			kudosCount: sourceArticle.kudosCount,
			bookmarkCount: sourceArticle.bookmarkCount,
			hitCount: sourceArticle.hitCount,
			lastPrefaceFetchDate: sourceArticle.lastPrefaceFetchDate,
			ao3WorkID: workID
		)
	}

	/// Batch-stubs every work found on one fetched listing page into
	/// `feedID`, one `account.updateAsync` call for the whole page (per
	/// its own doc comment about being written around one feed-shaped
	/// batch, not one call per work). Uses the listing row's own,
	/// already-parsed metadata (Phase 4b, extended by the listing-
	/// metadata follow-up to cover summary/fandoms/tags/word count, not
	/// just title) -- every work here except the one this call is
	/// ultimately opening still stays an unfetched stub with no
	/// `contentHTML` until it's next opened directly, same "content
	/// fetched only on open" contract as any other AO3-sourced stub in
	/// this app; only the placeholder's metadata is upgraded from the
	/// bare generic defaults, since it's already sitting unused on the
	/// row and costs nothing further to thread through. A later real
	/// fetch still always wins: `AO3ChapterFetcher.rebuildParsedItem`
	/// prefers the live work page's own metadata over whatever's already
	/// stored, falling back to the stored value only when the live page
	/// didn't have that field at all -- so a listing-derived stub value
	/// never lingers stale past the work's first real open.
	static func stubImport(_ works: [AO3SeriesListingExtractor.WorkListingEntry], feedID: String, account: Account) async {
		guard !works.isEmpty else {
			return
		}
		let stubs = Set(works.map { placeholderStub(from: $0, feedID: feedID) })
		_ = await account.updateAsync(feedID: feedID, parsedItems: stubs, deleteOlder: false)
	}

	/// `uniqueID: workID` (not the row's own `permalink`) -- matching
	/// `downloadAndAwait`'s `Article.calculatedArticleID(feedID:uniqueID:)`
	/// fallback and every other AO3-work `bookKey` derivation in this
	/// file. `AO3SearchResultsExtractor.parsedItem(fromWorkLI:)` uses
	/// `permalink` for its own `uniqueID` instead, but that's a different
	/// call site (search-results feed import) with its own established
	/// identity scheme; reusing its row-metadata helpers here doesn't
	/// mean reusing that convention too.
	static func placeholderStub(from entry: AO3SeriesListingExtractor.WorkListingEntry, feedID: String) -> ParsedItem {
		ParsedItem(
			syncServiceID: nil,
			uniqueID: entry.workID,
			feedURL: feedID,
			url: entry.permalink,
			externalURL: nil,
			title: entry.title,
			language: nil,
			contentHTML: nil,
			contentText: nil,
			markdown: nil,
			summary: entry.summary,
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			tags: entry.freeformTags.isEmpty ? nil : Set(entry.freeformTags),
			attachments: nil,
			wordCount: entry.wordCount,
			fandoms: entry.fandoms.isEmpty ? nil : entry.fandoms,
			relationships: entry.relationships.isEmpty ? nil : entry.relationships,
			characters: entry.characters.isEmpty ? nil : entry.characters,
			ratings: entry.ratings.isEmpty ? nil : entry.ratings,
			warnings: entry.warnings.isEmpty ? nil : entry.warnings,
			categories: entry.categories.isEmpty ? nil : entry.categories,
			ao3WorkID: entry.workID
		)
	}

	/// Generic placeholder for the no-listing-row case (a bare `workID`
	/// with no parsed metadata at all) -- `downloadAndAwait`'s own
	/// belt-and-suspenders stub when it's called without an existing row.
	/// Kept separate from `placeholderStub(from:feedID:)` above rather
	/// than threading a synthetic all-nil `WorkListingEntry` through it,
	/// since this path never has real listing data to lose.
	static func placeholderStub(workID: String, permalink: String, title: String, feedID: String) -> ParsedItem {
		ParsedItem(
			syncServiceID: nil,
			uniqueID: workID,
			feedURL: feedID,
			url: permalink,
			externalURL: nil,
			title: title,
			language: nil,
			contentHTML: nil,
			contentText: nil,
			markdown: nil,
			summary: nil,
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			tags: nil,
			attachments: nil,
			ao3WorkID: workID
		)
	}

	/// Fetches `workID`'s real content via
	/// `AO3ChapterFetcher.download(workID:articleID:accountID:feedID:)`,
	/// reusing its existing Cloudflare/registration-required/rate-limit
	/// handling rather than re-implementing it here.
	///
	/// `existingArticleID`, when non-nil, is the caller's already-resolved
	/// row for this work (from `existingArticlesByWorkID`, keyed on
	/// `bookKey` -- independent of whatever `uniqueID` scheme produced the
	/// row). Reusing it here, instead of always computing a fresh
	/// `Article.calculatedArticleID(feedID:uniqueID:)` from the bare
	/// `workID`, is what stops this function from creating a second row
	/// for a work that's already in the feed under a different `uniqueID`
	/// (Ambrosia sync being the common case). When it's nil -- no existing
	/// row for this work under any scheme -- this falls back to computing
	/// `articleID` the original way and stubbing one before the fetch, so
	/// `download`'s own `articleID`-only lookup (`AO3ChapterFetcher.swift`,
	/// "Article no longer exists" otherwise) has a row to find.
	///
	/// Waits on the notification pair `download` posts rather than
	/// re-querying the database afterward, since `articleID` is known
	/// up front either way.
	static func downloadAndAwait(workID: String, existingArticleID: String?, feedID: String, account: Account) async -> Result<String, AO3SeriesNavigationError> {
		ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: downloadAndAwait starting, workID=\(workID, privacy: .public) existingArticleID=\(existingArticleID ?? "nil", privacy: .public)")
		let articleID: String
		if let existingArticleID {
			// Reusing an existing row -- refresh it in place, no stub
			// creation, no risk of a duplicate under a fresh workID-based
			// uniqueID.
			articleID = existingArticleID
		} else {
			articleID = Article.calculatedArticleID(feedID: feedID, uniqueID: workID)

			// Belt-and-suspenders: openSeriesWork's own page-1/page-N walk
			// always stubs the target before calling this when there's no
			// existing row, but this entry point doesn't assume that -- a
			// stub-less call is still safe (deleteOlder: false, stable
			// uniqueID) and keeps this function usable on its own. No
			// listing row is available here (only a bare workID), so this
			// stub still uses the generic placeholder title/permalink --
			// irrelevant within moments anyway, since the real fetch this
			// function awaits immediately overwrites both via
			// rebuildParsedItem.
			_ = await account.updateAsync(feedID: feedID, parsedItems: [placeholderStub(workID: workID, permalink: "https://archiveofourown.org/works/\(workID)", title: String(format: NSLocalizedString("AO3 Work %@", comment: "Series-navigation placeholder title, before the work is fetched"), workID), feedID: feedID)], deleteOlder: false)
		}

		return await withCheckedContinuation { continuation in
			// NotificationCenter's addObserver(...using:) closure parameter
			// is @Sendable, and NSObjectProtocol (what addObserver returns)
			// isn't itself Sendable -- an unchecked box is used here rather
			// than threading the tokens through OSAllocatedUnfairLock's
			// generic state, since the lock's own Sendable requirement on
			// its State type rejects NSObjectProtocol just as directly.
			// Safe in practice: both observers only ever fire on queue:
			// .main, and removeObserver is called at most once, from
			// finish, gated by the same shouldResume check that also
			// guards continuation.resume.
			final class TokenBox: @unchecked Sendable {
				var tokens: [NSObjectProtocol] = []
			}
			let tokenBox = TokenBox()
			let didResume = OSAllocatedUnfairLock(initialState: false)

			@Sendable func finish(_ result: Result<String, AO3SeriesNavigationError>) {
				let shouldResume = didResume.withLock { resumed -> Bool in
					guard !resumed else { return false }
					resumed = true
					return true
				}
				guard shouldResume else { return }
				tokenBox.tokens.forEach(NotificationCenter.default.removeObserver)
				continuation.resume(returning: result)
			}

			let completeToken = NotificationCenter.default.addObserver(forName: .ao3ChapterFetchDidComplete, object: nil, queue: .main) { note in
				guard note.userInfo?[AO3ChapterFetchUserInfoKey.articleID] as? String == articleID else { return }
				ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: downloadAndAwait succeeded, workID=\(workID, privacy: .public) articleID=\(articleID, privacy: .public)")
				finish(.success(articleID))
			}
			let failToken = NotificationCenter.default.addObserver(forName: .ao3ChapterFetchDidFail, object: nil, queue: .main) { note in
				guard note.userInfo?[AO3ChapterFetchUserInfoKey.articleID] as? String == articleID else { return }
				let message = note.userInfo?[AO3ChapterFetchUserInfoKey.message] as? String ?? NSLocalizedString("Couldn't load this work", comment: "AO3 series navigation error")
				ao3SeriesNavigatorLogger.debug("AO3SeriesNavigator: downloadAndAwait failed, workID=\(workID, privacy: .public) articleID=\(articleID, privacy: .public) message=\(message, privacy: .public)")
				finish(.failure(.fetchFailed(message)))
			}
			tokenBox.tokens = [completeToken, failToken]

			AO3ChapterFetcher.shared.download(workID: workID, articleID: articleID, accountID: account.accountID, feedID: feedID)
		}
	}
}

// MARK: - Cross-file walk-cache invalidation

extension AO3SeriesNavigator {

	/// Invalidates any recorded walk for the given series IDs under
	/// `feedID` -- called by AO3ChapterFetcher.checkForUpdates(for:) when a
	/// fetch changes an article's own chapter content, since that content
	/// change can shift the article's position within any series it
	/// belongs to (a new chapter can itself be posted as a new series
	/// entry) in a way a stale cached walk wouldn't reflect. `nonisolated`
	/// rather than a member of the `@MainActor` AO3SeriesNavigator type
	/// above, since checkForUpdates(for:) is itself nonisolated and calls
	/// this synchronously, with no actor hop -- safe because the
	/// underlying storage (seriesWalkedRecords) is lock-protected at file
	/// scope, not actor-isolated. Deliberately declared in a plain
	/// (internal-access) extension rather than alongside walkKey/
	/// isWalkRecent/markWalked/walkedPagination in the `private extension`
	/// above: those are only ever called from within this file, but this
	/// one is called from AO3ChapterFetcher.swift, and `private extension`
	/// caps every member's effective access at `fileprivate` -- file-scoped,
	/// not just extension-scoped -- which would make this uncallable from
	/// another file in the same module despite `nonisolated static` looking
	/// unrestricted. Static rather than a member of AO3SeriesNavigator for
	/// the same reason walkKey/isWalkRecent/markWalked are: this is
	/// namespaced under AO3SeriesNavigator for discoverability, not because
	/// it needs the type's own actor isolation.
	nonisolated static func invalidateWalk(feedID: String, ao3SeriesIDs: [String]) {
		guard !ao3SeriesIDs.isEmpty else {
			return
		}
		let keys = ao3SeriesIDs.map { walkKey(feedID: feedID, ao3SeriesID: $0) }
		seriesWalkedRecords.withLock { records in
			for key in keys {
				records.removeValue(forKey: key)
			}
		}
	}
}
