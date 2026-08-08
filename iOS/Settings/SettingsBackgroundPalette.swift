//
//  SettingsBackgroundPalette.swift
//  NetNewsWire-iOS
//
//  surface-palette-and-badge-colors-plan, section 2.3. Shared wiring for
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
}

extension SettingsPaletteBackgroundHosting {

	/// Call once from `viewDidLoad()`.
	func configureSettingsPaletteBackground() {
		applySettingsPaletteBackground()

		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
			guard self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle else { return }
			self.applySettingsPaletteBackground()
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
