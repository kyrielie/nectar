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

	@objc private func surfaceTintDidChange(_ note: Notification) {
		reloadPreviewSection()
	}

	private func reloadPreviewSection() {
		tableView.reloadSections(IndexSet(integer: Section.preview.rawValue), with: .none)
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
			return SurfacePalette.allCases.count
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
		case .surfacePalette:
			if let surfacePalette = SurfacePalette(rawValue: indexPath.row) {
				AppDefaults.shared.surfaceTint = surfacePalette
			}
			tableView.reloadSections(IndexSet(integer: Section.surfacePalette.rawValue), with: .none)
		case .preview:
			break
		}
	}

}
