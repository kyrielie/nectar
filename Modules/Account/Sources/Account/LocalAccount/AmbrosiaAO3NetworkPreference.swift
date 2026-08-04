//
//  AmbrosiaAO3NetworkPreference.swift
//  NetNewsWire
//
//  Nectar AO3 direct-reading support -- Task 8's local-only-reader toggles.
//
//  AO3ChapterFetcher.fetchIfNeeded(for:) gates purely on article.bookKey
//  having the "ao3-work:" prefix -- it doesn't check article.isAmbrosiaItem
//  anywhere, so an Ambrosia-sourced article is exactly as eligible for a
//  live AO3 fetch as a native AO3-RSS article today. These two flags are
//  the only way to keep Nectar off AO3 servers entirely for someone using
//  it purely as a local Ambrosia/Calibre archive reader. Native (non-
//  Ambrosia) AO3-RSS-sourced articles are unaffected by either flag -- they
//  keep today's always-on fetch behavior, since there's no other way for
//  them to get content at all.
//
//  Comment/kudos/bookmark/hit-count stats and chapter content come from the
//  same HTTP fetch (AO3ChapterHTMLExtractor reads both off one downloaded
//  page), not two separate requests -- these flags gate what's applied from
//  that one response, not a second request. The network call itself only
//  fires at all if at least one flag is enabled (see the pre-request guard
//  in AO3ChapterFetcher.fetchIfNeeded/checkForUpdates); it isn't a
//  post-fetch filter.
//
//  Lives in the Account module for the same reason
//  AO3PrefaceRefetchPreference does -- AO3ChapterFetcher is what actually
//  needs to read this, and that shouldn't require depending on the iOS app
//  target.
//
import Foundation

public enum AmbrosiaAO3NetworkPreference {

	private static let contentUpdatesKey = "ambrosiaAO3ContentUpdatesEnabled"
	private static let statsUpdatesKey = "ambrosiaAO3StatsUpdatesEnabled"

	// UserDefaults is internally thread-safe but isn't marked Sendable, so a
	// global `let` of it still trips the concurrency checker;
	// nonisolated(unsafe) reflects the actual (safe) runtime behavior here --
	// same rationale, and the same app-group-suite-with-.standard-fallback
	// lookup, as AO3PrefaceRefetchPreference.store in the same directory.
	// Duplicated rather than factored out: AO3PrefaceRefetchPreference's
	// store is private to that type, and the lookup is three lines: not
	// worth widening that type's API just to share it.
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

	/// "Pull chapter updates for library works." Gates whether the
	/// regression-guarded content write (AO3ChapterFetcher.download's
	/// success path) is ever applied for an Ambrosia-sourced article --
	/// also doubles as the auto-check-on-open switch for "Check for
	/// updates," one flag with two related jobs. Default false: don't turn
	/// on a new source of automatic AO3 requests for a local-archive-only
	/// reader without an explicit opt-in.
	public static var contentUpdatesEnabled: Bool {
		get { store.bool(forKey: contentUpdatesKey) }
		set { store.set(newValue, forKey: contentUpdatesKey) }
	}

	/// "Fetch AO3 stats (kudos/comments/hits) for library works." Gates
	/// whether the comment/kudos/bookmark/hit counts from the same response
	/// get persisted/displayed. Default false, same reasoning as
	/// contentUpdatesEnabled.
	public static var statsUpdatesEnabled: Bool {
		get { store.bool(forKey: statsUpdatesKey) }
		set { store.set(newValue, forKey: statsUpdatesKey) }
	}
}
