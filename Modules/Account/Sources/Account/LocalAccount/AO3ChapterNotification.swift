//
//  AO3ChapterNotification.swift
//  Account
//
//  Created for the Nectar fork's AO3 direct-reading support, Workstream 2.
//

import Foundation

public extension Notification.Name {

	/// Posted when AO3ChapterFetcher successfully persists newly fetched
	/// chapter content for an article. Posted on the main thread. Mirrors
	/// HTMLMetadata's `.htmlMetadataAvailable` notification pattern.
	nonisolated static let ao3ChapterFetchDidComplete = Notification.Name("ao3ChapterFetchDidComplete")

	/// Posted when a chapter fetch for an article ends without persisting
	/// new content -- any of the `AO3ChapterExtractionOutcome` failure
	/// cases, a bad HTTP response, or a pre-response network error.
	/// `AO3ChapterFetchUserInfoKey.message` carries a human-readable reason
	/// (also retrievable afterward via
	/// `AO3ChapterFetcher.lastFetchFailureMessage(forArticleID:)`), so a
	/// view showing the article can explain why full text isn't available
	/// instead of silently sitting on the feed-derived blurb forever.
	/// Posted on the main thread.
	nonisolated static let ao3ChapterFetchDidFail = Notification.Name("ao3ChapterFetchDidFail")
}

public struct AO3ChapterFetchUserInfoKey {

	public static let articleID = "articleID" // String value
	public static let message = "message" // String value, .ao3ChapterFetchDidFail only
}
