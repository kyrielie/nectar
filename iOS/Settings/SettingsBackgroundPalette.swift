//
//  SettingsBackgroundPalette.swift
//  NetNewsWire-iOS
//
//  See docs/app-chrome-palette.md ("Badge Colors"). Shared wiring for
//  every pushed Settings screen (and the root Settings screen itself) that
//  paints its table/collection view background from
//  Assets.Colors.settingsBackground(for:) -- same three-notification shape
//  (viewDidLoad application, registerForTraitChanges, .surfaceTintDidChange
//  observer) ArticleViewController.applySurfacePaletteNavigationBarAppearance()
//  already established, factored out once rather than repeated identically
//  across five controllers.
//

import UIKit

@MainActor
protocol SettingsPaletteBackgroundHosting: UIViewController {
	/// The view whose `.backgroundColor` should track
	/// `Assets.Colors.settingsBackground(for:)`. A `UITableView` for
	/// `UITableViewController`s, a `UICollectionView` for
	/// `UICollectionViewController`s.
	var paletteBackgroundView: UIView { get }

	/// Repaint whatever per-row/per-cell fill this screen owns
	/// (`applySettingsCellBackground(to:)` over `visibleCells`, a plain
	/// `reloadData()`, a `reloadSections`, etc.) -- called after every
	/// `applySettingsPaletteBackground()`, including on a light/dark trait
	/// change. Default is a no-op, correct for any screen with no per-cell
	/// palette-driven fill of its own.
	func refreshPaletteCellBackgrounds()
}

extension SettingsPaletteBackgroundHosting {

	func refreshPaletteCellBackgrounds() {}

	/// Call once from `viewDidLoad()`.
	func configureSettingsPaletteBackground() {
		applySettingsPaletteBackground()
		refreshPaletteCellBackgrounds()

		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
			guard self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle else { return }
			self.applySettingsPaletteBackground()
			// Bug fix: this only used to repaint paletteBackgroundView (the
			// container). Each row's own settingsCellBackground fill is a
			// baked hex color (RSColor(cssHex:)), not a dynamic system color,
			// so it doesn't repaint itself on a light/dark switch -- it needs
			// the same explicit refresh a .surfaceTintDidChange palette
			// switch already gets below, or rows already on screen keep the
			// previous appearance's color until they scroll off and back.
			self.refreshPaletteCellBackgrounds()
		}

		NotificationCenter.default.addObserver(forName: .surfaceTintDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.applySettingsPaletteBackground()
			}
		}
	}

	func applySettingsPaletteBackground() {
		paletteBackgroundView.backgroundColor = Assets.Colors.settingsBackground(for: traitCollection)
	}

	/// Tints a single row's own cell background from
	/// `Assets.Colors.settingsCellBackground(for:)`, distinct from
	/// `paletteBackgroundView`'s gutter color above -- call from
	/// `tableView(_:willDisplay:forRowAt:)`.
	///
	/// Grouped-style `UITableViewCell`s otherwise keep UIKit's own
	/// `.secondarySystemGroupedBackground`, which a `SurfacePalette` never
	/// overrides -- the same class of bug `MainFeedCollectionViewCell` and
	/// `MainTimelineModernViewController`'s collection view background had:
	/// the screen's container color changes, but every row drawn on top of
	/// it stays the plain system color, so a palette like Slate never
	/// visibly reaches the settings list itself.
	func applySettingsCellBackground(to cell: UITableViewCell) {
		cell.backgroundColor = Assets.Colors.settingsCellBackground(for: traitCollection)
	}

}
