//
//  ArticleToolbarTogglesMigrationTests.swift
//  NetNewsWire-iOSTests
//
//  Guards AppDefaults.migrateArticleToolbarTogglesIfNeeded()'s one-time
//  derivation of the four independent articleToolbarShowX toggles from
//  the two legacy showTableOfContentsAndFind/showPrevNextArticleButtons
//  switches, at the raw-value level rather than trusting the doc comment
//  -- same reasoning as BadgeColorPaletteMigrationTests.swift. The two
//  legacy switches map directly onto the new toggles that used to be
//  bundled with them: showTableOfContentsAndFind onto both
//  articleToolbarShowTableOfContents and articleToolbarShowFind, and
//  showPrevNextArticleButtons onto articleToolbarShowPrevNext.
//  articleToolbarShowTheme has no legacy source and always keeps its
//  registered true default, regardless of the legacy switches.
//

import Testing
@testable import Nectar

@Suite struct ArticleToolbarTogglesMigrationTests {

	/// Resets every key this migration reads or writes, and the "already
	/// migrated" guard itself, so each test starts from a clean slate
	/// regardless of run order or what a previous test (or a previous
	/// app launch on this machine) left on disk.
	private func resetState() {
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.hasMigratedArticleToolbarToggles)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleToolbarShowTheme)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleToolbarShowTableOfContents)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleToolbarShowFind)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.articleToolbarShowPrevNext)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.showTableOfContentsAndFind)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.showPrevNextArticleButtons)
	}

	@MainActor
	@Test func bothLegacySwitchesOnMigratesBothPairsOn() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.showTableOfContentsAndFind = true
		AppDefaults.shared.showPrevNextArticleButtons = true

		AppDefaults.shared.migrateArticleToolbarTogglesIfNeeded()

		#expect(AppDefaults.shared.articleToolbarShowTableOfContents == true)
		#expect(AppDefaults.shared.articleToolbarShowFind == true)
		#expect(AppDefaults.shared.articleToolbarShowPrevNext == true)
		#expect(AppDefaults.shared.articleToolbarShowTheme == true)
	}

	@MainActor
	@Test func onlyTableOfContentsAndFindOnMigratesOnlyThatPairOn() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.showTableOfContentsAndFind = true
		AppDefaults.shared.showPrevNextArticleButtons = false

		AppDefaults.shared.migrateArticleToolbarTogglesIfNeeded()

		#expect(AppDefaults.shared.articleToolbarShowTableOfContents == true)
		#expect(AppDefaults.shared.articleToolbarShowFind == true)
		#expect(AppDefaults.shared.articleToolbarShowPrevNext == false)
	}

	@MainActor
	@Test func onlyPrevNextSwitchOnMigratesOnlyPrevNextOn() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.showTableOfContentsAndFind = false
		AppDefaults.shared.showPrevNextArticleButtons = true

		AppDefaults.shared.migrateArticleToolbarTogglesIfNeeded()

		#expect(AppDefaults.shared.articleToolbarShowTableOfContents == false)
		#expect(AppDefaults.shared.articleToolbarShowFind == false)
		#expect(AppDefaults.shared.articleToolbarShowPrevNext == true)
	}

	@MainActor
	@Test func neitherLegacySwitchOnMigratesAllThreeOff() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.showTableOfContentsAndFind = false
		AppDefaults.shared.showPrevNextArticleButtons = false

		AppDefaults.shared.migrateArticleToolbarTogglesIfNeeded()

		#expect(AppDefaults.shared.articleToolbarShowTableOfContents == false)
		#expect(AppDefaults.shared.articleToolbarShowFind == false)
		#expect(AppDefaults.shared.articleToolbarShowPrevNext == false)
		// Theme has no legacy source and keeps its registered true default
		// regardless of the legacy switches' state.
		#expect(AppDefaults.shared.articleToolbarShowTheme == true)
	}

	@MainActor
	@Test func migrationOnlyRunsOnce() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.showTableOfContentsAndFind = true
		AppDefaults.shared.showPrevNextArticleButtons = false
		AppDefaults.shared.migrateArticleToolbarTogglesIfNeeded()
		#expect(AppDefaults.shared.articleToolbarShowTableOfContents == true)
		#expect(AppDefaults.shared.articleToolbarShowPrevNext == false)

		// Simulate a person changing their mind on
		// ArticleToolbarCustomizerViewController after the one-time
		// migration already ran once (e.g. on a prior app launch).
		AppDefaults.shared.articleToolbarShowTableOfContents = false
		AppDefaults.shared.articleToolbarShowFind = false

		// Flipping the legacy switches afterward must not matter -- the
		// migration already ran, so a second call (as would happen on
		// every subsequent launch) must be a no-op regardless of what the
		// now-unused legacy keys say.
		AppDefaults.shared.showPrevNextArticleButtons = true
		AppDefaults.shared.migrateArticleToolbarTogglesIfNeeded()

		#expect(AppDefaults.shared.articleToolbarShowTableOfContents == false)
		#expect(AppDefaults.shared.articleToolbarShowFind == false)
		#expect(AppDefaults.shared.articleToolbarShowPrevNext == false)
	}

	@MainActor
	@Test func absentLegacyKeysDefaultTogglesToRegisteredDefaults() {
		// Direct stand-in for a fresh install: no legacy keys on disk at
		// all (registerDefaults() not simulated here). bool(for:) on an
		// absent key returns false, so both legacy switches read as off
		// and the migration writes both to false -- matching what
		// registerDefaults() would have registered anyway once it runs.
		resetState()
		defer { resetState() }

		AppDefaults.shared.migrateArticleToolbarTogglesIfNeeded()

		#expect(AppDefaults.shared.articleToolbarShowTableOfContents == false)
		#expect(AppDefaults.shared.articleToolbarShowFind == false)
		#expect(AppDefaults.shared.articleToolbarShowPrevNext == false)
	}
}
