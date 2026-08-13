//
//  AmbrosiaTransferFormatPreference.swift
//  NetNewsWire
//
//  A single preference, applied uniformly to every Ambrosia-paired feed --
//  no per-feed override, no automatic size-based switching. Lives in the
//  Account module (rather than the iOS app's AppDefaults) so
//  LocalAccountRefresher.url(for:) -- which is what actually needs to read
//  it on every refresh -- doesn't have to depend on the iOS app target. Uses
//  NectarAppGroupUserDefaults.store (same app-group suite AppDefaults.store
//  uses), so the iOS-side "Ambrosia transfer format: JSON / SQLite" UI (near
//  the existing Ambrosia-pairing UI) can read/write the same key through
//  this type rather than a second UserDefaults suite that could drift out
//  of sync with it.
//
import Foundation

public enum AmbrosiaTransferFormat: String, Sendable {
	case json
	case sqlite
}

public enum AmbrosiaTransferFormatPreference {

	private static let key = "ambrosiaTransferFormat"

	private static var store: UserDefaults { NectarAppGroupUserDefaults.store }

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
