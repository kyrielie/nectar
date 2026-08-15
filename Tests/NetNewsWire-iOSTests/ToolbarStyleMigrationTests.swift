//
//  ToolbarStyleMigrationTests.swift
//  NetNewsWire-iOSTests
//
//  Guards AppDefaults.migrateToolbarStyleDefaultIfNeeded()'s one-time port of
//  an upgrader's prior tinted-bar state onto the new three-state toolbarStyle
//  -- same raw-value-level reasoning as ArticleToolbarTogglesMigrationTests.swift
//  and BadgeColorPaletteMigrationTests.swift, not just trusting the doc
//  comment. Two independent legacy signals can each trigger the migration to
//  .tinted (the old useTintedNavigationBar Bool key being true, or a
//  non-.default surfaceTint predating that key entirely) -- see
//  toolbar-style-plan.md, Part 2.1.
//

import Testing
@testable import Nectar

@Suite struct ToolbarStyleMigrationTests {

	/// Resets every key this migration reads or writes, and the "already
	/// migrated" guard itself, so each test starts from a clean slate
	/// regardless of run order or what a previous test (or a previous app
	/// launch on this machine) left on disk.
	private func resetState() {
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.hasMigratedToolbarStyleDefault)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.useTintedNavigationBar)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.toolbarStyle)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.surfaceTint)
	}

	@MainActor
	@Test func legacyBoolTrueMigratesToTinted() {
		resetState()
		defer { resetState() }

		AppDefaults.setBool(for: AppDefaults.Key.useTintedNavigationBar, true)
		AppDefaults.shared.surfaceTint = .default

		AppDefaults.shared.migrateToolbarStyleDefaultIfNeeded()

		#expect(AppDefaults.shared.toolbarStyle == .tinted)
	}

	@MainActor
	@Test func legacyBoolFalseButNonDefaultSurfaceTintMigratesToTinted() {
		resetState()
		defer { resetState() }

		AppDefaults.setBool(for: AppDefaults.Key.useTintedNavigationBar, false)
		AppDefaults.shared.surfaceTint = .slate

		AppDefaults.shared.migrateToolbarStyleDefaultIfNeeded()

		#expect(AppDefaults.shared.toolbarStyle == .tinted)
	}

	@MainActor
	@Test func neitherLegacySignalKeepsRegisteredSystemDefault() {
		resetState()
		defer { resetState() }

		AppDefaults.setBool(for: AppDefaults.Key.useTintedNavigationBar, false)
		AppDefaults.shared.surfaceTint = .default

		AppDefaults.shared.migrateToolbarStyleDefaultIfNeeded()

		#expect(AppDefaults.shared.toolbarStyle == .system)
	}

	@MainActor
	@Test func freshInstallWithNoLegacyKeysKeepsSystemDefault() {
		// Stand-in for a fresh install: legacy useTintedNavigationBar key
		// simulated absent (bool(for:) reads false for a genuinely absent,
		// unregistered key), surfaceTint left at its own registered default.
		resetState()
		defer { resetState() }

		AppDefaults.shared.migrateToolbarStyleDefaultIfNeeded()

		#expect(AppDefaults.shared.toolbarStyle == .system)
	}

	@MainActor
	@Test func migrationOnlyRunsOnce() {
		resetState()
		defer { resetState() }

		AppDefaults.setBool(for: AppDefaults.Key.useTintedNavigationBar, true)
		AppDefaults.shared.surfaceTint = .default
		AppDefaults.shared.migrateToolbarStyleDefaultIfNeeded()
		#expect(AppDefaults.shared.toolbarStyle == .tinted)

		// Simulate a person changing their mind in Settings after the
		// one-time migration already ran once (e.g. on a prior app launch).
		AppDefaults.shared.toolbarStyle = .blend

		// Flipping the legacy signals afterward must not matter -- the
		// migration already ran, so a second call (as would happen on every
		// subsequent launch) must be a no-op regardless of what the
		// now-unused legacy key says.
		AppDefaults.setBool(for: AppDefaults.Key.useTintedNavigationBar, false)
		AppDefaults.shared.migrateToolbarStyleDefaultIfNeeded()

		#expect(AppDefaults.shared.toolbarStyle == .blend)
	}
}
