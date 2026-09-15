//
//  ArticleSorter.swift
//  NetNewsWire
//
//  Created by Phil Viso on 9/8/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import Foundation
import Articles

@MainActor struct ArticleSorter {

	/// Which field the timeline is sorted by. `.date` is the only field NNW
	/// supported before this; `.wordCount`, `.title`, and `.author` are the
	/// Ambrosia-fork additions.
	enum SortField: Int, Sendable, CaseIterable {
		case date = 0
		case wordCount = 1
		case title = 2
		case author = 3
		case hitCount = 4
		case kudosCount = 5
		case commentCount = 6
		case bookmarkCount = 7
		case dateBookmarked = 8

		var displayName: String {
			switch self {
			case .date:
				NSLocalizedString("Date", comment: "Sort field")
			case .wordCount:
				NSLocalizedString("Word Count", comment: "Sort field")
			case .title:
				NSLocalizedString("Title", comment: "Sort field")
			case .author:
				NSLocalizedString("Author", comment: "Sort field")
			case .hitCount:
				NSLocalizedString("Hits", comment: "Sort field")
			case .kudosCount:
				NSLocalizedString("Kudos", comment: "Sort field")
			case .commentCount:
				NSLocalizedString("Comments", comment: "Sort field")
			case .bookmarkCount:
				NSLocalizedString("Bookmarks", comment: "Sort field")
			case .dateBookmarked:
				NSLocalizedString("Date Bookmarked", comment: "Sort field")
			}
		}

		/// Label for the row when sorted ascending, worded for what this field
		/// actually means (chronological order reads oddly as "A to Z," and an
		/// alphabetic field reads oddly as "Oldest to Newest").
		var ascendingLabel: String {
			switch self {
			case .date:
				NSLocalizedString("Oldest First", comment: "Ascending sort direction — date")
			case .wordCount:
				NSLocalizedString("Fewest Words First", comment: "Ascending sort direction — word count")
			case .title, .author:
				NSLocalizedString("A to Z", comment: "Ascending sort direction — alphabetic")
			case .hitCount, .kudosCount, .commentCount, .bookmarkCount:
				NSLocalizedString("Fewest First", comment: "Ascending sort direction — count")
			case .dateBookmarked:
				NSLocalizedString("Oldest First", comment: "Ascending sort direction — date")
			}
		}

		/// Label for the row when sorted descending. See `ascendingLabel`.
		var descendingLabel: String {
			switch self {
			case .date:
				NSLocalizedString("Newest First", comment: "Descending sort direction — date")
			case .wordCount:
				NSLocalizedString("Most Words First", comment: "Descending sort direction — word count")
			case .title, .author:
				NSLocalizedString("Z to A", comment: "Descending sort direction — alphabetic")
			case .hitCount, .kudosCount, .commentCount, .bookmarkCount:
				NSLocalizedString("Most First", comment: "Descending sort direction — count")
			case .dateBookmarked:
				NSLocalizedString("Newest First", comment: "Descending sort direction — date")
			}
		}
	}

	static func sortedByDate(articles: [Article], sortDirection: ComparisonResult, groupByFeed: Bool, feedNameFor: (Article) -> String = { $0.sortableFeedName }) -> [Article] {
		if groupByFeed {
			sortedByFeedName(articles: articles, sortDirection: sortDirection, feedNameFor: feedNameFor)
		} else {
			sortedByDate(articles: articles, sortDirection: sortDirection)
		}
	}

	/// Entry point for the non-date sort fields. Unlike `sortedByDate`,
	/// these don't support `groupByFeed` — grouping by feed only makes
	/// sense as a secondary key under a primary date sort, per the
	/// existing UI's "Group by Feed" toggle.
	static func sorted(articles: [Article], by field: SortField, sortDirection: ComparisonResult) -> [Article] {
		switch field {
		case .date:
			sortedByDate(articles: articles, sortDirection: sortDirection)
		case .wordCount:
			sortedByWordCount(articles: articles, sortDirection: sortDirection)
		case .title:
			sortedByTitle(articles: articles, sortDirection: sortDirection)
		case .author:
			sortedByAuthor(articles: articles, sortDirection: sortDirection)
		case .hitCount:
			sortedByCount(articles: articles, sortDirection: sortDirection, countFor: \.hitCount)
		case .kudosCount:
			sortedByCount(articles: articles, sortDirection: sortDirection, countFor: \.kudosCount)
		case .commentCount:
			sortedByCount(articles: articles, sortDirection: sortDirection, countFor: \.commentCount)
		case .bookmarkCount:
			sortedByCount(articles: articles, sortDirection: sortDirection, countFor: \.bookmarkCount)
		case .dateBookmarked:
			sortedByDateBookmarked(articles: articles, sortDirection: sortDirection)
		}
	}
}

// MARK: - Private

private extension ArticleSorter {

	static func sortedByFeedName(articles: [Article], sortDirection: ComparisonResult, feedNameFor: (Article) -> String) -> [Article] {
		// Group articles by feed ID so that two feeds with the same name remain in distinct groups.
		let groupedArticles = Dictionary(grouping: articles, by: \.feedID)
		let groupsWithNames = groupedArticles.map { (feedID: $0.key, name: feedNameFor($0.value[0]), articles: $0.value) }
		return groupsWithNames
			.sorted { lhs, rhs in
				switch lhs.name.localizedCaseInsensitiveCompare(rhs.name) {
				case .orderedAscending: true
				case .orderedDescending: false
				case .orderedSame: lhs.feedID < rhs.feedID
				}
			}
			.flatMap { sortedByDate(articles: $0.articles, sortDirection: sortDirection) }
	}

	static func sortedByDate(articles: [Article], sortDirection: ComparisonResult) -> [Article] {
		articles.sorted { article1, article2 in
			if article1.logicalDatePublished == article2.logicalDatePublished {
				article1.articleID < article2.articleID
			} else if sortDirection == .orderedDescending {
				article1.logicalDatePublished > article2.logicalDatePublished
			} else {
				article1.logicalDatePublished < article2.logicalDatePublished
			}
		}
	}

	// Missing word counts sort to the end regardless of direction — an
	// article NNW hasn't extracted `_ambrosia` metadata for yet shouldn't
	// jump to the front of an ascending sort just because `nil` reads as
	// "less than" every count.
	static func sortedByWordCount(articles: [Article], sortDirection: ComparisonResult) -> [Article] {
		articles.sorted { article1, article2 in
			switch (article1.wordCount, article2.wordCount) {
			case (nil, nil):
				article1.articleID < article2.articleID
			case (nil, _):
				false
			case (_, nil):
				true
			case let (count1?, count2?):
				if count1 == count2 {
					article1.articleID < article2.articleID
				} else if sortDirection == .orderedDescending {
					count1 > count2
				} else {
					count1 < count2
				}
			}
		}
	}

	// Missing counts sort to the end regardless of direction, same rationale
	// as sortedByWordCount above — non-AO3 articles have no hit/kudos/
	// comment/bookmark counts at all and shouldn't front-load an ascending
	// sort just because `nil` reads as "less than" every count.
	static func sortedByCount(articles: [Article], sortDirection: ComparisonResult, countFor: (Article) -> Int?) -> [Article] {
		articles.sorted { article1, article2 in
			switch (countFor(article1), countFor(article2)) {
			case (nil, nil):
				article1.articleID < article2.articleID
			case (nil, _):
				false
			case (_, nil):
				true
			case let (count1?, count2?):
				if count1 == count2 {
					article1.articleID < article2.articleID
				} else if sortDirection == .orderedDescending {
					count1 > count2
				} else {
					count1 < count2
				}
			}
		}
	}

	// Missing dateBookmarked (every non-bookmarks-sourced article, per the
	// extractor's own div.user-gating) sorts to the end regardless of
	// direction — same rationale/shape as sortedByCount above, just on
	// Date instead of Int.
	static func sortedByDateBookmarked(articles: [Article], sortDirection: ComparisonResult) -> [Article] {
		articles.sorted { article1, article2 in
			switch (article1.dateBookmarked, article2.dateBookmarked) {
			case (nil, nil):
				article1.articleID < article2.articleID
			case (nil, _):
				false
			case (_, nil):
				true
			case let (date1?, date2?):
				if date1 == date2 {
					article1.articleID < article2.articleID
				} else if sortDirection == .orderedDescending {
					date1 > date2
				} else {
					date1 < date2
				}
			}
		}
	}

	static func sortedByTitle(articles: [Article], sortDirection: ComparisonResult) -> [Article] {
		articles.sorted { article1, article2 in
			let title1 = article1.title ?? ""
			let title2 = article2.title ?? ""
			return switch title1.localizedCaseInsensitiveCompare(title2) {
			case .orderedSame:
				article1.articleID < article2.articleID
			case .orderedAscending:
				sortDirection == .orderedAscending
			case .orderedDescending:
				sortDirection == .orderedDescending
			}
		}
	}

	static func sortedByAuthor(articles: [Article], sortDirection: ComparisonResult) -> [Article] {
		articles.sorted { article1, article2 in
			let name1 = article1.sortableAuthorName
			let name2 = article2.sortableAuthorName
			return switch name1.localizedCaseInsensitiveCompare(name2) {
			case .orderedSame:
				article1.articleID < article2.articleID
			case .orderedAscending:
				sortDirection == .orderedAscending
			case .orderedDescending:
				sortDirection == .orderedDescending
			}
		}
	}
}

// MARK: - Sorting

@MainActor extension Article {

	fileprivate var sortableFeedName: String {
		feed?.nameForDisplay ?? ""
	}

	// The lowest-sorting author name among an article's authors, or ""
	// when there are none. "Lowest-sorting" (rather than "first listed")
	// keeps the comparator well-defined without depending on Set's
	// unspecified iteration order.
	fileprivate var sortableAuthorName: String {
		guard let authors, !authors.isEmpty else {
			return ""
		}
		return authors.compactMap { $0.name }.min(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) ?? ""
	}
}
