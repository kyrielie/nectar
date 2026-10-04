//
//  AO3KudosNotification.swift
//  Account
//
//  Nectar AO3 direct-reading support, Task 6 ("kudos-on-like"). Mirrors
//  AO3ChapterNotification's shape.
//
//  Plumbing for a future haptic/UI hookup. .ao3KudosDidFail is posted on
//  every failed attempt, but nothing in the UI observes it yet (a failed
//  kudos has nowhere to surface right now); AO3KudosManager's ActivityLog
//  entry also records it.
//
import Foundation

public extension Notification.Name {

	/// Posted when AO3KudosManager successfully leaves (or confirms
	/// already-left) kudos for a work. Posted on the main thread.
	nonisolated static let ao3KudosDidSucceed = Notification.Name("ao3KudosDidSucceed")

	/// Posted when an AO3KudosManager attempt fails: an authorization
	/// error, an invalid work, a rate limit, or any other failure.
	/// userInfo carries the same article and work keys as the success
	/// notification. Posted on the main thread.
	nonisolated static let ao3KudosDidFail = Notification.Name("ao3KudosDidFail")
}

public struct AO3KudosUserInfoKey {

	public static let articleID = "articleID" // String value
	public static let workID = "workID" // String value
}
