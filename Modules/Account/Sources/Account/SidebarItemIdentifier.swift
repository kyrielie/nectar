//
//  ArticleFetcherType.swift
//  Account
//
//  Created by Maurice Parker on 11/13/19.
//  Copyright © 2019 Ranchero Software, LLC. All rights reserved.
//

import Foundation

@MainActor public protocol SidebarItemIdentifiable {
	var sidebarItemID: SidebarItemIdentifier? { get }
}

public enum SidebarItemIdentifier: CustomStringConvertible, Hashable, Equatable, Sendable {
	case smartFeed(String) // String is a unique identifier
	case feed(String, String) // accountID, feedID
	case folder(String, [String]) // accountID, path (ancestor names, immediate folder last)

	private struct TypeName {
		static let smartFeed = "smartFeed"
		static let script = "script"
		static let feed = "feed"
		static let folder = "folder"
	}

	private struct Key {
		static let typeName = "type"
		static let id = "id"
		static let accountID = "accountID"
		static let feedID = "feedID"
		static let oldFeedIDKey = "webFeedID"
		/// Replaces the old `folderName` key. Renamed (rather than
		/// reused) so old-format entries -- which have no `folderPath`
		/// key -- fail `init?(userInfo:)` cleanly instead of being
		/// misread as a single-segment path.
		static let folderPath = "folderPath"
	}

	/// `userInfo` is `[String: String]`, so a folder's path array is
	/// encoded as a single string joined by this separator rather than
	/// stored as a nested array. See `ContainerIdentifier`'s matching
	/// `pathSeparator` for the same reasoning.
	private static let pathSeparator = "\u{1}"

	private var typeName: String {
		switch self {
		case .smartFeed:
			return TypeName.smartFeed
		case .feed:
			return TypeName.feed
		case .folder:
			return TypeName.folder
		}
	}

	public var description: String {
		switch self {
		case .smartFeed(let id):
			return "(typeName): \(id)"
		case .feed(let accountID, let feedID):
			return "(typeName): \(accountID)_\(feedID)"
		case .folder(let accountID, let path):
			return "(typeName): \(accountID)_\(path.joined(separator: "/"))"
		}
	}

	public var userInfo: [String: String] {
		var d = [Key.typeName: typeName]

		switch self {
		case .smartFeed(let id):
			d[Key.id] = id
		case .feed(let accountID, let feedID):
			d[Key.accountID] = accountID
			d[Key.feedID] = feedID
		case .folder(let accountID, let path):
			d[Key.accountID] = accountID
			d[Key.folderPath] = path.joined(separator: SidebarItemIdentifier.pathSeparator)
		}

		return d
	}

	public init?(userInfo: [String: String]) {
		guard let type = userInfo[Key.typeName] else {
			return nil
		}

		switch type {
		case TypeName.smartFeed:
			guard let id = userInfo[Key.id] else {
				return nil
			}
			self = .smartFeed(id)
		case TypeName.feed:
			guard let accountID = userInfo[Key.accountID], let feedID = userInfo[Key.feedID] ?? userInfo[Key.oldFeedIDKey] else {
				return nil
			}
			self = .feed(accountID, feedID)
		case TypeName.folder:
			guard let accountID = userInfo[Key.accountID], let folderPath = userInfo[Key.folderPath] else {
				return nil
			}
			let path = folderPath.components(separatedBy: SidebarItemIdentifier.pathSeparator)
			guard !path.isEmpty else {
				return nil
			}
			self = .folder(accountID, path)
		default:
			assertionFailure("Expected valid SidebarItemIdentifier.userInfo but got \(userInfo)")
			return nil
		}
	}
}
