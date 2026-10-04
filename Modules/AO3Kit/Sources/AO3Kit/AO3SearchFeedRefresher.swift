//
//  AO3SearchFeedRefresher.swift
//  AO3Kit
//
//  Fetches page 1 of an AO3 listing feed (search, tag, shelf page) and
//  imports whatever works it lists. Extracted from
//  LocalAccountRefresher.fetchAndImportAO3SearchResults so the refresh
//  logic lives next to the fetchers and can be tested without the
//  refresher's bookkeeping.
//
//  The caller keeps what is specific to a refresh run: `lastCheckDate`,
//  outstanding-task accounting, and reporting a failure to the person.
//
//  `deleteOlder: false` on the update, deliberately: page 1 is a partial
//  view of the search (pagination is lazy), so treating it as
//  authoritative for pruning would delete every work that only appears on
//  page 2 or later.
//
import Foundation
import ActivityLog

@MainActor public enum AO3SearchFeedRefresher {

	public enum Result {
		case imported(workCount: Int)
		case noResults
		case failure(AO3FetchFailure)
	}

	/// - Parameters:
	///   - url: the listing URL to fetch.
	///   - feedURL: the feed's own URL string, used for logging and for the
	///     fetcher's per-feed behavior.
	///   - feedID: the feed the works are imported into.
	///   - tracker: receives `ao3SearchFetchedPages = [1]` and
	///     `ao3SearchTotalPages`.
	///   - updater: stores the parsed works and announces the changes.
	///   - activity: when present, the Activity Log entry that gets the
	///     "N works found" or "No results" completion message. Failures are
	///     left for the caller to report against the same entry.
	public static func refresh(url: URL, feedURL: String, feedID: String, tracker: AO3SearchFeedPageTracking, updater: AO3ArticleUpdating, activity: (owner: ActivityOwner, kind: ActivityKind)?) async -> Result {
		// Subscriptions and marked-for-later are always the signed-in
		// person's own, always private, so they route through the
		// authenticated-then-anonymous fetch (and surface `.notSignedIn`
		// when signed out). Any other listing also routes there once a
		// session exists, so a signed-in person gets the authenticated
		// attempt first. A signed-out refresh of any other listing keeps
		// using the plain anonymous fetch.
		let isAlwaysAuthenticatedListing = AO3Link.isAlwaysAuthenticatedListing(url)
		let requiresSignIn = isAlwaysAuthenticatedListing || AO3SessionStore.isSignedIn

		let outcome: AO3SearchResultsFetchOutcome
		do {
			if requiresSignIn {
				outcome = try await AO3SearchResultsFetcher.fetchRequiringSignIn(url: url, feedURL: feedURL, isAlwaysAuthenticatedListing: isAlwaysAuthenticatedListing, activityContext: activity)
			} else {
				outcome = try await AO3SearchResultsFetcher.fetch(url: url, feedURL: feedURL)
			}
		} catch {
			return .failure(.network(error.localizedDescription))
		}

		switch outcome {
		case .success(let parsedItems, _, _, let totalPages):
			// hasNextPage and pageTitle are not consumed: a routine
			// refresh always writes page 1, only the "load more" UI needs
			// the next-page signal (it calls the fetcher directly), and a
			// refresh must never overwrite a name the person may have
			// edited since the feed was created.
			let articleChanges = await updater.updateAsync(feedID: feedID, parsedItems: Set(parsedItems), deleteOlder: false)
			updater.sendNotificationAbout(articleChanges)
			tracker.ao3SearchFetchedPages = [1]
			tracker.ao3SearchTotalPages = totalPages
			if let activity {
				ActivityLog.shared.didComplete(activity.owner, kind: activity.kind, message: "\(parsedItems.count) work\(parsedItems.count == 1 ? "" : "s") found")
			}
			return .imported(workCount: parsedItems.count)
		case .noResults(_, let totalPages):
			if let totalPages {
				tracker.ao3SearchTotalPages = totalPages
			}
			if let activity {
				ActivityLog.shared.didComplete(activity.owner, kind: activity.kind, message: "No results")
			}
			return .noResults
		case .cloudflareChallenge(let challengedURL):
			// Recorded so Settings' "Verify Browser Access" solver can
			// default to the URL that was actually challenged.
			AO3ChallengeSessionStore.lastChallengedURL = challengedURL
			return .failure(.challenge)
		case .registrationRequired, .rateLimited, .notSignedIn, .filtersNotApplied:
			return .failure(outcome.failure ?? .unrecognizedPage)
		}
	}
}
