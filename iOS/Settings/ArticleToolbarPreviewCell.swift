//
//  ArticleToolbarPreviewCell.swift
//  NetNewsWire-iOS
//
//  Live preview row for ArticleToolbarCustomizerViewController -- a
//  synthetic UINavigationBar built with the same icons and order as
//  ArticleViewController.rightBarButtonItems() (theme, table of contents,
//  find, prev/next, then lock, each included only if its own AppDefaults
//  toggle is on), rather than an embedded real ArticleViewController, since that
//  controller needs a live Article, SceneCoordinator, and WebView machinery
//  this settings screen has no reason to stand up. If
//  rightBarButtonItems()'s ordering ever changes, configure() needs the
//  matching change or this preview silently drifts from the real reader.
//

import UIKit

final class ArticleToolbarPreviewCell: UICollectionViewListCell {

	static let reuseIdentifier = "ArticleToolbarPreviewCell"

	private let navigationBar: UINavigationBar = {
		let bar = UINavigationBar()
		bar.translatesAutoresizingMaskIntoConstraints = false
		bar.setItems([UINavigationItem(title: "")], animated: false)
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
		contentView.addSubview(navigationBar)
		NSLayoutConstraint.activate([
			navigationBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			navigationBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			navigationBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
			navigationBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
			contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
		])
	}

	/// Mirrors ArticleViewController.rightBarButtonItems() exactly: theme,
	/// table of contents, find, prev/next (array order [next, prev],
	/// matching that method's own literal), then lock -- each included
	/// only if its own AppDefaults toggle is currently on, so any
	/// combination (including none) renders correctly. The lock preview
	/// is always drawn unlocked (SF Symbol "lock.open"): the lock state
	/// itself is transient session state on SceneCoordinator, not an
	/// AppDefaults value, so there's nothing for this settings screen to
	/// read for it.
	func configure() {
		let defaults = AppDefaults.shared
		var items: [UIBarButtonItem] = []

		if defaults.isArticleToolbarToggleEnabled(.theme) {
			items.append(UIBarButtonItem(image: Assets.Images.theme, style: .plain, target: nil, action: nil))
		}
		if defaults.isArticleToolbarToggleEnabled(.tableOfContents) {
			items.append(UIBarButtonItem(image: Assets.Images.tableOfContents, style: .plain, target: nil, action: nil))
		}
		if defaults.isArticleToolbarToggleEnabled(.find) {
			items.append(UIBarButtonItem(image: Assets.Images.findInArticle, style: .plain, target: nil, action: nil))
		}
		if defaults.isArticleToolbarToggleEnabled(.prevNext) {
			let next = UIBarButtonItem(image: Assets.Images.nextArticle, style: .plain, target: nil, action: nil)
			let prev = UIBarButtonItem(image: Assets.Images.prevArticle, style: .plain, target: nil, action: nil)
			items.append(contentsOf: [next, prev])
		}
		if defaults.isArticleToolbarToggleEnabled(.lock) {
			items.append(UIBarButtonItem(image: UIImage(systemName: "lock.open"), style: .plain, target: nil, action: nil))
		}
		if defaults.isArticleToolbarToggleEnabled(.annotations) {
			items.append(UIBarButtonItem(image: Assets.Images.annotations, style: .plain, target: nil, action: nil))
		}
		if defaults.isArticleToolbarToggleEnabled(.settings) {
			items.append(UIBarButtonItem(image: Assets.Images.settings, style: .plain, target: nil, action: nil))
		}
		if defaults.isArticleToolbarToggleEnabled(.checkForUpdates) {
			items.append(UIBarButtonItem(image: Assets.Images.checkForUpdates, style: .plain, target: nil, action: nil))
		}

		let navItem = UINavigationItem(title: "")
		navItem.rightBarButtonItems = items
		navigationBar.setItems([navItem], animated: false)
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
