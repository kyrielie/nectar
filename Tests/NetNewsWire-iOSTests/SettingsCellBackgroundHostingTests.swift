//
//  SettingsCellBackgroundHostingTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for SettingsPaletteBackgroundHosting's applySettingsCellBackground(to:)
//  contract used by UIKit settings controllers (ManageStorage, TimelineCustomizer,
//  ToolbarsCustomizer).
//

import Testing
import UIKit
@testable import Nectar

@Suite struct SettingsCellBackgroundHostingTests {

	@MainActor
	private func makeHostedController() -> ManageStorageCollectionViewController {
		let controller = ManageStorageCollectionViewController()
		controller.loadViewIfNeeded()
		return controller
	}

	@MainActor
	@Test func applySettingsCellBackgroundUsesLiveSurfacePaletteColor() {
		defer { AppDefaults.shared.surfaceTint = .default }

		AppDefaults.shared.surfaceTint = .slate
		let controller = makeHostedController()
		let cell = UITableViewCell(style: .default, reuseIdentifier: nil)

		controller.applySettingsCellBackground(to: cell)

		#expect(cell.backgroundColor == Assets.Colors.settingsCellBackground(for: controller.traitCollection))
	}

	@MainActor
	@Test func settingsCellBackgroundDiffersFromDefaultWhenNonDefaultPaletteIsActive() {
		defer { AppDefaults.shared.surfaceTint = .default }

		let controller = makeHostedController()
		let defaultCell = UITableViewCell(style: .default, reuseIdentifier: nil)
		controller.applySettingsCellBackground(to: defaultCell)
		let defaultColor = defaultCell.backgroundColor

		AppDefaults.shared.surfaceTint = .berry
		let berryCell = UITableViewCell(style: .default, reuseIdentifier: nil)
		controller.applySettingsCellBackground(to: berryCell)

		#expect(berryCell.backgroundColor != defaultColor)
	}
}
