//
//  AO3IgnoreList.swift
//  AO3Kit
//
//  Nectar AO3 direct-reading support, Task 7 ("Ignore lists (by work /
//  by author)").
//
//  Lives in AO3Kit, not RSParser: RSParser can't depend on AO3Kit (the
//  dependency points the other way), so RSParser reaches this indirectly
//  through the AO3FeedExtending/AO3FeedExtensionPoint seam instead --
//  RSSParser/AtomParser call AO3FeedExtensionPoint.provider?.shouldExclude(_:),
//  and AO3FeedExtension (this module's conformer, registered as that
//  provider) forwards to shouldExclude(_:) below. Native AO3 tag/user
//  RSS/Atom reaches this that way; Task 9's search extractor
//  (AO3SearchResultsExtractor, same module) calls shouldExclude(_:)
//  directly.
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
//  Stored in NectarAppGroupUserDefaults.store, the same app-group suite
//  AO3PrefaceRefetchPreference and AO3KudosOnLikePreference use.
//
//  Labels: each rule may carry a display label (a work title, an author
//  name) kept in two separate dictionaries under their own keys, so the
//  original id/url keys and their stored shape are unchanged and rules
//  made before labels existed keep working. A rule without a label
//  displays as its id or URL (`workDisplayName(id:)`,
//  `authorDisplayName(url:)`). Labels never affect matching.
//
import Foundation
import RSParser

public enum AO3IgnoreList {

	private static let workIDsKey = "ao3IgnoredWorkIDs"
	private static let authorURLsKey = "ao3IgnoredAuthorURLs"
	private static let workLabelsKey = "ao3IgnoredWorkLabels"
	private static let authorLabelsKey = "ao3IgnoredAuthorLabels"

	private static var store: UserDefaults { NectarAppGroupUserDefaults.store }

	/// Bare AO3 work IDs (digits only, matching `ParsedItem.ao3WorkID`'s own
	/// shape -- see `AO3Link.workID(fromPermalink:)`), not
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

	/// Display labels for ignored works, keyed by work id. May hold fewer
	/// entries than `ignoredWorkIDs` (rules made without a label).
	public static var ignoredWorkLabels: [String: String] {
		get { store.dictionary(forKey: workLabelsKey) as? [String: String] ?? [:] }
		set { store.set(newValue, forKey: workLabelsKey) }
	}

	/// Display labels for ignored authors, keyed by author URL.
	public static var ignoredAuthorLabels: [String: String] {
		get { store.dictionary(forKey: authorLabelsKey) as? [String: String] ?? [:] }
		set { store.set(newValue, forKey: authorLabelsKey) }
	}

	/// Adds the work to the ignore list. A non-empty `label` is stored for
	/// display; calling again without one keeps any label already stored.
	public static func ignoreWork(id: String, label: String? = nil) {
		var ids = ignoredWorkIDs
		ids.insert(id)
		ignoredWorkIDs = ids
		if let label = trimmedLabel(label) {
			var labels = ignoredWorkLabels
			labels[id] = label
			ignoredWorkLabels = labels
		}
	}

	/// Removes the work and its label.
	public static func unignoreWork(id: String) {
		var ids = ignoredWorkIDs
		ids.remove(id)
		ignoredWorkIDs = ids
		var labels = ignoredWorkLabels
		if labels.removeValue(forKey: id) != nil {
			ignoredWorkLabels = labels
		}
	}

	/// Adds the author to the ignore list. A non-empty `label` is stored for
	/// display; calling again without one keeps any label already stored.
	public static func ignoreAuthor(url: String, label: String? = nil) {
		var urls = ignoredAuthorURLs
		urls.insert(url)
		ignoredAuthorURLs = urls
		if let label = trimmedLabel(label) {
			var labels = ignoredAuthorLabels
			labels[url] = label
			ignoredAuthorLabels = labels
		}
	}

	/// Removes the author and its label.
	public static func unignoreAuthor(url: String) {
		var urls = ignoredAuthorURLs
		urls.remove(url)
		ignoredAuthorURLs = urls
		var labels = ignoredAuthorLabels
		if labels.removeValue(forKey: url) != nil {
			ignoredAuthorLabels = labels
		}
	}

	/// What to show for an ignored work: its label, or the bare id for a
	/// rule made without one.
	public static func workDisplayName(id: String) -> String {
		ignoredWorkLabels[id] ?? id
	}

	/// What to show for an ignored author: its label, or the URL for a rule
	/// made without one.
	public static func authorDisplayName(url: String) -> String {
		ignoredAuthorLabels[url] ?? url
	}

	private static func trimmedLabel(_ label: String?) -> String? {
		guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
			return nil
		}
		return label
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
