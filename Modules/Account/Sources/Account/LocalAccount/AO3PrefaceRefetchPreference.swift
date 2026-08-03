//
//  AO3PrefaceRefetchPreference.swift
//  NetNewsWire
//
//  Nectar AO3 direct-reading support -- refetch-cadence setting.
//
//  Once a work's chapter count matches chapterCurrent, AO3ChapterFetcher.isStale
//  goes false permanently: nothing re-checks a "settled" work for new
//  comments/kudos/hits, or for formatting changes to an already-fetched
//  chapter. This preference adds a second, independent trigger alongside the
//  chapter-count check: refetch if the last successful preface fetch is older
//  than the chosen interval, regardless of chapter count.
//
//  Lives in the Account module (not the iOS app's AppDefaults) for the same
//  reason AmbrosiaTransferFormatPreference does -- AO3ChapterFetcher.isStale
//  is what actually needs to read it, and that shouldn't require depending on
//  the iOS app target. Uses the same app-group suite AppDefaults.store uses,
//  so the iOS-side picker (AO3AccountSettingsView) reads/writes the same key
//  through this type rather than a second UserDefaults suite that could
//  drift out of sync with it.
//
import Foundation

public enum AO3PrefaceRefetchInterval: String, Sendable, CaseIterable {
	case yearly
	case monthly
	case weekly
	case daily
	case always

	/// Seconds since the last successful preface fetch after which a
	/// "settled" (chapter-count-matching) article should still be refetched.
	/// `.always` returns 0 -- every fetchIfNeeded(for:) call for an AO3
	/// article is eligible, subject only to the attemptDates floor below,
	/// not to this interval.
	var timeInterval: TimeInterval {
		switch self {
		case .yearly:
			return 365 * 24 * 60 * 60
		case .monthly:
			return 30 * 24 * 60 * 60
		case .weekly:
			return 7 * 24 * 60 * 60
		case .daily:
			return 24 * 60 * 60
		case .always:
			return 0
		}
	}

	public var description: String {
		switch self {
		case .yearly:
			return NSLocalizedString("Yearly", comment: "AO3 preface refetch interval")
		case .monthly:
			return NSLocalizedString("Monthly", comment: "AO3 preface refetch interval")
		case .weekly:
			return NSLocalizedString("Weekly", comment: "AO3 preface refetch interval")
		case .daily:
			return NSLocalizedString("Daily", comment: "AO3 preface refetch interval")
		case .always:
			return NSLocalizedString("Every Time", comment: "AO3 preface refetch interval")
		}
	}
}

public enum AO3PrefaceRefetchPreference {

	private static let key = "ao3PrefaceRefetchInterval"

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

	/// Monthly by default -- frequent enough to pick up new comments/kudos/
	/// hits and any formatting fixes on a settled work without refetching
	/// every article on every app open.
	public static var current: AO3PrefaceRefetchInterval {
		get {
			guard let rawValue = store.string(forKey: key), let interval = AO3PrefaceRefetchInterval(rawValue: rawValue) else {
				return .monthly
			}
			return interval
		}
		set {
			store.set(newValue.rawValue, forKey: key)
		}
	}
}
