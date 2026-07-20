//
//  LastOpenedFeedDelegate.swift
//  Nectar
//
//  Mirrors ReadFeedDelegate.swift/LovedFeedDelegate.swift, against
//  FetchType.lastOpened instead of .read/.loved. Unlike those, fetchType
//  carries a fixed limit (10) rather than nil -- capping to "last 10 opened"
//  is the whole point of this feed, done via the SQL LIMIT in
//  ArticlesTable.fetchLastOpenedArticles rather than any write-side pruning
//  of bookState/statuses.
//

import Foundation
import RSCore
import Articles
import ArticlesDatabase
import Account
import Images

@MainActor struct LastOpenedFeedDelegate: SmartFeedDelegate {

	static let limit = 10

	var sidebarItemID: SidebarItemIdentifier? {
		return SidebarItemIdentifier.smartFeed(String(describing: LastOpenedFeedDelegate.self))
	}

	let nameForDisplay = NSLocalizedString("Last Opened", comment: "Last Opened pseudo-feed title")
	let fetchType: FetchType = .lastOpened(LastOpenedFeedDelegate.limit)
	var smallIcon: IconImage? {
		Assets.Images.lastOpenedFeed
	}

	// Unlike Read/Loved/Read Later, there's no natural "total" to repurpose
	// this badge as -- the feed is capped to a constant (10), not a count
	// that says anything about the library. Suppressed rather than shown.
	func fetchUnreadCount(account: Account) async -> Int {
		0
	}
}
