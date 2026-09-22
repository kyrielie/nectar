import BackupRestore

extension AppDefaults: BackupSettingsStoring {
	var eligibleKeys: [String] { Self.backupEligibleKeys }
	func object(forKey key: String) -> Any? { Self.store.object(forKey: key) }
	func set(_ value: Any, forKey key: String) { Self.store.set(value, forKey: key) }
}
