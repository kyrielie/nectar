//
//  BackupIgnoreList.swift
//  BackupRestore
//
//  The AO3 ignore list in a backup. `IgnoreList.json` at the zip's root holds one
//  `BackupIgnoreListSnapshot`. The ignore list is user content, not a preference, so unlike
//  `Settings.plist` it is not gated by the settings toggle and a restore only ever merges it in
//  (see `BackupIgnoreListSnapshot.merged(into:)`). This package cannot see `AO3IgnoreList`, so the
//  app supplies the live list through `BackupIgnoreListStoring`; the app side is
//  iOS/Backup/BackupIgnoreListStore.swift. See docs/backup-restore.md.
//

import Foundation

/// The four collections `AO3IgnoreList` persists, as plain values.
public struct BackupIgnoreListSnapshot: Codable, Equatable, Sendable {

	public static let fileName = "IgnoreList.json"

	/// Bare AO3 work IDs.
	public var workIDs: [String]
	/// Full AO3 author URLs.
	public var authorURLs: [String]
	/// Display labels keyed by work ID.
	public var workLabels: [String: String]
	/// Display labels keyed by author URL.
	public var authorLabels: [String: String]

	private enum CodingKeys: String, CodingKey {
		case workIDs, authorURLs, workLabels, authorLabels
	}

	public init(workIDs: [String] = [], authorURLs: [String] = [], workLabels: [String: String] = [:], authorLabels: [String: String] = [:]) {
		self.workIDs = workIDs
		self.authorURLs = authorURLs
		self.workLabels = workLabels
		self.authorLabels = authorLabels
	}

	/// Any key may be absent, so a file written before a field existed still decodes.
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		workIDs = try container.decodeIfPresent([String].self, forKey: .workIDs) ?? []
		authorURLs = try container.decodeIfPresent([String].self, forKey: .authorURLs) ?? []
		workLabels = try container.decodeIfPresent([String: String].self, forKey: .workLabels) ?? [:]
		authorLabels = try container.decodeIfPresent([String: String].self, forKey: .authorLabels) ?? [:]
	}

	/// True when there are no rules. Labels without a rule do not count.
	public var isEmpty: Bool {
		workIDs.isEmpty && authorURLs.isEmpty
	}

	/// Sorted and de-duplicated, so the same list always serializes to the same bytes and two
	/// snapshots of the same list compare equal.
	public func normalized() -> BackupIgnoreListSnapshot {
		BackupIgnoreListSnapshot(
			workIDs: Set(workIDs).sorted(),
			authorURLs: Set(authorURLs).sorted(),
			workLabels: workLabels,
			authorLabels: authorLabels
		)
	}

	/// Merges this snapshot (the backup's) into `local`. Additive only: every local rule and label
	/// survives. A label from the backup is used only for a rule that has no local label, the same
	/// "local wins" rule as `FeedSettings.db`. `rulesAdded` counts works plus authors that were not
	/// already in `local`.
	public func merged(into local: BackupIgnoreListSnapshot) -> (result: BackupIgnoreListSnapshot, rulesAdded: Int) {
		let localWorks = Set(local.workIDs)
		let localAuthors = Set(local.authorURLs)
		let works = localWorks.union(workIDs)
		let authors = localAuthors.union(authorURLs)

		var mergedWorkLabels = workLabels.filter { works.contains($0.key) }
		mergedWorkLabels.merge(local.workLabels) { _, localLabel in localLabel }
		var mergedAuthorLabels = authorLabels.filter { authors.contains($0.key) }
		mergedAuthorLabels.merge(local.authorLabels) { _, localLabel in localLabel }

		let result = BackupIgnoreListSnapshot(
			workIDs: works.sorted(),
			authorURLs: authors.sorted(),
			workLabels: mergedWorkLabels,
			authorLabels: mergedAuthorLabels
		)
		return (result, (works.count - localWorks.count) + (authors.count - localAuthors.count))
	}
}

/// The app's live ignore list. Implemented in the app target over `AO3IgnoreList`.
public protocol BackupIgnoreListStoring: AnyObject {
	func snapshot() -> BackupIgnoreListSnapshot
	/// Replaces the live list with `snapshot`. `BackupManager` passes an already merged snapshot,
	/// so this does not merge.
	func apply(_ snapshot: BackupIgnoreListSnapshot)
}

/// Default until the app installs its own, so the package works without an app host.
final class InMemoryBackupIgnoreListStore: BackupIgnoreListStoring {
	var stored = BackupIgnoreListSnapshot()
	func snapshot() -> BackupIgnoreListSnapshot { stored }
	func apply(_ snapshot: BackupIgnoreListSnapshot) { stored = snapshot }
}
