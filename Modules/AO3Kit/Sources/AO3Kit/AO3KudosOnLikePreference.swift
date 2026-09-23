//
//  AO3KudosOnLikePreference.swift
//  Account
//
//  Nectar AO3 direct-reading support, Task 6 ("kudos-on-like").
//
//  Default-off gate for AO3KudosManager. Landing ahead of the Settings UI
//  (a later checkpoint) so that AO3KudosManager's wiring into
//  AO3ChapterFetcher.download and SceneCoordinator's list-view love action
//  doesn't start firing live POSTs to AO3 the moment it lands -- every call
//  into AO3KudosManager checks this first. Uses
//  NectarAppGroupUserDefaults.store, same as AO3PrefaceRefetchPreference, for
//  the same reason: AO3KudosManager needs to read it from the Account module
//  without depending on the iOS app target, and the eventual Settings toggle
//  should read/write this same key rather than a second UserDefaults suite
//  that could drift out of sync with it.
//
import Foundation

public enum AO3KudosOnLikePreference {

	private static let key = "ao3KudosOnLikeEnabled"

	private static var store: UserDefaults { NectarAppGroupUserDefaults.store }

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
