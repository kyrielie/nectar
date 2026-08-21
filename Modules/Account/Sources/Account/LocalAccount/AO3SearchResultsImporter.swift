//
//  AO3SearchResultsImporter.swift
//  Account
//
//  Factors the "parse already-fetched HTML and import it" step out of
//  LocalAccountRefresher.fetchAndImportAO3SearchResults so that step is
//  shared between two callers: the ordinary headless
//  AO3SearchResultsFetcher.fetch(url:feedURL:) path, and (iOS target,
//  outside this module) a WKWebView HTML-harvest fallback used when a
//  headless fetch comes back Cloudflare-challenged. Both end up with an
//  HTML string and need the same
//  AO3SearchResultsExtractor.extract -> account.updateAsync ->
//  account.sendNotificationAbout -> feed.ao3SearchFetchedPages sequence;
//  this type is that sequence, with no notion of how the HTML was obtained.
//

import Foundation
import RSParser

@MainActor public enum AO3SearchResultsImporter {

	public enum ImportOutcome: Sendable {
		case imported(newWorkCount: Int, hasNextPage: Bool, pageTitle: String?)
		case noResults(pageTitle: String?)
		case registrationRequired
	}

	/// Parses `html` as an AO3 search-results page and imports whatever
	/// works it lists into `feed`/`account`.
	///
	/// `advancePageTo`, when non-nil, is inserted into
	/// `feed.ao3SearchFetchedPages` on a successful import -- callers
	/// doing a plain page-1 fetch (routine add-time fetch, or an explicit
	/// page-1 re-check) pass `1`; `AO3SearchResultsPaginator.loadNextPage`
	/// passes the page it just fetched. `deleteOlder: false` always --
	/// any single page is a partial view of the search, not the whole
	/// feed, so treating it as authoritative for pruning would delete
	/// every work that only shows up on a different page.
	public static func importFetchedPage(html: String, feedURL: String, feed: Feed, account: Account, advancePageTo: Int?) async -> ImportOutcome {
		switch AO3SearchResultsExtractor.extract(fromResultsPageHTML: html, feedURL: feedURL) {
		case .success(let items, let hasNextPage, let pageTitle, let totalPages):
			let articleChanges = await account.updateAsync(feedID: feed.feedID, parsedItems: Set(items), deleteOlder: false)
			account.sendNotificationAbout(articleChanges)
			if let advancePageTo {
				feed.ao3SearchFetchedPages = (feed.ao3SearchFetchedPages ?? []).union([advancePageTo])
			}
			if let totalPages {
				feed.ao3SearchTotalPages = totalPages
			}
			return .imported(newWorkCount: items.count, hasNextPage: hasNextPage, pageTitle: pageTitle)
		case .noResults(let pageTitle, let totalPages):
			if let totalPages {
				feed.ao3SearchTotalPages = totalPages
			}
			return .noResults(pageTitle: pageTitle)
		case .registrationRequired:
			return .registrationRequired
		}
	}
}
