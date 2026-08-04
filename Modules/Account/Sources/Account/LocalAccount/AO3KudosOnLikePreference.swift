//
//  AO3KudosOnLikePreference.swift
//  Account
//
//  Nectar AO3 direct-reading support, Task 6 ("kudos-on-like") -- see
//  nectar-ao3-features-plan-FINAL.md.
//
//  Default-off gate for AO3KudosManager. Landing ahead of the Settings UI
//  (a later checkpoint) so that AO3KudosManager's wiring into
//  AO3ChapterFetcher.download and SceneCoordinator's list-view love action
//  doesn't start firing live POSTs to AO3 the moment it lands -- every call
//  into AO3KudosManager checks this first. Same app-group-suite-backed
//  UserDefaults shape as AO3PrefaceRefetchPreference, for the same reason:
//  AO3KudosManager needs to read it from the Account module without
//  depending on the iOS app target, and the eventual Settings toggle should
//  read/write this same key rather than a second UserDefaults suite that
//  could drift out of sync with it.
//
import Foundation

public enum AO3KudosOnLikePreference {

	private static let key = "ao3KudosOnLikeEnabled"

	// UserDefaults is internally thread-safe but isn't marked Sendable, so a
	// global `let` of it still trips the concurrency checker; nonisolated(unsafe)
	// reflects the actual (safe) runtime behavior here.
	private nonisolated(unsafe) static let store: UserDefaults = {
		if let appIdentifierPrefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
		   let bundleIdentifier = Bundle.main.bundleIdentifier,
		   let suiteDefaults = UserDefaults(suiteName: "\(appIdentifierPrefix)group.\(bundleIdentifier)") {
			return suiteDefaults
		}
		// Fall back to .standard rather than force-unwrapping: this type is
		// also reachable from non-app contexts (e.g. unit tests) where the
		// AppIdentifierPrefix Info.plist key isn't present.
		return .standard
	}()

	/// Off by default -- this POSTs to a third-party service on the user's
	/// behalf, so it needs an explicit opt-in once the Settings toggle
	/// exists, not a silent default-on behavior change for existing users.
	public static var isEnabled: Bool {
		get {
			store.bool(forKey: key)
		}
		set {
			store.set(newValue, forKey: key)
		}
	}
}
