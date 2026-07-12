//
//  TodayFeedDelegate.swift
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

struct TodayFeedDelegate: SmartFeedDelegate {
	var sidebarItemID: SidebarItemIdentifier? {
		return SidebarItemIdentifier.smartFeed(String(describing: TodayFeedDelegate.self))
	}

	// Kept as "TodayFeedDelegate" (sidebarItemID is derived from the type
	// name and is effectively persisted via sidebar expansion/selection
	// state) even though this now means "recently added," not "today" --
	// renaming the type would make this look like a new, unrelated smart
	// feed to anything that already has this one expanded or selected.
	let nameForDisplay = NSLocalizedString("Recently Added", comment: "Recently Added pseudo-feed title")
	let fetchType = FetchType.today(nil)
	var smallIcon: IconImage? {
		Assets.Images.todayFeed
	}

	func fetchUnreadCount(account: Account) async -> Int {
		await account.fetchUnreadCountForTodayAsync()
	}
}
