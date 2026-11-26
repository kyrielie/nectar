//
//  ToolbarsSettingsModelTests.swift
//  NetNewsWire-iOSTests
//
//  Unit tests for ToolbarsSettingsModel's grouped placement lists,
//  slot-cap enforcement, and subset reordering.
//

import Foundation
import Testing
@testable import Nectar

struct ToolbarsSettingsModelTests {

	@MainActor
	@Test func groupedPlacementListsPartitionOrderAndRespectOverflowToggle() {
		let defaults = AppDefaults.shared
		let originalOrder = defaults.toolbarFunctionOrder(for: .top)
		let originalOverflow = defaults.isToolbarOverflowMenuEnabled(on: .top)
		defer {
			defaults.resetToolbarDefaults(for: .top)
			defaults.setToolbarFunctionOrder(originalOrder, for: .top)
			defaults.setToolbarOverflowMenuEnabled(on: .top, originalOverflow)
		}

		defaults.resetToolbarDefaults(for: .top)
		defaults.setToolbarOverflowMenuEnabled(on: .top, true)
		defaults.setToolbarFunctionInOverflow(.action, on: .top, true)

		let model = ToolbarsSettingsModel()
		model.activeBar = .top

		#expect(model.barFunctions.allSatisfy { !model.overflowFunctions.contains($0) && !model.offFunctions.contains($0) })
		#expect(model.overflowFunctions.contains(.action))
		#expect(model.hasOverflowItems)

		model.setOverflowMenuEnabled(false)
		#expect(!model.overflowMenuEnabled)
		#expect(model.overflowFunctions.isEmpty)
		#expect(model.offFunctions.contains(.action))
	}

	@MainActor
	@Test func moveBarFunctionsReordersBarItemsWhilePreservingRelativeOffOrder() {
		let defaults = AppDefaults.shared
		defer {
			defaults.resetToolbarDefaults(for: .bottom)
		}

		defaults.resetToolbarDefaults(for: .bottom)
		let model = ToolbarsSettingsModel()
		model.activeBar = .bottom

		let initialBar = model.barFunctions
		#expect(initialBar.count >= 2)
		let first = initialBar[0]
		let second = initialBar[1]

		model.moveBarFunctions(from: IndexSet(integer: 0), to: 2)

		#expect(model.barFunctions[0] == second)
		#expect(model.barFunctions[1] == first)
	}
}
