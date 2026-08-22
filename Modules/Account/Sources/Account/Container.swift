//
//  Container.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 4/17/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import RSCore
import Articles

extension Notification.Name {
	public static let ChildrenDidChange = Notification.Name("ChildrenDidChange")
}

@MainActor public protocol Container: AnyObject, ContainerIdentifiable {
	var account: Account? { get }
	var topLevelFeeds: OrderedSet<Feed> { get set }
	var folders: OrderedSet<Folder>? { get set }
	var externalID: String? { get set }

	func hasAtLeastOneFeed() -> Bool
	func objectIsChild(_ object: AnyObject) -> Bool

	@MainActor func hasChildFolder(with: String) -> Bool
	@MainActor func childFolder(with: String) -> Folder?

    func removeFeedFromTreeAtTopLevel(_ feed: Feed)
	func addFeedToTreeAtTopLevel(_ feed: Feed, at index: Int?)

	// Recursive — checks subfolders
	func flattenedFeeds() -> Set<Feed>
	func has(_ feed: Feed) -> Bool
	func hasFeed(with feedID: String) -> Bool
	func hasFeed(withURL url: String) -> Bool
	func existingFeed(withFeedID: String) -> Feed?
	func existingFeed(withURL url: String) -> Feed?
	func existingFeed(withExternalID externalID: String) -> Feed?
	@MainActor func existingFolder(with name: String) -> Folder?
	func existingFolder(withID: Int) -> Folder?
	func existingFolder(withPath path: [String]) -> Folder?

	func addFolderToTree(_ folder: Folder, at index: Int?)
	func removeFolderFromTree(_ folder: Folder)

	func postChildrenDidChangeNotification()
}

@MainActor public extension Container {

	func addFeedToTreeAtTopLevel(_ feed: Feed) {
		addFeedToTreeAtTopLevel(feed, at: nil)
	}

	func hasAtLeastOneFeed() -> Bool {
		return topLevelFeeds.count > 0
	}

	@MainActor func hasChildFolder(with name: String) -> Bool {
		return childFolder(with: name) != nil
	}

	@MainActor func childFolder(with name: String) -> Folder? {
		guard let folders = folders else {
			return nil
		}
		for folder in folders {
			if folder.name == name {
				return folder
			}
		}
		return nil
	}

	func objectIsChild(_ object: AnyObject) -> Bool {
		if let feed = object as? Feed {
			return topLevelFeeds.contains(feed)
		}
		if let folder = object as? Folder {
			return folders?.contains(folder) ?? false
		}
		return false
	}

	func flattenedFeeds() -> Set<Feed> {
		var feeds = Set<Feed>()
		feeds.formUnion(topLevelFeeds)
		if let folders = folders {
			for folder in folders {
				feeds.formUnion(folder.flattenedFeeds())
			}
		}
		return feeds
	}

	func hasFeed(with feedID: String) -> Bool {
		return existingFeed(withFeedID: feedID) != nil
	}

	func hasFeed(withURL url: String) -> Bool {
		return existingFeed(withURL: url) != nil
	}

	func has(_ feed: Feed) -> Bool {
		return flattenedFeeds().contains(feed)
	}

	func existingFeed(withFeedID feedID: String) -> Feed? {
		for feed in flattenedFeeds() {
			if feed.feedID == feedID {
				return feed
			}
		}
		return nil
	}

	func existingFeed(withURL url: String) -> Feed? {
		for feed in flattenedFeeds() {
			if feed.url == url {
				return feed
			}
		}
		return nil
	}

	func existingFeed(withExternalID externalID: String) -> Feed? {
		for feed in flattenedFeeds() {
			if feed.externalID == externalID {
				return feed
			}
		}
		return nil
	}

	@MainActor func existingFolder(with name: String) -> Folder? {
		guard let folders = folders else {
			return nil
		}

		for folder in folders {
			if folder.name == name {
				return folder
			}
			if let subFolder = folder.existingFolder(with: name) {
				return subFolder
			}
		}
		return nil
	}

	func existingFolder(withID folderID: Int) -> Folder? {
		guard let folders = folders else {
			return nil
		}

		for folder in folders {
			if folder.folderID == folderID {
				return folder
			}
			if let subFolder = folder.existingFolder(withID: folderID) {
				return subFolder
			}
		}
		return nil
	}

	/// Path-based folder lookup: `path` is an ordered list of folder
	/// names, ancestor-first, ending with the folder being sought.
	/// Unlike `existingFolder(with:)`, this resolves a specific folder
	/// even when multiple folders share a name via different parents.
	func existingFolder(withPath path: [String]) -> Folder? {
		guard let first = path.first else {
			return nil
		}
		guard let folder = folders?.first(where: { $0.nameForDisplay == first }) else {
			return nil
		}
		let rest = Array(path.dropFirst())
		if rest.isEmpty {
			return folder
		}
		return folder.existingFolder(withPath: rest)
	}

	func addFolderToTree(_ folder: Folder) {
		addFolderToTree(folder, at: nil)
	}

	/// Find or create a direct child folder named `name`. Used by both
	/// `ensureFolder(withFolderNames:)` (Account) and OPML import
	/// (`Account.addOPMLItems`) to build/extend a folder chain one
	/// level at a time, on whichever `Container` (`Account` or
	/// `Folder`) the chain has reached so far.
	@discardableResult
	func ensureChildFolder(named name: String) -> Folder? {
		if name.isEmpty {
			return nil
		}
		if let existing = folders?.first(where: { $0.nameForDisplay == name }) {
			return existing
		}
		guard let account = self.account else {
			return nil
		}
		let folder = Folder(account: account, name: name)
		addFolderToTree(folder)
		return folder
	}

	func postChildrenDidChangeNotification() {
		NotificationCenter.default.post(name: .ChildrenDidChange, object: self)
	}
}
