//
//  MainFeedCollectionViewCell.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 23/06/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit
import RSCore
import Account
import RSTree
import Images

final class MainFeedCollectionViewCell: UICollectionViewCell {
	@IBOutlet var feedTitle: UILabel!
	@IBOutlet var faviconView: IconView!
	@IBOutlet var unreadCountLabel: UILabel!
	private var faviconLeadingConstraint: NSLayoutConstraint?

	var iconImage: IconImage? {
		didSet {
			faviconView.iconImage = iconImage
			faviconView.tintColor = iconImage?.preferredColor ?? Assets.Colors.secondaryAccent
		}
	}

	private var _unreadCount: Int = 0

	var unreadCount: Int {
		get {
			return _unreadCount
		}
		set {
			_unreadCount = newValue
			if newValue == 0 {
				unreadCountLabel.isHidden = true
			} else {
				unreadCountLabel.isHidden = false
			}
			unreadCountLabel.text = newValue.formatted()
		}
	}

	/// If the feed is contained in a folder, the indentation level is 1
	/// and the cell's favicon leading constrain is increased. Otherwise,
	/// it has the standard leading constraint.
	///
	/// On the storyboard, no leading constraint is set.
	var indentationLevel: Int = 0 {
		didSet {
			if indentationLevel == 1 {
				faviconLeadingConstraint?.constant = 32
			} else {
				faviconLeadingConstraint?.constant = 16
			}
		}
	}

	override var accessibilityLabel: String? {
		get {
			let name = feedTitle.text ?? ""
			if unreadCount > 0 {
				let unreadLabel = NSLocalizedString("unread", comment: "Unread label for accessibility")
				return "\(name) \(unreadCount) \(unreadLabel)"
			} else {
				return name
			}
		}
		set {}
	}

    override func awakeFromNib() {
		MainActor.assumeIsolated {
			super.awakeFromNib()
			isAccessibilityElement = true
			feedTitle.isAccessibilityElement = false
			unreadCountLabel.isAccessibilityElement = false
			faviconView.isAccessibilityElement = false
			faviconLeadingConstraint = faviconView.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor)
			faviconLeadingConstraint?.isActive = true
		}
    }

	override func updateConfiguration(using state: UICellConfigurationState) {
		var backgroundConfig: UIBackgroundConfiguration
		if #available(iOS 18, *) {
			backgroundConfig = UIBackgroundConfiguration.listCell().updated(for: state)
		} else if traitCollection.userInterfaceIdiom == .pad {
			backgroundConfig = UIBackgroundConfiguration.listSidebarCell().updated(for: state)
		} else {
			backgroundConfig = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
		}

		switch (state.isHighlighted || state.isSelected || state.isFocused, traitCollection.userInterfaceIdiom) {
		case (true, .pad):
			// Palette-aware pressed fill, matching MainTimelineCell's swipe/
			// select treatment, instead of a plain system fill that ignored
			// the active SurfacePalette.
			backgroundConfig.backgroundColor = Assets.Colors.pressedCellBackground(for: traitCollection)
			feedTitle.textColor = Assets.Colors.primaryAccent
			feedTitle.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
											   weight: .semibold)
			unreadCountLabel.textColor = Assets.Colors.primaryAccent
			unreadCountLabel.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .semibold)
		case (false, .pad):
			// Deliberately leaves backgroundConfig.backgroundColor untouched
			// (nil) here. .pad's collection view background is intentionally
			// .clear -- MainFeedCollectionViewController.configureCollectionView()'s
			// "This defrosts the glass" case -- so a non-highlighted sidebar
			// row must stay transparent too, or every row paints an opaque
			// listBackground square over the sidebar material and the glass
			// effect disappears entirely. This case must stay separate from
			// the phone/insetGrouped default below, which intentionally does
			// paint an opaque listBackground.
			feedTitle.textColor = .label
			feedTitle.font = UIFont.preferredFont(forTextStyle: .body)
			unreadCountLabel.font = UIFont.preferredFont(forTextStyle: .body)
			unreadCountLabel.textColor = .secondaryLabel
		default:
			// Was left at UIBackgroundConfiguration's own default (systemBackground),
			// which meant a non-default SurfacePalette (e.g. Slate) tinted the
			// collection view's own background via MainFeedCollectionViewController's
			// applyListBackground(), but every row on top of it stayed the system's
			// plain white/black -- the exact "rows... remain white in light mode"
			// report. Rows now use settingsCellBackground, the same
			// lighter-than-container-background contrast MainTimelineCell already
			// uses for its own cards against listBackground -- not listBackground
			// itself, which made every row exactly match the container behind it
			// (no visible row at all, and in Slate specifically read as flatly
			// wrong rather than merely blending in). Phone/insetGrouped only --
			// see the (false, .pad) case above for why iPad's sidebar must not
			// take this branch.
			backgroundConfig.backgroundColor = Assets.Colors.settingsCellBackground(for: traitCollection)
			feedTitle.textColor = .label
			feedTitle.font = UIFont.preferredFont(forTextStyle: .body)
			unreadCountLabel.font = UIFont.preferredFont(forTextStyle: .body)
			unreadCountLabel.textColor = .secondaryLabel
			if traitCollection.userInterfaceIdiom == .phone {
				if feedTitle.text == "All Unread" {
					faviconView.tintColor = iconImage?.preferredColor ?? Assets.Colors.secondaryAccent
				}
			}
		}
		self.backgroundConfiguration = backgroundConfig
	}
}
