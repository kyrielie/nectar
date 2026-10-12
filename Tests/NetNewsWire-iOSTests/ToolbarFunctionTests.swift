//
//  ToolbarFunctionTests.swift
//  NetNewsWire-iOSTests
//
//  Guards the toolbar function table that every ToolbarFunction case has to be
//  added to by hand (title, icon, four UserDefaults keys, the backup allowlist,
//  bar button items). A missed entry would otherwise surface as a fatalError in
//  AppDefaults.toolbarKeys or as a setting that silently never backs up.
//
//  Reads UserDefaults only; nothing here writes.
//

import Foundation
import Testing
@testable import Nectar

@Suite struct ToolbarFunctionTests {

	@Test func everyFunctionResolvesKeysOnBothBars() {
		// toolbarKeys(_:_:) is a fatalError on a missing table entry, so simply
		// reaching the end of this loop is the assertion.
		for function in ToolbarFunction.allCases {
			for bar in [ToolbarBar.top, ToolbarBar.bottom] {
				_ = AppDefaults.shared.isToolbarFunctionEnabled(function, on: bar)
				_ = AppDefaults.shared.isToolbarFunctionInOverflow(function, on: bar)
			}
		}
	}

	@Test func everyFunctionHasATitle() {
		for function in ToolbarFunction.allCases {
			#expect(!function.title.isEmpty)
		}
	}

	@Test func defaultOrderListsEveryFunctionExactlyOnce() {
		for bar in [ToolbarBar.top, ToolbarBar.bottom] {
			let order = AppDefaults.defaultToolbarFunctionOrder(for: bar)
			#expect(order.count == ToolbarFunction.allCases.count)
			#expect(Set(order).count == order.count)
		}
	}

	@Test func ignoreFunctionIsLastInTheDefaultOrderOfBothBars() {
		// New cases take the tail of the default order, so adding one does not
		// move any function the person has already seen in a fixed position.
		for bar in [ToolbarBar.top, ToolbarBar.bottom] {
			#expect(AppDefaults.defaultToolbarFunctionOrder(for: bar).last == .ignore)
		}
	}

	@Test func ignoreFunctionKeysAreBackedUp() {
		let keys = [
			AppDefaults.Key.toolbarFnIgnoreTop,
			AppDefaults.Key.toolbarFnIgnoreTopOverflow,
			AppDefaults.Key.toolbarFnIgnoreBottom,
			AppDefaults.Key.toolbarFnIgnoreBottomOverflow
		]
		for key in keys {
			#expect(AppDefaults.backupEligibleKeys.contains(key))
		}
	}

	@Test func ignoreFunctionPersistedStringsAreFrozen() {
		// These are stored in people's toolbar settings once shipped.
		#expect(ToolbarFunction.ignore.rawValue == "ignore")
		#expect(AppDefaults.Key.toolbarFnIgnoreTop == "toolbarFnIgnoreTop")
		#expect(AppDefaults.Key.toolbarFnIgnoreTopOverflow == "toolbarFnIgnoreTopOverflow")
		#expect(AppDefaults.Key.toolbarFnIgnoreBottom == "toolbarFnIgnoreBottom")
		#expect(AppDefaults.Key.toolbarFnIgnoreBottomOverflow == "toolbarFnIgnoreBottomOverflow")
	}

	@Test @MainActor func ignoreActionsAreUnavailableWithoutAnArticle() {
		#expect(!ArticleIgnoreActions.isAvailable(for: nil))
	}
}
