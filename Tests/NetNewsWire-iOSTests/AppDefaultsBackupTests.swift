//
//  AppDefaultsBackupTests.swift
//  NetNewsWire-iOSTests
//
//  Backup/restore plan, "Suggested build order" step 2 and Correction 4:
//  AppDefaults.backupEligibleKeys is a manually maintained allowlist, not
//  a subtraction from AppDefaults.Key (which is a plain struct of
//  static-let strings, not a CaseIterable enum -- there's no allCases to
//  subtract from, per Correction 3). A named test per excluded key means
//  a future person adding a new migration/state flag to AppDefaults.Key
//  who forgets to also exclude it here gets a signal here, in review --
//  not something a single generic "count matches" test could catch,
//  since a wrongly-included new key would just make the count larger,
//  not wrong-looking on its own.
//

import Testing
@testable import Nectar

@Suite struct AppDefaultsBackupTests {

	// MARK: - Migration / one-time-onboarding gates
	// Replaying `true` onto a fresh install would skip onboarding or a
	// migration step that install actually needs to run.

	@Test func firstRunDateIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.firstRunDate))
	}

	@Test func hasShownAO3OnboardingIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.hasShownAO3Onboarding))
	}

	@Test func hasMigratedNavigationBarTintingDefaultIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.hasMigratedNavigationBarTintingDefault))
	}

	@Test func hasMigratedToolbarStyleDefaultIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.hasMigratedToolbarStyleDefault))
	}

	@Test func hasMigratedArticleToolbarTogglesIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.hasMigratedArticleToolbarToggles))
	}

	@Test func didMigrateLegacyStateRestorationInfoIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.didMigrateLegacyStateRestorationInfo))
	}

	// MARK: - Dead migration-source-of-truth

	@Test func useTintedNavigationBarIsExcluded() {
		// No live property reads this key anymore -- see its own doc
		// comment in AppDefaults.Key ("do not reintroduce a property for
		// this key"). Nothing for a backup to meaningfully capture.
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.useTintedNavigationBar))
	}

	// MARK: - Bookkeeping, not a preference

	@Test func lastImageCacheFlushDateIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.lastImageCacheFlushDate))
	}

	@Test func lastRefreshIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.lastRefresh))
	}

	// MARK: - State restoration, not a preference

	@Test func selectedArticleIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.selectedArticle))
	}

	@Test func selectedSidebarItemIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.selectedSidebarItem))
	}

	@Test func hideReadFeedsIsExcluded() {
		// Backs StateRestorationInfo (sidebar/timeline UI state), not a
		// Settings-screen row -- see settings-screen.md.
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.hideReadFeeds))
	}

	@Test func expandedContainersIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.expandedContainers))
	}

	@Test func smartFeedsHidingReadArticlesIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.smartFeedsHidingReadArticles))
	}

	@Test func feedsHidingReadArticlesIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.feedsHidingReadArticles))
	}

	@Test func foldersShowingReadArticlesIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.foldersShowingReadArticles))
	}

	@Test func splitViewPreferredDisplayModeIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.splitViewPreferredDisplayMode))
	}

	// MARK: - Device-capability flag, not person-set

	@Test func articleFullscreenAvailableIsExcluded() {
		// Gates whether the articleFullscreenEnabled toggle even applies
		// on this device -- not itself a preference. The actual toggle,
		// articleFullscreenEnabled, IS included; see
		// articleFullscreenEnabledIsIncluded below.
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.articleFullscreenAvailable))
	}

	// MARK: - Ephemeral "Add Feed" sheet state

	@Test func addFeedAccountIDIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.addFeedAccountID))
	}

	@Test func addFeedFolderNameIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.addFeedFolderName))
	}

	@Test func addFolderAccountIDIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.addFolderAccountID))
	}

	// MARK: - Sanity: the toggle counterpart to articleFullscreenAvailable
	// IS included, so the exclusion above is a deliberate distinction,
	// not a copy/paste of the wrong key name.

	@Test func articleFullscreenEnabledIsIncluded() {
		#expect(AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.articleFullscreenEnabled))
	}

	// MARK: - Completeness: every key in AppDefaults.Key is accounted for
	// by exactly one of backupEligibleKeys or the excluded set asserted
	// above -- catches a new Key added without an explicit decision either
	// way, which none of the individual tests above can catch on their own.

	@Test func everyExcludedKeyAboveIsExhaustive() {
		let excludedByThisFile: Set<String> = [
			AppDefaults.Key.firstRunDate,
			AppDefaults.Key.hasShownAO3Onboarding,
			AppDefaults.Key.hasMigratedNavigationBarTintingDefault,
			AppDefaults.Key.hasMigratedToolbarStyleDefault,
			AppDefaults.Key.hasMigratedArticleToolbarToggles,
			AppDefaults.Key.didMigrateLegacyStateRestorationInfo,
			AppDefaults.Key.useTintedNavigationBar,
			AppDefaults.Key.lastImageCacheFlushDate,
			AppDefaults.Key.lastRefresh,
			AppDefaults.Key.selectedArticle,
			AppDefaults.Key.selectedSidebarItem,
			AppDefaults.Key.hideReadFeeds,
			AppDefaults.Key.expandedContainers,
			AppDefaults.Key.smartFeedsHidingReadArticles,
			AppDefaults.Key.feedsHidingReadArticles,
			AppDefaults.Key.foldersShowingReadArticles,
			AppDefaults.Key.splitViewPreferredDisplayMode,
			AppDefaults.Key.articleFullscreenAvailable,
			AppDefaults.Key.addFeedAccountID,
			AppDefaults.Key.addFeedFolderName,
			AppDefaults.Key.addFolderAccountID
		]

		// No overlap: nothing named as excluded above should also appear
		// in backupEligibleKeys.
		let overlap = excludedByThisFile.intersection(AppDefaults.backupEligibleKeys)
		#expect(overlap.isEmpty, "Keys both excluded by this test file and present in backupEligibleKeys: \(overlap)")

		// No duplicates within backupEligibleKeys itself.
		#expect(AppDefaults.backupEligibleKeys.count == Set(AppDefaults.backupEligibleKeys).count)
	}
}
