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
	let numberOfLines: Int
	let iconSize: IconSize

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

	init(article: Article, showFeedName: ShowFeedName, feedName: String?, byline: String?, iconImage: IconImage?, showIcon: Bool, numberOfLines: Int, iconSize: IconSize) {

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
		self.numberOfLines = numberOfLines
		self.iconSize = iconSize

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
		self.numberOfLines = 0
		self.iconSize = .medium
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
}