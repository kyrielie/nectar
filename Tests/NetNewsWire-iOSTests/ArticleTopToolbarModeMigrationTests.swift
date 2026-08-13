//
//  ArticleTopToolbarModeMigrationTests.swift
//  NetNewsWire-iOSTests
//
//  Article view top toolbar settings plan. Guards
//  AppDefaults.migrateArticleTopToolbarModeIfNeeded()'s one-time derivation
//  of the new single articleTopToolbarMode setting from the two legacy
//  independent showTableOfContentsAndFind/showPrevNextArticleButtons
//  switches, at the raw-value level rather than trusting the doc comment --
//  same reasoning as BadgeColorPaletteMigrationTests.swift. In particular:
//  ArticleViewController's old rightBarButtonItems() resolved "both switches
//  on" as showTableOfContentsAndFind winning (an `else if`), so the
//  migration has to reproduce that same precedence, not just "whichever was
//  on".
//

import Testing
@testable import Nectar

@Suite struct ArticleTopToolbarModeMigrationTests {

	/// Resets every key this migration reads or writes, and the "already
	/// migrated" guard itself, so each test starts from a clean slate
	/// regardless of run order or what a previous test (or a previous
	/// app launch on this machine) left on disk.
	private func resetState() {
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.hasMigratedArticleTopToolbarMode)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleTopToolbarMode)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.showTableOfContentsAndFind)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.showPrevNextArticleButtons)
	}

	@MainActor
	@Test func bothLegacySwitchesOnMigratesToTableOfContentsAndFind() {
		resetState()
		defer { resetState() }

		// Reproduces ArticleViewController's old rightBarButtonItems()
		// precedence: showTableOfContentsAndFind wins when both are true.
		AppDefaults.shared.showTableOfContentsAndFind = true
		AppDefaults.shared.showPrevNextArticleButtons = true

		AppDefaults.shared.migrateArticleTopToolbarModeIfNeeded()

		#expect(AppDefaults.shared.articleTopToolbarMode == .tableOfContentsAndFind)
	}

	@MainActor
	@Test func onlyPrevNextSwitchOnMigratesToPrevNextArticle() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.showTableOfContentsAndFind = false
		AppDefaults.shared.showPrevNextArticleButtons = true

		AppDefaults.shared.migrateArticleTopToolbarModeIfNeeded()

		#expect(AppDefaults.shared.articleTopToolbarMode == .prevNextArticle)
	}

	@MainActor
	@Test func neitherLegacySwitchOnMigratesToOff() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.showTableOfContentsAndFind = false
		AppDefaults.shared.showPrevNextArticleButtons = false

		AppDefaults.shared.migrateArticleTopToolbarModeIfNeeded()

		#expect(AppDefaults.shared.articleTopToolbarMode == .off)
	}

	@MainActor
	@Test func migrationOnlyRunsOnce() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.showTableOfContentsAndFind = true
		AppDefaults.shared.showPrevNextArticleButtons = false
		AppDefaults.shared.migrateArticleTopToolbarModeIfNeeded()
		#expect(AppDefaults.shared.articleTopToolbarMode == .tableOfContentsAndFind)

		// Simulate a person changing their mind on
		// ArticleToolbarCustomizerViewController after the one-time
		// migration already ran once (e.g. on a prior app launch).
		AppDefaults.shared.articleTopToolbarMode = .off

		// Flipping the legacy switches afterward must not matter -- the
		// migration already ran, so a second call (as would happen on
		// every subsequent launch) must be a no-op regardless of what the
		// now-unused legacy keys say.
		AppDefaults.shared.showPrevNextArticleButtons = true
		AppDefaults.shared.migrateArticleTopToolbarModeIfNeeded()

		#expect(AppDefaults.shared.articleTopToolbarMode == .off)
	}

	@MainActor
	@Test func absentKeyDefaultsToTableOfContentsAndFind() {
		// Direct stand-in for a fresh install: no articleTopToolbarMode
		// value on disk at all (registerDefaults() not simulated here),
		// matching the registered default declared in registerDefaults().
		resetState()
		defer { resetState() }

		#expect(AppDefaults.shared.articleTopToolbarMode == .tableOfContentsAndFind)
	}
}
