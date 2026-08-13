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
}
