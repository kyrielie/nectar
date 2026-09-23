//
//  AO3KudosNotification.swift
//  Account
//
//  Nectar AO3 direct-reading support, Task 6 ("kudos-on-like"). Mirrors
//  AO3ChapterNotification's shape.
//
//  Only .ao3KudosDidSucceed is posted so far -- plumbing for a future
//  haptic/UI hookup (a later checkpoint). No corresponding "did fail"
//  notification yet: a failed kudos attempt has nowhere in the UI to
//  surface right now, and AO3KudosManager's ActivityLog entry already
//  records it for anyone checking the Activity Log.
//
import Foundation

public extension Notification.Name {

	/// Posted when AO3KudosManager successfully leaves (or confirms
	/// already-left) kudos for a work. Posted on the main thread.
	nonisolated static let ao3KudosDidSucceed = Notification.Name("ao3KudosDidSucceed")
}

public struct AO3KudosUserInfoKey {

	public static let articleID = "articleID" // String value
	public static let workID = "workID" // String value
}
