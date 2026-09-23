//
//  AmbrosiaFeedIdentity.swift
//  NetNewsWire
//
//  Phase 2 (fork addition): a stable identity for an Ambrosia feed URL,
//  independent of host/port. Ambrosia's collection/search/random-daily
//  routes are the only feeds Nectar ever subscribes to, and their path
//  component (not the host) is what identifies "the same Ambrosia
//  collection" across a LAN IP change. Used to detect re-pairs at OPML
//  import time so we can merge into the existing feed instead of creating
//  a duplicate sidebar entry.
//

import Foundation

enum AmbrosiaFeedIdentity {

	/// Returns a stable key identifying the Ambrosia collection/route that
	/// `urlString` points at, or nil if it isn't a recognized Ambrosia JSON
	/// Feed route. Two URLs with different hosts but the same collection ID
	/// (or the same search/random-daily route) return the same key.
	static func collectionKey(for urlString: String) -> String? {
		guard let url = URL(string: urlString), url.pathExtension.lowercased() == "json" else {
			return nil
		}

		let path = url.path
		if path.hasSuffix("/feed/search.json") {
			return "ambrosia-search"
		}
		if path.hasSuffix("/feed/random-daily.json") {
			return "ambrosia-random-daily"
		}
		if path.contains("/feed/collection/"), path.hasSuffix(".json") {
			let lastComponent = (path as NSString).lastPathComponent
			let collectionID = (lastComponent as NSString).deletingPathExtension
			guard !collectionID.isEmpty else {
				return nil
			}
			return "ambrosia-collection-\(collectionID)"
		}

		return nil
	}
}
