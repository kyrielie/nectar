//
//  AO3LinkListImporter.swift
//  AO3Kit
//
//  Nectar AO3 direct-reading support -- pasted-link-list import (one-time,
//  no refreshable feed; Task 3).
//

import Foundation
import RSParser

/// A single work recovered from a pasted blob of text: the permalink AO3
/// host it was found under, and the work id extracted from it.
public struct AO3ImportedLink: Hashable, Sendable {
	public let permalink: String
	public let ao3WorkID: String

	public init(permalink: String, ao3WorkID: String) {
		self.permalink = permalink
		self.ao3WorkID = ao3WorkID
	}
}

/// Scans pasted free text for AO3 work links, extracts a work id from each,
/// and dedupes by that id. No network access, no title/author inference from
/// surrounding text -- see Task 3's own note on why that's explicitly not
/// attempted. `NSDataDetector` does the URL-shaped-substring scanning;
/// everything past that is host-allowlist + work-id extraction.
public enum AO3LinkListImporter {

	/// Extracts every recognizable, deduped AO3 work link from `text`.
	/// Order is stable (first occurrence wins on a duplicate work id) so a
	/// re-paste of overlapping text doesn't reorder an existing import.
	public static func importedLinks(fromPastedText text: String) -> [AO3ImportedLink] {
		guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
			return []
		}

		var seenWorkIDs = Set<String>()
		var results: [AO3ImportedLink] = []

		let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
		for match in matches {
			guard let url = match.url else {
				continue
			}
			guard let workID = AO3Link.workID(from: url) else {
				continue
			}
			guard seenWorkIDs.insert(workID).inserted else {
				continue
			}
			results.append(AO3ImportedLink(permalink: url.absoluteString, ao3WorkID: workID))
		}

		return results
	}
}
