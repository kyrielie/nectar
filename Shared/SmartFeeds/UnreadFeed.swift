//
//  UnreadFeed.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 11/19/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

#if os(macOS)
import AppKit
#else
import Foundation
#endif
import RSCore
import Account
import Articles
import ArticlesDatabase
import Images

// This just shows the global unread count, which AccountManager already has. Easy.

@MainActor final class UnreadFeed: PseudoFeed {

	var account: Account?

	public var defaultReadFilterType: ReadFilterType {
		return .alwaysRead
	}

	var sidebarItemID: SidebarItemIdentifier? {
		return SidebarItemIdentifier.smartFeed(String(describing: UnreadFeed.self))
	}

	let nameForDisplay = NSLocalizedString("All Unread", comment: "All Unread pseudo-feed title")
	let fetchType = FetchType.unread(nil)

	var unreadCount = 0 {
		didSet {
			if unreadCount != oldValue {
				postUnreadCountDidChangeNotification()
			}
		}
	}

	var smallIcon: IconImage? {
		Assets.Images.unreadFeed
	}

	#if os(macOS)
	var pasteboardWriter: NSPasteboardWriting {
		return SmartFeedPasteboardWriter(smartFeed: self)
	}
	#endif

	let bookKeyIndex = SmartFeedBookKeyIndex()

	init() {

		self.unreadCount = AccountManager.shared.unreadCount
		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: AccountManager.shared)
	}

	@objc func unreadCountDidChange(_ note: Notification) {

		assert(note.object is AccountManager)
		unreadCount = AccountManager.shared.unreadCount
	}
}

@MainActor extension UnreadFeed: ArticleFetcher {

	func fetchArticles() -> Set<Article> {
		let (deduplicated, feedIDsByBookKey) = SmartFeedArticleGrouping.deduplicated(fetchUnreadArticles())
		bookKeyIndex.update(feedIDsByBookKey)
		return deduplicated
	}

	func fetchArticlesAsync() async -> Set<Article> {
		let (deduplicated, feedIDsByBookKey) = SmartFeedArticleGrouping.deduplicated(await fetchUnreadArticlesAsync())
		bookKeyIndex.update(feedIDsByBookKey)
		return deduplicated
	}

	// Kept undeduplicated: this is also the badge/count source, and
	// collapsing duplicate books here would make "All Unread"'s count
	// disagree with what actually gets marked read. See fetchArticles above
	// for the deduplicated timeline-display path.
	func fetchUnreadArticles() -> Set<Article> {
		AccountManager.shared.fetchArticles(fetchType)
	}

	func fetchUnreadArticlesAsync() async -> Set<Article> {
		await AccountManager.shared.fetchArticlesAsync(fetchType)
	}
}

extension UnreadFeed: SmartFeedArticleGroupProviding {
}