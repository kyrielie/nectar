//
//  SmartFeed.swift
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

@MainActor final class SmartFeed: PseudoFeed {
	var account: Account?

	public var defaultReadFilterType: ReadFilterType {
		return .none
	}

	var sidebarItemID: SidebarItemIdentifier? {
		delegate.sidebarItemID
	}

	var nameForDisplay: String {
		return delegate.nameForDisplay
	}

	var unreadCount = 0 {
		didSet {
			if unreadCount != oldValue {
				postUnreadCountDidChangeNotification()
			}
		}
	}

	var smallIcon: IconImage? {
		return delegate.smallIcon
	}

	#if os(macOS)
	var pasteboardWriter: NSPasteboardWriting {
		return SmartFeedPasteboardWriter(smartFeed: self)
	}
	#endif

	private let delegate: SmartFeedDelegate
	private var unreadCounts = [String: Int]()
	let bookKeyIndex = SmartFeedBookKeyIndex()

	init(delegate: SmartFeedDelegate) {
		self.delegate = delegate
		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(statusesDidChange(_:)), name: .StatusesDidChange, object: nil)
		queueFetchUnreadCounts() // Fetch unread count at startup
	}

	@objc func unreadCountDidChange(_ note: Notification) {
		if note.object is AppDelegate {
			queueFetchUnreadCounts()
		}
	}

	// Starred/loved status changes don't affect true unread counts, but
	// Read Later/Loved/All Read repurpose this badge as a total count, so
	// it needs to be recomputed whenever any status changes too.
	@objc func statusesDidChange(_ note: Notification) {
		queueFetchUnreadCounts()
	}

	@objc func fetchUnreadCounts() {
		let activeAccounts = AccountManager.shared.activeAccounts

		// Remove any accounts that are no longer active or have been deleted
		let activeAccountIDs = activeAccounts.map { $0.accountID }
		for accountID in unreadCounts.keys {
			if !activeAccountIDs.contains(accountID) {
				unreadCounts.removeValue(forKey: accountID)
			}
		}

		if activeAccounts.isEmpty {
			updateUnreadCount()
		} else {
			for account in activeAccounts {
				fetchUnreadCount(account: account)
			}
		}
	}

}

extension SmartFeed: ArticleFetcher {

	func fetchArticles() -> Set<Article> {
		let (deduplicated, feedIDsByBookKey) = SmartFeedArticleGrouping.deduplicated(delegate.fetchArticles())
		bookKeyIndex.update(feedIDsByBookKey)
		return deduplicated
	}

	func fetchArticlesAsync() async -> Set<Article> {
		let (deduplicated, feedIDsByBookKey) = SmartFeedArticleGrouping.deduplicated(await delegate.fetchArticlesAsync())
		bookKeyIndex.update(feedIDsByBookKey)
		return deduplicated
	}

	// Unread counts intentionally keep counting every occurrence, not just
	// deduplicated books -- collapsing duplicates here would make the badge
	// disagree with what "mark all as read" actually walks through. Dedup is
	// a timeline *display* concern (see fetchArticles/fetchArticlesAsync
	// above), not a counting one.
	func fetchUnreadArticles() -> Set<Article> {
		delegate.fetchUnreadArticles()
	}

	func fetchUnreadArticlesAsync() async -> Set<Article> {
		await delegate.fetchUnreadArticlesAsync()
	}
}

extension SmartFeed: SmartFeedArticleGroupProviding {
}

private extension SmartFeed {

	func queueFetchUnreadCounts() {
		CoalescingQueue.standard.add(self, #selector(fetchUnreadCounts))
	}

	func fetchUnreadCount(account: Account) {
		Task { @MainActor in
			let unreadCount = await delegate.fetchUnreadCount(account: account)
			unreadCounts[account.accountID] = unreadCount
			updateUnreadCount()
		}
	}

	func updateUnreadCount() {
		var updatedUnreadCount = 0
		for account in AccountManager.shared.activeAccounts {
			if let oneUnreadCount = unreadCounts[account.accountID] {
				updatedUnreadCount += oneUnreadCount
			}
		}

		unreadCount = updatedUnreadCount
	}
}
