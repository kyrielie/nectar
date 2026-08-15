//
//  AO3PrefetchNewWorksPreference.swift
//  Account
//
//  Nectar AO3 direct-reading support -- opt-in "fetch new works
//  immediately" setting.
//
//  ao3-integration.md's "Fetch triggers, philosophy" section commits to
//  every AO3 request tracing back to something the user directly did --
//  opening an article, Check for updates, or a series nav link. That's
//  correct as a default, but it has a real content-loss consequence for
//  native AO3 tag/user RSS feeds: a work can be deleted, locked, or moved
//  any time between being listed in the feed and the person actually
//  opening it, and AO3ChapterFetcher.fetchIfNeeded only ever runs at
//  open time. Once that first attempt comes back .notFound on both
//  retries, ao3ConfirmedMissingAt is set and isStale stops trying
//  forever (AO3ChapterFetcher.swift) -- there is no second chance.
//
//  This preference is the explicit, opt-in exception: with it on,
//  LocalAccountRefresher hands newly-discovered AO3-work articles to
//  AO3PrefetchQueue at refresh time instead of waiting for the person to
//  open them. Off by default -- this is a new source of automatic AO3
//  traffic made without the person having opened anything, which is
//  exactly what the philosophy section otherwise rules out, so it needs
//  a deliberate opt-in rather than a silent default-on behavior change.
//
//  Lives in the Account module for the same reason
//  AO3PrefaceRefetchPreference/AmbrosiaAO3NetworkPreference do --
//  LocalAccountRefresher is what actually needs to read this, and that
//  shouldn't require depending on the iOS app target. Uses
//  NectarAppGroupUserDefaults.store, same suite those use, so the
//  Settings toggle (AO3AccountSettingsView) reads/writes this same key.
//
import Foundation

public enum AO3PrefetchNewWorksPreference {

	private static let key = "ao3PrefetchNewWorksEnabled"

	private static var store: UserDefaults { NectarAppGroupUserDefaults.store }

	/// Off by default -- see the file doc comment above.
	public static var isEnabled: Bool {
		get {
			store.bool(forKey: key)
		}
		set {
			store.set(newValue, forKey: key)
		}
	}
}
