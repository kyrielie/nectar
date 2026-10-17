//
//  ParsedCollectionEntry.swift
//  RSParser
//
//  One AO3 collection a work belongs to, read from the work page's
//  `<dd class="collections">` links.
//

import Foundation

/// `name` is the collection's display title (for example "Voiceteam 2025:
/// Dapper Dormice"). `slug` is the stable identifier AO3 builds the URL from
/// (`/collections/<slug>`); the display title can be edited by the
/// collection's moderators, the slug is what links and lookups should key on.
/// `slug` is nil only if the link's `href` did not have the expected
/// `/collections/<slug>` shape.
///
/// Populated only by `AO3ChapterHTMLExtractor` (work page). Listing rows,
/// RSS/Atom and Ambrosia feeds carry no collection data.
public struct ParsedCollectionEntry: Hashable, Sendable {
	public let name: String
	public let slug: String?

	public init(name: String, slug: String?) {
		self.name = name
		self.slug = slug
	}
}
