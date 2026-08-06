//
//  AmbrosiaAO3NetworkPreference.swift
//  NetNewsWire
//
//  Nectar AO3 direct-reading support -- Task 8's local-only-reader toggle.
//
//  AO3ChapterFetcher.fetchIfNeeded(for:) gates purely on article.bookKey
//  having the "ao3-work:" prefix -- it doesn't check article.isAmbrosiaItem
//  anywhere, so an Ambrosia-sourced article is exactly as eligible for a
//  live AO3 fetch as a native AO3-RSS article today. This flag is the only
//  way to keep Nectar off AO3 servers entirely for someone using it purely
//  as a local Ambrosia/Calibre archive reader. Native (non-Ambrosia)
//  AO3-RSS-sourced articles are unaffected by this flag -- they keep
//  today's always-on fetch behavior, since there's no other way for them
//  to get content at all.
//
//  Formerly two independent flags (contentUpdatesEnabled / statsUpdatesEnabled).
//  Collapsed to one: comment/kudos/bookmark/hit-count stats and chapter
//  content come off the same HTTP fetch (AO3ChapterHTMLExtractor reads
//  both off one downloaded page), so splitting "fetch the numbers" from
//  "fetch the text" never saved a request -- it only decided what got
//  written from a request that had already happened either way. The
//  content side of that split existed to let someone freeze their
//  archived text on purpose while keeping stats live; the content-write
//  path is still protected against genuinely bad fetches by
//  AO3RegressionThreshold (chapter count going down, or word count
//  dropping both 10%+ and 300+ words), same as before -- that guard was
//  never conditional on this flag and still isn't.
//
//  Lives in the Account module for the same reason
//  AO3PrefaceRefetchPreference does -- AO3ChapterFetcher is what actually
//  needs to read this, and that shouldn't require depending on the iOS app
//  target.
//
import Foundation

public enum AmbrosiaAO3NetworkPreference {

	// Deliberately still the old "stats" key name, not renamed to match
	// the new property -- this is what makes an existing "stats only"
	// user's choice carry over as "on" with no migration code needed.
	private static let updatesKey = "ambrosiaAO3StatsUpdatesEnabled"

	// UserDefaults is internally thread-safe but isn't marked Sendable, so a
	// global `let` of it still trips the concurrency checker;
	// nonisolated(unsafe) reflects the actual (safe) runtime behavior here --
	// same rationale, and the same app-group-suite-with-.standard-fallback
	// lookup, as AO3PrefaceRefetchPreference.store in the same directory.
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

	/// "Fetch AO3 updates for library works." Gates whether any live AO3
	/// fetch happens at all for an Ambrosia-sourced article -- content and
	/// stats are always applied together from that one fetch when this is
	/// on (content still subject to the regression guard). Also doubles
	/// as the auto-check-on-open switch for "Check for updates," one flag
	/// with two related jobs, same as before. Default false: don't turn
	/// on a new source of automatic AO3 requests for a local-archive-only
	/// reader without an explicit opt-in.
	public static var updatesEnabled: Bool {
		get { store.bool(forKey: updatesKey) }
		set { store.set(newValue, forKey: updatesKey) }
	}
}
