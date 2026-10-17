import AO3Kit
import BackupRestore

/// Adapts `AO3IgnoreList` (app-group defaults) to the `BackupRestore` package, which cannot see
/// AO3Kit. Merging is done by `BackupIgnoreListSnapshot.merged(into:)`; this only reads and writes.
final class AO3IgnoreListBackupStore: BackupIgnoreListStoring {

	func snapshot() -> BackupIgnoreListSnapshot {
		BackupIgnoreListSnapshot(
			workIDs: AO3IgnoreList.ignoredWorkIDs.sorted(),
			authorURLs: AO3IgnoreList.ignoredAuthorURLs.sorted(),
			workLabels: AO3IgnoreList.ignoredWorkLabels,
			authorLabels: AO3IgnoreList.ignoredAuthorLabels
		)
	}

	func apply(_ snapshot: BackupIgnoreListSnapshot) {
		AO3IgnoreList.ignoredWorkIDs = Set(snapshot.workIDs)
		AO3IgnoreList.ignoredAuthorURLs = Set(snapshot.authorURLs)
		AO3IgnoreList.ignoredWorkLabels = snapshot.workLabels
		AO3IgnoreList.ignoredAuthorLabels = snapshot.authorLabels
	}
}
