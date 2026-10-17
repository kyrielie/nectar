import AO3Kit
import BackupRestore
import Foundation

extension AppDefaults: BackupSettingsStoring {

	/// Person-facing preferences that live in `NectarAppGroupUserDefaults.store` (the app-group
	/// suite) rather than `AppDefaults.store`, because modules that cannot depend on the app
	/// target read them. Each key is private to its preference type, so the strings are repeated
	/// here; `AppDefaultsBackupTests` round-trips every one through its preference type so a
	/// rename there fails the test instead of silently dropping the setting from backups.
	///
	/// Deliberately not listed: `ao3SessionLastEnded*` (session bookkeeping, tied to credentials
	/// that are never backed up) and `ambrosiaSQLiteTransferWalkState.*` (in-flight transfer
	/// state). The AO3 ignore list (`ao3Ignored*`) is user content, not a preference: it is backed
	/// up separately, merged on restore, through `AO3IgnoreListBackupStore`.
	static let appGroupBackupEligibleKeys: [String] = [
		"ao3KudosOnLikeEnabled", // AO3KudosOnLikePreference
		"ao3PrefetchNewWorksEnabled", // AO3PrefetchNewWorksPreference
		"ao3PrefaceRefetchInterval", // AO3PrefaceRefetchPreference
		"ambrosiaAO3StatsUpdatesEnabled", // AmbrosiaAO3NetworkPreference
		"ambrosiaTransferFormat" // AmbrosiaTransferFormatPreference
	]

	var eligibleKeys: [String] { Self.backupEligibleKeys + Self.appGroupBackupEligibleKeys }

	func object(forKey key: String) -> Any? { Self.backupStore(for: key).object(forKey: key) }

	func set(_ value: Any, forKey key: String) { Self.backupStore(for: key).set(value, forKey: key) }

	private static func backupStore(for key: String) -> UserDefaults {
		appGroupBackupEligibleKeys.contains(key) ? NectarAppGroupUserDefaults.store : store
	}
}
