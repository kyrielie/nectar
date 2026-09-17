//
//  TextReplacementApplyAutomaticallyMigrationTests.swift
//  NetNewsWire-iOSTests
//
//  Guards AppDefaults.migrateTextReplacementApplyAutomaticallyDefaultIfNeeded()
//  (Part 8): registerDefaults() flips Key.textReplacementApplyAutomatically's
//  registered default from true to false, and this migration writes an
//  explicit `true` into the store for every existing user so the flip only
//  changes what a *fresh* install starts on. Exercises the migration's own
//  static logic directly against AppDefaults.store/Key.firstRunDate, not
//  through AppDefaults.shared -- see the migration's own doc comment for why
//  it can't be gated on AppDefaults.shared.isFirstRun the way the other
//  migrations in this file are gated on their own instance state.
//

import Testing
import Foundation
@testable import Nectar

@Suite struct TextReplacementApplyAutomaticallyMigrationTests {

	/// Resets every key this migration reads or writes, so each test
	/// starts from a clean slate regardless of run order or what a
	/// previous test (or a previous app launch on this machine) left on
	/// disk.
	private func resetState() {
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.hasMigratedTextReplacementApplyAutomaticallyDefault)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.firstRunDate)
		AppDefaults.store.removeObject(forKey: AppDefaults.Key.textReplacementApplyAutomatically)
	}

	@Test("an existing user (firstRunDate already present) gets true written explicitly")
	func existingUserGetsExplicitTrue() {
		resetState()
		defer { resetState() }

		AppDefaults.store.set(Date(), forKey: AppDefaults.Key.firstRunDate)

		AppDefaults.migrateTextReplacementApplyAutomaticallyDefaultIfNeeded()

		#expect(AppDefaults.store.object(forKey: AppDefaults.Key.textReplacementApplyAutomatically) as? Bool == true)
	}

	@Test("a fresh install (firstRunDate absent) is left alone, no explicit value written")
	func freshInstallIsLeftAlone() {
		resetState()
		defer { resetState() }

		AppDefaults.migrateTextReplacementApplyAutomaticallyDefaultIfNeeded()

		#expect(AppDefaults.store.object(forKey: AppDefaults.Key.textReplacementApplyAutomatically) == nil)
	}

	@Test("migration only runs once -- a later explicit false from Settings is not clobbered on a second call")
	func migrationOnlyRunsOnce() {
		resetState()
		defer { resetState() }

		AppDefaults.store.set(Date(), forKey: AppDefaults.Key.firstRunDate)
		AppDefaults.migrateTextReplacementApplyAutomaticallyDefaultIfNeeded()
		#expect(AppDefaults.store.object(forKey: AppDefaults.Key.textReplacementApplyAutomatically) as? Bool == true)

		// Simulate the person turning the toggle off themselves in
		// Settings after the one-time migration already ran once (e.g.
		// on a prior app launch).
		AppDefaults.setBool(for: AppDefaults.Key.textReplacementApplyAutomatically, false)

		// A second call (as would happen on every subsequent launch)
		// must be a no-op regardless of firstRunDate's state.
		AppDefaults.migrateTextReplacementApplyAutomaticallyDefaultIfNeeded()

		#expect(AppDefaults.store.object(forKey: AppDefaults.Key.textReplacementApplyAutomatically) as? Bool == false)
	}

	@Test("hasMigrated flag is set after the migration runs")
	func hasMigratedFlagIsSet() {
		resetState()
		defer { resetState() }

		AppDefaults.migrateTextReplacementApplyAutomaticallyDefaultIfNeeded()

		#expect(AppDefaults.bool(for: AppDefaults.Key.hasMigratedTextReplacementApplyAutomaticallyDefault) == true)
	}
}
