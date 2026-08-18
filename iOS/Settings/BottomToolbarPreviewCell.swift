//
//  BottomToolbarPreviewCell.swift
//  NetNewsWire-iOS
//
//  Live preview row for BottomToolbarCustomizerViewController -- a
//  synthetic UIToolbar built with the same icons, order, and
//  flexibleSpace-separated layout as
//  ArticleViewController.bottomToolbarItems() (read, star, heart, next
//  unread, action -- each included only if its own AppDefaults toggle is
//  on), rather than an embedded real ArticleViewController, for the same
//  reasoning as ArticleToolbarPreviewCell. If bottomToolbarItems()'s
//  ordering ever changes, configure() needs the matching change or this
//  preview silently drifts from the real reader.
//

import UIKit

final class BottomToolbarPreviewCell: UICollectionViewListCell {

	static let reuseIdentifier = "BottomToolbarPreviewCell"

	private let toolbar: UIToolbar = {
		let bar = UIToolbar()
		bar.translatesAutoresizingMaskIntoConstraints = false
		return bar
	}()

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		contentView.addSubview(toolbar)
		NSLayoutConstraint.activate([
			toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
			toolbar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
			contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
		])
	}

	/// Mirrors ArticleViewController.bottomToolbarItems() exactly: read,
	/// star (bookmark, labeled "Read Later" -- see Assets.Images.starOpen's
	/// own historical-naming comment), heart, next unread, action -- each
	/// included only if its own AppDefaults toggle is currently on, with
	/// flexibleSpace only between two consecutive present items, so any
	/// combination (including none) renders correctly. Read/star/heart are
	/// always drawn in their "unselected" state (circle/bookmark-outline/
	/// heart-outline) since read/starred/loved status is per-article state,
	/// not something this settings screen has an article to read it from.
	func configure() {
		let defaults = AppDefaults.shared
		var items: [UIBarButtonItem] = []
		let flex = { UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil) }

		let candidates: [(BottomToolbarToggle, RSImage)] = [
			(.read, Assets.Images.circleOpen), (.star, Assets.Images.starOpen), (.heart, Assets.Images.heartOpen),
			(.nextUnread, Assets.Images.nextUnread), (.action, Assets.Images.action)
		]
		for (toggle, image) in candidates where defaults.isBottomToolbarToggleEnabled(toggle) {
			if !items.isEmpty {
				items.append(flex())
			}
			items.append(UIBarButtonItem(image: image, style: .plain, target: nil, action: nil))
		}

		toolbar.setItems(items, animated: false)
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
