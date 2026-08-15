//
//  ToolbarStylePickerSelectionTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for ColorPaletteTableViewController's toolbarStyle section --
//  toolbar-style-plan.md, section 2.7 -- exercised the same way
//  AccentColorTableViewControllerSelectionTests.swift covers that screen's
//  own selection/reentrancy contract: directly against the controller, no
//  navigation controller or UI test harness, since this is about state
//  (AppDefaults.shared.toolbarStyle and which row shows the checkmark) not
//  animation.
//

import Testing
import UIKit
@testable import Nectar

@Suite struct ToolbarStylePickerSelectionTests {

	@MainActor
	private func makeLoadedController() -> ColorPaletteTableViewController {
		let controller = UIStoryboard.settings.instantiateController(ofType: ColorPaletteTableViewController.self)
		controller.loadViewIfNeeded()
		return controller
	}

	private static let toolbarStyleSection = 1 // ColorPaletteTableViewController.Section.toolbarStyle

	@MainActor
	@Test func rowCountMatchesToolbarStyleCaseCount() {
		let controller = makeLoadedController()
		#expect(controller.tableView(controller.tableView, numberOfRowsInSection: Self.toolbarStyleSection) == ToolbarStyle.allCases.count)
	}

	@MainActor
	@Test func selectingARowUpdatesAppDefaultsAndMovesTheCheckmark() {
		defer { AppDefaults.shared.toolbarStyle = .system }

		let controller = makeLoadedController()

		guard let blendRow = ToolbarStyle.allCases.firstIndex(of: .blend) else {
			Issue.record("ToolbarStyle.blend missing from allCases")
			return
		}
		let indexPath = IndexPath(row: blendRow, section: Self.toolbarStyleSection)
		controller.tableView(controller.tableView, didSelectRowAt: indexPath)

		#expect(AppDefaults.shared.toolbarStyle == .blend)

		let cell = controller.tableView(controller.tableView, cellForRowAt: indexPath)
		#expect(cell.accessoryType == .checkmark)
		#expect(cell.textLabel?.text == ToolbarStyle.blend.description)
	}

	@MainActor
	@Test func selectingASecondRowLandsOnTheNewSelectionNotThePrevious() {
		// Same reentrancy-regression shape as
		// AccentColorTableViewControllerSelectionTests.selectingASecondAccentColorLandsOnTheNewSelectionNotThePrevious --
		// toolbarStyle's setter posts .surfaceTintDidChange synchronously,
		// same as surfaceTint's own setter, so this picker needs the same
		// isHandlingSurfacePaletteSelection guard the Surface Palette rows
		// already have. Pin the end-to-end contract: select Tinted, then
		// Blend, and only Blend's row ends up checked.
		defer { AppDefaults.shared.toolbarStyle = .system }

		let controller = makeLoadedController()

		guard let tintedRow = ToolbarStyle.allCases.firstIndex(of: .tinted),
			  let blendRow = ToolbarStyle.allCases.firstIndex(of: .blend) else {
			Issue.record("ToolbarStyle missing expected cases")
			return
		}

		let tintedIndexPath = IndexPath(row: tintedRow, section: Self.toolbarStyleSection)
		controller.tableView(controller.tableView, didSelectRowAt: tintedIndexPath)
		#expect(AppDefaults.shared.toolbarStyle == .tinted)

		let blendIndexPath = IndexPath(row: blendRow, section: Self.toolbarStyleSection)
		controller.tableView(controller.tableView, didSelectRowAt: blendIndexPath)
		#expect(AppDefaults.shared.toolbarStyle == .blend)

		let blendCell = controller.tableView(controller.tableView, cellForRowAt: blendIndexPath)
		#expect(blendCell.accessoryType == .checkmark)

		let tintedCell = controller.tableView(controller.tableView, cellForRowAt: tintedIndexPath)
		#expect(tintedCell.accessoryType == .none)
	}
}
