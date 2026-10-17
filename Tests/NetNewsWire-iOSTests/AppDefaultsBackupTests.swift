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

import Account
import AO3Kit
import Testing
@testable import Nectar

@Suite struct AppDefaultsBackupTests {

	// MARK: - Migration / one-time-onboarding gates
	// Replaying `true` onto a fresh install would skip onboarding or a
	// migration step that install actually needs to run.

	@Test func firstRunDateIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.firstRunDate))
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

	// MARK: - Fullscreen reading switch

	@Test func articleFullscreenAvailableIsIncluded() {
		// Despite the name, this is the person-set "Show full screen articles"
		// switch (FullScreenReadingViewController). The device check (phone idiom)
		// is separate, in WebViewController.isFullScreenAvailable. Excluding it
		// made a restore leave full screen reading off.
		#expect(AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.articleFullscreenAvailable))
	}

	// MARK: - Ephemeral "Add Feed" sheet state

	@Test func addFeedAccountIDIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.addFeedAccountID))
	}

	@Test func addFeedFolderPathIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.addFeedFolderPath))
	}

	@Test func addFolderAccountIDIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.addFolderAccountID))
	}

	// MARK: - Live Take a Break runtime state, not a preference
	// Replaying these onto another device could start or end a lockout
	// there. The Take a Break settings themselves are included.

	@Test func readingTimeRecurringBreakEndDateIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.readingTimeRecurringBreakEndDate))
	}

	@Test func readingTimeSecondsSinceLastBreakIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.readingTimeSecondsSinceLastBreak))
	}

	@Test func readingTimeLastResignDateIsExcluded() {
		#expect(!AppDefaults.backupEligibleKeys.contains(AppDefaults.Key.readingTimeLastResignDate))
	}

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
			AppDefaults.Key.addFeedAccountID,
			AppDefaults.Key.addFeedFolderPath,
			AppDefaults.Key.addFolderAccountID,
			AppDefaults.Key.readingTimeRecurringBreakEndDate,
			AppDefaults.Key.readingTimeSecondsSinceLastBreak,
			AppDefaults.Key.readingTimeLastResignDate
		]

		// No overlap: nothing named as excluded above should also appear
		// in backupEligibleKeys.
		let overlap = excludedByThisFile.intersection(AppDefaults.backupEligibleKeys)
		#expect(overlap.isEmpty, "Keys both excluded by this test file and present in backupEligibleKeys: \(overlap)")

		// No duplicates within backupEligibleKeys itself.
		#expect(AppDefaults.backupEligibleKeys.count == Set(AppDefaults.backupEligibleKeys).count)
	}

	@Test func everyDeclaredKeyIsAccountedFor() throws {
		let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		let repositoryRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
		let sourceFiles = [
			repositoryRoot.appendingPathComponent("iOS/AppDefaults.swift"),
			repositoryRoot.appendingPathComponent("iOS/ReadingStats/AppDefaults+ReadingStats.swift"),
			repositoryRoot.appendingPathComponent("iOS/ReadingTime/AppDefaults+ReadingTime.swift")
		]
		// Regex literal (not `Regex(String)`) so the output is statically typed and
		// `match.1` works. `\w+` excludes non-key constants such as `folderPathSeparator`.
		let pattern = #/static let \w+ = "(\w+)"/#
		var declaredKeys = Set<String>()
		for file in sourceFiles {
			let source = try String(contentsOf: file, encoding: .utf8)
			for match in source.matches(of: pattern) {
				declaredKeys.insert(String(match.1))
			}
		}

		let excluded: Set<String> = [
			AppDefaults.Key.firstRunDate, AppDefaults.Key.lastImageCacheFlushDate,
			AppDefaults.Key.lastRefresh, AppDefaults.Key.selectedArticle,
			AppDefaults.Key.selectedSidebarItem, AppDefaults.Key.hideReadFeeds,
			AppDefaults.Key.expandedContainers, AppDefaults.Key.smartFeedsHidingReadArticles,
			AppDefaults.Key.feedsHidingReadArticles, AppDefaults.Key.foldersShowingReadArticles,
			AppDefaults.Key.splitViewPreferredDisplayMode,
			AppDefaults.Key.addFeedAccountID, AppDefaults.Key.addFeedFolderPath,
			AppDefaults.Key.addFolderAccountID,
			AppDefaults.Key.readingTimeRecurringBreakEndDate, AppDefaults.Key.readingTimeSecondsSinceLastBreak,
			AppDefaults.Key.readingTimeLastResignDate
		]
		let accountedFor = excluded.union(AppDefaults.backupEligibleKeys)
		#expect(declaredKeys == accountedFor, "Every AppDefaults.Key must be explicitly included or excluded. Missing: \(declaredKeys.subtracting(accountedFor)); unexpected: \(accountedFor.subtracting(declaredKeys))")
	}

	// MARK: - App-group preferences

	/// Each app-group key must be the one its preference type really reads and writes, or the
	/// setting silently drops out of backups.
	@Test func appGroupBackupKeysMatchTheirPreferenceTypes() {
		let defaults = NectarAppGroupUserDefaults.store
		let originals = AppDefaults.appGroupBackupEligibleKeys.map { ($0, defaults.object(forKey: $0)) }
		defer {
			for (key, value) in originals {
				if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
			}
		}
		let store = AppDefaults.shared

		AO3KudosOnLikePreference.isEnabled = true
		#expect(store.object(forKey: "ao3KudosOnLikeEnabled") as? Bool == true)
		AO3PrefetchNewWorksPreference.isEnabled = true
		#expect(store.object(forKey: "ao3PrefetchNewWorksEnabled") as? Bool == true)
		AmbrosiaAO3NetworkPreference.updatesEnabled = true
		#expect(store.object(forKey: "ambrosiaAO3StatsUpdatesEnabled") as? Bool == true)
		AO3PrefaceRefetchPreference.current = .daily
		#expect(store.object(forKey: "ao3PrefaceRefetchInterval") as? String == AO3PrefaceRefetchInterval.daily.rawValue)
		AmbrosiaTransferFormatPreference.current = .sqlite
		#expect(store.object(forKey: "ambrosiaTransferFormat") as? String == AmbrosiaTransferFormat.sqlite.rawValue)
	}

	@Test func appGroupKeysAreNeverAlsoAppDefaultsKeys() {
		#expect(Set(AppDefaults.appGroupBackupEligibleKeys).isDisjoint(with: AppDefaults.backupEligibleKeys))
	}
}
