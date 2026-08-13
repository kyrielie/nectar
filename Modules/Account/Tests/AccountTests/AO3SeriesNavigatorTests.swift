//
//  AO3SeriesNavigatorTests.swift
//  AccountTests
//
//  Nectar inline-series-navigation work, Phase 4: coverage for
//  AO3SeriesNavigator.openSeriesWork, which replaced the old
//  fetchAdjacentWork/fetchFirstWorkInSeries pair this file used to test
//  (both deleted -- they collapsed a work's multiple series memberships
//  to one, which per-series inline links no longer do).
//
//  Previously this file could only cover openSeriesWork's pre-network
//  guards -- Downloader.shared had no injected seam, a limitation
//  AO3ChapterFetcherTests's header comment documented directly. That gap
//  is now closed: Downloader's own URLSession picks up TestingURLProtocol
//  under Platform.isRunningUnitTests, the same way URLSession.webservice
//  already did (see RSWeb's Downloader.swift and
//  TestingURLProtocol+Responses.swift). Every openSeriesWork branch below
//  is exercised against canned responses, not a live archiveofourown.org
//  fetch.
//
//  AO3SeriesNavigationError is Equatable (added alongside this rewrite)
//  purely so Result<String, AO3SeriesNavigationError> can be compared
//  with XCTAssertEqual below.
//
//  Fixtures: ao3-series-nav-page1.html/page2.html are small, hand-built
//  two-work/one-work series-listing pages -- markup shape (work row,
//  pagination widget, both the "has next page" and "last page" forms)
//  copied verbatim from the real captured ao3-series-listing.html and
//  longseries.html fixtures in RSParserTests, not invented. The work
//  actually downloaded in most tests (87955346) reuses
//  RSParserTests/Resources/ao3-work-single-chapter.html, a real captured
//  work page already proven to round-trip through
//  AO3ChapterHTMLExtractor.extract -- that extractor doesn't cross-check
//  extracted content against the requested work ID, so the same fixture
//  is registered under several different work-page URLs below without
//  misrepresenting anything the extractor itself checks.
//

import XCTest
import RSParser
import RSWeb
import Articles
@testable import Account

@MainActor final class AO3SeriesNavigatorTests: XCTestCase {

	private var account: Account!

	// Every test's existingArticle lives under this feed -- created via
	// the same importPastedAO3Links path a real "already reading this
	// series" article would have gone through, rather than
	// hand-constructing an Article directly.
	private var existingArticle: Article!

	override func setUp() async throws {
		TestingURLProtocol.reset()
		DownloadCache.shared.removeAll()
		AO3SeriesNavigator.resetWalkedStateForTesting()
		account = TestAccountManager.shared.createAccount(type: .onMyMac)
		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/1")
		let feed = account.existingFeed(withURL: Account.importedLinksFeedURL)!
		existingArticle = await account.fetchArticlesAsync(.feed(feed)).first!
	}

	override func tearDown() async throws {
		TestingURLProtocol.reset()
		AO3SeriesNavigator.resetWalkedStateForTesting()
		TestAccountManager.shared.deleteAccount(account)
		account = nil
		existingArticle = nil
	}

	// MARK: - Pre-network guards (.previous/.next only -- .first has none)

	func testPreviousWithNilTargetWorkURLFailsWithNoAdjacentWork() async {
		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .previous, targetWorkURL: nil, targetIndex: nil,
			existingArticle: existingArticle, account: account
		)
		XCTAssertEqual(result, .failure(.noAdjacentWork))
	}

	func testNextWithUnparseableTargetWorkURLFailsWithNoAdjacentWork() async {
		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .next, targetWorkURL: "not a permalink", targetIndex: nil,
			existingArticle: existingArticle, account: account
		)
		XCTAssertEqual(result, .failure(.noAdjacentWork))
	}

	// MARK: - Cache hit (Step 1) -- no listing fetch at all

	func testNextReturnsCachedArticleWithoutFetchingListing() async {
		// A work already fetched under the same feed, with content --
		// exactly existingArticlesByWorkID's match condition (bookKey
		// resolves to workID, contentHTML != nil).
		_ = await account.updateAsync(feedID: existingArticle.feedID, parsedItems: [
			ParsedItem(syncServiceID: nil, uniqueID: "87955346", feedURL: existingArticle.feedID,
			           url: "https://archiveofourown.org/works/87955346", externalURL: nil,
			           title: "Cached Work", language: nil, contentHTML: "<p>already fetched</p>",
			           contentText: nil, markdown: nil, summary: nil, imageURL: nil, bannerImageURL: nil,
			           datePublished: nil, dateModified: nil, authors: nil, tags: nil, attachments: nil,
			           ao3WorkID: "87955346")
		], deleteOlder: false)

		// Deliberately NOT registering any TestingURLProtocol response for
		// series/999001 -- if the cache check were skipped, the fetch
		// would hit the default 200/no-data stub and this would fail with
		// .networkError instead of matching the cached article.
		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .next,
			targetWorkURL: "https://archiveofourown.org/works/87955346", targetIndex: 2,
			existingArticle: existingArticle, account: account
		)
		XCTAssertEqual(result, .success(Article.calculatedArticleID(feedID: existingArticle.feedID, uniqueID: "87955346")))
	}

	func testNextReusesExistingStubWithoutFetchingListingButStillFetchesContent() async {
		// A work already stubbed under the same feed -- e.g. batch-stubbed
		// as someone else's neighbor by an earlier Next/Previous tap --
		// but never opened, so contentHTML is nil. This fast path is now
		// trusted only when a recent page-1 walk is recorded for the
		// feed/series pair; seed that here so this test keeps covering the
		// legitimate prior-walk shortcut.
		_ = await account.updateAsync(feedID: existingArticle.feedID, parsedItems: [
			ParsedItem(syncServiceID: nil, uniqueID: "87955346", feedURL: existingArticle.feedID,
			           url: "https://archiveofourown.org/works/87955346", externalURL: nil,
			           title: "AO3 Work 87955346", language: nil, contentHTML: nil,
			           contentText: nil, markdown: nil, summary: nil, imageURL: nil, bannerImageURL: nil,
			           datePublished: nil, dateModified: nil, authors: nil, tags: nil, attachments: nil,
			           ao3WorkID: "87955346")
		], deleteOlder: false)
		AO3SeriesNavigator.markWalkedForTesting(feedID: existingArticle.feedID, ao3SeriesID: "999001")

		// Deliberately NOT registering any TestingURLProtocol response for
		// series/999001 -- if the listing fetch weren't skipped, the fetch
		// would hit the default 200/no-data stub and the subsequent
		// content download would fail to resolve the expected work.
		TestingURLProtocol.setResponse("archiveofourown.org/works/87955346", file: "ao3-work-single-chapter.html")

		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .next,
			targetWorkURL: "https://archiveofourown.org/works/87955346", targetIndex: 2,
			existingArticle: existingArticle, account: account
		)
		let articleID = Article.calculatedArticleID(feedID: existingArticle.feedID, uniqueID: "87955346")
		XCTAssertEqual(result, .success(articleID))
		XCTAssertFalse(TestingURLProtocol.requestedURLs.contains { $0.absoluteString.contains("archiveofourown.org/series/999001") })

		let articles = await account.fetchArticlesAsync(.feed(account.existingFeed(withFeedID: existingArticle.feedID)!))
		let fetched = articles.first { $0.articleID == articleID }
		XCTAssertNotNil(fetched?.contentHTML)
	}

	func testNextBackfillsPageOneWhenExistingStubHasNoRecentWalk() async throws {
		// Real repro shape, built from the actual captured data (the
		// original bug report): work 779835 ("The Parting Glass", the
		// true next work in series 43794) already exists under this feed
		// as a stub -- not from any prior series-nav walk, but because it
		// coincidentally also appears as one of ~20 rows on an unrelated
		// AO3 tag search-results page ("The Devil Wears Prada (2006)")
		// the person subscribed to first. Seeded the way a real search
		// import would, via AO3SearchResultsImporter -- not
		// AO3SeriesNavigator.stubImport -- so this exercises the actual
		// foreign-stub shape (uniqueID is the work's permalink, not the
		// bare work id `stubImport` would have used) rather than a
		// synthetic stand-in for it. The old Step 1 code trusted any
		// same-feed stub unconditionally and fetched only the target,
		// never walking the series listing. With no recent walk recorded,
		// page 1 should be fetched and the rest of the series page should
		// be stubbed before the target is fetched in place.
		let searchFeed = account.existingFeed(withFeedID: existingArticle.feedID)!
		let searchResultsHTML = try String(contentsOf: Bundle.module.resourceURL!.appendingPathComponent("ao3-search-results-tdwp.html"), encoding: .utf8)
		let importOutcome = await AO3SearchResultsImporter.importFetchedPage(html: searchResultsHTML, feedURL: searchFeed.url, feed: searchFeed, account: account, advancePageTo: 1)
		guard case .imported(let newWorkCount, _, _) = importOutcome else {
			XCTFail("expected the tdwp fixture to import successfully, got \(importOutcome)")
			return
		}
		XCTAssertGreaterThan(newWorkCount, 0)

		let seededArticles = await account.fetchArticlesAsync(.feed(searchFeed))
		let seededStub = try XCTUnwrap(seededArticles.first { AO3ChapterFetcher.ao3WorkID(fromBookKey: $0.bookKey) == "779835" })
		XCTAssertNil(seededStub.contentHTML)

		TestingURLProtocol.setResponse("archiveofourown.org/series/43794", file: "ao3-series-nav-43794-page1.html")
		TestingURLProtocol.setResponse("archiveofourown.org/works/779835", file: "ao3-work-single-chapter.html")

		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "43794", direction: .next,
			targetWorkURL: "https://archiveofourown.org/works/779835", targetIndex: 2,
			existingArticle: existingArticle, account: account
		)

		XCTAssertEqual(result, .success(seededStub.articleID))
		XCTAssertTrue(TestingURLProtocol.requestedURLs.contains { $0.absoluteString == "https://archiveofourown.org/series/43794" })

		let articles = await account.fetchArticlesAsync(.feed(searchFeed))
		let workIDs = Set(articles.compactMap { AO3ChapterFetcher.ao3WorkID(fromBookKey: $0.bookKey) })
		XCTAssertTrue(workIDs.isSuperset(of: ["779826", "779835", "779840", "1836235", "2085420"]))
		XCTAssertEqual(articles.filter { AO3ChapterFetcher.ao3WorkID(fromBookKey: $0.bookKey) == "779835" }.count, 1)
	}

	func testNextStubHitWithMissingBackfillStillFetchesKnownTarget() async {
		_ = await account.updateAsync(feedID: existingArticle.feedID, parsedItems: [
			ParsedItem(syncServiceID: nil, uniqueID: "87955346", feedURL: existingArticle.feedID,
			           url: "https://archiveofourown.org/works/87955346", externalURL: nil,
			           title: "AO3 Work 87955346", language: nil, contentHTML: nil,
			           contentText: nil, markdown: nil, summary: nil, imageURL: nil, bannerImageURL: nil,
			           datePublished: nil, dateModified: nil, authors: nil, tags: nil, attachments: nil,
			           ao3WorkID: "87955346")
		], deleteOlder: false)
		TestingURLProtocol.setResponse("archiveofourown.org/works/87955346", file: "ao3-work-single-chapter.html")

		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .next,
			targetWorkURL: "https://archiveofourown.org/works/87955346", targetIndex: 2,
			existingArticle: existingArticle, account: account
		)

		XCTAssertEqual(result, .success(Article.calculatedArticleID(feedID: existingArticle.feedID, uniqueID: "87955346")))
		XCTAssertTrue(TestingURLProtocol.requestedURLs.contains { $0.absoluteString == "https://archiveofourown.org/series/999001" })
	}

	// MARK: - Cross-feed reuse (Step 1b, Bug 3b)

	func testNextCopiesFetchedCrossFeedArticleWithoutFetchingListingOrContent() async {
		// A different feed already has this work fully fetched (e.g. it's
		// also a member of some other series the person has separately
		// navigated). Step 1b should find it by bookKey, copy its
		// content/metadata into a new row under existingArticle's own
		// feed, and return that -- no listing fetch, no work-page fetch.
		let otherFeed = account.createFeed(with: "Other Feed", url: "https://example.com/other-feed", feedID: "other-feed-id", homePageURL: nil)
		account.addFeedToTreeAtTopLevel(otherFeed)
		_ = await account.updateAsync(feedID: otherFeed.feedID, parsedItems: [
			ParsedItem(syncServiceID: nil, uniqueID: "some-other-uniqueid", feedURL: otherFeed.feedID,
			           url: "https://archiveofourown.org/works/87955346", externalURL: nil,
			           title: "Already Fetched Elsewhere", language: nil, contentHTML: "<p>already fetched, different feed</p>",
			           contentText: nil, markdown: nil, summary: "a summary", imageURL: nil, bannerImageURL: nil,
			           datePublished: nil, dateModified: nil, authors: nil, tags: nil, attachments: nil,
			           wordCount: 4200, fandoms: ["Some Fandom"],
			           ao3WorkID: "87955346")
		], deleteOlder: false)

		// Deliberately NOT registering any TestingURLProtocol response for
		// series/999001 or works/87955346 -- if Step 1b were skipped, both
		// the listing fetch and the work-page fetch would hit the default
		// 200/no-data stub and this would fail with .networkError instead.
		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .next,
			targetWorkURL: "https://archiveofourown.org/works/87955346", targetIndex: 2,
			existingArticle: existingArticle, account: account
		)
		let expectedArticleID = Article.calculatedArticleID(feedID: existingArticle.feedID, uniqueID: "87955346")
		XCTAssertEqual(result, .success(expectedArticleID))

		let articles = await account.fetchArticlesAsync(.feed(account.existingFeed(withFeedID: existingArticle.feedID)!))
		let copied = articles.first { $0.articleID == expectedArticleID }
		XCTAssertEqual(copied?.contentHTML, "<p>already fetched, different feed</p>")
		XCTAssertEqual(copied?.summary, "a summary")
		XCTAssertEqual(copied?.wordCount, 4200)
		XCTAssertEqual(copied?.fandoms, ["Some Fandom"])
		XCTAssertEqual(copied?.uniqueID, "87955346")

		// The other feed's own copy is untouched, not moved or deleted.
		let otherFeedArticles = await account.fetchArticlesAsync(.feed(otherFeed))
		XCTAssertTrue(otherFeedArticles.contains { $0.uniqueID == "some-other-uniqueid" })
	}

	func testNextIgnoresUnfetchedCrossFeedStubAndFallsThroughToListing() async {
		// A different feed has a *stub* for this work (contentHTML nil,
		// e.g. batch-stubbed there by that series' own Step 2) -- Step 1b
		// should NOT treat this as a usable cross-feed hit (see that
		// step's own comment on why), so this must fall through to the
		// normal page-1 listing fetch.
		let otherFeed = account.createFeed(with: "Other Feed", url: "https://example.com/other-feed-2", feedID: "other-feed-id-2", homePageURL: nil)
		account.addFeedToTreeAtTopLevel(otherFeed)
		_ = await account.updateAsync(feedID: otherFeed.feedID, parsedItems: [
			ParsedItem(syncServiceID: nil, uniqueID: "87955346", feedURL: otherFeed.feedID,
			           url: "https://archiveofourown.org/works/87955346", externalURL: nil,
			           title: "AO3 Work 87955346", language: nil, contentHTML: nil,
			           contentText: nil, markdown: nil, summary: nil, imageURL: nil, bannerImageURL: nil,
			           datePublished: nil, dateModified: nil, authors: nil, tags: nil, attachments: nil,
			           ao3WorkID: "87955346")
		], deleteOlder: false)

		TestingURLProtocol.setResponse("archiveofourown.org/series/999001", file: "ao3-series-nav-page1.html")
		TestingURLProtocol.setResponse("archiveofourown.org/works/87955346", file: "ao3-work-single-chapter.html")

		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .next,
			targetWorkURL: "https://archiveofourown.org/works/87955346", targetIndex: 1,
			existingArticle: existingArticle, account: account
		)
		XCTAssertEqual(result, .success(Article.calculatedArticleID(feedID: existingArticle.feedID, uniqueID: "87955346")))
	}



	func testFirstResolvesFirstWorkFromPageOne() async throws {
		TestingURLProtocol.setResponse("archiveofourown.org/series/999001", file: "ao3-series-nav-page1.html")
		TestingURLProtocol.setResponse("archiveofourown.org/works/87955346", file: "ao3-work-single-chapter.html")

		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .first, targetWorkURL: nil, targetIndex: nil,
			existingArticle: existingArticle, account: account
		)
		XCTAssertEqual(result, .success(Article.calculatedArticleID(feedID: existingArticle.feedID, uniqueID: "87955346")))

		// Both page-1 rows should be stubbed into the feed, not just the
		// one actually downloaded (Step 2's batch-stub behavior).
		let articles = await account.fetchArticlesAsync(.feed(account.existingFeed(withFeedID: existingArticle.feedID)!))
		XCTAssertTrue(articles.contains { $0.uniqueID == "22222" })

		// Listing-metadata follow-up: the stubbed neighbor (22222, never
		// itself fetched in this test) should carry the richer metadata
		// this fixture's row now has -- summary/fandom/word-count/tags --
		// not just title/permalink, confirming workPermalinks' new fields
		// actually reach the stored Article via placeholderStub(from:).
		let neighbor = try XCTUnwrap(articles.first { $0.uniqueID == "22222" })
		XCTAssertNil(neighbor.contentHTML)
		XCTAssertEqual(neighbor.wordCount, 1500)
		XCTAssertEqual(neighbor.fandoms, ["Test Fandom"])
		XCTAssertEqual(neighbor.ratings, ["Teen And Up Audiences"])
		XCTAssertEqual(neighbor.categories, ["Gen"])
		XCTAssertEqual(neighbor.warnings, ["No Archive Warnings Apply"])
		XCTAssertTrue(neighbor.summary?.contains("The second part of the story.") == true)
	}

	func testNextResolvesFromPageOneWhenTargetIsThere() async {
		TestingURLProtocol.setResponse("archiveofourown.org/series/999001", file: "ao3-series-nav-page1.html")
		TestingURLProtocol.setResponse("archiveofourown.org/works/87955346", file: "ao3-work-single-chapter.html")

		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .next,
			targetWorkURL: "https://archiveofourown.org/works/87955346", targetIndex: 1,
			existingArticle: existingArticle, account: account
		)
		XCTAssertEqual(result, .success(Article.calculatedArticleID(feedID: existingArticle.feedID, uniqueID: "87955346")))
	}

	func testEmptySeriesListingWhenPageOneHasNoWorkRows() async {
		TestingURLProtocol.setResponse("archiveofourown.org/series/999002", file: "ao3-series-nav-empty.html")

		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999002", direction: .first, targetWorkURL: nil, targetIndex: nil,
			existingArticle: existingArticle, account: account
		)
		XCTAssertEqual(result, .failure(.emptySeriesListing))
	}

	func testNetworkErrorWhenPageOneCantBeLoaded() async {
		// No response registered for this series ID at all -- resolves to
		// TestingURLProtocol's default 200/no-data stub, which
		// fetchListingPage treats as unreadable.
		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999999", direction: .first, targetWorkURL: nil, targetIndex: nil,
			existingArticle: existingArticle, account: account
		)
		guard case .failure(.networkError) = result else {
			XCTFail("expected .networkError, got \(result)")
			return
		}
	}

	// MARK: - Dedup (Fix 4): existing article under a different uniqueID scheme

	func testExistingAmbrosiaStyleArticleIsReusedNotDuplicated() async {
		// An Ambrosia-synced article for work 87955346 whose uniqueID is
		// Ambrosia's own id, not the bare AO3 work id -- bookKey routes
		// through ao3WorkID regardless (JSONFeedParser.swift:241 always
		// sets ao3WorkID for AO3-sourced items). This work also appears
		// on page 1 of the fetched listing.
		_ = await account.updateAsync(feedID: existingArticle.feedID, parsedItems: [
			ParsedItem(syncServiceID: nil, uniqueID: "ambrosia-item-9001", feedURL: existingArticle.feedID,
			           url: "https://archiveofourown.org/works/87955346", externalURL: nil,
			           title: "Part One", language: nil, contentHTML: nil,
			           contentText: nil, markdown: nil, summary: nil, imageURL: nil, bannerImageURL: nil,
			           datePublished: nil, dateModified: nil, authors: nil, tags: nil, attachments: nil,
			           ao3WorkID: "87955346")
		], deleteOlder: false)
		let ambrosiaArticleID = Article.calculatedArticleID(feedID: existingArticle.feedID, uniqueID: "ambrosia-item-9001")

		TestingURLProtocol.setResponse("archiveofourown.org/series/999001", file: "ao3-series-nav-page1.html")
		TestingURLProtocol.setResponse("archiveofourown.org/works/87955346", file: "ao3-work-single-chapter.html")

		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .first, targetWorkURL: nil, targetIndex: nil,
			existingArticle: existingArticle, account: account
		)

		// download must have been handed the Ambrosia article's own
		// articleID, not a freshly computed one from the bare workID.
		XCTAssertEqual(result, .success(ambrosiaArticleID))

		// No second row for work 87955346 -- stubImport must have
		// filtered it out of page1Works before handing anything to
		// updateAsync.
		let articles = await account.fetchArticlesAsync(.feed(account.existingFeed(withFeedID: existingArticle.feedID)!))
		let matchingArticles = articles.filter { AO3ChapterFetcher.ao3WorkID(fromBookKey: $0.bookKey) == "87955346" }
		XCTAssertEqual(matchingArticles.count, 1)
		XCTAssertEqual(matchingArticles.first?.articleID, ambrosiaArticleID)
	}

	func testCurrentlyOpenWorkOnPageOneDoesNotDuplicate() async {
		// Regression case for the "always at least one duplicate" report:
		// existingArticle's own work (id "1", from setUp's
		// importPastedAO3Links) additionally appears on the fetched
		// page-1 listing -- confirms the feed's article count for that
		// ao3WorkID stays at 1 after the call, not 2.
		TestingURLProtocol.setResponse("archiveofourown.org/series/999003", file: "ao3-series-nav-page1-with-work-one.html")
		TestingURLProtocol.setResponse("archiveofourown.org/works/22222", file: "ao3-work-single-chapter.html")

		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999003", direction: .next,
			targetWorkURL: "https://archiveofourown.org/works/22222", targetIndex: 2,
			existingArticle: existingArticle, account: account
		)
		XCTAssertEqual(result, .success(Article.calculatedArticleID(feedID: existingArticle.feedID, uniqueID: "22222")))

		let articles = await account.fetchArticlesAsync(.feed(account.existingFeed(withFeedID: existingArticle.feedID)!))
		let matchingArticles = articles.filter { AO3ChapterFetcher.ao3WorkID(fromBookKey: $0.bookKey) == "1" }
		XCTAssertEqual(matchingArticles.count, 1)
		XCTAssertEqual(matchingArticles.first?.articleID, existingArticle.articleID)
	}

	// MARK: - Second page needed (Step 3)

	func testTwoPageWalkFindsTargetOnPageTwo() async {
		TestingURLProtocol.setResponse("archiveofourown.org/series/999001?page=2", file: "ao3-series-nav-page2.html")
		TestingURLProtocol.setResponse("archiveofourown.org/series/999001", file: "ao3-series-nav-page1.html")
		TestingURLProtocol.setResponse("archiveofourown.org/works/33333", file: "ao3-work-single-chapter.html")

		// pageSize is 2 (page1Works.count); targetIndex 3 -> ceil(3/2) = page 2.
		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .next,
			targetWorkURL: "https://archiveofourown.org/works/33333", targetIndex: 3,
			existingArticle: existingArticle, account: account
		)
		XCTAssertEqual(result, .success(Article.calculatedArticleID(feedID: existingArticle.feedID, uniqueID: "33333")))

		// Page 2's own row should be stubbed too.
		let articles = await account.fetchArticlesAsync(.feed(account.existingFeed(withFeedID: existingArticle.feedID)!))
		XCTAssertTrue(articles.contains { $0.uniqueID == "33333" })
	}

	func testSeriesListingMismatchWhenComputedPageDoesNotContainTarget() async {
		TestingURLProtocol.setResponse("archiveofourown.org/series/999001?page=2", file: "ao3-series-nav-page2.html")
		TestingURLProtocol.setResponse("archiveofourown.org/series/999001", file: "ao3-series-nav-page1.html")

		// targetIndex 3 -> page 2, but this target isn't actually on
		// either fixture page.
		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .next,
			targetWorkURL: "https://archiveofourown.org/works/404404", targetIndex: 3,
			existingArticle: existingArticle, account: account
		)
		XCTAssertEqual(result, .failure(.seriesListingMismatch))
	}

	func testSeriesListingMismatchWhenIndexMathSaysPageOneButTargetIsMissing() async {
		TestingURLProtocol.setResponse("archiveofourown.org/series/999001", file: "ao3-series-nav-page1.html")
		// Deliberately no ?page=2 response registered: targetIndex 1 means
		// targetPage resolves to 1 (not >1), so Step 3's guard should stop
		// before ever requesting a second page. If it requested one
		// anyway, the missing stub would surface as .networkError instead
		// of .seriesListingMismatch, catching the regression.
		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .next,
			targetWorkURL: "https://archiveofourown.org/works/404404", targetIndex: 1,
			existingArticle: existingArticle, account: account
		)
		XCTAssertEqual(result, .failure(.seriesListingMismatch))
	}

	func testSeriesListingMismatchWhenComputedPageExceedsTotalPages() async {
		TestingURLProtocol.setResponse("archiveofourown.org/series/999001", file: "ao3-series-nav-page1.html")
		// pageSize is 2 and the pagination widget says there are only 2
		// pages. targetIndex 5 computes page 3, so Step 3 should fail
		// before sleeping or requesting `?page=3`.
		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .next,
			targetWorkURL: "https://archiveofourown.org/works/404404", targetIndex: 5,
			existingArticle: existingArticle, account: account
		)
		XCTAssertEqual(result, .failure(.seriesListingMismatch))
		XCTAssertFalse(TestingURLProtocol.requestedURLs.contains { $0.absoluteString.contains("archiveofourown.org/series/999001?page=3") })
	}

	// MARK: - Fetch failure (Step 4)

	func testFetchFailedWhenTargetWorkPageCantBeExtracted() async {
		TestingURLProtocol.setResponse("archiveofourown.org/series/999001", file: "ao3-series-nav-page1.html")
		// A page with no chapter content at all -- AO3ChapterHTMLExtractor
		// can't extract anything usable from it.
		TestingURLProtocol.setResponse("archiveofourown.org/works/87955346", file: "ao3-series-nav-empty.html")

		let result = await AO3SeriesNavigator.openSeriesWork(
			ao3SeriesID: "999001", direction: .first, targetWorkURL: nil, targetIndex: nil,
			existingArticle: existingArticle, account: account
		)
		guard case .failure(.fetchFailed) = result else {
			XCTFail("expected .fetchFailed, got \(result)")
			return
		}
	}
}
