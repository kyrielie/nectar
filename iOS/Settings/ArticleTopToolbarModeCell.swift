//
//  ArticleTopToolbarModeCell.swift
//  NetNewsWire-iOS
//
//  Article view top toolbar settings plan. Checkmark-style single-select
//  row, one per ArticleTopToolbarMode case -- same shape as
//  AccentColorTableViewController's accent-color/badge-palette rows, applied
//  to a UICollectionViewListCell instead of a UITableViewCell since this
//  screen (like TimelineCustomizerCollectionViewController) is collection-
//  view-based.
//

import UIKit

final class ArticleTopToolbarModeCell: UICollectionViewListCell {

	static let reuseIdentifier = "ArticleTopToolbarModeCell"

	func configure(mode: ArticleTopToolbarMode, isSelected: Bool) {
		var content = defaultContentConfiguration()
		content.text = Self.title(for: mode)
		contentConfiguration = content
		accessories = isSelected ? [.checkmark()] : []
	}

	private static func title(for mode: ArticleTopToolbarMode) -> String {
		switch mode {
		case .off:
			return NSLocalizedString("Off", comment: "Article top toolbar mode: off")
		case .tableOfContentsAndFind:
			return NSLocalizedString("Table of Contents & Find", comment: "Article top toolbar mode: table of contents and find")
		case .prevNextArticle:
			return NSLocalizedString("Previous & Next Article", comment: "Article top toolbar mode: previous and next article")
		}
	}

	override func updateConfiguration(using state: UICellConfigurationState) {
		var backgroundConfig: UIBackgroundConfiguration
		if #available(iOS 18, *) {
			backgroundConfig = UIBackgroundConfiguration.listCell().updated(for: state)
		} else {
			backgroundConfig = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
		}
		backgroundConfig.backgroundColor = Assets.Colors.settingsCellBackground(for: traitCollection)
		backgroundConfig.cornerRadius = 20
		self.backgroundConfiguration = backgroundConfig
	}
}
