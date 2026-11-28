//
//  AppDefaults+Toolbars.swift
//  Nectar
//

import Foundation

extension AppDefaults {

	/// Table-driven key lookup for the unified toolbar model: (inline key,
	/// overflow key) per (ToolbarFunction, ToolbarBar). A hand-written
	/// per-function x 2-bar x 2-role switch would be dozens of near-identical
	/// cases; this keeps the mapping in one place and the read/write
	/// dispatch functions below as thin wrappers. Force-unwrapped
	/// dictionary lookups are safe here because ToolbarFunction/ToolbarBar
	/// are both closed enums fully enumerated in toolbarFunctionKeys'
	/// literal below -- AppDefaultsBackupTests / a unit test should assert
	/// every ToolbarFunction x ToolbarBar pair resolves, so an
	/// accidentally-omitted case fails a test rather than crashing at
	/// runtime on first use.
	private static let toolbarFunctionKeys: [ToolbarFunction: [ToolbarBar: (inline: String, overflow: String)]] = [
		.theme: [.top: (Key.toolbarFnThemeTop, Key.toolbarFnThemeTopOverflow), .bottom: (Key.toolbarFnThemeBottom, Key.toolbarFnThemeBottomOverflow)],
		.tableOfContents: [.top: (Key.toolbarFnTableOfContentsTop, Key.toolbarFnTableOfContentsTopOverflow), .bottom: (Key.toolbarFnTableOfContentsBottom, Key.toolbarFnTableOfContentsBottomOverflow)],
		.find: [.top: (Key.toolbarFnFindTop, Key.toolbarFnFindTopOverflow), .bottom: (Key.toolbarFnFindBottom, Key.toolbarFnFindBottomOverflow)],
		.prevNext: [.top: (Key.toolbarFnPrevNextTop, Key.toolbarFnPrevNextTopOverflow), .bottom: (Key.toolbarFnPrevNextBottom, Key.toolbarFnPrevNextBottomOverflow)],
		.lock: [.top: (Key.toolbarFnLockTop, Key.toolbarFnLockTopOverflow), .bottom: (Key.toolbarFnLockBottom, Key.toolbarFnLockBottomOverflow)],
		.annotations: [.top: (Key.toolbarFnAnnotationsTop, Key.toolbarFnAnnotationsTopOverflow), .bottom: (Key.toolbarFnAnnotationsBottom, Key.toolbarFnAnnotationsBottomOverflow)],
		.settings: [.top: (Key.toolbarFnSettingsTop, Key.toolbarFnSettingsTopOverflow), .bottom: (Key.toolbarFnSettingsBottom, Key.toolbarFnSettingsBottomOverflow)],
		.checkForUpdates: [.top: (Key.toolbarFnCheckForUpdatesTop, Key.toolbarFnCheckForUpdatesTopOverflow), .bottom: (Key.toolbarFnCheckForUpdatesBottom, Key.toolbarFnCheckForUpdatesBottomOverflow)],
		.read: [.top: (Key.toolbarFnReadTop, Key.toolbarFnReadTopOverflow), .bottom: (Key.toolbarFnReadBottom, Key.toolbarFnReadBottomOverflow)],
		.star: [.top: (Key.toolbarFnStarTop, Key.toolbarFnStarTopOverflow), .bottom: (Key.toolbarFnStarBottom, Key.toolbarFnStarBottomOverflow)],
		.heart: [.top: (Key.toolbarFnHeartTop, Key.toolbarFnHeartTopOverflow), .bottom: (Key.toolbarFnHeartBottom, Key.toolbarFnHeartBottomOverflow)],
		.nextUnread: [.top: (Key.toolbarFnNextUnreadTop, Key.toolbarFnNextUnreadTopOverflow), .bottom: (Key.toolbarFnNextUnreadBottom, Key.toolbarFnNextUnreadBottomOverflow)],
		.action: [.top: (Key.toolbarFnActionTop, Key.toolbarFnActionTopOverflow), .bottom: (Key.toolbarFnActionBottom, Key.toolbarFnActionBottomOverflow)],
		.scrollBack: [.top: (Key.toolbarFnScrollBackTop, Key.toolbarFnScrollBackTopOverflow), .bottom: (Key.toolbarFnScrollBackBottom, Key.toolbarFnScrollBackBottomOverflow)],
		.scrollToTop: [.top: (Key.toolbarFnScrollToTopTop, Key.toolbarFnScrollToTopTopOverflow), .bottom: (Key.toolbarFnScrollToTopBottom, Key.toolbarFnScrollToTopBottomOverflow)],
		.scrollToBottom: [.top: (Key.toolbarFnScrollToBottomTop, Key.toolbarFnScrollToBottomTopOverflow), .bottom: (Key.toolbarFnScrollToBottomBottom, Key.toolbarFnScrollToBottomBottomOverflow)],
		.readingTimeRemaining: [.top: (Key.toolbarFnReadingTimeRemainingTop, Key.toolbarFnReadingTimeRemainingTopOverflow), .bottom: (Key.toolbarFnReadingTimeRemainingBottom, Key.toolbarFnReadingTimeRemainingBottomOverflow)],
		.readingStats: [.top: (Key.toolbarFnReadingStatsTop, Key.toolbarFnReadingStatsTopOverflow), .bottom: (Key.toolbarFnReadingStatsBottom, Key.toolbarFnReadingStatsBottomOverflow)],
		.ignore: [.top: (Key.toolbarFnIgnoreTop, Key.toolbarFnIgnoreTopOverflow), .bottom: (Key.toolbarFnIgnoreBottom, Key.toolbarFnIgnoreBottomOverflow)],
		.workInfo: [.top: (Key.toolbarFnWorkInfoTop, Key.toolbarFnWorkInfoTopOverflow), .bottom: (Key.toolbarFnWorkInfoBottom, Key.toolbarFnWorkInfoBottomOverflow)]
	]

	private func toolbarKeys(_ function: ToolbarFunction, _ bar: ToolbarBar) -> (inline: String, overflow: String) {
		guard let keys = AppDefaults.toolbarFunctionKeys[function]?[bar] else {
			fatalError("Missing toolbarFunctionKeys entry for \(function)/\(bar) -- every ToolbarFunction x ToolbarBar pair must be present in the table above.")
		}
		return keys
	}

	/// Whether `function` is placed inline (not in the overflow menu) on
	/// `bar`. Used anywhere placement needs to be read generically --
	/// ToolbarsCustomizerViewController's row loop, ArticleViewController's
	/// bar-building, SettingsViewController's summary label -- instead of
	/// a per-function switch at each call site.
	func isToolbarFunctionEnabled(_ function: ToolbarFunction, on bar: ToolbarBar) -> Bool {
		AppDefaults.bool(for: toolbarKeys(function, bar).inline)
	}

	/// Setting a function inline on a bar also clears that same function's
	/// overflow flag on that same bar -- inline and overflow are mutually
	/// exclusive *per bar* (the ToolbarsCustomizerViewController mockup's
	/// rule: an overflow-menu table only offers functions not already
	/// placed inline in that same bar). This enforces the invariant at
	/// the model layer, not just in the UI that happens to filter the
	/// overflow list -- a future direct writer of this property can't
	/// leave both flags set for the same (function, bar).
	func setToolbarFunctionEnabled(_ function: ToolbarFunction, on bar: ToolbarBar, _ enabled: Bool) {
		let keys = toolbarKeys(function, bar)
		AppDefaults.setBool(for: keys.inline, enabled)
		if enabled {
			AppDefaults.setBool(for: keys.overflow, false)
		}
	}

	/// Whether `function` is placed in `bar`'s overflow menu. Only
	/// meaningful when that bar's own toolbarTopUseOverflowMenu/
	/// toolbarBottomUseOverflowMenu is also true -- ToolbarsCustomizerViewController
	/// hides the overflow-picks section entirely when the bar's overflow
	/// switch is off, same as this property being false for everything
	/// in that state.
	func isToolbarFunctionInOverflow(_ function: ToolbarFunction, on bar: ToolbarBar) -> Bool {
		AppDefaults.bool(for: toolbarKeys(function, bar).overflow)
	}

	/// Setting a function into a bar's overflow also clears that same
	/// function's inline flag on that same bar -- same mutual-exclusion
	/// invariant as setToolbarFunctionEnabled(_:on:_:) above, enforced
	/// symmetrically from this direction too.
	func setToolbarFunctionInOverflow(_ function: ToolbarFunction, on bar: ToolbarBar, _ inOverflow: Bool) {
		let keys = toolbarKeys(function, bar)
		AppDefaults.setBool(for: keys.overflow, inOverflow)
		if inOverflow {
			AppDefaults.setBool(for: keys.inline, false)
		}
	}

	/// Slots `function` costs toward its bar's icon cap when placed
	/// inline -- prevNext counts as 2 (it renders both prev and next as
	/// separate bar items), everything else counts as 1. Does not apply
	/// to overflow placement (see ToolbarsCustomizerViewController's cap
	/// logic: the cap protects each bar's fixed-width leading/trailing
	/// icon cluster, and a function inside the overflow menu doesn't
	/// occupy a slot in that cluster).
	static func toolbarFunctionSlotCost(_ function: ToolbarFunction) -> Int {
		function == .prevNext ? 2 : 1
	}

	/// Shipped default display order per bar -- also what registerDefaults()
	/// seeds the persisted order keys to, and what resetToolbarDefaults(for:)
	/// restores by removing the persisted key entirely (so the default only
	/// has to be correct in this one place). Matches the pre-order-persistence
	/// hardcoded arrays that used to live independently in
	/// ArticleViewController.displayOrder(for:) and ToolbarPreviewCell.configure(bar:).
	static func defaultToolbarFunctionOrder(for bar: ToolbarBar) -> [ToolbarFunction] {
		let native: [ToolbarFunction] = bar == .top
			? [.theme, .tableOfContents, .find, .prevNext, .lock, .annotations, .settings, .checkForUpdates]
			: [.read, .star, .heart, .nextUnread, .action]
		let rest = ToolbarFunction.allCases.filter { !native.contains($0) }
		return native + rest
	}

	/// The person's current display order for `bar` -- read by
	/// ArticleViewController.displayOrder(for:) (the real reader),
	/// ToolbarPreviewCell.configure(bar:) (the settings preview), and
	/// ToolbarsCustomizerViewController's functions table (the reorderable
	/// list itself), so all three stay on one source instead of the three
	/// independent hardcoded arrays this replaced.
	///
	/// Decodes the persisted rawValue array back into ToolbarFunction,
	/// silently dropping any string that no longer maps to a case (e.g.
	/// a case removed in a future version) and appending, in
	/// defaultToolbarFunctionOrder(for:) order, any ToolbarFunction
	/// missing from the stored array (covers a case added after someone
	/// already saved a custom order, and covers a first run before
	/// registerDefaults() has populated the key in an unregistered
	/// UserDefaults suite such as a unit test).
	func toolbarFunctionOrder(for bar: ToolbarBar) -> [ToolbarFunction] {
		let key = bar == .top ? Key.toolbarTopFunctionOrder : Key.toolbarBottomFunctionOrder
		let stored = (AppDefaults.stringArray(for: key) ?? []).compactMap { ToolbarFunction(rawValue: $0) }
		let missing = ToolbarFunction.allCases.filter { !stored.contains($0) }
		return stored + AppDefaults.defaultToolbarFunctionOrder(for: bar).filter { missing.contains($0) }
	}

	/// Persists a new display order for `bar` -- written by
	/// ToolbarsCustomizerViewController's collectionView(_:moveItemAt:to:)
	/// after a drag-reorder. `order` should contain every ToolbarFunction
	/// exactly once; toolbarFunctionOrder(for:) tolerates a short/stale
	/// array on read, but callers should still pass a complete list.
	func setToolbarFunctionOrder(_ order: [ToolbarFunction], for bar: ToolbarBar) {
		let key = bar == .top ? Key.toolbarTopFunctionOrder : Key.toolbarBottomFunctionOrder
		AppDefaults.setStringArray(for: key, order.map(\.rawValue))
	}

	/// Resets every ToolbarFunction's placement (inline/overflow, both
	/// cleared to off), that bar's overflow-menu switch, and that bar's
	/// display order back to the shipped defaults -- scoped to `bar`
	/// only, matching ToolbarsCustomizerViewController's per-bar-tab
	/// framing (its "Reset" button resets whichever bar is active, not
	/// both at once).
	///
	/// Implemented as key removal, not as re-writing the literal default
	/// values -- removing a UserDefaults key falls back to whatever
	/// registerDefaults() already registered for it, so the default only
	/// needs to be correct in registerDefaults() (for placement/overflow)
	/// and defaultToolbarFunctionOrder(for:) (for order), not duplicated
	/// a third time here. UserDefaults.removeObject(forKey:) posts
	/// .didChangeNotification on .standard, so
	/// ToolbarsCustomizerViewController's existing generic-notification
	/// reload picks this up with no additional wiring.
	func resetToolbarDefaults(for bar: ToolbarBar) {
		for function in ToolbarFunction.allCases {
			let keys = toolbarKeys(function, bar)
			AppDefaults.store.removeObject(forKey: keys.inline)
			AppDefaults.store.removeObject(forKey: keys.overflow)
		}
		let overflowKey = bar == .top ? Key.toolbarTopUseOverflowMenu : Key.toolbarBottomUseOverflowMenu
		AppDefaults.store.removeObject(forKey: overflowKey)
		let orderKey = bar == .top ? Key.toolbarTopFunctionOrder : Key.toolbarBottomFunctionOrder
		AppDefaults.store.removeObject(forKey: orderKey)
	}

	/// Whether the top toolbar collapses its overflow-flagged functions
	/// into a single trailing menu icon. Replaces the pre-unification
	/// articleToolbarUseOverflowMenu (top-only, no bottom counterpart).
	var toolbarTopUseOverflowMenu: Bool {
		get {
			return AppDefaults.bool(for: Key.toolbarTopUseOverflowMenu)
		}
		set {
			AppDefaults.setBool(for: Key.toolbarTopUseOverflowMenu, newValue)
		}
	}

	/// Whether the bottom toolbar collapses its overflow-flagged
	/// functions into a single trailing menu icon. New with unification
	/// -- the bottom bar had no overflow concept at all before (see
	/// ToolbarFunction's own doc comment on the pre-unification bottom
	/// bar never having a cap or an overflow menu).
	var toolbarBottomUseOverflowMenu: Bool {
		get {
			return AppDefaults.bool(for: Key.toolbarBottomUseOverflowMenu)
		}
		set {
			AppDefaults.setBool(for: Key.toolbarBottomUseOverflowMenu, newValue)
		}
	}

	/// Dispatch over toolbarTopUseOverflowMenu/toolbarBottomUseOverflowMenu
	/// by ToolbarBar, for call sites that already have a bar value in
	/// hand (ToolbarsCustomizerViewController's per-tab logic) rather
	/// than a hardcoded .top or .bottom.
	func isToolbarOverflowMenuEnabled(on bar: ToolbarBar) -> Bool {
		switch bar {
		case .top: return toolbarTopUseOverflowMenu
		case .bottom: return toolbarBottomUseOverflowMenu
		}
	}

	func setToolbarOverflowMenuEnabled(on bar: ToolbarBar, _ enabled: Bool) {
		switch bar {
		case .top: toolbarTopUseOverflowMenu = enabled
		case .bottom: toolbarBottomUseOverflowMenu = enabled
		}
	}
}
