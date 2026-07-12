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
		// TODO: add a heart-icon asset catalog entry (e.g. Assets.Images.lovedFeed)
		// and point this at it. Asset catalog contents aren't part of this patch
		// series since they're not diffable as text.
		Assets.Images.starredFeed
	}
	func fetchUnreadCount(account: Account) async -> Int {
		await account.fetchUnreadCountForLovedArticlesAsync()
	}
}
