//
//  AO3FilterURLLength.swift
//  AO3Kit
//
//  Length policy for filtered AO3 requests (a `work_search[...]`
//  search or tag listing). AO3 doesn't error on a query it can't
//  process; it silently serves its unfiltered "Latest Works" listing
//  instead (see `AO3FilterFallbackPage`). Only requests at or past
//  `limit` are ever checked for that fallback -- anything shorter is
//  treated as fine and never inspected.
//

import Foundation

/// What was and wasn't confirmed: a 3,949-character filtered URL worked,
/// and a longer one (its exact length is unknown -- the capture was
/// truncated at 4,096) got the fallback page. `limit` is therefore a
/// chosen bound, not a documented AO3 number, and a URL between 3,950
/// and 4,095 characters is untested by design: it is not checked.
///
/// Length is the byte count of `URL.absoluteString`, i.e. what is
/// actually sent (percent-encoding included). For an all-ASCII URL that
/// equals the character count.
///
/// Three tiers, matching the add-feed behavior:
/// - under `limit`: nothing happens.
/// - exactly `limit`: no warning, but the fetched page is checked for
///   the fallback (`needsFallbackCheck`).
/// - over `limit`: `exceedsLimit` is true, so the add-feed screen warns
///   first (the person can continue); the fetched page is checked too.
///
/// A later page's URL (`page=N` appended) is longer than the stored
/// page-1 URL, so the check is applied to each request URL rather than
/// once to the feed URL.
public enum AO3FilterURLLength {

	public static let limit = 4096

	/// True for a filtered request strictly longer than `limit`.
	public static func exceedsLimit(_ url: URL) -> Bool {
		AO3SearchResultsFetcher.requestHasFilters(url) && length(of: url) > limit
	}

	/// True for a filtered request at or past `limit` -- the only
	/// requests whose response is inspected for AO3's fallback page.
	public static func needsFallbackCheck(_ url: URL) -> Bool {
		AO3SearchResultsFetcher.requestHasFilters(url) && length(of: url) >= limit
	}

	private static func length(of url: URL) -> Int {
		url.absoluteString.utf8.count
	}
}
