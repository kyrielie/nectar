//
//  ParsedSeriesEntry.swift
//  RSParser
//
//  Created for the Nectar fork.
//

import Foundation

/// One entry in a JSON Feed item's `_ambrosia.series` array. Mirrors
/// `JSONFeedSeriesEntry` in Ambrosia's `LocalFeedServer.swift`:
/// `{"name": String, "index": Int, "ao3_id": String?}`.
///
/// Inline series navigation (per-series previous/next): `previousWorkURL`/
/// `nextWorkURL` carry the AO3-absolute URL of the adjacent work in *this*
/// series membership specifically, not a single navigator-wide pair -- a
/// work in more than one series can have a different previous/next work per
/// series. Populated only by `AO3ChapterHTMLExtractor.seriesEntriesWithNavigation(fromDD:)`
/// (each span's own `<a class="previous">`/`<a class="next">`); always nil
/// from every other producer of a `ParsedSeriesEntry`
/// (`AO3SearchResultsExtractor.seriesEntries(fromLI:)`,
/// `AO3SummaryExtractor`, `JSONFeedParser.parseAmbrosiaSeries`), since none
/// of those sources carry that chrome at all.
public struct ParsedSeriesEntry: Hashable, Sendable {
	public let name: String
	public let index: Int
	public let ao3ID: String?
	public let previousWorkURL: String?
	public let nextWorkURL: String?

	public init(name: String, index: Int, ao3ID: String?, previousWorkURL: String? = nil, nextWorkURL: String? = nil) {
		self.name = name
		self.index = index
		self.ao3ID = ao3ID
		self.previousWorkURL = previousWorkURL
		self.nextWorkURL = nextWorkURL
	}
}
