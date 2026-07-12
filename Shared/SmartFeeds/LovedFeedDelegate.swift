//
//  LovedFeedDelegate.swift
//  Nectar
//
//  Phase 5 fork addition. Mirrors StarredFeedDelegate.swift exactly, against
//  the independent ArticleStatus.Key.loved status instead of .starred.
//

import Foundation
import RSCore
import Articles
import ArticlesDatabase
import Account
import Images

@MainActor struct LovedFeedDelegate: SmartFeedDelegate {

	var sidebarItemID: SidebarItemIdentifier? {
		return SidebarItemIdentifier.smartFeed(String(describing: LovedFeedDelegate.self))
	}

	let nameForDisplay = NSLocalizedString("Loved", comment: "Loved")
	let fetchType: FetchType = .loved(nil)
	var smallIcon: IconImage? {
		Assets.Images.lovedFeed
	}
	func fetchUnreadCount(account: Account) async -> Int {
		await account.fetchUnreadCountForLovedArticlesAsync()
	}
}
