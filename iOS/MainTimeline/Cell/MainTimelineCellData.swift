//
//  MainTimelineCellData.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/6/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import UIKit
import Articles
import Images

@MainActor struct MainTimelineCellData {

	private static let noText = NSLocalizedString("(No Text)", comment: "No Text")

	let accountID: String
	let articleID: String
	let title: String
	let attributedTitle: NSAttributedString
	let summary: String
	let dateString: String
	let feedName: String
	let byline: String
	let showFeedName: ShowFeedName
	let iconImage: IconImage? // feed icon, user avatar, or favicon
	let showIcon: Bool // Make space even when icon is nil
	let read: Bool
	let starred: Bool
	let loved: Bool
	let numberOfLines: Int
	let iconSize: IconSize
	let tagDisplayMode: TagDisplayMode

	/// Fraction (0...1) of the article read, or nil if never opened. The card hides its
	/// progress bar for nil, for 0 (never actually scrolled), and when `read` is true --
	/// showing "100%" on something already marked read is noise, not information.
	let readingProgress: Double?

	// MARK: - Ambrosia extension

	/// "" when the article has no word count (not yet extracted from
	/// `_ambrosia`, or the feed item never had one). Never a placeholder
	/// like "0" — the row must be able to tell "no data" apart from
	/// "confirmed zero," and an empty string renders as nothing rather
	/// than a wrong-looking zero.
	let wordCountString: String

	/// Comma-joined fandom list, truncated for row display. "" when absent.
	let fandomString: String

	/// nil when completion status is unknown (not "confirmed incomplete").
	let isComplete: Bool?

	/// nil when no rating was extracted. An empty array (rating extracted,
	/// explicitly zero warnings) is distinct from nil and both are valid —
	/// callers must render nil as "not available," never as "confirmed
	/// none," per the fork plan's correctness requirement for this field.
	let ratings: [String]?
	let warnings: [String]?

	/// Plain-text metadata line(s) to render, depending on `tagDisplayMode`.
	/// `.compact` yields at most one combined line (word count, completion,
	/// fandom, rating/warnings — e.g. "12,345 words · Complete · My Fandom ·
	/// Explicit"). `.expanded` yields one line per non-nil field. `.badges`
	/// yields a single word-count/completion line; fandom/rating/warnings
	/// render separately as pills, via `metadataBadges`, instead of here.
	///
	/// Empty lines are never included — an empty array collapses the row to
	/// zero height exactly like `title`/`summary` already do. Nil-vs-empty-
	/// array is respected for `ratings`/`warnings` (an absent field
	/// contributes nothing; only a present, non-empty field shows), but a
	/// *confirmed empty* array currently also contributes nothing rather than
	/// an explicit "none" label — same silent-omission tradeoff for all three
	/// modes, so this never mislabels "not available" as "confirmed none," it
	/// just doesn't yet distinguish the two visually.
	var metadataLines: [String] {
		switch tagDisplayMode {
		case .compact:
			let line = Self.compactMetadataLine(wordCountString: wordCountString, isComplete: isComplete, fandomString: fandomString, ratings: ratings, warnings: warnings)
			return line.isEmpty ? [] : [line]
		case .expanded:
			var rows: [String] = []
			if !wordCountString.isEmpty {
				rows.append(String(format: NSLocalizedString("%@ words", comment: "Word count"), wordCountString))
			}
			switch isComplete {
			case true:
				rows.append(NSLocalizedString("Complete", comment: "Completion status"))
			case false:
				rows.append(NSLocalizedString("WIP", comment: "Completion status"))
			case nil:
				break
			}
			if !fandomString.isEmpty {
				rows.append(fandomString)
			}
			if let ratings, !ratings.isEmpty {
				rows.append(ratings.joined(separator: ", "))
			}
			if let warnings, !warnings.isEmpty {
				rows.append(warnings.joined(separator: ", "))
			}
			return rows
		case .badges:
			let line = Self.wordCountCompletionLine(wordCountString: wordCountString, isComplete: isComplete)
			return line.isEmpty ? [] : [line]
		}
	}

	/// Fandom/rating/warnings as individual pill badges. Non-empty only in
	/// `.badges` mode -- `.compact` and `.expanded` fold this same data into
	/// `metadataLines` instead.
	var metadataBadges: [String] {
		guard tagDisplayMode == .badges else { return [] }
		var badges: [String] = []
		if !fandomString.isEmpty {
			badges.append(fandomString)
		}
		if let ratings {
			badges.append(contentsOf: ratings)
		}
		if let warnings {
			badges.append(contentsOf: warnings)
		}
		return badges
	}

	init(article: Article, showFeedName: ShowFeedName, feedName: String?, byline: String?, iconImage: IconImage?, showIcon: Bool, numberOfLines: Int, iconSize: IconSize, tagDisplayMode: TagDisplayMode) {

		self.accountID = article.accountID
		self.articleID = article.articleID
		self.title = ArticleStringFormatter.shared.truncatedTitle(article)
		self.attributedTitle = ArticleStringFormatter.shared.attributedTruncatedTitle(article)

		let truncatedSummary = ArticleStringFormatter.shared.truncatedSummary(article)
		if self.title.isEmpty && truncatedSummary.isEmpty {
			self.summary = Self.noText
		} else {
			self.summary = truncatedSummary
		}

		self.dateString = ArticleStringFormatter.shared.dateString(article.logicalDatePublished)

		if let feedName = feedName {
			self.feedName = ArticleStringFormatter.shared.truncatedFeedName(feedName)
		} else {
			self.feedName = ""
		}

		if let byline = byline {
			self.byline = byline
		} else {
			self.byline = ""
		}

		self.showFeedName = showFeedName

		self.showIcon = showIcon
		self.iconImage = iconImage

		self.read = article.status.read
		self.starred = article.status.starred
		self.loved = article.status.loved
		self.numberOfLines = numberOfLines
		self.iconSize = iconSize
		self.tagDisplayMode = tagDisplayMode
		self.readingProgress = article.status.readingProgress

		if let wordCount = article.wordCount {
			self.wordCountString = Self.wordCountFormatter.string(from: NSNumber(value: wordCount)) ?? String(wordCount)
		} else {
			self.wordCountString = ""
		}

		if let fandoms = article.fandoms, !fandoms.isEmpty {
			self.fandomString = Self.truncatedJoinedList(fandoms)
		} else {
			self.fandomString = ""
		}

		self.isComplete = article.isComplete
		self.ratings = article.ratings
		self.warnings = article.warnings

	}

	init() { // Empty
		self.accountID = ""
		self.articleID = ""
		self.title = ""
		self.attributedTitle = NSAttributedString()
		self.summary = ""
		self.dateString = ""
		self.feedName = ""
		self.byline = ""
		self.showFeedName = .none
		self.showIcon = false
		self.iconImage = nil
		self.read = true
		self.starred = false
		self.loved = false
		self.numberOfLines = 0
		self.iconSize = .medium
		self.tagDisplayMode = .compact
		self.readingProgress = nil
		self.wordCountString = ""
		self.fandomString = ""
		self.isComplete = nil
		self.ratings = nil
		self.warnings = nil
	}

}

// MARK: - Private

private extension MainTimelineCellData {

	static let wordCountFormatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		return formatter
	}()

	// Row-display truncation for fandom (and any future comma-joined tag
	// list): join with ", ", then cap at a fixed item count rather than a
	// character count, since a badge that cuts off mid-word reads as
	// broken in a way a trailing "+N more" doesn't.
	static func truncatedJoinedList(_ items: [String], maxItems: Int = 3) -> String {
		if items.count <= maxItems {
			return items.joined(separator: ", ")
		}
		let shown = items.prefix(maxItems).joined(separator: ", ")
		let remaining = items.count - maxItems
		return "\(shown) +\(remaining)"
	}

	static func metadataLineComponents(wordCountString: String, isComplete: Bool?) -> [String] {
		var parts: [String] = []
		if !wordCountString.isEmpty {
			parts.append(String(format: NSLocalizedString("%@ words", comment: "Word count"), wordCountString))
		}
		switch isComplete {
		case true:
			parts.append(NSLocalizedString("Complete", comment: "Completion status"))
		case false:
			parts.append(NSLocalizedString("WIP", comment: "Completion status"))
		case nil:
			break
		}
		return parts
	}

	/// Word count + completion only — the `.badges` mode's top line, with
	/// fandom/rating/warnings rendered separately as pills instead.
	static func wordCountCompletionLine(wordCountString: String, isComplete: Bool?) -> String {
		metadataLineComponents(wordCountString: wordCountString, isComplete: isComplete).joined(separator: " · ")
	}

	/// The `.compact` mode's single truncating line combining word count,
	/// completion, fandom, and rating/warnings.
	static func compactMetadataLine(wordCountString: String, isComplete: Bool?, fandomString: String, ratings: [String]?, warnings: [String]?) -> String {
		var parts = metadataLineComponents(wordCountString: wordCountString, isComplete: isComplete)

		if !fandomString.isEmpty {
			parts.append(fandomString)
		}

		if let ratings, !ratings.isEmpty {
			parts.append(ratings.joined(separator: ", "))
		}
		if let warnings, !warnings.isEmpty {
			parts.append(warnings.joined(separator: ", "))
		}

		return parts.joined(separator: " · ")
	}
}