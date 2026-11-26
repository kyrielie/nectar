//
//  SearchFeedDelegate.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/24/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import Foundation
import RSCore
import Account
import Articles
import ArticlesDatabase
import Images

struct SearchFeedDelegate: SmartFeedDelegate {

	var sidebarItemID: SidebarItemIdentifier? {
		let identifier = isTimelineScoped ? "SearchTimelineFeedDelegate" : String(describing: SearchFeedDelegate.self)
		return SidebarItemIdentifier.smartFeed(identifier)
	}

	var nameForDisplay: String {
		return nameForDisplayPrefix + searchString
	}

	let nameForDisplayPrefix = NSLocalizedString("Search: ", comment: "Search smart feed title prefix")
	let searchString: String
	let fetchType: FetchType
	let isTimelineScoped: Bool
	var smallIcon: IconImage? = Assets.Images.searchFeed

	init(searchString: String, articleIDs: Set<String>? = nil) {
		self.searchString = searchString
		if let articleIDs {
			self.fetchType = .searchWithArticleIDs(searchString, articleIDs)
			self.isTimelineScoped = true
		} else {
			self.fetchType = .search(searchString)
			self.isTimelineScoped = false
		}
	}

	func fetchArticlesOrderedAsync() async -> [Article]? {
		await AccountManager.shared.fetchArticlesOrderedAsync(fetchType)
	}

	func fetchArticleSearchMatchesOrderedAsync() async -> [ArticleSearchMatch]? {
		await AccountManager.shared.fetchArticleSearchMatchesOrderedAsync(fetchType)
	}

	func fetchUnreadCount(account: Account) async -> Int {
		// TODO: after 5.0
		0
	}
}
