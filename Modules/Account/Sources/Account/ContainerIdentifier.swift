//
//  ContainerIdentifier.swift
//  Account
//
//  Created by Maurice Parker on 11/24/19.
//  Copyright © 2019 Ranchero Software, LLC. All rights reserved.
//

import Foundation

@MainActor public protocol ContainerIdentifiable {
	var containerID: ContainerIdentifier? { get }
}

public enum ContainerIdentifier: Hashable, Equatable, Sendable {
	case smartFeedController
	case account(String) // accountID
	case folder(String, [String]) // accountID, path (ancestor names, immediate folder last)

	/// `userInfo` (and the `Encodable`/`Decodable` conformances below)
	/// ultimately round-trip through storage that only holds `String`
	/// values (`UserDefaults`, via `[String: String]`/`[[String: String]]`
	/// casts elsewhere in the app) -- so a folder's path array is encoded
	/// as a single string, joined with `pathSeparator`, rather than
	/// stored as a nested array. The key is `folderPath` (not the old
	/// `folderName`) specifically so old-format entries -- which have no
	/// `folderPath` key at all -- fail to parse via the `!path.isEmpty`
	/// guard below instead of being misread, with no separate migration
	/// step required.
	private static let pathSeparator = "\u{1}"

	public var userInfo: [AnyHashable: AnyHashable] {
		switch self {
		case .smartFeedController:
			return [
				"type": "smartFeedController"
			]
		case .account(let accountID):
			return [
				"type": "account",
				"accountID": accountID
			]
		case .folder(let accountID, let path):
			return [
				"type": "folder",
				"accountID": accountID,
				"folderPath": path.joined(separator: ContainerIdentifier.pathSeparator)
			]
		}
	}

	public init?(userInfo: [AnyHashable: AnyHashable]) {
		guard let type = userInfo["type"] as? String else { return nil }

		switch type {
		case "smartFeedController":
			self = ContainerIdentifier.smartFeedController
		case "account":
			guard let accountID = userInfo["accountID"] as? String else { return nil }
			self = ContainerIdentifier.account(accountID)
		case "folder":
			guard let accountID = userInfo["accountID"] as? String,
				  let folderPath = userInfo["folderPath"] as? String else { return nil }
			let path = folderPath.components(separatedBy: ContainerIdentifier.pathSeparator)
			guard !path.isEmpty else { return nil }
			self = ContainerIdentifier.folder(accountID, path)
		default:
			return nil
		}
	}

}

extension ContainerIdentifier: Encodable {
	enum CodingKeys: CodingKey {
		case type
		case accountID
		case folderPath
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		switch self {
		case .smartFeedController:
			try container.encode("smartFeedController", forKey: .type)
		case .account(let accountID):
			try container.encode("account", forKey: .type)
			try container.encode(accountID, forKey: .accountID)
		case .folder(let accountID, let path):
			try container.encode("folder", forKey: .type)
			try container.encode(accountID, forKey: .accountID)
			try container.encode(path, forKey: .folderPath)
		}
	}
}

extension ContainerIdentifier: Decodable {

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let type =  try container.decode(String.self, forKey: .type)

		switch type {
		case "smartFeedController":
			self = .smartFeedController
		case "account":
			let accountID =  try container.decode(String.self, forKey: .accountID)
			self = .account(accountID)
		default:
			let accountID =  try container.decode(String.self, forKey: .accountID)
			let path =  try container.decode([String].self, forKey: .folderPath)
			self = .folder(accountID, path)
		}
	}
}
