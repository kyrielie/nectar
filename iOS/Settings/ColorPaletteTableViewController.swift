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

import UIKit

final class ColorPaletteTableViewController: UITableViewController, SettingsPaletteBackgroundHosting {

	var paletteBackgroundView: UIView { tableView }

	private enum Section: Int, CaseIterable {
		case interfaceStyle = 0
		case surfacePalette = 1
		case preview = 2
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
		case .surfacePalette:
			// +1 for the "Tinted Navigation Bar" toggle row, above the palette list.
			return SurfacePalette.allCases.count + 1
		case .preview:
			return 1
		}
    }

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch Section(rawValue: section) {
		case .interfaceStyle, .none:
			return nil
		case .surfacePalette:
			return NSLocalizedString("Surface Palette", comment: "Surface palette section header")
		case .preview:
			return NSLocalizedString("Preview", comment: "Surface palette preview section header")
		}
	}

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		switch Section(rawValue: indexPath.section) {
		case .preview:
			let cell = tableView.dequeueReusableCell(withIdentifier: SurfacePalettePreviewCell.reuseIdentifier, for: indexPath) as! SurfacePalettePreviewCell
			cell.configure()
			return cell
		case .surfacePalette:
			let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
			if indexPath.row == 0 {
				cell.textLabel?.text = NSLocalizedString("Tinted Navigation Bar", comment: "Tinted navigation bar toggle row")
				cell.accessoryType = AppDefaults.shared.useTintedNavigationBar ? .checkmark : .none
				return cell
			}
			let rowSurfacePalette = SurfacePalette.allCases[indexPath.row - 1]
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
		case .surfacePalette:
			if indexPath.row == 0 {
				// Same reentrancy guard as the palette rows below: useTintedNavigationBar's
				// setter now posts .surfaceTintDidChange synchronously too, and this
				// screen's own surfaceTintDidChange(_:) handler would otherwise reenter
				// mid-selection the same way isHandlingSurfacePaletteSelection's doc
				// comment describes for the palette rows themselves.
				isHandlingSurfacePaletteSelection = true
				AppDefaults.shared.useTintedNavigationBar.toggle()
				isHandlingSurfacePaletteSelection = false

				tableView.reloadSections(IndexSet([Section.surfacePalette.rawValue, Section.preview.rawValue]), with: .none)
				return
			}

			guard let surfacePalette = SurfacePalette(rawValue: indexPath.row - 1) else { return }

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
