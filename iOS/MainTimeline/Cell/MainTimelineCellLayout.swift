//
//  MainTimelineCellLayout.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 4/29/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import RSCore
import Images

@MainActor protocol MainTimelineCellLayout {
	var height: CGFloat { get }
	var unreadIndicatorRect: CGRect { get }
	var starRect: CGRect { get }
	var iconImageRect: CGRect { get }
	var titleRect: CGRect { get }
	var progressRect: CGRect { get }
	var summaryRect: CGRect { get }
	/// One rect per plain-text metadata line -- see `MainTimelineCellData.metadataLines`.
	/// `.compact` yields at most one; `.expanded` yields one per non-nil field;
	/// `.badges` yields at most one (the word-count/completion line, with
	/// fandom/rating/warnings in `metadataBadgeRects` instead).
	var metadataLineRects: [CGRect] { get }
	/// Wrapping pill-badge rects for fandom/rating/warnings, non-empty only in
	/// `.badges` mode -- see `MainTimelineCellData.metadataBadges`.
	var metadataBadgeRects: [CGRect] { get }
	var feedNameRect: CGRect { get }
	var dateRect: CGRect { get }
	var separatorRect: CGRect { get }
}

extension MainTimelineCellLayout {

	static func rectForUnreadIndicator(_ point: CGPoint) -> CGRect {
		var r = CGRect.zero
		r.size = CGSize(width: MainTimelineDefaultCellLayout.unreadCircleDimension, height: MainTimelineDefaultCellLayout.unreadCircleDimension)
		r.origin.x = point.x
		r.origin.y = point.y + 5
		return r
	}

	static func rectForStar(_ point: CGPoint) -> CGRect {
		var r = CGRect.zero
		r.size.width = MainTimelineDefaultCellLayout.starDimension
		r.size.height = MainTimelineDefaultCellLayout.starDimension
		r.origin.x = floor(point.x - ((MainTimelineDefaultCellLayout.starDimension - MainTimelineDefaultCellLayout.unreadCircleDimension) / 2.0))
		r.origin.y = point.y + 3
		return r
	}

	static func rectForIconView(_ point: CGPoint, iconSize: IconSize) -> CGRect {
		var r = CGRect.zero
		r.size = iconSize.size
		r.origin.x = point.x
		r.origin.y = point.y + 4
		return r
	}

	static func rectForTitle(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat) -> (CGRect, Int) {
		var r = CGRect.zero
		if cellData.title.isEmpty {
			return (r, 0)
		}
		r.origin = point
		let sizeInfo = MultilineUILabelSizer.size(for: cellData.title, font: MainTimelineDefaultCellLayout.titleFont, numberOfLines: cellData.numberOfLines, width: Int(textAreaWidth))
		r.size.width = textAreaWidth
		r.size.height = sizeInfo.size.height
		if sizeInfo.numberOfLinesUsed < 1 {
			r.size.height = 0
		}
		return (r, sizeInfo.numberOfLinesUsed)
	}

	// Thin bar under the title, showing how far into the article the user has read.
	// Zero rect (hidden) when there's no progress to show, same "hidden when zero, not
	// confirmed-none" shape as rectForTitle/rectForSummary -- covers nil (never opened),
	// 0 (never actually scrolled), and fully read (showing "100%" is noise, not signal).
	static func rectForProgress(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat) -> CGRect {
		var r = CGRect.zero
		// Deliberately not gated on !cellData.read: read-marking fires at the same
		// 99% scroll threshold used to compute progress (see
		// WebViewController.scrollPositionDidChange), so excluding read articles
		// meant the bar was suppressed the same instant it would have appeared.
		// Only progress <= 0 (never scrolled) and progress >= 1 (fully read, not
		// informative) are hidden.
		guard let progress = cellData.readingProgress, progress > 0, progress < 1 else {
			return r
		}
		r.origin = point
		r.size.width = textAreaWidth
		r.size.height = MainTimelineDefaultCellLayout.progressBarHeight
		return r
	}

	static func rectForSummary(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat, _ linesUsed: Int) -> CGRect {
		let linesLeft = cellData.numberOfLines - linesUsed
		var r = CGRect.zero
		if cellData.summary.isEmpty || linesLeft < 1 {
			return r
		}
		r.origin = point
		let sizeInfo = MultilineUILabelSizer.size(for: cellData.summary, font: MainTimelineDefaultCellLayout.summaryFont, numberOfLines: linesLeft, width: Int(textAreaWidth))
		r.size.width = textAreaWidth
		r.size.height = sizeInfo.size.height
		if sizeInfo.numberOfLinesUsed < 1 {
			r.size.height = 0
		}
		return r
	}

	static func rectForFeedName(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat) -> CGRect {
		var r = CGRect.zero
		r.origin = point
		let feedName = cellData.showFeedName == .feed ? cellData.feedName : cellData.byline
		let size = SingleLineUILabelSizer.size(for: feedName, font: MainTimelineDefaultCellLayout.feedNameFont)
		r.size = size
		if r.size.width > textAreaWidth {
			r.size.width = textAreaWidth
		}
		return r
	}

	// One rect per line in cellData.metadataLines, stacked vertically -- same
	// "hidden when zero, not confirmed-none" collapse as rectForTitle/
	// rectForSummary when the line list is empty. `.compact` and `.badges`
	// produce at most one rect here (single truncating line, same shape the
	// old single-mode rectForMetadata always had); `.expanded` can produce
	// several.
	static func rectsForMetadataLines(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat) -> [CGRect] {
		var rects: [CGRect] = []
		var y = point.y
		for line in cellData.metadataLines {
			guard !line.isEmpty else { continue }
			var r = CGRect.zero
			r.origin = CGPoint(x: point.x, y: y)
			let size = SingleLineUILabelSizer.size(for: line, font: MainTimelineDefaultCellLayout.metadataFont)
			r.size = size
			if r.size.width > textAreaWidth {
				r.size.width = textAreaWidth
			}
			rects.append(r)
			y = r.maxY + MainTimelineDefaultCellLayout.metadataLineSpacing
		}
		return rects
	}

	// Flow-wrapping pill rects for cellData.metadataBadges -- unlike the stacked
	// line rects above, badge count and per-badge width both vary, so badges
	// wrap to a new row (rather than each getting a fixed-height rect) whenever
	// the next pill would overflow textAreaWidth. Empty array (not `.badges`
	// mode, or no fandom/rating/warnings data) collapses to no rects, same
	// hidden-when-empty rule as everywhere else in this layout.
	static func rectsForMetadataBadges(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat) -> [CGRect] {
		var rects: [CGRect] = []
		var x = point.x
		var y = point.y
		var isFirstOnRow = true

		for badge in cellData.metadataBadges {
			guard !badge.isEmpty else { continue }
			let textSize = SingleLineUILabelSizer.size(for: badge, font: MainTimelineDefaultCellLayout.badgeFont)
			let cappedTextWidth = min(textSize.width, textAreaWidth - MainTimelineDefaultCellLayout.badgeHorizontalPadding * 2)
			let badgeWidth = cappedTextWidth + MainTimelineDefaultCellLayout.badgeHorizontalPadding * 2
			let badgeHeight = textSize.height + MainTimelineDefaultCellLayout.badgeVerticalPadding * 2

			if !isFirstOnRow, (x - point.x) + badgeWidth > textAreaWidth {
				x = point.x
				y += badgeHeight + MainTimelineDefaultCellLayout.badgeLineSpacing
				isFirstOnRow = true
			}

			rects.append(CGRect(x: x, y: y, width: badgeWidth, height: badgeHeight))
			x += badgeWidth + MainTimelineDefaultCellLayout.badgeSpacing
			isFirstOnRow = false
		}

		return rects
	}
}

// MARK: - Default

struct MainTimelineDefaultCellLayout: MainTimelineCellLayout {

	static let cellPadding = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 20)

	static let unreadCircleMarginLeft = CGFloat(0)
	static let unreadCircleDimension = CGFloat(12)
	static let unreadCircleMarginRight = CGFloat(8)

	static let starDimension = CGFloat(16)

	static let iconMarginRight = CGFloat(8)
	static let iconCornerRadius = CGFloat(4)

	static var titleFont: UIFont { UIFont.preferredFont(forTextStyle: .headline) }
	static let titleBottomMargin = CGFloat(1)

	static let progressBarHeight = CGFloat(2)
	static let progressBarTopMargin = CGFloat(4)
	static let progressBarBottomMargin = CGFloat(4)

	static var feedNameFont: UIFont { UIFont.preferredFont(forTextStyle: .footnote) }
	static let feedRightMargin = CGFloat(8)

	static var dateFont: UIFont { UIFont.preferredFont(forTextStyle: .footnote) }
	static let dateMarginBottom = CGFloat(1)

	static var summaryFont: UIFont { UIFont.preferredFont(forTextStyle: .body) }

	static var metadataFont: UIFont { UIFont.preferredFont(forTextStyle: .caption1) }
	static let metadataBottomMargin = CGFloat(1)
	// Vertical gap between stacked .expanded metadata lines.
	static let metadataLineSpacing = CGFloat(2)

	// .badges pill styling.
	static var badgeFont: UIFont { UIFont.preferredFont(forTextStyle: .caption2) }
	static let badgeHorizontalPadding = CGFloat(8)
	static let badgeVerticalPadding = CGFloat(3)
	static let badgeSpacing = CGFloat(6)
	static let badgeLineSpacing = CGFloat(6)

	let height: CGFloat
	let unreadIndicatorRect: CGRect
	let starRect: CGRect
	let iconImageRect: CGRect
	let titleRect: CGRect
	let progressRect: CGRect
	let summaryRect: CGRect
	let feedNameRect: CGRect
	let dateRect: CGRect
	let separatorRect: CGRect
	let metadataLineRects: [CGRect]
	let metadataBadgeRects: [CGRect]

	init(width: CGFloat, insets: UIEdgeInsets, cellData: MainTimelineCellData) {

		var currentPoint = CGPoint.zero
		currentPoint.x = Self.cellPadding.left + insets.left + Self.unreadCircleMarginLeft
		currentPoint.y = Self.cellPadding.top

		self.unreadIndicatorRect = Self.rectForUnreadIndicator(currentPoint)
		self.starRect = Self.rectForStar(currentPoint)

		currentPoint.x += Self.unreadCircleDimension + Self.unreadCircleMarginRight

		if cellData.showIcon {
			self.iconImageRect = Self.rectForIconView(currentPoint, iconSize: cellData.iconSize)
			currentPoint.x = self.iconImageRect.maxX + Self.iconMarginRight
		} else {
			self.iconImageRect = CGRect.zero
		}

		let textAreaWidth = width - (currentPoint.x + Self.cellPadding.right + insets.right)
		self.separatorRect = CGRect(x: currentPoint.x, y: 0, width: textAreaWidth, height: 0)

		let (titleRect, numberOfLinesForTitle) = Self.rectForTitle(cellData, currentPoint, textAreaWidth)
		self.titleRect = titleRect

		if self.titleRect != CGRect.zero {
			currentPoint.y = self.titleRect.maxY + Self.titleBottomMargin
		}

		let progressPoint = CGPoint(x: currentPoint.x, y: currentPoint.y + Self.progressBarTopMargin)
		self.progressRect = Self.rectForProgress(cellData, progressPoint, textAreaWidth)
		if self.progressRect != CGRect.zero {
			currentPoint.y = self.progressRect.maxY + Self.progressBarBottomMargin
		}

		self.summaryRect = Self.rectForSummary(cellData, currentPoint, textAreaWidth, numberOfLinesForTitle)

		var y = [self.titleRect, self.progressRect, self.summaryRect].maxY()
		if y == 0 {
			y = iconImageRect.origin.y + iconImageRect.height
			let tmp = Self.rectForDate(cellData, currentPoint, textAreaWidth)
			y -= tmp.height
		}
		currentPoint.y = y

		self.metadataLineRects = Self.rectsForMetadataLines(cellData, currentPoint, textAreaWidth)
		if !self.metadataLineRects.isEmpty {
			currentPoint.y = self.metadataLineRects.maxY() + Self.metadataBottomMargin
		}

		self.metadataBadgeRects = Self.rectsForMetadataBadges(cellData, currentPoint, textAreaWidth)
		if !self.metadataBadgeRects.isEmpty {
			currentPoint.y = self.metadataBadgeRects.maxY() + Self.metadataBottomMargin
		}

		self.dateRect = Self.rectForDate(cellData, currentPoint, textAreaWidth)

		let feedNameWidth = textAreaWidth - (Self.feedRightMargin + self.dateRect.size.width)
		self.feedNameRect = Self.rectForFeedName(cellData, currentPoint, feedNameWidth)

		self.height = [self.iconImageRect, self.feedNameRect].maxY() + Self.cellPadding.bottom
	}

	static func rectForDate(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat) -> CGRect {
		var r = CGRect.zero
		let size = SingleLineUILabelSizer.size(for: cellData.dateString, font: Self.dateFont)
		r.size = size
		r.origin.x = (point.x + textAreaWidth) - size.width
		r.origin.y = point.y
		return r
	}
}

// MARK: - Accessibility

struct MainTimelineAccessibilityCellLayout: MainTimelineCellLayout {

	let height: CGFloat
	let unreadIndicatorRect: CGRect
	let starRect: CGRect
	let iconImageRect: CGRect
	let titleRect: CGRect
	let progressRect: CGRect
	let summaryRect: CGRect
	let feedNameRect: CGRect
	let dateRect: CGRect
	let separatorRect: CGRect
	let metadataLineRects: [CGRect]
	let metadataBadgeRects: [CGRect]

	init(width: CGFloat, insets: UIEdgeInsets, cellData: MainTimelineCellData) {

		var currentPoint = CGPoint.zero
		currentPoint.x = MainTimelineDefaultCellLayout.cellPadding.left + insets.left + MainTimelineDefaultCellLayout.unreadCircleMarginLeft
		currentPoint.y = MainTimelineDefaultCellLayout.cellPadding.top

		self.unreadIndicatorRect = Self.rectForUnreadIndicator(currentPoint)
		self.starRect = Self.rectForStar(currentPoint)

		currentPoint.x += MainTimelineDefaultCellLayout.unreadCircleDimension + MainTimelineDefaultCellLayout.unreadCircleMarginRight

		if cellData.showIcon {
			self.iconImageRect = Self.rectForIconView(currentPoint, iconSize: cellData.iconSize)
			currentPoint.y = self.iconImageRect.maxY
		} else {
			self.iconImageRect = CGRect.zero
		}

		let textAreaWidth = width - (currentPoint.x + MainTimelineDefaultCellLayout.cellPadding.right + insets.right)
		self.separatorRect = CGRect(x: currentPoint.x, y: 0, width: textAreaWidth, height: 0)

		let (titleRect, numberOfLinesForTitle) = Self.rectForTitle(cellData, currentPoint, textAreaWidth)
		self.titleRect = titleRect

		if self.titleRect != CGRect.zero {
			currentPoint.y = self.titleRect.maxY + MainTimelineDefaultCellLayout.titleBottomMargin
		}

		let progressPoint = CGPoint(x: currentPoint.x, y: currentPoint.y + MainTimelineDefaultCellLayout.progressBarTopMargin)
		self.progressRect = Self.rectForProgress(cellData, progressPoint, textAreaWidth)
		if self.progressRect != CGRect.zero {
			currentPoint.y = self.progressRect.maxY + MainTimelineDefaultCellLayout.progressBarBottomMargin
		}

		self.summaryRect = Self.rectForSummary(cellData, currentPoint, textAreaWidth, numberOfLinesForTitle)

		currentPoint.y = [self.titleRect, self.progressRect, self.summaryRect].maxY()

		self.metadataLineRects = Self.rectsForMetadataLines(cellData, currentPoint, textAreaWidth)
		if !self.metadataLineRects.isEmpty {
			currentPoint.y = self.metadataLineRects.maxY() + MainTimelineDefaultCellLayout.metadataBottomMargin
		}

		self.metadataBadgeRects = Self.rectsForMetadataBadges(cellData, currentPoint, textAreaWidth)
		if !self.metadataBadgeRects.isEmpty {
			currentPoint.y = self.metadataBadgeRects.maxY() + MainTimelineDefaultCellLayout.metadataBottomMargin
		}

		if cellData.showFeedName != .none {
			self.feedNameRect = Self.rectForFeedName(cellData, currentPoint, textAreaWidth)
			currentPoint.y = self.feedNameRect.maxY
		} else {
			self.feedNameRect = CGRect.zero
		}

		self.dateRect = Self.rectForDate(cellData, currentPoint, textAreaWidth)

		self.height = self.dateRect.maxY + MainTimelineDefaultCellLayout.cellPadding.bottom
	}

	static func rectForDate(_ cellData: MainTimelineCellData, _ point: CGPoint, _ textAreaWidth: CGFloat) -> CGRect {
		var r = CGRect.zero
		let size = SingleLineUILabelSizer.size(for: cellData.dateString, font: MainTimelineDefaultCellLayout.dateFont)
		r.size = size
		r.origin = point
		return r
	}
}
