//
//  AddComboTableViewCell.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 11/16/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit

final class AddComboTableViewCell: VibrantTableViewCell {
	@IBOutlet var icon: UIImageView!
	@IBOutlet var label: UILabel!
	@IBOutlet var iconLeadingConstraint: NSLayoutConstraint!

	override func updateVibrancy(animated: Bool) {
		super.updateVibrancy(animated: animated)

		let iconTintColor = isHighlighted || isSelected ? Assets.Colors.vibrantText(for: traitCollection) : Assets.Colors.secondaryAccent
		if animated {
			UIView.animate(withDuration: Self.duration) {
				self.icon.tintColor = iconTintColor
			}
		} else {
			self.icon.tintColor = iconTintColor
		}
		updateLabelVibrancy(label, color: labelColor, animated: animated)
	}

	/// `depth` is the row's position in the account/folder tree: 0 for
	/// an account row, 1 for a top-level folder, up to 3 for a folder
	/// nested to the cap (see `nested-folders.md`). `20 + 30 * depth`
	/// deliberately reproduces this cell's two original storyboard
	/// leading constants exactly -- 20 for `AccountCell` (depth 0), 50
	/// for `FolderCell` (depth 1, the only depth that existed before
	/// nesting) -- so existing rows don't shift, and every deeper level
	/// steps out by the same 30pt `FolderCell` already used once.
	func setIndentationDepth(_ depth: Int) {
		iconLeadingConstraint.constant = 20 + CGFloat(depth) * 30
	}

}
