//
//  AccentColorTableViewController.swift
//  NetNewsWire-iOS
//
//  App-wide accent color, mirroring ColorPaletteTableViewController's list-picker pattern exactly --
//  same static-checkmark-row shape, same singular "Cell" reuse identifier
//  convention. Wired into Settings.storyboard as a second row
//  (AppearanceRow.accentColor) below Color Palette in the Appearance
//  section; pushed from SettingsViewController.tableView(_:
//  didSelectRowAt:) the same way Color Palette is.
//
//  Each row's textLabel is followed by a small filled-circle swatch in
//  cell.imageView, so a person can tell Rosé Pine from Slate from Berry
//  without having to select each one and back out to see it take effect --
//  requested alongside the theme-picker dropdown revert. `.default` uses the
//  same asset-catalog colors Assets.swift itself falls back to (AccentColor's
//  own contract: nil hex means "use the asset catalog"), not a placeholder.
//
//  See docs/app-chrome-palette.md ("Badge Colors"): grown from a flat
//  single-section list with unconditional pop-on-select to three sections
//  -- Accent Colors, Badge Colors, Preview -- mirroring
//  ColorPaletteTableViewController's guard-and-reload-in-place selection
//  shape (which itself came from the now-merged SurfacePaletteTableViewController).
//  Accent Color selection no longer
//  pops either -- now that this screen also hosts Badge Colors and Preview,
//  popping on every accent tap kicked the person back out to the main
//  Settings menu before they could reach those. Both sections now reload
//  in place, the same shape.
//

import UIKit
import Articles

final class AccentColorTableViewController: UITableViewController, SettingsPaletteBackgroundHosting {

	var paletteBackgroundView: UIView { tableView }

	private enum Section: Int, CaseIterable {
		case accentColors = 0
		case badgePalette = 1
		case highlightPalette = 2
		case preview = 3
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.register(BadgeColorPalettePreviewCell.self, forCellReuseIdentifier: BadgeColorPalettePreviewCell.reuseIdentifier)
		tableView.register(HighlightPalettePreviewCell.self, forCellReuseIdentifier: HighlightPalettePreviewCell.reuseIdentifier)
		NotificationCenter.default.addObserver(self, selector: #selector(badgeColorModeDidChange(_:)), name: .badgeColorModeDidChange, object: nil)
		// Highlight Palette's own live preview lives in the same .preview
		// section as Badge Colors' -- see tableView(_:cellForRowAt:) below,
		// which distinguishes the two sub-previews inside one section the
		// same way app-chrome-palette.md's "Where it lives in the UI" note
		// anticipated. reloadSections(.preview) already covers both, so no
		// separate reload scope is needed for this notification.
		NotificationCenter.default.addObserver(self, selector: #selector(highlightPaletteDidChange(_:)), name: .highlightPaletteDidChange, object: nil)
		// .accent badges (BadgeColorTable's accentDerived*Backgrounds) are
		// computed from AppDefaults.shared.accentColor, not from
		// badgeColorMode -- so selecting a different Accent Color on this
		// same screen needs its own reload of the Preview section, or an
		// .accent-palette preview would sit stale until the person also
		// touched Badge Colors. See accentColorDidChange below for why
		// this handler deliberately reloads only .preview, not
		// .accentColors.
		NotificationCenter.default.addObserver(self, selector: #selector(accentColorDidChange(_:)), name: .accentColorDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(surfaceTintDidChange(_:)), name: .surfaceTintDidChange, object: nil)
		configureSettingsPaletteBackground()
	}

	@objc private func surfaceTintDidChange(_ note: Notification) {
		refreshPaletteCellBackgrounds()
	}

	// SettingsPaletteBackgroundHosting -- also called on a light/dark trait
	// change now, not just a palette switch; see SettingsBackgroundPalette.swift.
	func refreshPaletteCellBackgrounds() {
		for cell in tableView.visibleCells {
			applySettingsCellBackground(to: cell)
		}
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		guard Section(rawValue: indexPath.section) != .preview else { return } // BadgeColorPalettePreviewCell paints its own swatches
		applySettingsCellBackground(to: cell)
	}

	@objc private func badgeColorModeDidChange(_ note: Notification) {
		tableView.reloadSections(IndexSet(integer: Section.preview.rawValue), with: .none)
	}

	@objc private func highlightPaletteDidChange(_ note: Notification) {
		// Same scope-and-reasoning as badgeColorModeDidChange above: only
		// .preview needs a reload here. didSelectRowAt's own explicit
		// reload already moves the checkmark for a same-screen tap; a
		// second reload of .highlightPalette from this notification would
		// hit the same reentrancy issue accentColorDidChange's own doc
		// comment describes, since AppDefaults.shared.highlightPalette's
		// setter also posts synchronously.
		tableView.reloadSections(IndexSet(integer: Section.preview.rawValue), with: .none)
	}

	@objc private func accentColorDidChange(_ note: Notification) {
		// Reloads .preview only -- matches badgeColorModeDidChange's scope
		// exactly, and deliberately does NOT also reload .accentColors.
		//
		// It used to reload both, on the reasoning that the checkmark
		// needs to move to the newly-selected row. But AppDefaults.shared.
		// accentColor's setter posts this notification synchronously, so
		// when didSelectRowAt below sets accentColor, this handler runs
		// *during* that same didSelectRowAt call -- before didSelectRowAt
		// reaches its own explicit reloadSections call a few lines later.
		// That meant .accentColors got reloadSections'd twice, reentrantly,
		// while UIKit was still in the middle of processing that same
		// section's row selection -- and UIKit's post-selection bookkeeping
		// (restoring highlight/selection state after the delegate call
		// returns) would then apply against a section that had been torn
		// down and rebuilt twice underneath it, landing the checkmark on
		// the previously-selected row instead of the one just tapped.
		//
		// didSelectRowAt's own explicit reload already moves the checkmark
		// correctly for a same-screen tap, exactly once, not reentrantly --
		// this handler only needs to keep Preview in sync, the same as
		// badgeColorModeDidChange does for badge palette changes.
		tableView.reloadSections(IndexSet(integer: Section.preview.rawValue), with: .none)
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return Section.allCases.count
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		switch Section(rawValue: section) {
		case .accentColors, .none:
			return AccentColor.allCases.count
		case .badgePalette:
			return BadgeColorPalette.allCases.count
		case .highlightPalette:
			return HighlightPalette.allCases.count
		case .preview:
			// Two rows, not one: badge-palette preview first (pre-existing),
			// then the highlight-palette swatch preview -- see PreviewRow
			// below for which index is which. Kept as two distinct rows
			// in one section, rather than a single combined cell, so each
			// sub-preview's own reload/measurement logic
			// (BadgeColorPalettePreviewCell.configure()'s self-sizing
			// collection view vs. HighlightPalettePreviewCell's much
			// simpler fixed-height swatch row) stays independent.
			return PreviewRow.allCases.count
		}
	}

	private enum PreviewRow: Int, CaseIterable {
		case badgePalette = 0
		case highlightPalette = 1
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch Section(rawValue: section) {
		case .accentColors, .none:
			return NSLocalizedString("Accent Color", comment: "Accent color section header")
		case .badgePalette:
			return NSLocalizedString("Badge Colors", comment: "Badge color palette section header")
		case .highlightPalette:
			return NSLocalizedString("Highlight Palette", comment: "Highlight palette section header")
		case .preview:
			return NSLocalizedString("Preview", comment: "Badge color palette preview section header")
		}
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		switch Section(rawValue: section) {
		case .badgePalette:
			return NSLocalizedString("Badges appear in the timeline when Tag Display is set to Badges in Timeline Layout. Accent palette badges follow your Accent Color choice above.", comment: "Badge color palette section footer")
		case .highlightPalette:
			return NSLocalizedString("Changes what each of the five highlight colors actually looks like, everywhere a highlight is shown -- the color you pick for a given highlight (yellow, red, green, blue, purple) doesn't change.", comment: "Highlight palette section footer")
		default:
			return nil
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		switch Section(rawValue: indexPath.section) {
		case .preview:
			switch PreviewRow(rawValue: indexPath.row) {
			case .highlightPalette:
				let cell = tableView.dequeueReusableCell(withIdentifier: HighlightPalettePreviewCell.reuseIdentifier, for: indexPath) as! HighlightPalettePreviewCell
				cell.configure()
				return cell
			case .badgePalette, .none:
				let cell = tableView.dequeueReusableCell(withIdentifier: BadgeColorPalettePreviewCell.reuseIdentifier, for: indexPath) as! BadgeColorPalettePreviewCell
				cell.configure()
				return cell
			}
		case .badgePalette:
			let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
			let rowPalette = BadgeColorPalette.allCases[indexPath.row]
			cell.textLabel?.text = rowPalette.description
			cell.imageView?.image = nil
			cell.accessoryType = rowPalette == AppDefaults.shared.badgeColorMode ? .checkmark : .none
			return cell
		case .highlightPalette:
			let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
			let rowPalette = HighlightPalette.allCases[indexPath.row]
			cell.textLabel?.text = rowPalette.description
			cell.imageView?.image = Self.swatchImage(for: rowPalette)
			cell.accessoryType = rowPalette == AppDefaults.shared.highlightPalette ? .checkmark : .none
			return cell
		case .accentColors, .none:
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
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		switch Section(rawValue: indexPath.section) {
		case .accentColors, .none:
			// Was `navigationController?.popViewController(animated: true)`
			// after setting accentColor -- appropriate back when this
			// screen only had one section, but this screen now also
			// hosts Badge Colors and the Preview row, so popping on
			// every accent selection kicked the person back out to the
			// main Settings menu before they could get to those. Reload
			// in place instead, matching how .badgePalette below already
			// behaves.
			//
			// See docs/app-chrome-palette.md ("Badge Colors", reentrancy
			// guards): the row's tap
			// highlight used to rely on the ambient window.tintColor,
			// which SceneDelegate.handleAccentColorDidChange reassigns
			// the instant AppDefaults.shared.accentColor's setter posts
			// .accentColorDidChange (synchronously -- see that setter's
			// own comments). But UIKit's built-in highlight animation
			// had already started rendering with the *old* tint on
			// touch-down, and reloadSections below tears the row down
			// before that animation finishes -- net effect, a truncated
			// flash of a stale color. This screen is choosing the
			// color, so it shouldn't depend on the ambient tint at all:
			// set an explicit selectedBackgroundView sourced from the
			// tapped row's own color before changing accentColor, then
			// hold it briefly before reloading. Matches
			// VibrantTableViewCell.applyThemeProperties()'s established
			// flat, fully-opaque selectedBackgroundView convention, not
			// a new design choice -- sourced from the row's own
			// primaryHex (via the same swatchImage helper) rather than
			// VibrantTableViewCell's ambient secondaryAccent, since here
			// the row *is* the color being chosen.
			guard let accentColor = AccentColor(rawValue: indexPath.row) else { return }

			if let cell = tableView.cellForRow(at: indexPath) {
				let highlightColor = accentColor.primaryHex.flatMap { UIColor(cssHex: $0) } ?? Self.defaultPrimarySwatchColor
				let selectedBackgroundView = UIView(frame: .zero)
				selectedBackgroundView.backgroundColor = highlightColor
				cell.selectedBackgroundView = selectedBackgroundView
			}

			AppDefaults.shared.accentColor = accentColor

			UIView.animate(withDuration: 0.2, delay: 0.15, options: [], animations: {
				tableView.deselectRow(at: indexPath, animated: true)
			}, completion: { _ in
				tableView.reloadSections(IndexSet([Section.accentColors.rawValue, Section.preview.rawValue]), with: .none)
			})
		case .badgePalette:
			// Pre-existing off-by-one, fixed alongside the Badge Colors
			// work (see docs/app-chrome-palette.md, "Badge Colors"): BadgeColorPalette's raw values are 1-based
			// (.monochrome = 1) but indexPath.row is 0-based, so
			// `BadgeColorPalette(rawValue: indexPath.row)` silently no-op'd
			// on row 0 and selected the wrong case on every other row. Row
			// display already uses `BadgeColorPalette.allCases[indexPath.row]`
			// (see tableView(_:cellForRowAt:) above) -- selection now matches
			// that same array-index lookup instead of reusing the row index
			// as a raw value.
			let palette = BadgeColorPalette.allCases[indexPath.row]
			AppDefaults.shared.badgeColorMode = palette
			tableView.reloadSections(IndexSet([Section.badgePalette.rawValue, Section.preview.rawValue]), with: .none)
		case .highlightPalette:
			// Same guard-and-reload-in-place shape as .badgePalette above --
			// AppDefaults.shared.highlightPalette's setter also posts its
			// notification synchronously (highlightPaletteDidChange(_:)
			// above), so this explicit reload is the one that actually
			// moves the checkmark for a same-screen tap; the notification
			// handler only touches .preview, matching accentColorDidChange's
			// reentrancy-guard reasoning.
			let palette = HighlightPalette.allCases[indexPath.row]
			AppDefaults.shared.highlightPalette = palette
			tableView.reloadSections(IndexSet([Section.highlightPalette.rawValue, Section.preview.rawValue]), with: .none)
		case .preview:
			break
		}
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

	/// A row of five small filled circles (yellow/red/green/blue/purple,
	/// matching Annotation.Color's CaseIterable order) for a
	/// HighlightPalette row -- distinct from swatchImage(for:) above
	/// (AccentColor's own two-color split-circle), since a highlight
	/// palette has five independent colors to show at once rather than a
	/// primary/secondary pair. Uses the palette's own darkHexSet when the
	/// current trait collection is dark, lightHexSet otherwise -- table
	/// view cell images don't participate in dynamic-color resolution the
	/// way UIColor(dynamicProvider:) does, so this is resolved once per
	/// dequeue against traitCollection.userInterfaceStyle rather than left
	/// to redraw automatically; a light/dark switch while this screen is
	/// visible reaches this via refreshPaletteCellBackgrounds()'s existing
	/// per-visible-cell pass triggering willDisplay -> this method again on
	/// the next reload, same as swatchImage(for:) above already relies on
	/// for AccentColor rows.
	private static func swatchImage(for highlightPalette: HighlightPalette) -> UIImage {
		let isDark = UITraitCollection.current.userInterfaceStyle == .dark
		let hexSet = highlightPalette.hexSet(isDark: isDark)
		let colors = Annotation.Color.allCases.map { UIColor(cssHex: hexSet[$0]) ?? .systemYellow }

		let diameter: CGFloat = 20
		let spacing: CGFloat = 4
		let size = CGSize(width: CGFloat(colors.count) * diameter + CGFloat(colors.count - 1) * spacing, height: diameter)
		let renderer = UIGraphicsImageRenderer(size: size)
		return renderer.image { context in
			for (index, color) in colors.enumerated() {
				let rect = CGRect(x: CGFloat(index) * (diameter + spacing), y: 0, width: diameter, height: diameter)
				color.setFill()
				context.cgContext.fillEllipse(in: rect)
			}
		}.withRenderingMode(.alwaysOriginal)
	}

}
