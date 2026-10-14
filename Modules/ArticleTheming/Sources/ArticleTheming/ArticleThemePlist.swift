//
//  ArticleThemePlist.swift
//  NetNewsWire
//
//  Created by Stuart Breckenridge on 19/09/2021.
//  Copyright © 2021 Ranchero Software. All rights reserved.
//

import Foundation

public struct ArticleThemePlist: Codable, Equatable, Sendable {
	public let name: String
	public let themeIdentifier: String
	public let creatorHomePage: String
	public let creatorName: String
	public let version: Int

	/// Optional. Purely presentational grouping for the theme gallery -- e.g. "Dracula"
	/// or "Rosé Pine" -- shared across sibling bundles that are the same design family
	/// with different accents/palettes. Does not affect storage, selection, deletion,
	/// or import: each variant is still its own complete .nnwtheme bundle with its own
	/// identity. Absent (nil) for the large majority of themes, which aren't part of a
	/// family. See docs/nnwtheme-format.md's "Theme families" section.
	public let family: String?

	/// Optional. This bundle's variant label within `family` (e.g. "Purple", "Moon").
	/// Meaningless without `family` also being set.
	public let familyVariant: String?

	enum CodingKeys: String, CodingKey {
		case name = "Name"
		case themeIdentifier = "ThemeIdentifier"
		case creatorHomePage = "CreatorHomePage"
		case creatorName = "CreatorName"
		case version = "Version"
		case family = "Family"
		case familyVariant = "FamilyVariant"
	}

	public init(name: String, themeIdentifier: String, creatorHomePage: String, creatorName: String, version: Int, family: String?, familyVariant: String?) {
		self.name = name
		self.themeIdentifier = themeIdentifier
		self.creatorHomePage = creatorHomePage
		self.creatorName = creatorName
		self.version = version
		self.family = family
		self.familyVariant = familyVariant
	}

	/// Lenient on purpose. Upstream NetNewsWire's synthesized decoder throws when any of the
	/// five keys is missing or has the wrong type, which makes a theme with a typo in its
	/// plist impossible to load. Here every key is optional: a missing or mistyped string is
	/// "", a missing or unreadable `Version` is 0, and `Version` also accepts a numeric
	/// string or a real number. Every upstream-valid plist decodes to the same values as
	/// before. Callers treat "" as unknown (see `ArticleTheme.creatorName`).
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.name = container.lenientString(.name)
		self.themeIdentifier = container.lenientString(.themeIdentifier)
		self.creatorHomePage = container.lenientString(.creatorHomePage)
		self.creatorName = container.lenientString(.creatorName)
		self.version = container.lenientVersion(.version)
		let family = container.lenientString(.family)
		let familyVariant = container.lenientString(.familyVariant)
		self.family = family.isEmpty ? nil : family
		self.familyVariant = familyVariant.isEmpty ? nil : familyVariant
	}

	/// Decodes an `Info.plist`, or returns nil when the data is not a property list
	/// dictionary at all. Never throws; callers fall back to the folder name.
	public static func lenient(from data: Data) -> ArticleThemePlist? {
		try? PropertyListDecoder().decode(ArticleThemePlist.self, from: data)
	}
}

private extension KeyedDecodingContainer where Key == ArticleThemePlist.CodingKeys {

	func lenientString(_ key: Key) -> String {
		if let string = try? decodeIfPresent(String.self, forKey: key) {
			return string.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		if let int = try? decodeIfPresent(Int.self, forKey: key) {
			return String(int)
		}
		return ""
	}

	func lenientVersion(_ key: Key) -> Int {
		if let int = try? decodeIfPresent(Int.self, forKey: key) {
			return int
		}
		if let double = try? decodeIfPresent(Double.self, forKey: key), double.isFinite, abs(double) < Double(Int.max) {
			return Int(double)
		}
		if let string = try? decodeIfPresent(String.self, forKey: key) {
			return Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
		}
		return 0
	}
}
