//
//  AmbrosiaTransferFormatPreference.swift
//  NetNewsWire
//
//  Nectar Implementation Plan, Phase 2, section 2f "Settings toggle."
//
//  A single preference, applied uniformly to every Ambrosia-paired feed --
//  no per-feed override, no automatic size-based switching, per the plan.
//  Lives in the Account module (rather than the iOS app's AppDefaults) so
//  LocalAccountRefresher.url(for:) -- which is what actually needs to read
//  it on every refresh -- doesn't have to depend on the iOS app target. Uses
//  the same app-group suite AppDefaults.store uses, so the iOS-side "Ambrosia
//  transfer format: JSON / SQLite" UI (near existing Ambrosia-pairing UI, per
//  the plan) can read/write the same key through this type rather than a
//  second UserDefaults suite that could drift out of sync with it.
//
import Foundation

public enum AmbrosiaTransferFormat: String, Sendable {
	case json
	case sqlite
}

public enum AmbrosiaTransferFormatPreference {

	private static let key = "ambrosiaTransferFormat"

	private static let store: UserDefaults = {
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

	public static var current: AmbrosiaTransferFormat {
		get {
			guard let rawValue = store.string(forKey: key), let format = AmbrosiaTransferFormat(rawValue: rawValue) else {
				return .json
			}
			return format
		}
		set {
			store.set(newValue.rawValue, forKey: key)
		}
	}
}
