//
//  MainTimelineCell.swift
//  NetNewsWire-iOS
//
//  Created by Brent Simmons on 6/22/26.
//

import UIKit
import RSCore
import Images

///  Manual-layout timeline cell modeled on the Mac timeline
///  and the pre-7.0 iOS table view cell.
final class MainTimelineCell: UICollectionViewCell {

	static let reuseIdentifier = "MainTimelineCell"

	var isPreview = false

	private let titleView = MainTimelineCell.multiLineLabel()
	private let summaryView = MainTimelineCell.multiLineLabel()
	// Pools rather than a single label: the number of metadata lines/badges
	// varies with TagDisplayMode (and, for badges, with how many fandom/
	// rating/warning values an article has), so these grow to the largest
	// count seen and hide any views beyond the current count -- see
	// ensureLabelCount.
	private var metadataLineViews: [UILabel] = []
	private var metadataBadgeViews: [UILabel] = []
	private let dateView = MainTimelineCell.singleLineLabel()
	private let feedNameView = MainTimelineCell.singleLineLabel()
	private lazy var iconView = IconView()
	private lazy var indicatorView = IconView()
	private let topSeparator = UIView()
	private let progressTrackView = UIView()
	private let progressFillView = UIView()

	var cellData: MainTimelineCellData! {
		didSet {
			updateSubviews()
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		indicatorView.isHidden = true
	}

	override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
		let layout = updatedLayout(width: layoutAttributes.frame.width)
		layoutAttributes.frame.size.height = layout.height
		return layoutAttributes
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		let layout = updatedLayout(width: contentView.bounds.width)

		setFrame(for: titleView, rect: layout.titleRect)
		setFrame(for: progressTrackView, rect: layout.progressRect)
		setFrame(for: summaryView, rect: layout.summaryRect)

		for (index, rect) in layout.metadataLineRects.enumerated() where index < metadataLineViews.count {
			setFrame(for: metadataLineViews[index], rect: rect)
		}
		for (index, rect) in layout.metadataBadgeRects.enumerated() where index < metadataBadgeViews.count {
			let badgeView = metadataBadgeViews[index]
			setFrame(for: badgeView, rect: rect)
			badgeView.layer.cornerRadius = rect.height / 2
		}

		feedNameView.setFrameIfNotEqual(layout.feedNameRect)
		dateView.setFrameIfNotEqual(layout.dateRect)
		iconView.setFrameIfNotEqual(layout.iconImageRect)
		indicatorView.setFrameIfNotEqual(cellData.starred ? layout.starRect : layout.unreadIndicatorRect)
		topSeparator.frame = CGRect(x: layout.separatorRect.minX, y: 0, width: layout.separatorRect.width, height: 1.0 / traitCollection.displayScale)
		layoutProgressFill()
	}

	override func updateConfiguration(using state: UICellConfigurationState) {
		super.updateConfiguration(using: state)

		var backgroundConfig: UIBackgroundConfiguration
		if #available(iOS 18, *) {
			backgroundConfig = UIBackgroundConfiguration.listCell().updated(for: state)
		} else {
			backgroundConfig = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
		}
		if state.traitCollection.horizontalSizeClass == .compact {
			// Full-bleed rectangle selection in compact width; iPad (regular width) keeps the
			// rounded, inset selection below.
			backgroundConfig.cornerRadius = 0
			backgroundConfig.backgroundInsets = .zero
			backgroundConfig.edgesAddingLayoutMarginsToBackgroundInsets = []
		} else if #available(iOS 26, *) {
			backgroundConfig.cornerRadius = 20
			backgroundConfig.edgesAddingLayoutMarginsToBackgroundInsets = [.leading, .trailing]
			if UIDevice.current.userInterfaceIdiom == .pad {
				backgroundConfig.backgroundInsets = NSDirectionalEdgeInsets(top: 0, leading: -8, bottom: 0, trailing: -8)
			} else if isPreview {
				backgroundConfig.backgroundInsets = NSDirectionalEdgeInsets(top: 0, leading: -16, bottom: 0, trailing: -16)
			} else {
				backgroundConfig.backgroundInsets = NSDirectionalEdgeInsets(top: 0, leading: -12, bottom: 0, trailing: -12)
			}
		} else {
			backgroundConfig.cornerRadius = 0
		}

		// Selected cells keep the standard system selection color from updated(for: state).
		if state.isSwiped {
			backgroundConfig.backgroundColor = .secondarySystemFill
		} else if !state.isSelected {
			backgroundConfig.backgroundColor = .clear
		}

		let isActive = state.isSwiped || state.isSelected

		if isPreview {
			backgroundConfig.backgroundColor = traitCollection.userInterfaceStyle == .dark ? .secondarySystemBackground : .white
		}
		backgroundConfiguration = backgroundConfig

		topSeparator.alpha = (isActive || isPreview) ? 0.0 : 1.0

		updateColors()
		updateIndicatorView()
	}

	func setIconImage(_ image: IconImage) {
		iconView.iconImage = image
	}
}

// MARK: - Private

private extension MainTimelineCell {

	static func singleLineLabel() -> UILabel {
		let label = NonIntrinsicLabel()
		label.lineBreakMode = .byTruncatingTail
		label.allowsDefaultTighteningForTruncation = false
		label.adjustsFontForContentSizeCategory = true
		return label
	}

	static func multiLineLabel() -> UILabel {
		let label = NonIntrinsicLabel()
		label.numberOfLines = 0
		label.lineBreakMode = .byTruncatingTail
		label.allowsDefaultTighteningForTruncation = false
		label.adjustsFontForContentSizeCategory = true
		return label
	}

	// A pill-styled label for .badges mode: centered text over a rounded,
	// tinted background. The rect from rectsForMetadataBadges already bakes
	// in horizontal/vertical padding around the text, so centering the text
	// within that (wider) frame reads as padding without a separate
	// container view. cornerRadius is set per-rect in layoutSubviews, since
	// it depends on the rect's (dynamic-type-dependent) height.
	static func badgeLabel() -> UILabel {
		let label = NonIntrinsicLabel()
		label.font = MainTimelineDefaultCellLayout.badgeFont
		label.textAlignment = .center
		label.lineBreakMode = .byTruncatingTail
		label.allowsDefaultTighteningForTruncation = false
		label.adjustsFontForContentSizeCategory = true
		label.backgroundColor = .tertiarySystemFill
		label.clipsToBounds = true
		return label
	}

	func commonInit() {
		isAccessibilityElement = true
		topSeparator.backgroundColor = .separator.withAlphaComponent(0.1)
		for view in [titleView, summaryView, dateView, feedNameView, iconView, indicatorView, topSeparator] {
			contentView.addSubview(view)
			view.isAccessibilityElement = false
		}
		indicatorView.isHidden = true

		progressTrackView.backgroundColor = .tertiarySystemFill
		progressTrackView.layer.cornerRadius = MainTimelineDefaultCellLayout.progressBarHeight / 2
		progressTrackView.clipsToBounds = true
		progressTrackView.isAccessibilityElement = false
		contentView.addSubview(progressTrackView)
		progressTrackView.addSubview(progressFillView)
		progressFillView.backgroundColor = Assets.Colors.secondaryAccent
		progressFillView.layer.cornerRadius = MainTimelineDefaultCellLayout.progressBarHeight / 2
	}

	/// Grows `views` to `count` (adding new views made by `makeView`, inserted
	/// into the content view) and hides -- without removing, so they're ready
	/// to reuse if the count grows again -- any existing views beyond `count`.
	func ensureViewCount(_ count: Int, in views: inout [UILabel], makeView: () -> UILabel) {
		while views.count < count {
			let view = makeView()
			view.isAccessibilityElement = false
			contentView.addSubview(view)
			views.append(view)
		}
		if views.count > count {
			for index in count..<views.count {
				views[index].isHidden = true
			}
		}
	}

	func updatedLayout(width: CGFloat) -> MainTimelineCellLayout {
		guard cellData != nil else {
			return MainTimelineDefaultCellLayout(width: width, insets: .zero, cellData: MainTimelineCellData())
		}
		if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
			return MainTimelineAccessibilityCellLayout(width: width, insets: .zero, cellData: cellData)
		}
		return MainTimelineDefaultCellLayout(width: width, insets: .zero, cellData: cellData)
	}

	func setFrame(for view: UIView, rect: CGRect) {
		if Int(floor(rect.height)) == 0 || Int(floor(rect.width)) == 0 {
			view.isHidden = true
		} else {
			view.isHidden = false
			view.setFrameIfNotEqual(rect)
		}
	}

	/// The track (progressTrackView) is a plain UIView, not a UILabel, so it's framed
	/// directly rather than through setFrame(for:rect:) -- same hidden-when-zero rule,
	/// applied by hand since there's no label to hide.
	func layoutProgressFill() {
		guard !progressTrackView.isHidden, cellData != nil else {
			progressFillView.frame = .zero
			return
		}
		let progress = min(max(cellData.readingProgress ?? 0, 0), 1)
		let trackBounds = progressTrackView.bounds
		progressFillView.frame = CGRect(x: 0, y: 0, width: trackBounds.width * CGFloat(progress), height: trackBounds.height)
	}

	func updateSubviews() {
		titleView.font = MainTimelineDefaultCellLayout.titleFont
		titleView.attributedText = cellData.attributedTitle.applyingBaseFont(MainTimelineDefaultCellLayout.titleFont)

		summaryView.font = MainTimelineDefaultCellLayout.summaryFont
		summaryView.text = cellData.summary

		updateMetadataLines()
		updateMetadataBadges()

		dateView.font = MainTimelineDefaultCellLayout.dateFont
		dateView.text = cellData.dateString

		switch cellData.showFeedName {
		case .feed:
			feedNameView.font = MainTimelineDefaultCellLayout.feedNameFont
			feedNameView.text = cellData.feedName
			feedNameView.isHidden = false
		case .byline:
			feedNameView.font = MainTimelineDefaultCellLayout.feedNameFont
			feedNameView.text = cellData.byline
			feedNameView.isHidden = false
		case .none:
			feedNameView.isHidden = true
		}

		if cellData.showIcon, let iconImage = cellData.iconImage {
			iconView.iconImage = iconImage
			iconView.isHidden = false
		} else {
			iconView.iconImage = nil
			iconView.isHidden = true
		}

		updateColors()
		updateIndicatorView()
		updateAccessibilityLabel()
		setNeedsLayout()
	}

	func updateMetadataLines() {
		let lines = cellData.metadataLines
		ensureViewCount(lines.count, in: &metadataLineViews, makeView: MainTimelineCell.singleLineLabel)
		for (index, line) in lines.enumerated() {
			let label = metadataLineViews[index]
			label.font = MainTimelineDefaultCellLayout.metadataFont
			label.textColor = .secondaryLabel
			label.text = line
		}
	}

	func updateMetadataBadges() {
		let badges = cellData.metadataBadges
		ensureViewCount(badges.count, in: &metadataBadgeViews, makeView: MainTimelineCell.badgeLabel)
		for (index, badge) in badges.enumerated() {
			let label = metadataBadgeViews[index]
			label.textColor = .secondaryLabel
			label.text = badge
		}
	}

	func updateColors() {
		titleView.textColor = .label
		summaryView.textColor = cellData.title.isEmpty ? .label : .secondaryLabel
		for label in metadataLineViews {
			label.textColor = .secondaryLabel
		}
		dateView.textColor = .secondaryLabel
		feedNameView.textColor = .secondaryLabel
	}

	func updateIndicatorView() {
		guard cellData != nil else {
			indicatorView.isHidden = true
			return
		}
		if cellData.starred {
			indicatorView.iconImage = Assets.Images.starredFeed
			indicatorView.tintColor = Assets.Colors.star
			indicatorView.isHidden = false
		} else if !cellData.read {
			indicatorView.iconImage = Assets.Images.unreadCellIndicator
			indicatorView.tintColor = Assets.Colors.secondaryAccent
			indicatorView.isHidden = false
		} else {
			indicatorView.isHidden = true
		}
	}

	func updateAccessibilityLabel() {
		let starredStatus = cellData.starred ? "\(NSLocalizedString("Read Later", comment: "Read Later")), " : ""
		let unreadStatus = cellData.read ? "" : "\(NSLocalizedString("Unread", comment: "Unread")), "
		accessibilityLabel = starredStatus + unreadStatus + "\(cellData.feedName), \(cellData.title), \(cellData.summary), \(cellData.dateString)"
	}
}
