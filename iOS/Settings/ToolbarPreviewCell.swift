//
//  ToolbarPreviewCell.swift
//  NetNewsWire-iOS
//
//  Live preview row for ToolbarsCustomizerViewController -- unifies
//  ArticleToolbarPreviewCell (top, UINavigationBar-based) and
//  BottomToolbarPreviewCell (bottom, UIToolbar-based) into one cell that
//  switches its internal bar view by ToolbarBar, since the two
//  pre-unification cells differed only in which UIKit bar type they
//  wrapped and which AppDefaults reads/ordering they used -- both now
//  come from AppDefaults.toolbarFunctionOrder(for:)/
//  isToolbarFunctionEnabled(_:on:)/isToolbarFunctionInOverflow(_:on:)
//  via ToolbarFunction, so a single configure(bar:) covers both. Not an
//  embedded real ArticleViewController, for the same reasoning the two
//  prior cells documented: this settings screen has no live Article,
//  SceneCoordinator, or WebView to back one.
//
//  Order now comes from the same AppDefaults.toolbarFunctionOrder(for:)
//  call ArticleViewController.displayOrder(for:) uses, rather than an
//  independently-hardcoded copy -- see that property's own doc comment.
//  If ArticleViewController.toolbarItems(for:)/rebuildOverflowMenu(for:)
//  collapse behavior ever changes, configure(bar:) still needs the
//  matching change or this preview silently drifts from the real reader.
//

import UIKit
import RSCore

final class ToolbarPreviewCell: UICollectionViewListCell {

	static let reuseIdentifier = "ToolbarPreviewCell"

	private let navigationBar: UINavigationBar = {
		let bar = UINavigationBar()
		bar.translatesAutoresizingMaskIntoConstraints = false
		bar.setItems([UINavigationItem(title: "")], animated: false)
		return bar
	}()

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
		contentView.addSubview(navigationBar)
		contentView.addSubview(toolbar)
		NSLayoutConstraint.activate([
			navigationBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			navigationBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			navigationBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
			navigationBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
			toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
			toolbar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
			contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
		])
	}

	/// icon(for:) mirrors ToolbarFunction.icon except for the dynamic
	/// cases (lock, prevNext) -- see ToolbarFunction's own doc comment
	/// on why those two build runtime state elsewhere; this preview has
	/// no live article/session either, so it draws them in the same
	/// fixed "unlocked" / static-arrows state ArticleToolbarPreviewCell
	/// and BottomToolbarPreviewCell already did.
	private func icon(for function: ToolbarFunction) -> RSImage? {
		function.icon
	}

	/// Mirrors ArticleViewController.toolbarItems(for:overflowItem:)/
	/// rebuildOverflowMenu(for:) exactly: inline functions in
	/// displayOrder(for:) order (flexibleSpace between consecutive
	/// items on .bottom only, matching that method's own separator
	/// rule), plus a trailing command-glyph item when that bar's
	/// overflow mode is on and at least one function is
	/// overflow-flagged there -- additive on both bars, matching the
	/// real reader (the overflow icon sits alongside inline icons, it
	/// no longer replaces them). No UIMenu is attached: every item here
	/// is already target/action-less (a preview, not a live control).
	func configure(bar: ToolbarBar) {
		navigationBar.isHidden = bar != .top
		toolbar.isHidden = bar != .bottom

		let defaults = AppDefaults.shared
		// Reads the same persisted per-bar order ArticleViewController.displayOrder(for:)
		// does, rather than an independently-hardcoded literal -- this was
		// previously a second, separately-maintained copy of the native-order
		// arrays with its own drift risk (see this file's header comment);
		// AppDefaults.toolbarFunctionOrder(for:) is now the one source both read.
		let displayOrder = defaults.toolbarFunctionOrder(for: bar)

		var items: [UIBarButtonItem] = []
		for function in displayOrder where defaults.isToolbarFunctionEnabled(function, on: bar) {
			if bar == .bottom, !items.isEmpty {
				items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
			}
			if function == .prevNext {
				let next = UIBarButtonItem(image: Assets.Images.nextArticle, style: .plain, target: nil, action: nil)
				let prev = UIBarButtonItem(image: Assets.Images.prevArticle, style: .plain, target: nil, action: nil)
				items.append(contentsOf: bar == .top ? [next, prev] : [prev, next])
			} else {
				items.append(UIBarButtonItem(image: icon(for: function), style: .plain, target: nil, action: nil))
			}
		}

		if defaults.isToolbarOverflowMenuEnabled(on: bar) {
			let anyOverflow = displayOrder.contains { defaults.isToolbarFunctionInOverflow($0, on: bar) }
			if anyOverflow {
				if bar == .bottom, !items.isEmpty {
					items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
				}
				items.append(UIBarButtonItem(image: Assets.Images.command, style: .plain, target: nil, action: nil))
			}
		}

		apply(items, to: bar)
	}

	private func apply(_ items: [UIBarButtonItem], to bar: ToolbarBar) {
		switch bar {
		case .top:
			let navItem = UINavigationItem(title: "")
			navItem.rightBarButtonItems = items
			navigationBar.setItems([navItem], animated: false)
		case .bottom:
			toolbar.setItems(items, animated: false)
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
