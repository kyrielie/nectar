//
//  SettingsCellBackgroundHostingTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for the reported feature request "Slate color palette does not
//  change the color of rows of settings" -- SurfacePalette.HexSet already
//  had settingsCellBackground values, but nothing applied them to
//  individual UITableViewCells. SettingsBackgroundPalette.swift's new
//  applySettingsCellBackground(to:) is the fix; these tests pin its
//  contract directly (a plain UITableViewCell, not a nib-loaded one, so
//  there's no risk of touching unconnected @IBOutlets the way exercising
//  a real Settings.storyboard cell or MainFeedCollectionViewCell would).
//

import Testing
import UIKit
@testable import Nectar

@Suite struct SettingsCellBackgroundHostingTests {

	@MainActor
	private func makeLoadedController() -> SettingsViewController {
		let controller = UIStoryboard.settings.instantiateController(ofType: SettingsViewController.self)
		controller.loadViewIfNeeded()
		controller.viewWillAppear(false)
		return controller
	}

	@MainActor
	@Test func applySettingsCellBackgroundUsesLiveSurfacePaletteColor() {
		defer { AppDefaults.shared.surfaceTint = .default }

		AppDefaults.shared.surfaceTint = .slate
		let controller = makeLoadedController()
		let cell = UITableViewCell(style: .default, reuseIdentifier: nil)

		controller.applySettingsCellBackground(to: cell)

		#expect(cell.backgroundColor == Assets.Colors.settingsCellBackground(for: controller.traitCollection))
	}

	@MainActor
	@Test func willDisplayAppliesSettingsCellBackgroundToRealRows() {
		// Regression for the actual reported symptom: a row scrolling on
		// screen (willDisplay) must get the live palette color, not
		// whatever UIKit's own grouped-cell default is.
		defer { AppDefaults.shared.surfaceTint = .default }

		AppDefaults.shared.surfaceTint = .forest
		let controller = makeLoadedController()
		let cell = UITableViewCell(style: .default, reuseIdentifier: nil)

		controller.tableView(controller.tableView, willDisplay: cell, forRowAt: IndexPath(row: 0, section: 0))

		#expect(cell.backgroundColor == Assets.Colors.settingsCellBackground(for: controller.traitCollection))
	}

	@MainActor
	@Test func settingsCellBackgroundDiffersFromDefaultWhenNonDefaultPaletteIsActive() {
		defer { AppDefaults.shared.surfaceTint = .default }

		let controller = makeLoadedController()
		let defaultCell = UITableViewCell(style: .default, reuseIdentifier: nil)
		controller.applySettingsCellBackground(to: defaultCell)
		let defaultColor = defaultCell.backgroundColor

		AppDefaults.shared.surfaceTint = .berry
		let berryCell = UITableViewCell(style: .default, reuseIdentifier: nil)
		controller.applySettingsCellBackground(to: berryCell)

		#expect(berryCell.backgroundColor != defaultColor)
	}
}
