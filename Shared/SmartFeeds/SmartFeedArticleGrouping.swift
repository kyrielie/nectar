//
//  SmartFeedArticleGrouping.swift
//  NetNewsWire
//
//  Nectar fork addition: smart feeds (Today/Unread/Starred/Loved/Read/Search)
//  pull articles from every feed at once, so the same book can legitimately
//  appear more than once -- e.g. a fic in both a fandom collection feed and
//  the search feed. Article.bookKey (see ParsedItem.bookKey) already gives us
//  a stable cross-feed identity for "the same book" (anthology/series id,
//  then AO3 work id, then a bare uniqueID fallback); this collapses a smart
//  feed's raw article set down to one row per bookKey.
//

import Articles

enum SmartFeedArticleGrouping {

	/// Collapses `articles` by `bookKey`. Returns the deduplicated set (one
	/// representative `Article` per `bookKey`) plus a lookup of every feedID
	/// each book appeared in before collapsing, so callers can build a
	/// combined "In: Fandom A, Search Results" label instead of showing just
	/// the representative's own feed name.
	///
	/// Representative selection: unread wins over read, so an unread copy of
	/// a book in one feed isn't hidden behind an already-read copy of the
	/// same book in another feed; ties broken by most recently published.
	static func deduplicated(_ articles: Set<Article>) -> (articles: Set<Article>, feedIDsByBookKey: [String: Set<String>]) {
		guard !articles.isEmpty else {
			return (articles, [:])
		}

		var byBookKey = [String: [Article]]()
		for article in articles {
			byBookKey[article.bookKey, default: []].append(article)
		}

		var representatives = Set<Article>()
		var feedIDsByBookKey = [String: Set<String>]()
		representatives.reserveCapacity(byBookKey.count)
		feedIDsByBookKey.reserveCapacity(byBookKey.count)

		for (bookKey, group) in byBookKey {
			feedIDsByBookKey[bookKey] = Set(group.map { $0.feedID })

			guard let first = group.first else { continue }
			guard group.count > 1 else {
				representatives.insert(first)
				continue
			}

			let representative = group.sorted { lhs, rhs in
				if lhs.status.read != rhs.status.read {
					return !lhs.status.read // unread sorts first
				}
				return lhs.logicalDatePublished > rhs.logicalDatePublished
			}.first ?? first
			representatives.insert(representative)
		}

		return (representatives, feedIDsByBookKey)
	}
}

/// Tracks the most recent bookKey -> feedIDs grouping for a smart feed, so
/// the timeline can render a combined feed name for rows that came from more
/// than one feed. Owned by each smart-feed type (`SmartFeed`, `UnreadFeed`)
/// and refreshed every time articles are (re)fetched.
@MainActor final class SmartFeedBookKeyIndex {

	private(set) var feedIDsByBookKey = [String: Set<String>]()

	func update(_ feedIDsByBookKey: [String: Set<String>]) {
		self.feedIDsByBookKey = feedIDsByBookKey
	}

	/// The set of feedIDs a given bookKey appeared in as of the last fetch,
	/// or nil if that bookKey wasn't part of it (or nothing's been fetched
	/// yet). A single-element set means "not actually shared" -- callers
	/// should treat that the same as no combined name needed.
	func feedIDs(forBookKey bookKey: String) -> Set<String>? {
		feedIDsByBookKey[bookKey]
	}
}

/// Conformed to by smart-feed types that expose a `SmartFeedBookKeyIndex`, so
/// the timeline can look up combined feed membership without caring whether
/// it's looking at a `SmartFeed` or `UnreadFeed` instance.
@MainActor protocol SmartFeedArticleGroupProviding: AnyObject {
	var bookKeyIndex: SmartFeedBookKeyIndex { get }
}
