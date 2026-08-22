//
//  AO3SearchResultsPaginator.swift
//  Account
//
//  Nectar AO3 search-results refresh-cadence work, Workstream D
//  ("Load more results" pagination).
//
//  Same shape as AO3SeriesNavigator: a standalone @MainActor public enum
//  for one-off, explicitly-triggered fetches that deliberately does NOT go
//  through LocalAccountRefresher.refreshFeeds's shared batch-refresh
//  session state (isRefreshing, outstandingParseTasks,
//  completions/pendingFeeds coalescing, completeRefreshIfReady()). That
//  machinery exists to coordinate many feeds finishing together for one
//  overall progress UI; a single tap on "load more" for one already-open
//  feed doesn't need it, and piggybacking on it risks interaction with an
//  in-flight full refresh (pendingFeeds.formUnion coalescing could
//  silently defer or collide with a manual tap).
//

import Foundation
import RSParser

@MainActor public enum AO3SearchResultsPaginator {

	public enum PageOutcome: Sendable {
		case loaded(newWorkCount: Int, hasNextPage: Bool)
		case noResults        // no more works past this page
		case registrationRequired
		case rateLimited
		case cloudflareChallenge(challengedURL: URL)
		/// Distinct from `.registrationRequired` -- see
		/// `AO3SearchResultsFetchOutcome.notSignedIn`'s own doc comment.
		/// Reachable here only for an always-authenticated listing feed
		/// (subscriptions, marked-for-later) whose stored AO3 session is
		/// missing or was rejected between page 1's add-time fetch (which
		/// went through `fetchRequiringSignIn`) and this later page.
		case notSignedIn
	}

	// MARK: - Infill / arbitrary-page fetch

	/// The person typed a page number that's out of range against a known
	/// `feed.ao3SearchTotalPages`, or asked to fetch a page that's already
	/// in `feed.ao3SearchFetchedPages` (allowed -- refetching is additive,
	/// never harmful -- but surfaced separately so a caller can choose
	/// whether to warn "already fetched" before spending a network
	/// request on it).
	public enum PageValidationOutcome: Sendable, Equatable {
		case valid
		case outOfRange(totalPages: Int)
	}

	/// Smallest positive integer not already in `fetchedPages`. Public so
	/// both `loadNextPage` and any UI-layer caller that needs to know
	/// which page a given "load more" attempt is targeting (e.g. to retry
	/// the same page after a Cloudflare challenge) use one implementation.
	/// For a feed with no gaps this is identical to "highest + 1" -- the
	/// difference only matters once the arbitrary-fetch action (Part 3)
	/// has jumped ahead and left a gap behind.
	public static func nextPageToFetch(fetchedPages: Set<Int>) -> Int {
		var candidate = 1
		while fetchedPages.contains(candidate) {
			candidate += 1
		}
		return candidate
	}

	/// Fetches the infill page (see `nextPageToFetch(fetchedPages:)`) for
	/// `feed` and imports it, inserting the fetched page number into
	/// `feed.ao3SearchFetchedPages` on success.
	public static func loadNextPage(for feed: Feed, account: Account) async -> PageOutcome {
		let nextPage = nextPageToFetch(fetchedPages: feed.ao3SearchFetchedPages ?? [])
		return await fetchPage(nextPage, for: feed, account: account, advancePageTo: nextPage)
	}

	/// Re-fetches page 1 without touching `ao3SearchFetchedPages` --
	/// see `FeedSettings.ao3SearchFetchedPages`'s own doc comment for
	/// why a page-1 re-check is deliberately not treated as pagination
	/// progress. Plumbing only for now -- not wired to a user-facing
	/// action this pass; kept for a future "check for new results"
	/// affordance and reused internally by add-time fetch consolidation.
	public static func refreshFirstPage(for feed: Feed, account: Account) async -> PageOutcome {
		await fetchPage(1, for: feed, account: account, advancePageTo: nil)
	}

	/// Validates `page` against `feed.ao3SearchTotalPages` without making
	/// a network request:
	/// - total known, page in range -> `.valid`
	/// - total known, page out of range -> `.outOfRange(totalPages:)`
	/// - total unknown -> `.valid` (caller should fetch page 1 first to
	///   populate the total, then re-validate -- see `fetchSpecificPage`,
	///   which does this automatically).
	public static func validate(page: Int, against feed: Feed) -> PageValidationOutcome {
		guard let totalPages = feed.ao3SearchTotalPages else {
			return .valid
		}
		guard page <= totalPages else {
			return .outOfRange(totalPages: totalPages)
		}
		return .valid
	}

	/// Entry point for the inspector's "fetch page N" action (Part 3's
	/// validation flow):
	/// 1. If `feed.ao3SearchTotalPages` is known and `page` is within it,
	///    fetch `page` directly.
	/// 2. If `feed.ao3SearchTotalPages` is known and `page` exceeds it,
	///    don't fetch -- return `.noResults` (the caller already has
	///    `validate(page:against:)` to check this ahead of time and avoid
	///    even calling this function; this outcome-based fallback is a
	///    guard for a total that changed between the caller's check and
	///    this call, not the primary way callers are expected to avoid an
	///    out-of-range fetch).
	/// 3. If `feed.ao3SearchTotalPages` isn't known yet, fetch page 1
	///    first (which both populates `ao3SearchTotalPages` and is itself
	///    a legitimate, additive refetch per the existing "additive only"
	///    rule), then re-validate `page` against the now-known total.
	public static func fetchSpecificPage(_ page: Int, for feed: Feed, account: Account) async -> PageOutcome {
		if feed.ao3SearchTotalPages == nil {
			let page1Outcome = await fetchPage(1, for: feed, account: account, advancePageTo: 1)
			guard case .loaded = page1Outcome else {
				return page1Outcome
			}
			guard page != 1 else {
				return page1Outcome
			}
		}

		if case .outOfRange = validate(page: page, against: feed) {
			return .noResults
		}

		return await fetchPage(page, for: feed, account: account, advancePageTo: page)
	}

	private static func fetchPage(_ page: Int, for feed: Feed, account: Account, advancePageTo: Int?) async -> PageOutcome {
		guard let pageURL = url(for: feed, page: page) else {
			return .noResults
		}

		let fetchOutcome: AO3SearchResultsFetchOutcome
		do {
			// Subscriptions and marked-for-later are always-yours,
			// always-private -- page 1 of these feeds was fetched via
			// fetchRequiringSignIn (LocalAccountDelegate.createFeed /
			// LocalAccountRefresher.fetchAndImportAO3SearchResults), and
			// later pages need the same authenticated-then-anonymous
			// fetch, or a signed-out person would see every page past 1
			// silently fail registration instead of getting the same
			// "sign in" state page 1 already surfaces. Widened beyond
			// isAlwaysAuthenticatedAO3ListingFeed alone: any general
			// search/tag page also routes through fetchRequiringSignIn
			// once a session exists, matching the two add-time call
			// sites above. Every other listing type, when signed out,
			// keeps using the plain anonymous fetch, unchanged.
			//
			// activityContext is deliberately left nil (unlike
			// LocalAccountRefresher's call site): this file's own header
			// comment explains fetchPage deliberately doesn't participate
			// in any running ActivityLog entry the way a batch refresh
			// does, so there's no in-flight activity for
			// ActivityLog.updateProgress(owner:kind:) to find and update
			// -- passing one through would silently no-op rather than do
			// anything, the same reason LocalAccountDelegate.createFeed
			// also passes nil. `account` is still needed below, for the
			// actual article write on success.
			let isAlwaysAuthenticatedListing = LocalAccountRefresher.isAlwaysAuthenticatedAO3ListingFeed(pageURL)
			if isAlwaysAuthenticatedListing || AO3SessionStore.isSignedIn {
				fetchOutcome = try await AO3SearchResultsFetcher.fetchRequiringSignIn(url: pageURL, feedURL: feed.url, isAlwaysAuthenticatedListing: isAlwaysAuthenticatedListing)
			} else {
				fetchOutcome = try await AO3SearchResultsFetcher.fetch(url: pageURL, feedURL: feed.url)
			}
		} catch {
			return .noResults
		}

		switch fetchOutcome {
		case .success(let parsedItems, let hasNextPage, _, let totalPages):
			// pageTitle deliberately unused here: renaming an already-
			// named feed off a later page's <title> (identical fandom/tag
			// text on every page of the same search/tag listing, so
			// there's nothing new to learn past page 1) isn't this
			// function's job -- see LocalAccountDelegate.createFeed's AO3
			// branch, the only place a page's title is used to name the
			// feed.
			let articleChanges = await account.updateAsync(feedID: feed.feedID, parsedItems: Set(parsedItems), deleteOlder: false)
			account.sendNotificationAbout(articleChanges)
			if let advancePageTo {
				feed.ao3SearchFetchedPages = (feed.ao3SearchFetchedPages ?? []).union([advancePageTo])
			}
			if let totalPages {
				feed.ao3SearchTotalPages = totalPages
			}
			return .loaded(newWorkCount: parsedItems.count, hasNextPage: hasNextPage)
		case .noResults(_, let totalPages):
			// pageTitle deliberately unused here, same reasoning as
			// .success above. A returned totalPages still self-corrects a
			// stale cached value even on a .noResults outcome -- see
			// AO3SearchResultsOutcome's own doc comment.
			if let totalPages {
				feed.ao3SearchTotalPages = totalPages
			}
			return .noResults
		case .registrationRequired:
			return .registrationRequired
		case .rateLimited:
			return .rateLimited
		case .cloudflareChallenge(let challengedURL):
			AO3ChallengeSessionStore.lastChallengedURL = challengedURL
			return .cloudflareChallenge(challengedURL: challengedURL)
		case .notSignedIn:
			return .notSignedIn
		}
	}

	/// Builds the page-`page` URL from `feed.url` (always the stored
	/// page-1 URL -- `LocalAccountRefresher.url(for:)` returns it verbatim
	/// and isn't reused here since it also carries Ambrosia sqlite-swap
	/// logic that has no bearing on an AO3 URL). Replaces any existing
	/// `page` query item, or appends one; page 1 is passed through as the
	/// feed's own URL unmodified (AO3 omits `page=1` on its own listing
	/// links, per the captured `voltron.html` pagination widget, which
	/// links "2" onward but represents "1" as the plain current-page
	/// anchor with no href at all).
	private static func url(for feed: Feed, page: Int) -> URL? {
		guard let baseURL = URL(string: feed.url) else {
			return nil
		}
		guard page != 1 else {
			return baseURL
		}
		guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
			return nil
		}
		var queryItems = (components.queryItems ?? []).filter { $0.name != "page" }
		queryItems.append(URLQueryItem(name: "page", value: String(page)))
		components.queryItems = queryItems
		return components.url
	}
}
