//
//  BackupIgnoreListTests.swift
//  BackupRestoreTests
//
//  The ignore list in a backup: the merge rules, the IgnoreList.json file, and how it sits in the
//  manifest. Export and import are exercised through `writeIgnoreList(to:)` and
//  `importIgnoreList(from:)` directly, since the full `exportBackup`/`importBackup` paths need a
//  real AccountManager (see BackupManagerTests). Serialized: `BackupManager.ignoreListStore` is
//  global.
//

import Testing
import Foundation
@testable import BackupRestore

@Suite("Backup ignore list", .serialized)
@MainActor
struct BackupIgnoreListTests {

	private func tempDirectory() throws -> URL {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("BackupIgnoreListTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	/// Installs a fresh in-memory store holding `snapshot` as the live ignore list.
	@discardableResult
	private func installStore(_ snapshot: BackupIgnoreListSnapshot = BackupIgnoreListSnapshot()) -> InMemoryBackupIgnoreListStore {
		let store = InMemoryBackupIgnoreListStore()
		store.stored = snapshot
		BackupManager.ignoreListStore = store
		return store
	}

	// MARK: - Merge rules

	@Test("merge unions works and authors, and counts only the new ones")
	func mergeUnionsAndCounts() {
		let local = BackupIgnoreListSnapshot(workIDs: ["1", "2"], authorURLs: ["https://a/u1"])
		let backup = BackupIgnoreListSnapshot(workIDs: ["2", "3"], authorURLs: ["https://a/u1", "https://a/u2"])

		let merged = backup.merged(into: local)

		#expect(merged.result.workIDs == ["1", "2", "3"])
		#expect(merged.result.authorURLs == ["https://a/u1", "https://a/u2"])
		#expect(merged.rulesAdded == 2)
	}

	@Test("merge never removes a local rule or label the backup lacks")
	func mergeKeepsEverythingLocal() {
		let local = BackupIgnoreListSnapshot(workIDs: ["1"], authorURLs: ["https://a/u1"], workLabels: ["1": "Local Title"], authorLabels: ["https://a/u1": "Local Author"])

		let merged = BackupIgnoreListSnapshot().merged(into: local)

		#expect(merged.result == local.normalized())
		#expect(merged.rulesAdded == 0)
	}

	@Test("a local label wins; the backup's label fills a rule that has none")
	func localLabelWinsBackupFillsGaps() {
		let local = BackupIgnoreListSnapshot(workIDs: ["1", "2"], workLabels: ["1": "Local"])
		let backup = BackupIgnoreListSnapshot(workIDs: ["1", "2", "3"], workLabels: ["1": "Backup", "2": "Backup Two", "3": "Backup Three"])

		let merged = backup.merged(into: local)

		#expect(merged.result.workLabels == ["1": "Local", "2": "Backup Two", "3": "Backup Three"])
	}

	@Test("author labels follow the same rule, keyed by URL")
	func authorLabelsMerge() {
		let local = BackupIgnoreListSnapshot(authorURLs: ["https://a/u1"], authorLabels: ["https://a/u1": "Local"])
		let backup = BackupIgnoreListSnapshot(authorURLs: ["https://a/u1", "https://a/u2"], authorLabels: ["https://a/u1": "Backup", "https://a/u2": "Two"])

		let merged = backup.merged(into: local)

		#expect(merged.result.authorLabels == ["https://a/u1": "Local", "https://a/u2": "Two"])
	}

	@Test("a backup label for a rule that is in neither list is dropped")
	func strayBackupLabelIsDropped() {
		let backup = BackupIgnoreListSnapshot(workIDs: ["1"], workLabels: ["1": "One", "99": "Stray"])

		let merged = backup.merged(into: BackupIgnoreListSnapshot())

		#expect(merged.result.workLabels == ["1": "One"])
	}

	@Test("normalized sorts and de-duplicates, and isEmpty ignores labels without rules")
	func normalizedAndIsEmpty() {
		let snapshot = BackupIgnoreListSnapshot(workIDs: ["2", "1", "2"], authorURLs: ["b", "a", "a"])
		let normalized = snapshot.normalized()
		#expect(normalized.workIDs == ["1", "2"])
		#expect(normalized.authorURLs == ["a", "b"])

		#expect(BackupIgnoreListSnapshot().isEmpty)
		#expect(BackupIgnoreListSnapshot(workLabels: ["1": "Orphan label"]).isEmpty)
		#expect(!BackupIgnoreListSnapshot(workIDs: ["1"]).isEmpty)
	}

	// MARK: - File format

	@Test("a snapshot survives an encode and decode")
	func snapshotRoundTrips() throws {
		let snapshot = BackupIgnoreListSnapshot(workIDs: ["1"], authorURLs: ["https://a/u1"], workLabels: ["1": "T"], authorLabels: ["https://a/u1": "A"])
		let decoded = try JSONDecoder().decode(BackupIgnoreListSnapshot.self, from: JSONEncoder().encode(snapshot))
		#expect(decoded == snapshot)
	}

	@Test("a file missing keys still decodes, with those collections empty")
	func decodesWithMissingKeys() throws {
		let decoded = try JSONDecoder().decode(BackupIgnoreListSnapshot.self, from: Data(#"{"workIDs": ["7"]}"#.utf8))
		#expect(decoded.workIDs == ["7"])
		#expect(decoded.authorURLs.isEmpty)
		#expect(decoded.workLabels.isEmpty)
		#expect(decoded.authorLabels.isEmpty)
	}

	// MARK: - Manifest

	@Test("a manifest written before ignoreListIncluded existed decodes with nil")
	func oldManifestDecodes() throws {
		let json = #"{"schemaVersion":1,"appVersion":"1","appBuild":"1","exportDate":"2023-11-14T22:13:20Z","accountFolderNames":[],"settingsIncluded":false}"#
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let manifest = try decoder.decode(BackupManifest.self, from: Data(json.utf8))
		#expect(manifest.ignoreListIncluded == nil)
	}

	@Test("ignoreListIncluded round-trips through the manifest")
	func manifestRoundTripsIgnoreListFlag() throws {
		let manifest = BackupManifest(schemaVersion: BackupManifest.currentSchemaVersion, appVersion: "1", appBuild: "1", exportDate: Date(timeIntervalSince1970: 1_700_000_000), accountFolderNames: [], settingsIncluded: false, ignoreListIncluded: true)
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let decoded = try decoder.decode(BackupManifest.self, from: encoder.encode(manifest))
		#expect(decoded.ignoreListIncluded == true)
	}

	// MARK: - Export

	@Test("export writes IgnoreList.json with the live rules, and reports it")
	func exportWritesFile() throws {
		let directory = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		installStore(BackupIgnoreListSnapshot(workIDs: ["2", "1"], authorURLs: ["https://a/u1"], workLabels: ["1": "One"]))

		let written = try BackupManager.writeIgnoreList(to: directory)

		#expect(written)
		let data = try Data(contentsOf: directory.appendingPathComponent(BackupIgnoreListSnapshot.fileName))
		let decoded = try JSONDecoder().decode(BackupIgnoreListSnapshot.self, from: data)
		#expect(decoded.workIDs == ["1", "2"])
		#expect(decoded.authorURLs == ["https://a/u1"])
		#expect(decoded.workLabels == ["1": "One"])
	}

	@Test("export writes no file when the ignore list is empty")
	func exportSkipsEmptyList() throws {
		let directory = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		installStore()

		let written = try BackupManager.writeIgnoreList(to: directory)

		#expect(!written)
		#expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(BackupIgnoreListSnapshot.fileName).path))
	}

	// MARK: - Import

	@Test("import merges the backup's rules into the live list and keeps the local ones")
	func importMerges() throws {
		let directory = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let backup = BackupIgnoreListSnapshot(workIDs: ["2", "3"], authorURLs: ["https://a/u2"], workLabels: ["2": "Backup Two", "3": "Backup Three"])
		try JSONEncoder().encode(backup).write(to: directory.appendingPathComponent(BackupIgnoreListSnapshot.fileName))
		let store = installStore(BackupIgnoreListSnapshot(workIDs: ["1", "2"], authorURLs: ["https://a/u1"], workLabels: ["2": "Local Two"]))

		let added = BackupManager.importIgnoreList(from: directory)

		#expect(added == 2)
		#expect(store.stored.workIDs == ["1", "2", "3"])
		#expect(store.stored.authorURLs == ["https://a/u1", "https://a/u2"])
		#expect(store.stored.workLabels == ["2": "Local Two", "3": "Backup Three"])
	}

	@Test("importing a list already present changes nothing and adds zero")
	func importIsIdempotent() throws {
		let directory = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let list = BackupIgnoreListSnapshot(workIDs: ["1"], authorURLs: ["https://a/u1"], workLabels: ["1": "One"])
		try JSONEncoder().encode(list).write(to: directory.appendingPathComponent(BackupIgnoreListSnapshot.fileName))
		let store = installStore(list)

		#expect(BackupManager.importIgnoreList(from: directory) == 0)
		#expect(store.stored == list)
	}

	@Test("a backup with no IgnoreList.json leaves the live list alone")
	func importWithoutFileIsNoOp() throws {
		let directory = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let local = BackupIgnoreListSnapshot(workIDs: ["1"])
		let store = installStore(local)

		#expect(BackupManager.importIgnoreList(from: directory) == 0)
		#expect(store.stored == local)
	}

	@Test("an unreadable IgnoreList.json adds nothing and does not touch the live list")
	func importWithCorruptFileIsNoOp() throws {
		let directory = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		try Data("not json".utf8).write(to: directory.appendingPathComponent(BackupIgnoreListSnapshot.fileName))
		let local = BackupIgnoreListSnapshot(workIDs: ["1"])
		let store = installStore(local)

		#expect(BackupManager.importIgnoreList(from: directory) == 0)
		#expect(store.stored == local)
	}

	@Test("an export followed by an import on an empty device restores the list")
	func exportThenImportRoundTrips() throws {
		let directory = try tempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let original = BackupIgnoreListSnapshot(workIDs: ["1", "2"], authorURLs: ["https://a/u1"], workLabels: ["1": "One"], authorLabels: ["https://a/u1": "Author"])
		installStore(original)
		try BackupManager.writeIgnoreList(to: directory)

		let freshDevice = installStore()
		let added = BackupManager.importIgnoreList(from: directory)

		#expect(added == 3)
		#expect(freshDevice.stored == original.normalized())
	}
}
