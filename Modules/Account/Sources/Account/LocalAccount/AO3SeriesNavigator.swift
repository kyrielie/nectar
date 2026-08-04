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

	/// Adds and fetches `existingArticle.previousWorkURL`/`nextWorkURL`
	/// (whichever `direction` selects), returning the new article's
	/// `articleID` once its content has finished loading, so the caller
	/// can navigate the reader straight to it.
	public static func fetchAdjacentWork(direction: Direction, from existingArticle: Article, account: Account) async -> Result<String, AO3SeriesNavigationError> {
		let permalink = direction == .previous ? existingArticle.previousWorkURL : existingArticle.nextWorkURL
		guard let permalink, let workID = AO3SummaryExtractor.ao3WorkID(fromPermalink: permalink) else {
			return .failure(.noAdjacentWork)
		}
		return await fetchAndAddWork(workID: workID, feedID: existingArticle.feedID, account: account)
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
		guard let seriesID = existingArticle.series?.first(where: { $0.ao3ID != nil })?.ao3ID,
		      let seriesURL = URL(string: "https://archiveofourown.org/series/\(seriesID)") else {
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

		return await fetchAndAddWork(workID: workID, feedID: existingArticle.feedID, account: account)
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
