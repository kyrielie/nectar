//
//  AO3SeriesNavigatorTests.swift
//  AccountTests
//
//  Nectar inline-series-navigation plan, Phase 4: coverage for
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
		account = TestAccountManager.shared.createAccount(type: .onMyMac)
		_ = await account.importPastedAO3Links("https://archiveofourown.org/works/1")
		let feed = account.existingFeed(withURL: Account.importedLinksFeedURL)!
		existingArticle = await account.fetchArticlesAsync(.feed(feed)).first!
	}

	override func tearDown() async throws {
		TestingURLProtocol.reset()
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

	// MARK: - Page 1 resolves it (Step 2)

	func testFirstResolvesFirstWorkFromPageOne() async {
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
