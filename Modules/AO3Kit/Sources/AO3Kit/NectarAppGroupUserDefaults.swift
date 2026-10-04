//
//  NectarAppGroupUserDefaults.swift
//  Account
//
//  Shared app-group UserDefaults lookup for the AO3/Ambrosia preference
//  types in this directory (AO3PrefaceRefetchPreference,
//  AO3KudosOnLikePreference, AO3PrefetchNewWorksPreference,
//  AmbrosiaAO3NetworkPreference) and AO3IgnoreList. Extracted from
//  byte-identical copies -- there's no cross-module layering reason for
//  these to be separate: every type that uses it lives in this module, so
//  sharing one lookup here adds no new coupling. Also read by Account's
//  Ambrosia transfer types.
//
import Foundation

public enum NectarAppGroupUserDefaults {

	// UserDefaults is internally thread-safe but isn't marked Sendable, so a
	// global `let` of it still trips the concurrency checker; nonisolated(unsafe)
	// reflects the actual (safe) runtime behavior here.
	public nonisolated(unsafe) static let store: UserDefaults = {
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
}
