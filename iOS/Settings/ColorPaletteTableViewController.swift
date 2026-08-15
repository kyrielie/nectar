//
//  ColorPaletteTableViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 3/15/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//
//  surface-palette-and-badge-colors-plan, section 1: absorbs the standalone
//  Surface Palette screen (formerly SurfacePaletteTableViewController,
//  deleted) as a second section here, plus a third section holding the
//  live SurfacePalettePreviewCell -- same three-section shape that screen
//  already had, moved verbatim rather than redesigned. Section 0
//  (UserInterfaceColorPalette, light/dark/automatic) is unchanged.
//
//  nectar-navbar-toggle-plan.md, item 3: the toolbar-style setting is its
//  own section, rather than a row mixed into the Surface Palette list --
//  it's a separate, mutually-exclusive three-way choice (System/Blend/
//  Tinted), not one of the palette choices, and living inside that list
//  read as though it were another palette option.
//
//  toolbar-style-plan.md: replaced the original boolean useTintedNavigationBar
//  UISwitch row with a three-row, checkmark-based picker -- same selection
//  pattern the Surface Palette section below already uses -- once tinting
//  stopped being a single on/off gate and became one of three mutually
//  exclusive toolbar styles (System/Blend/Tinted) applied to both the top
//  nav bar and bottom toolbar together. See SurfacePaletteNavigationBarAware
//  and ArticleViewController.applyToolbarStyle().
//

import UIKit

final class ColorPaletteTableViewController: UITableViewController, SettingsPaletteBackgroundHosting {

	var paletteBackgroundView: UIView { tableView }

	private enum Section: Int, CaseIterable {
		case interfaceStyle = 0
		case toolbarStyle = 1
		case surfacePalette = 2
		case preview = 3
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.register(SurfacePalettePreviewCell.self, forCellReuseIdentifier: SurfacePalettePreviewCell.reuseIdentifier)
		NotificationCenter.default.addObserver(self, selector: #selector(surfaceTintDidChange(_:)), name: .surfaceTintDidChange, object: nil)
		configureSettingsPaletteBackground()
	}

	// surface-palette-followup-plan: guards against the same reentrancy
	// AccentColorTableViewController's accentColorDidChange doc comment
	// describes. AppDefaults.shared.surfaceTint's setter posts
	// .surfaceTintDidChange synchronously, so when didSelectRowAt below
	// sets surfaceTint, this handler runs *during* that same
	// didSelectRowAt call, before didSelectRowAt reaches its own
	// reloadSections a few lines later -- any reloadSections call made
	// here while true tears the table down while UIKit is still in the
	// middle of processing that same row's selection, and its
	// post-selection bookkeeping (restoring the checkmark/highlight after
	// the delegate call returns) then lands against a section that's
	// been rebuilt underneath it, leaving the checkmark on the
	// previously-selected row instead of the one just tapped. Set while
	// didSelectRowAt's .surfacePalette case is running its own deferred
	// reload; that reload already covers .preview too, so this handler
	// only needs to fire for changes that originate elsewhere (e.g. the
	// Surface Palette preview being changed from another screen).
	//
	// The toolbarStyle picker's own didSelectRowAt handling sets this too,
	// for the same reason: toolbarStyle's setter posts .surfaceTintDidChange
	// synchronously as well, same as surfaceTint's own setter.
	private var isHandlingSurfacePaletteSelection = false

	@objc private func surfaceTintDidChange(_ note: Notification) {
		guard !isHandlingSurfacePaletteSelection else { return }
		reloadPreviewSection()
	}

	private func reloadPreviewSection() {
		tableView.reloadSections(IndexSet(integer: Section.preview.rawValue), with: .none)
	}

	// SettingsPaletteBackgroundHosting -- also called on a light/dark trait
	// change, not just a palette switch; see SettingsBackgroundPalette.swift.
	// This screen previously relied on the protocol's no-op default here,
	// which is why its rows never picked up settingsCellBackground at all.
	func refreshPaletteCellBackgrounds() {
		for cell in tableView.visibleCells {
			applySettingsCellBackground(to: cell)
		}
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		guard Section(rawValue: indexPath.section) != .preview else { return } // SurfacePalettePreviewCell paints its own swatches
		applySettingsCellBackground(to: cell)
	}

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
		return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		switch Section(rawValue: section) {
		case .interfaceStyle, .none:
			return UserInterfaceColorPalette.allCases.count
		case .toolbarStyle:
			return ToolbarStyle.allCases.count
		case .surfacePalette:
			return SurfacePalette.allCases.count
		case .preview:
			return 1
		}
    }

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch Section(rawValue: section) {
		case .interfaceStyle, .toolbarStyle, .none:
			return nil
		case .surfacePalette:
			return NSLocalizedString("Surface Palette", comment: "Surface palette section header")
		case .preview:
			return NSLocalizedString("Preview", comment: "Surface palette preview section header")
		}
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		switch Section(rawValue: section) {
		case .toolbarStyle:
			return NSLocalizedString("Default: the top navigation bar and bottom toolbar use plain system appearance. Blend: both bars match the current article's background color. Tinted: both bars pick up the Surface Palette's tint color.", comment: "Toolbar style picker footer")
		default:
			return nil
		}
	}

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		switch Section(rawValue: indexPath.section) {
		case .preview:
			let cell = tableView.dequeueReusableCell(withIdentifier: SurfacePalettePreviewCell.reuseIdentifier, for: indexPath) as! SurfacePalettePreviewCell
			cell.configure()
			return cell
		case .toolbarStyle:
			let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
			let rowStyle = ToolbarStyle.allCases[indexPath.row]
			cell.textLabel?.text = rowStyle.description
			cell.accessoryType = rowStyle == AppDefaults.shared.toolbarStyle ? .checkmark : .none
			return cell
		case .surfacePalette:
			let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
			let rowSurfacePalette = SurfacePalette.allCases[indexPath.row]
			cell.textLabel?.text = rowSurfacePalette.description
			cell.accessoryType = rowSurfacePalette == AppDefaults.shared.surfaceTint ? .checkmark : .none
			return cell
		case .interfaceStyle, .none:
			let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
			let rowColorPalette = UserInterfaceColorPalette.allCases[indexPath.row]
			cell.textLabel?.text = String(describing: rowColorPalette)
			if rowColorPalette == AppDefaults.userInterfaceColorPalette {
				cell.accessoryType = .checkmark
			} else {
				cell.accessoryType = .none
			}
			return cell
		}
    }

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		switch Section(rawValue: indexPath.section) {
		case .interfaceStyle, .none:
			if let colorPalette = UserInterfaceColorPalette(rawValue: indexPath.row) {
				AppDefaults.userInterfaceColorPalette = colorPalette
			}
			tableView.reloadSections(IndexSet(integer: Section.interfaceStyle.rawValue), with: .none)
		case .toolbarStyle:
			let style = ToolbarStyle.allCases[indexPath.row]

			isHandlingSurfacePaletteSelection = true
			AppDefaults.shared.toolbarStyle = style
			isHandlingSurfacePaletteSelection = false

			// Same reasoning as the .surfacePalette case below: one combined
			// reload, after setting, covering both the row that changed and
			// the preview -- not two separate reloadSections calls that could
			// race with UIKit's own post-selection checkmark bookkeeping.
			tableView.reloadSections(IndexSet([Section.toolbarStyle.rawValue, Section.preview.rawValue]), with: .none)
		case .surfacePalette:
			guard let surfacePalette = SurfacePalette(rawValue: indexPath.row) else { return }

			isHandlingSurfacePaletteSelection = true
			AppDefaults.shared.surfaceTint = surfacePalette
			isHandlingSurfacePaletteSelection = false

			// Reload after setting, not before -- and in one call covering
			// both sections, so this is the only reloadSections touching
			// .surfacePalette during this selection (see
			// isHandlingSurfacePaletteSelection's doc comment above).
			tableView.reloadSections(IndexSet([Section.surfacePalette.rawValue, Section.preview.rawValue]), with: .none)
		case .preview:
			break
		}
	}

}
