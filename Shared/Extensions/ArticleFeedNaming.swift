//
//  ArticleFeedNaming.swift
//  NetNewsWire
//
//  Nectar fork addition. Shared by the timeline cell (MainTimelineModernViewController)
//  and the reader view (ArticleRenderer/WebViewController) so both agree on
//  the same rule: a book opened from a real feed shows that one feed's name;
//  a book opened from a smart feed (Today/Unread/Starred/Loved/Read/Search)
//  where SmartFeedArticleGrouping collapsed it from more than one feed shows
//  every one of those feeds, comma-separated, since crediting it to only the
//  surviving representative's feed would be arbitrary and misleading.
//

import Articles
import Account

@MainActor enum ArticleFeedNaming {

	/// `timelineFeed` is whatever SidebarItem the article is currently being
	/// viewed under (SceneCoordinator.timelineFeed on iOS). Pass nil if that
	/// context isn't available (e.g. rendering outside the timeline/reader
	/// flow) to always fall back to the article's own single feed name.
	static func displayName(for article: Article, timelineFeed: SidebarItem?) -> String? {
		if let groupProvider = timelineFeed as? SmartFeedArticleGroupProviding,
		   let feedIDs = groupProvider.bookKeyIndex.feedIDs(forBookKey: article.bookKey),
		   feedIDs.count > 1 {
			let names = feedIDs.compactMap { feedID in
				article.account?.existingFeed(withFeedID: feedID)?.nameForDisplay
			}.sorted()
			if !names.isEmpty {
				return names.joined(separator: ", ")
			}
		}
		return article.feed?.nameForDisplay
	}
}
