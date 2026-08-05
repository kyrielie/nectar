//
//  AccentColorTableViewController.swift
//  NetNewsWire-iOS
//
//  Personalization & Theming plan, item 3 ("App-wide accent color").
//  Mirrors ColorPaletteTableViewController's list-picker pattern exactly --
//  same static-checkmark-row shape, same push/pop navigation, same singular
//  "Cell" reuse identifier convention. Wired into Settings.storyboard as a
//  second row (AppearanceRow.accentColor) below Color Palette in the
//  Appearance section; pushed from SettingsViewController.tableView(_:
//  didSelectRowAt:) the same way Color Palette is.
//

import UIKit

final class AccentColorTableViewController: UITableViewController {

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return AccentColor.allCases.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
		let rowAccentColor = AccentColor.allCases[indexPath.row]
		cell.textLabel?.text = rowAccentColor.description
		if rowAccentColor == AppDefaults.shared.accentColor {
			cell.accessoryType = .checkmark
		} else {
			cell.accessoryType = .none
		}
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if let accentColor = AccentColor(rawValue: indexPath.row) {
			AppDefaults.shared.accentColor = accentColor
		}
		navigationController?.popViewController(animated: true)
	}

}
