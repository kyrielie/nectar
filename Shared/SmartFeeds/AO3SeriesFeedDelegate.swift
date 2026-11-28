//
//  AO3SeriesFeedDelegate.swift
//  NetNewsWire
//
//  Ephemeral SmartFeedDelegate backing Nectar's native timeline
//  (MainTimelineModernViewController) for an AO3 series, mirroring
//  SearchFeedDelegate / LibrarySearchFeedDelegate.
//

import Foundation
import RSCore
import Account
import Articles
import ArticlesDatabase
import Images

struct AO3SeriesFeedDelegate: SmartFeedDelegate {

	var sidebarItemID: SidebarItemIdentifier? {
		SidebarItemIdentifier.smartFeed("AO3SeriesFeedDelegate:\(ao3SeriesID)")
	}

	var nameForDisplay: String {
		seriesName
	}

	let ao3SeriesID: String
	let seriesName: String
	let accountID: String
	let preferredFeedID: String?
	let fetchType: FetchType = .today(nil)
	var smallIcon: IconImage? = Assets.Images.searchFeed

	init(seriesEntry: ArticleSeriesEntry, account: Account, preferredFeedID: String? = nil) {
		self.ao3SeriesID = seriesEntry.ao3ID ?? seriesEntry.name
		self.seriesName = seriesEntry.name
		self.accountID = account.accountID
		self.preferredFeedID = preferredFeedID
	}

	func fetchArticles() -> Set<Article> {
		Set()
	}

	func fetchArticlesAsync() async -> Set<Article> {
		guard let account = AccountManager.shared.existingAccount(accountID: accountID) else {
			return Set()
		}
		return await account.fetchArticlesAsync(ao3SeriesID: ao3SeriesID)
	}

	func fetchArticlesOrderedAsync() async -> [Article]? {
		let articles = await fetchArticlesAsync()
		return Self.orderedArticles(from: articles, ao3SeriesID: ao3SeriesID, preferredFeedID: preferredFeedID)
	}

	func fetchUnreadCount(account: Account) async -> Int {
		let articles = await account.fetchArticlesAsync(ao3SeriesID: ao3SeriesID)
		return articles.unreadArticles().count
	}

	static func orderedArticles(
		from articles: Set<Article>,
		ao3SeriesID: String,
		preferredFeedID: String?
	) -> [Article] {
		// Deduplicate sibling copies sharing a bookKey: prefer downloaded content, then preferredFeedID.
		var byBookKey = [String: Article]()
		for article in articles {
			if let existing = byBookKey[article.bookKey] {
				let existingHasContent = !(existing.contentHTML?.isEmpty ?? true)
				let incomingHasContent = !(article.contentHTML?.isEmpty ?? true)
				if !existingHasContent && incomingHasContent {
					byBookKey[article.bookKey] = article
				} else if existingHasContent == incomingHasContent,
				          let preferredFeedID,
				          article.feedID == preferredFeedID,
				          existing.feedID != preferredFeedID {
					byBookKey[article.bookKey] = article
				}
			} else {
				byBookKey[article.bookKey] = article
			}
		}

		return byBookKey.values.sorted { lhs, rhs in
			let lhsIndex = lhs.series?.first(where: { $0.ao3ID == ao3SeriesID })?.index ?? Int.max
			let rhsIndex = rhs.series?.first(where: { $0.ao3ID == ao3SeriesID })?.index ?? Int.max
			if lhsIndex != rhsIndex {
				return lhsIndex < rhsIndex
			}
			return (lhs.title ?? "") < (rhs.title ?? "")
		}
	}
}
