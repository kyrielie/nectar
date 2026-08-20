//
//  LocalAccountRefresherRoutingTests.swift
//  AccountTests
//
//  Coverage for LocalAccountRefresher.isAO3ListingFeed(_:) (formerly
//  isAO3SearchResultsFeed) after its broadening from two URL shapes
//  (search/tag results) to the full set in
//  nectar-toolbar-ao3-listing-feeds.md: author works, bookmarks,
//  marked-for-later, subscriptions, collections, and series -- plus
//  isAlwaysAuthenticatedAO3ListingFeed(_:), the narrower "always
//  requires a signed-in session" subset (subscriptions,
//  marked-for-later only).
//
//  Deliberately does not exercise AO3SearchResultsFetcher/
//  fetchRequiringSignIn here -- these two classifiers are pure
//  host+path/query matching with no network dependency, and
//  AO3ChapterFetcherTests/AO3SeriesNavigatorTests already cover the
//  authenticated-fetch machinery this feature reuses.
//

import XCTest
@testable import Account

@MainActor final class LocalAccountRefresherRoutingTests: XCTestCase {

	private func url(_ string: String) -> URL {
		guard let url = URL(string: string) else {
			XCTFail("Invalid test URL: \(string)")
			return URL(string: "https://archiveofourown.org")!
		}
		return url
	}

	// MARK: - isAO3ListingFeed: shapes matched before this broadening

	func testTagListingWorksMatches() {
		XCTAssertTrue(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/tags/Some%20Fandom/works")))
	}

	func testSearchResultsWorksMatches() {
		XCTAssertTrue(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/works?work_search%5Bquery%5D=test")))
	}

	func testPlainWorksPathWithoutSearchQueryDoesNotMatch() {
		// /works alone, or with unrelated query params, is not a listing
		// page shape this feature recognizes -- only a work_search[...]
		// prefixed key qualifies.
		XCTAssertFalse(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/works")))
		XCTAssertFalse(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/works?page=2")))
	}

	// MARK: - isAO3ListingFeed: newly broadened shapes

	func testAuthorWorksMatches() {
		XCTAssertTrue(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/users/someauthor/works")))
	}

	func testPseudScopedAuthorWorksMatches() {
		XCTAssertTrue(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/users/someauthor/pseuds/somepseud/works")))
	}

	func testBookmarksMatches() {
		XCTAssertTrue(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/users/someuser/bookmarks")))
	}

	func testMarkedForLaterMatchesOnlyWithToReadQuery() {
		XCTAssertTrue(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/users/someuser/readings?show=to-read")))
		// Reading history without the to-read filter (no query, or a
		// different show= value) is a different AO3 page and is
		// deliberately not matched -- see isAO3ListingFeed's own doc
		// comment.
		XCTAssertFalse(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/users/someuser/readings")))
		XCTAssertFalse(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/users/someuser/readings?show=all")))
	}

	func testSubscriptionsMatchesIgnoringQueryAndTrailingSlash() {
		XCTAssertTrue(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/users/someuser/subscriptions")))
		XCTAssertTrue(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/users/someuser/subscriptions/")))
		XCTAssertTrue(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/users/someuser/subscriptions?page=2")))
	}

	func testCollectionWorksMatches() {
		XCTAssertTrue(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/collections/SomeCollection/works")))
	}

	func testSeriesMatches() {
		XCTAssertTrue(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/series/348731")))
	}

	func testSeriesWithNonNumericSuffixDoesNotMatch() {
		// /series/<digits> only -- not e.g. a hypothetical
		// /series/recommended or similar non-ID path.
		XCTAssertFalse(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/series/recommended")))
		XCTAssertFalse(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/series/")))
	}

	// MARK: - Host allowlist still applies to every shape

	func testDisallowedHostNeverMatchesRegardlessOfPathShape() {
		XCTAssertFalse(LocalAccountRefresher.isAO3ListingFeed(url("https://example.com/users/someuser/subscriptions")))
		XCTAssertFalse(LocalAccountRefresher.isAO3ListingFeed(url("https://example.com/series/348731")))
	}

	// MARK: - Series non-collision with inline series-navigation

	/// `nectar-toolbar-ao3-listing-feeds.md` item 1 flags a real risk:
	/// widening isAO3ListingFeed to match `/series/<digits>` must not
	/// make an *existing* series-navigation fetch
	/// (AO3SeriesNavigator/AO3SeriesListingExtractor's "jump to first
	/// work in series" / inline series-nav feature) get accidentally
	/// treated as "subscribe to this as a feed" -- those code paths call
	/// AO3SeriesListingExtractor/AO3SeriesNavigator directly and never
	/// call isAO3ListingFeed at all, so there is no shared code path for
	/// the classifier to leak into. This test doesn't (and can't, from
	/// this file) prove a negative about every call site in the app;
	/// it pins down the two things that are checkable here: (1) the
	/// classifier itself correctly recognizes the series URL shape
	/// AO3SeriesNavigator's own inline navigation operates on, and (2)
	/// that recognition is confined to isAO3ListingFeed's own two call
	/// sites (LocalAccountDelegate.createFeed,
	/// feedShouldBeSkippedForAO3SearchResultsReasons) per this file's own
	/// grep-confirmed claim in isAO3ListingFeed's doc comment -- not
	/// verifiable by a unit test, flagged here so it stays visible if
	/// that invariant is ever broken by a future call site addition.
	func testSeriesURLShapeMatchesWhatInlineNavigationOperatesOn() {
		// Same series ID AO3SeriesListingExtractorTests/
		// AO3SeriesNavigatorTests exercise via the real captured
		// ao3-series-listing.html fixture (RSParserTests) --
		// confirms the classifier and the inline-nav fixtures agree on
		// what a "series URL" looks like, rather than drifting apart.
		XCTAssertTrue(LocalAccountRefresher.isAO3ListingFeed(url("https://archiveofourown.org/series/348731")))
	}

	// MARK: - isAlwaysAuthenticatedAO3ListingFeed: the narrower "always yours" subset

	func testSubscriptionsRequiresSignIn() {
		XCTAssertTrue(LocalAccountRefresher.isAlwaysAuthenticatedAO3ListingFeed(url("https://archiveofourown.org/users/someuser/subscriptions")))
	}

	func testMarkedForLaterRequiresSignIn() {
		XCTAssertTrue(LocalAccountRefresher.isAlwaysAuthenticatedAO3ListingFeed(url("https://archiveofourown.org/users/someuser/readings?show=to-read")))
	}

	func testBookmarksDoNotRequireSignIn() {
		// Bookmarks are only *sometimes* gated (public-vs-private per
		// user), so they're deliberately excluded here and left to the
		// ordinary anonymous-fetch-then-registration-wall path -- see
		// isAlwaysAuthenticatedAO3ListingFeed's own doc comment.
		XCTAssertFalse(LocalAccountRefresher.isAlwaysAuthenticatedAO3ListingFeed(url("https://archiveofourown.org/users/someuser/bookmarks")))
	}

	func testAuthorWorksAndSeriesAndCollectionsDoNotRequireSignIn() {
		XCTAssertFalse(LocalAccountRefresher.isAlwaysAuthenticatedAO3ListingFeed(url("https://archiveofourown.org/users/someuser/works")))
		XCTAssertFalse(LocalAccountRefresher.isAlwaysAuthenticatedAO3ListingFeed(url("https://archiveofourown.org/series/348731")))
		XCTAssertFalse(LocalAccountRefresher.isAlwaysAuthenticatedAO3ListingFeed(url("https://archiveofourown.org/collections/SomeCollection/works")))
	}

	func testTagAndSearchResultsDoNotRequireSignIn() {
		XCTAssertFalse(LocalAccountRefresher.isAlwaysAuthenticatedAO3ListingFeed(url("https://archiveofourown.org/tags/Some%20Fandom/works")))
		XCTAssertFalse(LocalAccountRefresher.isAlwaysAuthenticatedAO3ListingFeed(url("https://archiveofourown.org/works?work_search%5Bquery%5D=test")))
	}
}
