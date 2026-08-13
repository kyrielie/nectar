//
//  AO3LinkListImporter.swift
//  Account
//
//  Nectar AO3 direct-reading support -- pasted-link-list import (one-time,
//  no refreshable feed; Task 3).
//

import Foundation
import RSParser

/// A single work recovered from a pasted blob of text: the permalink AO3
/// host it was found under, and the work id extracted from it.
struct AO3ImportedLink: Hashable, Sendable {
	let permalink: String
	let ao3WorkID: String
}

/// Scans pasted free text for AO3 work links, extracts a work id from each,
/// and dedupes by that id. No network access, no title/author inference from
/// surrounding text -- see Task 3's own note on why that's explicitly not
/// attempted. `NSDataDetector` does the URL-shaped-substring scanning;
/// everything past that is host-allowlist + work-id extraction.
public enum AO3LinkListImporter {

	/// Sourced directly from AO3's own work-skin proxy-detection script and
	/// cross-checked against AO3's public Accessing Fanworks FAQ. Exact-match
	/// only (no subdomain/suffix matching) -- this is a short, finite,
	/// AO3-controlled list, not an open-ended domain family the way Reddit's
	/// blog hosting is elsewhere in this codebase. Deliberately excludes
	/// mirror/proxy domains: AO3 itself disclaims responsibility for those.
	static let permittedHosts: Set<String> = [
		"104.153.64.122", "208.85.241.152", "208.85.241.157",
		"ao3.org", "www.ao3.org",
		"archiveofourown.com", "www.archiveofourown.com",
		"archiveofourown.net", "www.archiveofourown.net",
		"archiveofourown.org", "www.archiveofourown.org",
		"archiveofourown.gay",
		"download.archiveofourown.org", "insecure.archiveofourown.org", "secure.archiveofourown.org",
		"archive.transformativeworks.org"
	]

	/// Extracts every recognizable, deduped AO3 work link from `text`.
	/// Order is stable (first occurrence wins on a duplicate work id) so a
	/// re-paste of overlapping text doesn't reorder an existing import.
	static func importedLinks(fromPastedText text: String) -> [AO3ImportedLink] {
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
			guard isPermittedHost(url) else {
				continue
			}
			guard let workID = AO3SummaryExtractor.ao3WorkID(fromPermalink: url.absoluteString) else {
				continue
			}
			guard seenWorkIDs.insert(workID).inserted else {
				continue
			}
			results.append(AO3ImportedLink(permalink: url.absoluteString, ao3WorkID: workID))
		}

		return results
	}

	private static func isPermittedHost(_ url: URL) -> Bool {
		guard let host = url.host()?.lowercased() else {
			return false
		}
		return permittedHosts.contains(host)
	}

	/// Public wrapper around `isPermittedHost(_:)` -- same allowlist, same
	/// exact-match-only matching, exposed so other targets (the iOS app's
	/// `WebViewController`, routing AO3 links to the in-app authenticated
	/// browser vs. a regular in-app browser) can check against the same
	/// list instead of maintaining a second, possibly-drifting one. Kept
	/// as a single function rather than making `permittedHosts` itself
	/// public, to keep the actual list single-sourced here.
	public static func isAO3Host(_ url: URL) -> Bool {
		isPermittedHost(url)
	}
}
