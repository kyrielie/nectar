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
//  Each row's textLabel is followed by a small filled-circle swatch in
//  cell.imageView, so a person can tell Rosé Pine from Slate from Berry
//  without having to select each one and back out to see it take effect --
//  requested alongside the theme-picker dropdown revert. `.default` uses the
//  same asset-catalog colors Assets.swift itself falls back to (AccentColor's
//  own contract: nil hex means "use the asset catalog"), not a placeholder.
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
		cell.imageView?.image = Self.swatchImage(for: rowAccentColor)
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

	// MARK: - Swatch

	private static let swatchDiameter: CGFloat = 28
	private static let defaultPrimarySwatchColor = UIColor(named: "primaryAccentColor") ?? .systemBlue
	private static let defaultSecondarySwatchColor = UIColor(named: "secondaryAccentColor") ?? .systemTeal

	/// A filled circle, split diagonally between `primaryHex`/`secondaryHex` when
	/// both are present, otherwise a solid circle -- reusing the exact colors
	/// AccentColor already applies to icons/progress fill, not a separately
	/// invented preview palette.
	private static func swatchImage(for accentColor: AccentColor) -> UIImage {
		let primary = accentColor.primaryHex.flatMap { UIColor(cssHex: $0) } ?? defaultPrimarySwatchColor
		let secondary = accentColor.secondaryHex.flatMap { UIColor(cssHex: $0) } ?? defaultSecondarySwatchColor

		let rect = CGRect(x: 0, y: 0, width: swatchDiameter, height: swatchDiameter)
		let renderer = UIGraphicsImageRenderer(size: rect.size)
		return renderer.image { context in
			let cgContext = context.cgContext
			let ellipsePath = UIBezierPath(ovalIn: rect).cgPath

			cgContext.saveGState()
			cgContext.addPath(ellipsePath)
			cgContext.clip()

			cgContext.addPath(UIBezierPath(rect: CGRect(x: 0, y: 0, width: swatchDiameter, height: swatchDiameter / 2)).cgPath)
			cgContext.setFillColor(primary.cgColor)
			cgContext.fillPath()

			cgContext.addPath(UIBezierPath(rect: CGRect(x: 0, y: swatchDiameter / 2, width: swatchDiameter, height: swatchDiameter / 2)).cgPath)
			cgContext.setFillColor(secondary.cgColor)
			cgContext.fillPath()

			cgContext.restoreGState()

			UIColor.separator.setStroke()
			let strokePath = UIBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
			strokePath.lineWidth = 1
			strokePath.stroke()
		}.withRenderingMode(.alwaysOriginal)
	}

}
