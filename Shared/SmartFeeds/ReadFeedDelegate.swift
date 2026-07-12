//
//  ReadFeedDelegate.swift
//  Nectar
//
//  Mirrors LovedFeedDelegate.swift/StarredFeedDelegate.swift, against the
//  new FetchType.read case instead of .loved/.starred.
//

import Foundation
import RSCore
import Articles
import ArticlesDatabase
import Account
import Images

@MainActor struct ReadFeedDelegate: SmartFeedDelegate {

	var sidebarItemID: SidebarItemIdentifier? {
		return SidebarItemIdentifier.smartFeed(String(describing: ReadFeedDelegate.self))
	}

	let nameForDisplay = NSLocalizedString("All Read", comment: "All Read pseudo-feed title")
	let fetchType: FetchType = .read(nil)
	var smallIcon: IconImage? {
		Assets.Images.readFeed
	}

	// By definition every article in this feed is read, so a true unread
	// count would always be zero. Repurposed as a general badge count
	// instead, showing the total number of read articles.
	func fetchUnreadCount(account: Account) async -> Int {
		await account.fetchCountForReadArticlesAsync()
	}
}
