//
//  SurfaceTintTableViewController.swift
//  NetNewsWire-iOS
//
//  Nectar Theming plan §6.3 ("Native UI surface color system").
//  Direct copy of AccentColorTableViewController's list-picker pattern with
//  AccentColor replaced by SurfaceTint -- same static-checkmark-row shape,
//  same push/pop navigation, same singular "Cell" reuse identifier
//  convention. Wired into Settings.storyboard as a third row
//  (AppearanceRow.surfaceTint) below Accent Color in the Appearance section;
//  pushed from SettingsViewController.tableView(_:didSelectRowAt:) the same
//  way Accent Color is.
//

import UIKit

final class SurfaceTintTableViewController: UITableViewController {

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return SurfaceTint.allCases.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
		let rowSurfaceTint = SurfaceTint.allCases[indexPath.row]
		cell.textLabel?.text = rowSurfaceTint.description
		cell.accessoryType = rowSurfaceTint == AppDefaults.shared.surfaceTint ? .checkmark : .none
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if let surfaceTint = SurfaceTint(rawValue: indexPath.row) {
			AppDefaults.shared.surfaceTint = surfaceTint
		}
		navigationController?.popViewController(animated: true)
	}

}
