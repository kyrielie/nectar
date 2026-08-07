//
//  AO3SearchResultsPaginator.swift
//  Account
//
//  Nectar AO3 search-results refresh-cadence work, Workstream D
//  ("Load more results" pagination) -- see
//  nectar-ao3-search-refresh-plan.md.
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
	}

	/// Fetches page `(feed.ao3SearchLastFetchedPage ?? 1) + 1` for `feed`
	/// and imports it, bumping `feed.ao3SearchLastFetchedPage` on success.
	public static func loadNextPage(for feed: Feed, account: Account) async -> PageOutcome {
		let nextPage = (feed.ao3SearchLastFetchedPage ?? 1) + 1
		return await fetchPage(nextPage, for: feed, account: account, advancePageTo: nextPage)
	}

	/// Re-fetches page 1 without touching `ao3SearchLastFetchedPage` --
	/// see `FeedSettings.ao3SearchLastFetchedPage`'s own doc comment for
	/// why a page-1 re-check is deliberately not treated as pagination
	/// progress. Plumbing only for now -- not wired to a user-facing
	/// action this pass; kept for a future "check for new results"
	/// affordance and reused internally by add-time fetch consolidation.
	public static func refreshFirstPage(for feed: Feed, account: Account) async -> PageOutcome {
		await fetchPage(1, for: feed, account: account, advancePageTo: nil)
	}

	private static func fetchPage(_ page: Int, for feed: Feed, account: Account, advancePageTo: Int?) async -> PageOutcome {
		guard let pageURL = url(for: feed, page: page) else {
			return .noResults
		}

		let fetchOutcome: AO3SearchResultsFetchOutcome
		do {
			fetchOutcome = try await AO3SearchResultsFetcher.fetch(url: pageURL, feedURL: feed.url)
		} catch {
			return .noResults
		}

		switch fetchOutcome {
		case .success(let parsedItems, let hasNextPage):
			let articleChanges = await account.updateAsync(feedID: feed.feedID, parsedItems: Set(parsedItems), deleteOlder: false)
			account.sendNotificationAbout(articleChanges)
			if let advancePageTo {
				feed.ao3SearchLastFetchedPage = advancePageTo
			}
			return .loaded(newWorkCount: parsedItems.count, hasNextPage: hasNextPage)
		case .noResults:
			return .noResults
		case .registrationRequired:
			return .registrationRequired
		case .rateLimited:
			return .rateLimited
		case .cloudflareChallenge(let challengedURL):
			AO3ChallengeSessionStore.lastChallengedURL = challengedURL
			return .cloudflareChallenge(challengedURL: challengedURL)
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
