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
}

public struct AO3ChapterFetchUserInfoKey {

	public static let articleID = "articleID" // String value
}
