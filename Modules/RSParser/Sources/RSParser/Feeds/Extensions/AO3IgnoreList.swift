//
//  AO3IgnoreList.swift
//  RSParser
//
//  Nectar AO3 direct-reading support, Task 7 ("Ignore lists (by work /
//  by author)").
//
//  Lives in RSParser, not Account, so every AO3-sourced ingestion path can
//  reach it without a dependency inversion: native AO3 tag/user RSS/Atom
//  (RSSItem.toParsedItem, wired below), and -- in their own later
//  checkpoints, not here -- Task 9's search extractor and Task 3's
//  pasted-link-list import, both of which already depend on RSParser for
//  AO3SummaryExtractor/AO3ChapterHTMLExtractor. Account depends on
//  RSParser, never the other way around, so RSParser is the only shared
//  home available.
//
//  Filtering happens at ParsedItem construction time -- see
//  shouldExclude(_:), called from RSSParser/AtomParser right after mapping
//  RSSItems to ParsedItems -- which is what makes this simultaneously solve
//  "don't show," "don't fetch," and "don't save": an excluded item never
//  becomes a persisted ParsedItem at all, so it never reaches
//  Account.updateAsync, AO3ChapterFetcher, or the timeline.
//
//  Retroactivity: never offered, no exceptions. Adding a rule here only ever affects items parsed after the
//  rule was added -- nothing here touches already-stored Articles, and
//  there's no cleanup path for existing matches by design.
//
//  Same app-group-suite-backed UserDefaults shape as
//  AO3PrefaceRefetchPreference (Account) and AO3KudosOnLikePreference
//  (Account) -- duplicated here rather than shared, since those live in
//  Account and this can't depend on Account.
//
import Foundation

public enum AO3IgnoreList {

	private static let workIDsKey = "ao3IgnoredWorkIDs"
	private static let authorURLsKey = "ao3IgnoredAuthorURLs"

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

	/// Bare AO3 work IDs (digits only, matching `ParsedItem.ao3WorkID`'s own
	/// shape -- see `AO3SummaryExtractor.ao3WorkID(fromPermalink:)`), not
	/// full permalinks. Callers that only have a permalink or partial URL
	/// (a future Settings UI, or an opened article's "block this work"
	/// context menu action) are expected to normalize through that same
	/// helper before calling `ignoreWork(id:)`, so a work is never stored
	/// under two different string shapes.
	public static var ignoredWorkIDs: Set<String> {
		get { Set(store.stringArray(forKey: workIDsKey) ?? []) }
		set { store.set(Array(newValue), forKey: workIDsKey) }
	}

	/// Full author URLs (e.g. `https://archiveofourown.org/users/someone/pseuds/someone`),
	/// matching `ParsedAuthor.url` as populated by whichever ingestion path
	/// found it -- see this file's header comment for which paths do and
	/// don't populate that field. Matched by exact string equality, not
	/// display name (names collide).
	public static var ignoredAuthorURLs: Set<String> {
		get { Set(store.stringArray(forKey: authorURLsKey) ?? []) }
		set { store.set(Array(newValue), forKey: authorURLsKey) }
	}

	public static func ignoreWork(id: String) {
		var ids = ignoredWorkIDs
		ids.insert(id)
		ignoredWorkIDs = ids
	}

	public static func unignoreWork(id: String) {
		var ids = ignoredWorkIDs
		ids.remove(id)
		ignoredWorkIDs = ids
	}

	public static func ignoreAuthor(url: String) {
		var urls = ignoredAuthorURLs
		urls.insert(url)
		ignoredAuthorURLs = urls
	}

	public static func unignoreAuthor(url: String) {
		var urls = ignoredAuthorURLs
		urls.remove(url)
		ignoredAuthorURLs = urls
	}

	/// Whether `item` should be dropped before it's ever turned into a
	/// persisted Article. By-work checks `item.ao3WorkID` directly; by-
	/// author checks every author in `item.authors` against
	/// `ignoredAuthorURLs` and excludes on any single match -- multi-author
	/// default is "any ignored co-author is sufficient to hide the work,"
	/// not "all must match". Both checks
	/// are simply skipped (never excluded) when the relevant field isn't
	/// populated -- an item with no `ao3WorkID` isn't an AO3 work to begin
	/// with, and an author with no `url` can't be matched by-author,
	/// reliably or otherwise.
	public static func shouldExclude(_ item: ParsedItem) -> Bool {
		if let workID = item.ao3WorkID, !workID.isEmpty, ignoredWorkIDs.contains(workID) {
			return true
		}

		guard let authors = item.authors, !authors.isEmpty else {
			return false
		}
		let ignoredURLs = ignoredAuthorURLs
		guard !ignoredURLs.isEmpty else {
			return false
		}
		return authors.contains { author in
			guard let url = author.url else { return false }
			return ignoredURLs.contains(url)
		}
	}
}
