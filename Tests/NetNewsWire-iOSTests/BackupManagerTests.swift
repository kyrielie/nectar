//
//  BackupManagerTests.swift
//  NetNewsWire-iOSTests
//
//  Backup/restore plan, "Suggested build order" step 6 and "Tests":
//  BackupManagerTests (new): manifest round-trip, settingsIncluded gating,
//  and "a corrupt/missing-manifest zip fails the import before any live
//  data is touched." Deliberately scoped to what's exercisable without a
//  real AccountManager/local-account fixture (none exists yet in this test
//  target, and CLAUDE.md says not to guess APIs) -- the full
//  exportBackup()-produces-a-real-zip-with-real-accounts path and the
//  no-credential-in-the-zip regression test both need that fixture and are
//  not covered here; see docs/backup-restore.md's "Tests" section in the
//  plan for what's still open.
//
//  What IS covered without an account fixture: BackupManager.importBackup
//  reads and validates manifest.json before it ever touches
//  AccountManager.shared.accounts (the accounts loop is the last thing
//  importBackup does), so a zip with no manifest.json at all is a valid,
//  fixture-free way to exercise "fails before touching live data."
//

import Testing
import Foundation
import Zip
@testable import Nectar

@Suite("BackupManager manifest handling")
@MainActor
struct BackupManagerTests {

	private func tempWorkingDirectory() throws -> URL {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("BackupManagerTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	/// Zips `contents` (files/directories to place at the zip's own root,
	/// same shape `BackupManager.exportBackup` itself produces) into a new
	/// temp `.zip` and returns its URL.
	private func makeZip(rootEntries: [URL]) throws -> URL {
		let exportsFolder = FileManager.default.temporaryDirectory.appendingPathComponent("BackupManagerTests-zip-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: exportsFolder, withIntermediateDirectories: true)
		let zipURL = exportsFolder.appendingPathComponent("test-backup.zip")
		try Zip.zipFiles(paths: rootEntries, zipFilePath: zipURL, password: nil, progress: nil)
		return zipURL
	}

	// MARK: - manifest.json round-trip

	@Test("BackupManifest encodes and decodes with schemaVersion and settingsIncluded intact")
	func manifestRoundTrips() throws {
		let manifest = BackupManifest(
			schemaVersion: BackupManifest.currentSchemaVersion,
			appVersion: "1.2.3",
			appBuild: "456",
			exportDate: Date(timeIntervalSince1970: 1_700_000_000),
			accountFolderNames: ["onmymac_abc123"],
			settingsIncluded: true
		)

		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let data = try encoder.encode(manifest)

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let decoded = try decoder.decode(BackupManifest.self, from: data)

		#expect(decoded.schemaVersion == BackupManifest.currentSchemaVersion)
		#expect(decoded.appVersion == "1.2.3")
		#expect(decoded.appBuild == "456")
		#expect(decoded.accountFolderNames == ["onmymac_abc123"])
		#expect(decoded.settingsIncluded == true)
	}

	// MARK: - a corrupt/missing-manifest zip fails before touching live data

	@Test("importBackup on a zip with no manifest.json throws manifestMissingOrUnreadable")
	func missingManifestThrows() async throws {
		let workingDirectory = try tempWorkingDirectory()
		defer { try? FileManager.default.removeItem(at: workingDirectory) }

		// A zip with real-looking contents but deliberately no manifest.json
		// -- the point is that importBackup must not get far enough to read
		// Accounts/ at all when the manifest itself can't be trusted.
		let accountsFolder = workingDirectory.appendingPathComponent("Accounts", isDirectory: true)
		try FileManager.default.createDirectory(at: accountsFolder, withIntermediateDirectories: true)

		let zipURL = try makeZip(rootEntries: [accountsFolder])

		await #expect(throws: BackupManagerError.self) {
			_ = try await BackupManager.importBackup(from: zipURL, includeSettings: false)
		}
	}

	@Test("importBackup on a zip with an unparseable manifest.json throws manifestMissingOrUnreadable")
	func corruptManifestThrows() async throws {
		let workingDirectory = try tempWorkingDirectory()
		defer { try? FileManager.default.removeItem(at: workingDirectory) }

		let manifestURL = workingDirectory.appendingPathComponent("manifest.json")
		try Data("not valid json".utf8).write(to: manifestURL)

		let zipURL = try makeZip(rootEntries: [manifestURL])

		await #expect(throws: BackupManagerError.self) {
			_ = try await BackupManager.importBackup(from: zipURL, includeSettings: false)
		}
	}

	// MARK: - peekSettingsIncluded

	@Test("peekSettingsIncluded reflects the manifest's settingsIncluded flag without merging anything")
	func peekSettingsIncludedReflectsManifest() throws {
		let workingDirectory = try tempWorkingDirectory()
		defer { try? FileManager.default.removeItem(at: workingDirectory) }

		let manifest = BackupManifest(
			schemaVersion: BackupManifest.currentSchemaVersion,
			appVersion: "1.0",
			appBuild: "1",
			exportDate: Date(),
			accountFolderNames: [],
			settingsIncluded: true
		)
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let manifestURL = workingDirectory.appendingPathComponent("manifest.json")
		try encoder.encode(manifest).write(to: manifestURL)

		let zipURL = try makeZip(rootEntries: [manifestURL])

		let settingsIncluded = try BackupManager.peekSettingsIncluded(zipURL: zipURL)
		#expect(settingsIncluded == true)
	}

	@Test("peekSettingsIncluded throws (rather than defaulting silently) on a zip with no manifest.json -- callers are expected to treat any failure here as \"assume false\"")
	func peekSettingsIncludedThrowsOnMissingManifest() throws {
		let workingDirectory = try tempWorkingDirectory()
		defer { try? FileManager.default.removeItem(at: workingDirectory) }

		let placeholderURL = workingDirectory.appendingPathComponent("placeholder.txt")
		try Data("not a backup".utf8).write(to: placeholderURL)

		let zipURL = try makeZip(rootEntries: [placeholderURL])

		#expect(throws: BackupManagerError.self) {
			_ = try BackupManager.peekSettingsIncluded(zipURL: zipURL)
		}
	}
}
