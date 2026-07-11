//
//  StarredFeedDelegate.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 11/19/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import Foundation
import RSCore
import Articles
import ArticlesDatabase
import Account
import Images

@MainActor struct StarredFeedDelegate: SmartFeedDelegate {

	var sidebarItemID: SidebarItemIdentifier? {
		return SidebarItemIdentifier.smartFeed(String(describing: StarredFeedDelegate.self))
	}

	// Label reads "Read Later" (Phase 3) — internal type name, delegate, and
	// underlying ArticleStatus.Key.starred are unchanged deliberately.
	let nameForDisplay = NSLocalizedString("Read Later", comment: "Read Later")
	let fetchType: FetchType = .starred(nil)
	var smallIcon: IconImage? {
		Assets.Images.starredFeed
	}
	func fetchUnreadCount(account: Account) async -> Int {
		await account.fetchUnreadCountForStarredArticlesAsync()
	}
}
