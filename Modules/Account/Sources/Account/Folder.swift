//
//  Folder.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/1/17.
//  Copyright © 2017 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import Articles
import RSCore

public final class Folder: SidebarItem, Renamable, Container, Hashable {
	nonisolated public let accountID: String
	public weak var account: Account?

	public var defaultReadFilterType: ReadFilterType {
		return .read
	}

	public var containerID: ContainerIdentifier? {
		ContainerIdentifier.folder(accountID, pathNames)
	}

	public var sidebarItemID: SidebarItemIdentifier? {
		SidebarItemIdentifier.folder(accountID, pathNames)
	}

	/// This folder's container -- another `Folder` if nested, or the
	/// `Account` if this is a top-level folder. Set explicitly at every
	/// insertion call site (`Account`/`Folder`'s `addFolderToTree`,
	/// `ensureChildFolder`) rather than kept in sync automatically,
	/// since `OrderedSet` mutation happens through methods rather than
	/// a property `didSet` that could hook a single insertion point.
	public weak var parent: Container?

	/// Ancestor folder names from top level down to and including this
	/// folder. Does not include the account itself -- callers needing
	/// the account pair it with `accountID` separately (see
	/// `ContainerIdentifier.folder`/`SidebarItemIdentifier.folder`).
	public var pathNames: [String] {
		var names = [nameForDisplay]
		var current: Container? = parent
		while let folder = current as? Folder {
			names.insert(folder.nameForDisplay, at: 0)
			current = folder.parent
		}
		return names
	}

	public var topLevelFeeds: OrderedSet<Feed> = OrderedSet<Feed>()
	public var folders: OrderedSet<Folder>? = OrderedSet<Folder>()

	public var name: String? {
		didSet {
			postDisplayNameDidChangeNotification()
		}
	}

	static let untitledName = NSLocalizedString("Untitled ƒ", comment: "Folder name")
	nonisolated public let folderID: Int // not saved: per-run only
	public var externalID: String?
	static var incrementingID = 0

	// MARK: - DisplayNameProvider

	public var nameForDisplay: String {
		return name ?? Folder.untitledName
	}

	// MARK: - UnreadCountProvider

	public var unreadCount = 0 {
		didSet {
			if unreadCount != oldValue {
				postUnreadCountDidChangeNotification()
			}
		}
	}

	// MARK: - Renamable

	public func rename(to name: String, completion: @escaping (Result<Void, Error>) -> Void) {
		guard let account else {
			return
		}
		Task { @MainActor in
			do {
				try await account.renameFolder(self, to: name)
				completion(.success(()))
			} catch {
				completion(.failure(error))
			}
		}
	}

	// MARK: - Init

	init(account: Account, name: String?) {
		self.accountID = account.accountID
		self.account = account
		self.name = name

		let folderID = Folder.incrementingID
		Folder.incrementingID += 1
		self.folderID = folderID

		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(childrenDidChange(_:)), name: .ChildrenDidChange, object: self)
	}

	// MARK: - Notifications

	@objc func unreadCountDidChange(_ note: Notification) {
		if let object = note.object {
			if objectIsChild(object as AnyObject) {
				updateUnreadCount()
			}
		}
	}

	@objc func childrenDidChange(_ note: Notification) {
		updateUnreadCount()
	}

	// MARK: Container

	// flattenedFeeds() is not overridden here -- the Container protocol
	// extension's default (topLevelFeeds plus every subfolder's own
	// flattenedFeeds(), recursively) is exactly correct now that
	// folders can nest.

	public func objectIsChild(_ object: AnyObject) -> Bool {
		if let feed = object as? Feed {
			return topLevelFeeds.contains(feed)
		}
		if let folder = object as? Folder {
			return folders?.contains(folder) ?? false
		}
		return false
	}

	public func addFeedToTreeAtTopLevel(_ feed: Feed, at index: Int?) {
		if let index {
			topLevelFeeds.insert(feed, at: index)
		} else {
			topLevelFeeds.insert(feed)
		}
		postChildrenDidChangeNotification()
	}

	public func addFolderToTree(_ folder: Folder, at index: Int?) {
		if let index {
			folders!.insert(folder, at: index)
		} else {
			folders!.insert(folder)
		}
		folder.parent = self
		postChildrenDidChangeNotification()
		account?.structureDidChange()
	}

	public func removeFolderFromTree(_ folder: Folder) {
		folders?.remove(folder)
		postChildrenDidChangeNotification()
		account?.structureDidChange()
	}

	/// The deepest number of levels below this folder that its own
	/// subfolders extend -- 0 if this folder has no subfolders. Used by
	/// the depth-3 nesting cap when deciding whether moving this folder
	/// into some destination would push its deepest descendant past the
	/// cap.
	public var maxDescendantDepth: Int {
		guard let folders, !folders.isEmpty else {
			return 0
		}
		return 1 + folders.map { $0.maxDescendantDepth }.max()!
	}

	/// True if `other` is `self`, or is nested (at any depth) inside
	/// `self`. Used to guard against dropping a folder into itself or
	/// into one of its own descendants.
	public func isAncestor(of other: Folder) -> Bool {
		if other === self {
			return true
		}
		var current: Container? = other.parent
		while let folder = current as? Folder {
			if folder === self {
				return true
			}
			current = folder.parent
		}
		return false
	}

	/// Every container (this folder, plus any subfolder at any depth)
	/// that directly holds `feed` at its own top level. Mirrors
	/// `Account.existingContainers(withFeed:)`, which recurses into this
	/// method one level down.
	public func existingContainers(withFeed feed: Feed) -> [Container] {
		var containers = [Container]()
		if topLevelFeeds.contains(feed) {
			containers.append(self)
		}
		if let folders {
			for folder in folders {
				containers.append(contentsOf: folder.existingContainers(withFeed: feed))
			}
		}
		return containers
	}

	public func addFeeds(_ feeds: Set<Feed>) {
		guard !feeds.isEmpty else {
			return
		}
		topLevelFeeds.formUnion(feeds)
		postChildrenDidChangeNotification()
	}

	public func removeFeedFromTreeAtTopLevel(_ feed: Feed) {
		topLevelFeeds.remove(feed)
		postChildrenDidChangeNotification()
	}

	public func removeFeedsFromTreeAtTopLevel(_ feeds: Set<Feed>) {
		guard !feeds.isEmpty else {
			return
		}
		topLevelFeeds.subtract(feeds)
		postChildrenDidChangeNotification()
	}

	/// Replace the entire top-level feed set in one shot, posting a single change notification.
	public func replaceTopLevelFeeds(_ feeds: OrderedSet<Feed>) {
		topLevelFeeds = feeds
		postChildrenDidChangeNotification()
	}

	// MARK: - Hashable

	public func hash(into hasher: inout Hasher) {
		hasher.combine(folderID)
	}

	// MARK: - Equatable

	static public func ==(lhs: Folder, rhs: Folder) -> Bool {
		return lhs === rhs
	}
}

// MARK: - Private

private extension Folder {

	func updateUnreadCount() {
		var updatedUnreadCount = 0
		for feed in topLevelFeeds {
			updatedUnreadCount += feed.unreadCount
		}
		unreadCount = updatedUnreadCount
	}

	func childrenContain(_ feed: Feed) -> Bool {
		return topLevelFeeds.contains(feed)
	}
}

// MARK: - OPMLRepresentable

extension Folder: OPMLRepresentable {

	public func OPMLString(indentLevel: Int, allowCustomAttributes: Bool) -> String {

		let attrExternalID: String = {
			if allowCustomAttributes, let externalID = externalID {
				return " nnw_externalID=\"\(externalID.escapingSpecialXMLCharacters)\""
			} else {
				return ""
			}
		}()

		let escapedTitle = nameForDisplay.escapingSpecialXMLCharacters
		var s = "<outline text=\"\(escapedTitle)\" title=\"\(escapedTitle)\"\(attrExternalID)>\n"
		s = s.prepending(tabCount: indentLevel)

		var hasAtLeastOneChild = false

		for feed in topLevelFeeds {
			s += feed.OPMLString(indentLevel: indentLevel + 1, allowCustomAttributes: allowCustomAttributes)
			hasAtLeastOneChild = true
		}

		if let folders {
			for folder in folders {
				s += folder.OPMLString(indentLevel: indentLevel + 1, allowCustomAttributes: allowCustomAttributes)
				hasAtLeastOneChild = true
			}
		}

		if !hasAtLeastOneChild {
			s = "<outline text=\"\(escapedTitle)\" title=\"\(escapedTitle)\"\(attrExternalID)/>\n"
			s = s.prepending(tabCount: indentLevel)
			return s
		}

		s = s + String(repeating: "\t", count: indentLevel) + "</outline>\n"

		return s
	}
}


