//
//  AO3SeriesNavigator.swift
//  NetNewsWire
//
//  Nectar AO3 direct-reading support, Task 10 ("Prev/next/first
//  navigation -- independent of the grouping toggle"). See
//  nectar-ao3-features-plan-FINAL.md.
//
//  Tapping Previous/Next/First in the reader adds that work to the
//  current article's own feed (mirroring the stub-then-fetch shape of
//  Account.importPastedAO3Links(_:), but under existingArticle.feedID
//  rather than the "Imported Links" feed) and fetches it immediately --
//  unlike AO3ChapterFetcher.fetchIfNeeded's lazy on-open trigger, this is
//  an explicit "read this now" tap.
//

import Foundation
import Articles
import RSParser
import RSWeb

public enum AO3SeriesNavigationError: Error, Sendable {
	/// `article.previousWorkURL`/`nextWorkURL` was nil -- the work is
	/// first/last in every series it belongs to (for that direction), or
	/// has no series membership at all.
	case noAdjacentWork
	/// `article.series` has no entry with a non-nil `ao3ID` to build a
	/// `/series/<id>` listing URL from.
	case noSeriesID
	/// The series-listing page loaded but no work row was found in it
	/// (see `AO3SeriesListingExtractor.firstWorkPermalink`).
	case emptySeriesListing
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
		case .noSeriesID:
			return NSLocalizedString("This work's series page isn't available", comment: "AO3 series navigation error")
		case .emptySeriesListing:
			return NSLocalizedString("Couldn't find the first work in this series", comment: "AO3 series navigation error")
		case .networkError(let message), .fetchFailed(let message):
			return message
		}
	}
}

@MainActor
public enum AO3SeriesNavigator {

	/// Adds and fetches the adjacent work in `existingArticle`'s series
	/// (whichever `direction` selects), returning the new article's
	/// `articleID` once its content has finished loading, so the caller
	/// can navigate the reader straight to it.
	///
	/// Interim Phase 1/2 shim: since the inline-series-navigation plan's
	/// Phase 1 folded `previousWorkURL`/`nextWorkURL` into each
	/// `ArticleSeriesEntry` (a work in more than one series can have a
	/// different adjacent work per series -- see `ArticleSeriesEntry`'s
	/// doc comment), this whole entry point is superseded by Phase 4's
	/// `openSeriesWork(ao3SeriesID:direction:targetWorkURL:targetIndex:existingArticle:account:)`,
	/// which is per-series rather than per-article. Until Phase 4 lands,
	/// this keeps the existing context-menu behavior working by picking
	/// the first series membership with a non-nil URL for `direction` --
	/// the same "first membership wins" collapsing the old
	/// `AO3ChapterHTMLExtractor.previousNextWorkURLs(fromDD:)` used to do
	/// before Phase 2 replaced it. Delete this function (and this whole
	/// call path) once Phase 4 ships.
	public static func fetchAdjacentWork(direction: Direction, from existingArticle: Article, account: Account) async -> Result<String, AO3SeriesNavigationError> {
		let permalink = existingArticle.series?.compactMap { direction == .previous ? $0.previousWorkURL : $0.nextWorkURL }.first
		guard let permalink, let workID = AO3SummaryExtractor.ao3WorkID(fromPermalink: permalink) else {
			return .failure(.noAdjacentWork)
		}
		return await fetchAndAddWork(workID: workID, feedID: existingArticle.feedID, account: account)
	}

	/// Same fetch as `fetchAdjacentWork(direction:from:account:)` above,
	/// but taking the already-known target work URL directly rather than
	/// re-deriving it from `existingArticle.series`'s collapsed "first
	/// membership wins" pick. Used by the inline `nectar-series:` link
	/// handler (`WebViewController.handleNectarSeriesLink`, plan Phase
	/// 3a/3c) -- the tapped link already carries the correct per-series
	/// URL from `AO3ChapterHTMLExtractor.seriesEntriesWithNavigation`'s
	/// per-span parse, so reusing the article-wide entry point above
	/// would silently pick the wrong series' URL for a work in more than
	/// one series, the exact bug Phase 1/2's data-model change fixed.
	///
	/// Interim, same as `fetchAdjacentWork(direction:from:account:)`: just
	/// the single-work fetch-and-add every Task 10 entry point in this
	/// file already does, not yet Phase 4's bounded series-listing walk
	/// or batch stub-import of other series members.
	public static func fetchAdjacentWork(direction: Direction, workURL: String, feedID: String, account: Account) async -> Result<String, AO3SeriesNavigationError> {
		guard let workID = AO3SummaryExtractor.ao3WorkID(fromPermalink: workURL) else {
			return .failure(.noAdjacentWork)
		}
		return await fetchAndAddWork(workID: workID, feedID: feedID, account: account)
	}

	public enum Direction: Sendable {
		case previous
		case next
	}

	/// Fetches `existingArticle`'s series-listing page (lazily -- this is
	/// the only Task 10 codepath that needs it, since prev/next alone
	/// never reach work #1 directly) to find the first work, then adds
	/// and fetches it the same way `fetchAdjacentWork` does.
	///
	/// A work in more than one series picks the first membership with a
	/// non-nil `ao3ID`, same "first one wins" reasoning as
	/// `AO3ChapterHTMLExtractor.previousNextWorkURLs`'s doc comment --
	/// the reader's "First work" button is singular, so some choice has
	/// to be made when there's more than one series to be first-in.
	public static func fetchFirstWorkInSeries(from existingArticle: Article, account: Account) async -> Result<String, AO3SeriesNavigationError> {
		guard let seriesID = existingArticle.series?.first(where: { $0.ao3ID != nil })?.ao3ID else {
			return .failure(.noSeriesID)
		}
		return await fetchFirstWorkInSeries(ao3SeriesID: seriesID, feedID: existingArticle.feedID, account: account)
	}

	/// Same fetch as `fetchFirstWorkInSeries(from:account:)` above, but
	/// taking `ao3SeriesID` directly rather than deriving it from
	/// `existingArticle.series`'s "first membership with a non-nil ao3ID
	/// wins" pick. Used by the inline `nectar-series:first` link handler
	/// (`WebViewController.handleNectarSeriesLink`) -- the tapped link
	/// already names the specific series it belongs to (plan Phase 3a),
	/// so a work in more than one series resolves First against whichever
	/// series row was actually tapped, not always the first one in
	/// `article.series`.
	public static func fetchFirstWorkInSeries(ao3SeriesID: String, feedID: String, account: Account) async -> Result<String, AO3SeriesNavigationError> {
		guard let seriesURL = URL(string: "https://archiveofourown.org/series/\(ao3SeriesID)") else {
			return .failure(.noSeriesID)
		}

		let downloadResponse: DownloadResponse
		do {
			downloadResponse = try await Downloader.shared.download(seriesURL)
		} catch {
			return .failure(.networkError(error.localizedDescription))
		}

		guard let data = downloadResponse.data, !data.isEmpty,
		      let response = downloadResponse.response, response.statusIsOK,
		      let html = String(data: data, encoding: .utf8) else {
			return .failure(.networkError(NSLocalizedString("Couldn't load the series page", comment: "AO3 series navigation error")))
		}

		guard let permalink = AO3SeriesListingExtractor.firstWorkPermalink(fromSeriesListingHTML: html),
		      let workID = AO3SummaryExtractor.ao3WorkID(fromPermalink: permalink) else {
			return .failure(.emptySeriesListing)
		}

		return await fetchAndAddWork(workID: workID, feedID: feedID, account: account)
	}
}

private extension AO3SeriesNavigator {

	/// Creates a placeholder stub for `workID` under `feedID` (same
	/// bare-link shape `Account.importPastedAO3Links(_:)` uses --
	/// `updateAsync`'s `deleteOlder: false` plus a stable `uniqueID` of
	/// `workID` means calling this twice for the same work is a no-op,
	/// not a duplicate), then fetches it via the same
	/// `AO3ChapterFetcher.download(workID:articleID:accountID:feedID:)`
	/// every on-open/explicit refetch already goes through -- reusing its
	/// existing Cloudflare/registration-required/rate-limit handling
	/// rather than re-implementing it here. `articleID` is computed with
	/// `Article.calculatedArticleID(feedID:uniqueID:)` up front (the same
	/// derivation the database uses for any nil-`syncServiceID`
	/// `ParsedItem`) so it's known before the write completes, letting
	/// this wait on the notification pair `download` posts rather than
	/// re-querying the database afterward.
	static func fetchAndAddWork(workID: String, feedID: String, account: Account) async -> Result<String, AO3SeriesNavigationError> {
		let articleID = Article.calculatedArticleID(feedID: feedID, uniqueID: workID)

		let stub = ParsedItem(
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
		_ = await account.updateAsync(feedID: feedID, parsedItems: [stub], deleteOlder: false)

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
