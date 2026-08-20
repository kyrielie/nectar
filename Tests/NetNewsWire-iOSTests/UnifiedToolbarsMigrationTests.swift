//
//  UnifiedToolbarsMigrationTests.swift
//  NetNewsWire-iOSTests
//
//  Guards AppDefaults.migrateUnifiedToolbarsIfNeeded()'s one-time
//  derivation of the unified ToolbarFunction inline/overflow placement
//  from the pre-unification split model (top-only articleToolbarShow*,
//  bottom-only bottomToolbarShow*, and the top-only
//  articleToolbarUseOverflowMenu Bool) -- same raw-value-level
//  reasoning as ArticleToolbarTogglesMigrationTests.swift, sibling to
//  that file per toolbarfixes.md's plan.
//

import Testing
@testable import Nectar

@Suite struct UnifiedToolbarsMigrationTests {

	private func resetState() {
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.hasMigratedUnifiedToolbars)

		// Legacy top-bar sources this migration reads.
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleToolbarShowTheme)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleToolbarShowTableOfContents)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleToolbarShowFind)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleToolbarShowPrevNext)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleToolbarShowLock)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleToolbarShowAnnotations)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleToolbarShowSettings)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleToolbarShowCheckForUpdates)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleToolbarUseOverflowMenu)

		// Legacy bottom-bar sources this migration reads.
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.bottomToolbarShowRead)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.bottomToolbarShowStar)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.bottomToolbarShowHeart)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.bottomToolbarShowNextUnread)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.bottomToolbarShowAction)

		// Unified destination keys this migration writes -- every
		// ToolbarFunction x ToolbarBar pair, inline and overflow.
		for function in ToolbarFunction.allCases {
			for bar in [ToolbarBar.top, .bottom] {
				AppDefaults.shared.setToolbarFunctionEnabled(function, on: bar, false)
				AppDefaults.shared.setToolbarFunctionInOverflow(function, on: bar, false)
			}
		}
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.toolbarTopUseOverflowMenu)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.toolbarBottomUseOverflowMenu)
	}

	@MainActor
	@Test func legacyTopTogglesMigrateToTopInlineOnly() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.articleToolbarShowTheme = true
		AppDefaults.shared.articleToolbarShowTableOfContents = true
		AppDefaults.shared.articleToolbarShowFind = false
		AppDefaults.shared.articleToolbarShowPrevNext = false
		AppDefaults.shared.articleToolbarShowLock = false
		AppDefaults.shared.articleToolbarShowAnnotations = false
		AppDefaults.shared.articleToolbarShowSettings = false
		AppDefaults.shared.articleToolbarShowCheckForUpdates = false

		AppDefaults.shared.migrateUnifiedToolbarsIfNeeded()

		#expect(AppDefaults.shared.isToolbarFunctionEnabled(.theme, on: .top) == true)
		#expect(AppDefaults.shared.isToolbarFunctionEnabled(.tableOfContents, on: .top) == true)
		#expect(AppDefaults.shared.isToolbarFunctionEnabled(.find, on: .top) == false)

		// Migration preserves prior behavior exactly -- it does not opt
		// anyone into the new cross-bar duplication feature, so a
		// migrated top function must not also appear on .bottom.
		#expect(AppDefaults.shared.isToolbarFunctionEnabled(.theme, on: .bottom) == false)
		#expect(AppDefaults.shared.isToolbarFunctionEnabled(.tableOfContents, on: .bottom) == false)
	}

	@MainActor
	@Test func legacyBottomTogglesMigrateToBottomInlineOnly() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.bottomToolbarShowRead = true
		AppDefaults.shared.bottomToolbarShowStar = false
		AppDefaults.shared.bottomToolbarShowHeart = true
		AppDefaults.shared.bottomToolbarShowNextUnread = false
		AppDefaults.shared.bottomToolbarShowAction = false

		AppDefaults.shared.migrateUnifiedToolbarsIfNeeded()

		#expect(AppDefaults.shared.isToolbarFunctionEnabled(.read, on: .bottom) == true)
		#expect(AppDefaults.shared.isToolbarFunctionEnabled(.star, on: .bottom) == false)
		#expect(AppDefaults.shared.isToolbarFunctionEnabled(.heart, on: .bottom) == true)

		// Same cross-bar-preservation guarantee as the top-bar test, from
		// the other direction.
		#expect(AppDefaults.shared.isToolbarFunctionEnabled(.read, on: .top) == false)
		#expect(AppDefaults.shared.isToolbarFunctionEnabled(.heart, on: .top) == false)
	}

	@MainActor
	@Test func legacyTopOverflowBoolMigratesToTopOverflowSwitchWithEmptyPicks() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.articleToolbarShowTheme = true
		AppDefaults.store.set(true, forKey: AppDefaults.Key.articleToolbarUseOverflowMenu)

		AppDefaults.shared.migrateUnifiedToolbarsIfNeeded()

		#expect(AppDefaults.shared.isToolbarOverflowMenuEnabled(on: .top) == true)
		// No legacy concept of "which" functions were in the overflow
		// menu -- migration must not populate any per-function overflow
		// flag, even for a function it just placed inline on .top.
		#expect(AppDefaults.shared.isToolbarFunctionInOverflow(.theme, on: .top) == false)
		// Bottom overflow has no legacy counterpart and stays at its
		// registered-default false.
		#expect(AppDefaults.shared.isToolbarOverflowMenuEnabled(on: .bottom) == false)
	}

	@MainActor
	@Test func migrationOnlyRunsOnce() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.articleToolbarShowTheme = true
		AppDefaults.shared.migrateUnifiedToolbarsIfNeeded()
		#expect(AppDefaults.shared.isToolbarFunctionEnabled(.theme, on: .top) == true)

		// Simulate a person changing their mind on
		// ToolbarsCustomizerViewController after the one-time migration
		// already ran once (e.g. on a prior app launch).
		AppDefaults.shared.setToolbarFunctionEnabled(.theme, on: .top, false)

		// Flipping the legacy switch afterward must not matter -- the
		// migration already ran, so a second call (as would happen on
		// every subsequent launch) must be a no-op regardless of what the
		// now-unused legacy key says.
		AppDefaults.shared.articleToolbarShowTheme = true
		AppDefaults.shared.migrateUnifiedToolbarsIfNeeded()

		#expect(AppDefaults.shared.isToolbarFunctionEnabled(.theme, on: .top) == false)
	}

	@MainActor
	@Test func inlineAndOverflowStayMutuallyExclusivePerBarAfterMigration() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.articleToolbarShowTheme = true
		AppDefaults.shared.migrateUnifiedToolbarsIfNeeded()

		// Placing the migrated function into .top's overflow afterward
		// must clear its inline flag on .top -- the setter invariant
		// applies regardless of whether the value got there via
		// migration or a direct write.
		AppDefaults.shared.setToolbarFunctionInOverflow(.theme, on: .top, true)
		#expect(AppDefaults.shared.isToolbarFunctionEnabled(.theme, on: .top) == false)
		#expect(AppDefaults.shared.isToolbarFunctionInOverflow(.theme, on: .top) == true)
	}
}
