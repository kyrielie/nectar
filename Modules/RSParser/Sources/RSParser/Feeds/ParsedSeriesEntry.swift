//
//  ParsedSeriesEntry.swift
//  RSParser
//
//  Created for the Ambrosia Reader fork.
//

import Foundation

/// One entry in a JSON Feed item's `_ambrosia.series` array. Mirrors
/// `JSONFeedSeriesEntry` in Ambrosia's `LocalFeedServer.swift`:
/// `{"name": String, "index": Int, "ao3_id": String?}`.
public struct ParsedSeriesEntry: Hashable, Sendable {
	public let name: String
	public let index: Int
	public let ao3ID: String?

	public init(name: String, index: Int, ao3ID: String?) {
		self.name = name
		self.index = index
		self.ao3ID = ao3ID
	}
}
