//
//  AO3SeriesNavigator.swift
//  NetNewsWire
//
//  Nectar AO3 direct-reading support. Originally Task 10 ("Prev/next/
//  first navigation -- independent of the grouping toggle"), now the
//  inline-series-navigation plan's Phase 4: `openSeriesWork` below
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
import Articles
import RSParser
import RSWeb

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
	///    id isn't known yet). If a cached article already exists under
	///    `existingArticle.feedID` for the target work id, with content
	///    already fetched, return it directly -- no listing fetch at all.
	/// 2. **Fetch page 1**, always. This is the only fetch `.first` ever
	///    needs -- series list works in ascending Part order, so #1 is
	///    never on a later page. Every work found is batch-stubbed into
	///    the feed (one `account.updateAsync` call, not one per work).
	///    `.previous`/`.next` whose target is on this page resolve here
	///    too, no second fetch.
	/// 3. **Fetch the computed page** (`.previous`/`.next` only, when the
	///    target isn't on page 1) -- the single allowed second fetch,
	///    paced by `AO3ChapterFetcher.secondsBetweenSweepRequests` before
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
	public static func openSeriesWork(
		ao3SeriesID: String,
		direction: Direction,
		targetWorkURL: String?,
		targetIndex: Int?,
		existingArticle: Article,
		account: Account
	) async -> Result<String, AO3SeriesNavigationError> {

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

		// Step 1: cache check -- skipped entirely for .first, whose
		// target id isn't known until page 1 is parsed below.
		if let knownTargetWorkID {
			if let cachedArticleID = await cachedArticleID(forWorkID: knownTargetWorkID, feedID: existingArticle.feedID, account: account) {
				return .success(cachedArticleID)
			}
		}

		// Step 2: page 1, always.
		guard let page1HTML = await fetchListingPage(ao3SeriesID: ao3SeriesID, page: 1) else {
			return .failure(.networkError(NSLocalizedString("Couldn't load the series page", comment: "AO3 series navigation error")))
		}
		let (page1Works, _) = AO3SeriesListingExtractor.workPermalinks(fromSeriesListingHTML: page1HTML)
		guard !page1Works.isEmpty else {
			return .failure(.emptySeriesListing)
		}
		await stubImport(page1Works, feedID: existingArticle.feedID, account: account)

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
			return await downloadAndAwait(workID: targetWorkID, feedID: existingArticle.feedID, account: account)
		}

		// .first's target is always page1Works[0], so it can never reach
		// here -- only .previous/.next fall through to the second fetch.

		// Step 3: the single allowed second fetch, only when the target's
		// position math says it isn't on page 1.
		guard let targetIndex else {
			return .failure(.seriesListingMismatch)
		}
		let pageSize = page1Works.count
		let targetPage = Int((Double(targetIndex) / Double(pageSize)).rounded(.up))
		guard targetPage > 1 else {
			// The index math says the target should have been on page 1,
			// but it wasn't found there -- treat as a mismatch rather
			// than silently fetching page 1 again.
			return .failure(.seriesListingMismatch)
		}

		try? await Task.sleep(nanoseconds: UInt64(AO3ChapterFetcher.secondsBetweenSweepRequests * 1_000_000_000))

		guard let pageNHTML = await fetchListingPage(ao3SeriesID: ao3SeriesID, page: targetPage) else {
			return .failure(.networkError(NSLocalizedString("Couldn't load the series page", comment: "AO3 series navigation error")))
		}
		let (pageNWorks, _) = AO3SeriesListingExtractor.workPermalinks(fromSeriesListingHTML: pageNHTML)
		await stubImport(pageNWorks, feedID: existingArticle.feedID, account: account)

		guard pageNWorks.contains(where: { $0.workID == targetWorkID }) else {
			return .failure(.seriesListingMismatch)
		}

		return await downloadAndAwait(workID: targetWorkID, feedID: existingArticle.feedID, account: account)
	}
}

private extension AO3SeriesNavigator {

	/// An existing article under `feedID` whose `ao3WorkID` (recovered
	/// from `bookKey`, same as every other AO3-refetch call site --
	/// `Article` itself carries no separate `ao3WorkID` property) matches
	/// `workID` and already has fetched content. `Account.fetchArticlesAsync`
	/// is used over the synchronous `fetchArticles` since this already
	/// runs off an async context and the feed's article set can be large.
	static func cachedArticleID(forWorkID workID: String, feedID: String, account: Account) async -> String? {
		guard let feed = account.existingFeed(withFeedID: feedID) else {
			return nil
		}
		let articles = await account.fetchArticlesAsync(.feed(feed))
		return articles.first(where: { AO3ChapterFetcher.ao3WorkID(fromBookKey: $0.bookKey) == workID && $0.contentHTML != nil })?.articleID
	}

	/// `GET https://archiveofourown.org/series/<id>` for page 1 (bare, no
	/// query string -- AO3's own page-1-is-bare-URL convention), or
	/// `.../series/<id>?page=<n>` for `n >= 2`.
	static func fetchListingPage(ao3SeriesID: String, page: Int) async -> String? {
		var urlString = "https://archiveofourown.org/series/\(ao3SeriesID)"
		if page > 1 {
			urlString += "?page=\(page)"
		}
		guard let url = URL(string: urlString) else {
			return nil
		}
		guard let downloadResponse = try? await Downloader.shared.download(url) else {
			return nil
		}
		guard let data = downloadResponse.data, !data.isEmpty,
		      let response = downloadResponse.response, response.statusIsOK else {
			return nil
		}
		return String(data: data, encoding: .utf8)
	}

	/// Batch-stubs every work found on one fetched listing page into
	/// `feedID`, one `account.updateAsync` call for the whole page (per
	/// its own doc comment about being written around one feed-shaped
	/// batch, not one call per work). Placeholder-title shape matches
	/// `downloadAndAwait`'s single-work stub exactly (Phase 4b) --
	/// deliberately not using the listing row's real, already-parsed
	/// title: every work here except the one this call is ultimately
	/// opening stays an unfetched stub until it's next opened directly,
	/// same "content fetched only on open" contract as any other
	/// AO3-sourced stub in this app, so richer upfront metadata would be
	/// work with no consumer.
	static func stubImport(_ works: [AO3SeriesListingExtractor.WorkListingEntry], feedID: String, account: Account) async {
		guard !works.isEmpty else {
			return
		}
		let stubs = Set(works.map { placeholderStub(workID: $0.workID, feedID: feedID) })
		_ = await account.updateAsync(feedID: feedID, parsedItems: stubs, deleteOlder: false)
	}

	static func placeholderStub(workID: String, feedID: String) -> ParsedItem {
		ParsedItem(
			syncServiceID: nil,
			uniqueID: workID,
			feedURL: feedID,
			url: "https://archiveofourown.org/works/\(workID)",
			externalURL: nil,
			title: String(format: NSLocalizedString("AO3 Work %@", comment: "Series-navigation placeholder title, before the work is fetched"), workID),
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

	/// Ensures a stub exists for `workID` (a no-op if `stubImport` already
	/// created one -- `updateAsync`'s `deleteOlder: false` upsert on a
	/// stable `uniqueID` of `workID` makes calling this twice for the same
	/// work harmless, not a duplicate), then fetches it via
	/// `AO3ChapterFetcher.download(workID:articleID:accountID:feedID:)`,
	/// reusing its existing Cloudflare/registration-required/rate-limit
	/// handling rather than re-implementing it here. `articleID` is
	/// computed with `Article.calculatedArticleID(feedID:uniqueID:)` up
	/// front (the same derivation the database uses for any
	/// nil-`syncServiceID` `ParsedItem`) so it's known before the write
	/// completes, letting this wait on the notification pair `download`
	/// posts rather than re-querying the database afterward.
	static func downloadAndAwait(workID: String, feedID: String, account: Account) async -> Result<String, AO3SeriesNavigationError> {
		let articleID = Article.calculatedArticleID(feedID: feedID, uniqueID: workID)

		// Belt-and-suspenders: openSeriesWork's own page-1/page-N walk
		// always stubs the target before calling this, but this entry
		// point doesn't assume that -- a stub-less call is still safe
		// (deleteOlder: false, stable uniqueID) and keeps this function
		// usable on its own.
		_ = await account.updateAsync(feedID: feedID, parsedItems: [placeholderStub(workID: workID, feedID: feedID)], deleteOlder: false)

		return await withCheckedContinuation { continuation in
			var tokens: [NSObjectProtocol] = []
			var didResume = false

			func finish(_ result: Result<String, AO3SeriesNavigationError>) {
				guard !didResume else { return }
				didResume = true
				tokens.forEach(NotificationCenter.default.removeObserver)
				continuation.resume(returning: result)
			}

			tokens.append(NotificationCenter.default.addObserver(forName: .ao3ChapterFetchDidComplete, object: nil, queue: .main) { note in
				guard note.userInfo?[AO3ChapterFetchUserInfoKey.articleID] as? String == articleID else { return }
				finish(.success(articleID))
			})
			tokens.append(NotificationCenter.default.addObserver(forName: .ao3ChapterFetchDidFail, object: nil, queue: .main) { note in
				guard note.userInfo?[AO3ChapterFetchUserInfoKey.articleID] as? String == articleID else { return }
				let message = note.userInfo?[AO3ChapterFetchUserInfoKey.message] as? String ?? NSLocalizedString("Couldn't load this work", comment: "AO3 series navigation error")
				finish(.failure(.fetchFailed(message)))
			})

			AO3ChapterFetcher.shared.download(workID: workID, articleID: articleID, accountID: account.accountID, feedID: feedID)
		}
	}
}
