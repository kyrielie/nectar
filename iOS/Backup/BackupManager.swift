//
//  BackupManager.swift
//  Nectar
//
//  Backup/restore plan, "Suggested build order" step 3:
//  BackupManager.exportBackup() -- accounts (Subscriptions.opml,
//  FeedSettings.db, a full ArticlesDatabase snapshot), custom-installed
//  themes, an optional Settings.plist, and manifest.json, zipped and
//  handed back as a URL for UIDocumentPickerViewController(forExporting:),
//  matching every existing export action in this codebase (Correction 1).
//
//  App-target-only (iOS/Backup), not a module -- nothing outside
//  iOS/Settings needs this, same reasoning as the rest of Settings'
//  export flows living directly in the app target.
//

import Foundation
import os
import Account
import Zip

/// `manifest.json`'s shape. `schemaVersion` is what makes a future
/// additive change (e.g. the blacklist/mute feature noted in the plan)
/// non-breaking -- a backup written before that field exists simply omits
/// it, and any importer reading an older backup already has to treat
/// "field absent" as a normal case.
struct BackupManifest: Codable {
	static let currentSchemaVersion = 1

	let schemaVersion: Int
	let appVersion: String
	let appBuild: String
	let exportDate: Date
	let accountFolderNames: [String]
	let settingsIncluded: Bool
}

enum BackupManagerError: Error, CustomStringConvertible {
	case noAccountsToBackUp
	case zipFailed(String)
	case unzipFailed(String)
	case manifestMissingOrUnreadable

	var description: String {
		switch self {
		case .noAccountsToBackUp:
			return "There are no accounts to back up."
		case .zipFailed(let detail):
			return "Creating the backup archive failed: \(detail)"
		case .unzipFailed(let detail):
			return "Reading the backup archive failed: \(detail)"
		case .manifestMissingOrUnreadable:
			return "This doesn't look like a valid Nectar backup (manifest.json is missing or unreadable)."
		}
	}
}

/// What `BackupManager.importBackup(from:)` did, for the caller to summarize to
/// the person -- which accounts in the zip had no matching local account (and
/// were therefore skipped entirely, per the plan's "matched by type+accountID"
/// restore scope; restore never creates a new account on the person's behalf),
/// and whether the fixed AO3 sign-in-again notice should be shown (always, per
/// Correction 5 -- included here so the caller doesn't have to duplicate that
/// "always true" knowledge).
struct BackupImportResult: Sendable {
	let manifest: BackupManifest
	let matchedAccountFolderNames: [String]
	let unmatchedAccountFolderNames: [String]
	let settingsApplied: Bool
	let installedThemeFilenames: [String]
	let skippedThemeFilenames: [String]
}

@MainActor
enum BackupManager {

	private static let logger = Logger(subsystem: "Nectar", category: "BackupManager")

	/// Builds a backup zip in a temporary, caller-owned location and hands
	/// back its `URL`. The caller (`SettingsViewController`) is responsible
	/// for presenting it via `UIDocumentPickerViewController(forExporting:)`
	/// and deleting the temp working directory afterward (success or
	/// cancel) -- this function does not clean up its own output, since
	/// the document picker needs the file to still exist when its
	/// completion handler fires.
	///
	/// No credential of any kind is ever written into the zip (Correction
	/// 5) -- AO3SessionStore/AO3ChallengeSessionStore are Keychain-backed
	/// and never touched here.
	static func exportBackup(includeSettings: Bool) throws -> URL {
		let accounts = AccountManager.shared.accounts
		guard !accounts.isEmpty else {
			throw BackupManagerError.noAccountsToBackUp
		}

		let workingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("NectarBackup-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

		var accountFolderNames: [String] = []

		let accountsRoot = workingDirectory.appendingPathComponent("Accounts", isDirectory: true)
		try FileManager.default.createDirectory(at: accountsRoot, withIntermediateDirectories: true)

		for account in accounts {
			let accountFolderName = (account.dataFolder as NSString).lastPathComponent
			accountFolderNames.append(accountFolderName)

			let destinationFolder = accountsRoot.appendingPathComponent(accountFolderName, isDirectory: true)
			try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

			// Subscriptions.opml -- copied as-is.
			let opmlSource = (account.dataFolder as NSString).appendingPathComponent("Subscriptions.opml")
			if FileManager.default.fileExists(atPath: opmlSource) {
				try FileManager.default.copyItem(atPath: opmlSource, toPath: destinationFolder.appendingPathComponent("Subscriptions.opml").path)
			}

			// FeedSettings.db -- copied as-is (Correction 6: not all of this
			// file's columns are disposable cache, so it's included verbatim
			// rather than selectively).
			let feedSettingsSource = (account.dataFolder as NSString).appendingPathComponent("FeedSettings.db")
			if FileManager.default.fileExists(atPath: feedSettingsSource) {
				try FileManager.default.copyItem(atPath: feedSettingsSource, toPath: destinationFolder.appendingPathComponent("FeedSettings.db").path)
			}

			// DB.sqlite3 -- a full, atomic, consistent snapshot (VACUUM
			// INTO), not the partial ATTACH-based per-feed export. This is
			// the only path that includes bookState and the FTS search
			// table, per exportFullSnapshot's own doc comment.
			let dbDestination = destinationFolder.appendingPathComponent("DB.sqlite3").path
			try account.exportFullSnapshot(toPath: dbDestination)
		}

		// Custom-installed themes: unconditional, not gated by
		// includeSettings -- a custom theme file is user content the same
		// way a feed subscription is, not a preference. Only the
		// installed-folder contents, not the app-bundled themes (which
		// ship with every install already).
		let themesSourceFolder = ArticleThemesManager.shared.folderPath
		if FileManager.default.fileExists(atPath: themesSourceFolder) {
			let themesDestination = workingDirectory.appendingPathComponent("Themes", isDirectory: true)
			try FileManager.default.copyItem(atPath: themesSourceFolder, toPath: themesDestination.path)
		}

		// Settings.plist -- gated by includeSettings, filtered through the
		// explicit backupEligibleKeys allowlist (Stage 2), not "every key
		// minus known system prefixes."
		if includeSettings {
			var settingsDictionary: [String: Any] = [:]
			for key in AppDefaults.backupEligibleKeys {
				if let value = AppDefaults.store.object(forKey: key) {
					settingsDictionary[key] = value
				}
			}
			let settingsPlistPath = workingDirectory.appendingPathComponent("Settings.plist").path
			let plistData = try PropertyListSerialization.data(fromPropertyList: settingsDictionary, format: .xml, options: 0)
			try plistData.write(to: URL(fileURLWithPath: settingsPlistPath))
		}

		// manifest.json
		let bundle = Bundle.main
		let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
		let appBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
		let manifest = BackupManifest(
			schemaVersion: BackupManifest.currentSchemaVersion,
			appVersion: appVersion,
			appBuild: appBuild,
			exportDate: Date(),
			accountFolderNames: accountFolderNames,
			settingsIncluded: includeSettings
		)
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		let manifestData = try encoder.encode(manifest)
		try manifestData.write(to: workingDirectory.appendingPathComponent("manifest.json"))

		// Zip. `Zip.zipFiles(paths:)` archives each given URL at its own
		// basename; for a directory, `ZipUtilities.expandDirectoryFilePath`
		// walks its contents and -- verified against the actual pinned Zip
		// source (project.yml's revision pin), not assumed -- always
		// prefixes entries with that directory's own name
		// (`includeRootDirectory` is `true` and not configurable in this
		// version). Passing `workingDirectory` itself would therefore nest
		// everything under an extra "NectarBackup-<uuid>/" folder inside
		// the zip. Passing its *contents* individually instead keeps
		// manifest.json/Accounts/Themes/Settings.plist at the zip's own
		// root, matching the plan's file layout.
		let topLevelEntries = try FileManager.default.contentsOfDirectory(at: workingDirectory, includingPropertiesForKeys: nil)
		let exportsFolder = FileManager.default.temporaryDirectory.appendingPathComponent("NectarBackupExport-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: exportsFolder, withIntermediateDirectories: true)
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "yyyy-MM-dd"
		let zipFilename = "Nectar Backup \(dateFormatter.string(from: Date())).zip"
		let zipDestination = exportsFolder.appendingPathComponent(zipFilename)

		do {
			try Zip.zipFiles(paths: topLevelEntries, zipFilePath: zipDestination, password: nil, progress: nil)
		} catch {
			try? FileManager.default.removeItem(at: workingDirectory)
			throw BackupManagerError.zipFailed(error.localizedDescription)
		}

		try? FileManager.default.removeItem(at: workingDirectory)

		Self.logger.debug("BackupManager: exportBackup produced \(zipDestination.path, privacy: .public)")
		return zipDestination
	}

	// MARK: - Restore UI support

	/// Reads just `manifest.json`'s `settingsIncluded` flag out of a backup
	/// zip, without merging anything -- lets the restore UI (merge-options
	/// screen) decide whether to offer the settings toggle before the person
	/// has committed to a real import. Unzips into its own short-lived temp
	/// directory rather than reusing importBackup's, since this can run
	/// (and be thrown away) before the person has picked an import option at
	/// all. Throws the same manifestMissingOrUnreadable case importBackup
	/// itself would hit on the same bad file -- the UI-facing caller treats
	/// any failure here as "assume settings weren't included," matching
	/// the plan's "should not show the toggle" default for anything short
	/// of a confirmed settingsIncluded: true.
	static func peekSettingsIncluded(zipURL: URL) throws -> Bool {
		let peekDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("NectarRestorePeek-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: peekDirectory) }

		do {
			try Zip.unzipFile(zipURL, destination: peekDirectory, overwrite: true, password: nil, progress: nil, fileOutputHandler: nil)
		} catch {
			throw BackupManagerError.unzipFailed(error.localizedDescription)
		}

		let manifestURL = peekDirectory.appendingPathComponent("manifest.json")
		guard let manifestData = try? Data(contentsOf: manifestURL) else {
			throw BackupManagerError.manifestMissingOrUnreadable
		}
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		guard let manifest = try? decoder.decode(BackupManifest.self, from: manifestData) else {
			throw BackupManagerError.manifestMissingOrUnreadable
		}
		return manifest.settingsIncluded
	}

	// MARK: - Import

	/// Non-destructive merge restore, per the plan's "Import" section. Every
	/// merge path this drives is additive-only: `BackupSQLiteImportTable`'s
	/// `INSERT OR IGNORE`/OR-of-booleans/later-timestamp-wins SQL for
	/// articles/statuses/bookState/annotations, `account.importOPML` for
	/// feeds/folders (itself additive -- see `Account.importOPML`/
	/// `LocalAccountDelegate.importOPML`, which only ever adds or repoints,
	/// never deletes), `INSERT OR IGNORE` for `FeedSettings.db` (Correction 6),
	/// and keep-local-on-name-collision for custom themes. The one deliberate
	/// exception is Settings, and only when `includeSettings` is true -- see
	/// the loop below.
	///
	/// `zipURL` is expected to already be a local file URL (the document
	/// picker's `asCopy: true` copy, or the "Open in Nectar" extension point's
	/// delivered file) -- this does not itself fetch or download anything.
	static func importBackup(from zipURL: URL, includeSettings: Bool) async throws -> BackupImportResult {
		let workingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("NectarRestore-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: workingDirectory) }

		do {
			try Zip.unzipFile(zipURL, destination: workingDirectory, overwrite: true, password: nil, progress: nil, fileOutputHandler: nil)
		} catch {
			throw BackupManagerError.unzipFailed(error.localizedDescription)
		}

		// manifest.json is read and validated before anything else is touched
		// (plan's Import step 1) -- a corrupt/missing manifest must fail here,
		// before any live data is touched.
		let manifestURL = workingDirectory.appendingPathComponent("manifest.json")
		guard let manifestData = try? Data(contentsOf: manifestURL) else {
			throw BackupManagerError.manifestMissingOrUnreadable
		}
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		guard let manifest = try? decoder.decode(BackupManifest.self, from: manifestData) else {
			throw BackupManagerError.manifestMissingOrUnreadable
		}

		// Settings toggle only ever applies if the backup actually included
		// settings -- a caller passing includeSettings: true against a backup
		// that never wrote Settings.plist is a no-op here, not an error, since
		// SettingsViewController's restore screen is expected to gate the
		// toggle on manifest.settingsIncluded in the first place and this is
		// just the belt-and-suspenders check on the import side.
		let shouldApplySettings = includeSettings && manifest.settingsIncluded
		if shouldApplySettings {
			let settingsPlistURL = workingDirectory.appendingPathComponent("Settings.plist")
			if let plistData = try? Data(contentsOf: settingsPlistURL),
			   let settingsDictionary = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
				// The one deliberate exception to "never delete/overwrite" in
				// this whole restore flow (see the merge guarantees table in
				// the plan) -- a person restoring settings is explicitly
				// asking to replace their current device's preferences.
				// Still scoped to backupEligibleKeys only: a backup written
				// by an older app version can't smuggle in a key this
				// version doesn't recognize as eligible, since the loop only
				// ever reads keys the *current* app's allowlist names.
				for key in AppDefaults.backupEligibleKeys {
					if let value = settingsDictionary[key] {
						AppDefaults.store.set(value, forKey: key)
					}
				}
			}
		}

		// Custom themes: unconditional, not gated by includeSettings (see
		// "Custom themes" in the plan) -- a custom theme file is user
		// content, not a preference. Name collision with an already-installed
		// theme of the same filename: skip and keep the local copy: this
		// deliberately does NOT call ArticleThemesManager.importTheme(filename:)
		// unconditionally, since that method's own contract is
		// remove-then-copy (an overwrite), not skip-on-collision.
		var installedThemeFilenames: [String] = []
		var skippedThemeFilenames: [String] = []
		let themesSourceFolder = workingDirectory.appendingPathComponent("Themes", isDirectory: true)
		if let themeFilenames = try? FileManager.default.contentsOfDirectory(atPath: themesSourceFolder.path) {
			for themeFilename in themeFilenames {
				if ArticleThemesManager.shared.themeExists(filename: themeFilename) {
					skippedThemeFilenames.append(themeFilename)
					continue
				}
				let sourcePath = themesSourceFolder.appendingPathComponent(themeFilename).path
				do {
					try ArticleThemesManager.shared.importTheme(filename: sourcePath)
					installedThemeFilenames.append(themeFilename)
				} catch {
					Self.logger.error("BackupManager: importBackup failed to install theme \(themeFilename, privacy: .public): \(error.localizedDescription, privacy: .public)")
				}
			}
		}

		// Accounts: matched by folder name (== "<type>_<accountID>", the same
		// naming AccountManager already uses for account.dataFolder's last
		// path component -- see BackupManager.exportBackup's own use of this
		// same lastPathComponent above). Restore never creates a new account
		// on the person's behalf -- a folder in the zip with no matching
		// local account is reported back as unmatched, not silently skipped
		// with no trace, so the caller can tell the person "N accounts from
		// this backup weren't restored because they don't exist on this
		// device" rather than restoring a partial set with no explanation.
		let accountsRoot = workingDirectory.appendingPathComponent("Accounts", isDirectory: true)
		let localAccountsByFolderName = Dictionary(uniqueKeysWithValues: AccountManager.shared.accounts.map { (($0.dataFolder as NSString).lastPathComponent, $0) })

		var matchedAccountFolderNames: [String] = []
		var unmatchedAccountFolderNames: [String] = []

		for accountFolderName in manifest.accountFolderNames {
			guard let account = localAccountsByFolderName[accountFolderName] else {
				unmatchedAccountFolderNames.append(accountFolderName)
				continue
			}
			matchedAccountFolderNames.append(accountFolderName)

			let backupAccountFolder = accountsRoot.appendingPathComponent(accountFolderName, isDirectory: true)

			// FeedSettings.db: INSERT OR IGNORE, keep-local-backfill-missing
			// (Correction 6). This merges directly into the live
			// FeedSettings.db file via ATTACH, mirroring the same idiom as
			// BackupSQLiteImportTable -- see FeedSettingsRestoreImportTable.
			let backupFeedSettingsPath = backupAccountFolder.appendingPathComponent("FeedSettings.db").path
			if FileManager.default.fileExists(atPath: backupFeedSettingsPath) {
				do {
					try await account.mergeFeedSettings(fromBackupAtPath: backupFeedSettingsPath)
				} catch {
					Self.logger.error("BackupManager: importBackup FeedSettings merge failed for \(accountFolderName, privacy: .public): \(error.localizedDescription, privacy: .public)")
				}
			}

			// DB.sqlite3 (articles/statuses/bookState/annotations): the
			// non-destructive merge built in BackupSQLiteImportTable.
			let backupDatabasePath = backupAccountFolder.appendingPathComponent("DB.sqlite3").path
			if FileManager.default.fileExists(atPath: backupDatabasePath) {
				do {
					try account.importBackupSnapshot(backupDatabasePath: backupDatabasePath)
				} catch {
					Self.logger.error("BackupManager: importBackup DB.sqlite3 merge failed for \(accountFolderName, privacy: .public): \(error.localizedDescription, privacy: .public)")
				}
			}

			// Subscriptions.opml: reuse account.importOPML directly
			// (Correction 7) rather than a second diff-and-add-missing
			// implementation -- this also triggers reconcileRepairedFeeds
			// for any feed whose URL changed on the source device, and (per
			// Account.importOPML's own existing behavior) a refreshAll
			// afterward, which is what actually populates the newly-added
			// feeds/folders with content rather than leaving them empty
			// subscriptions until the next scheduled refresh.
			let backupOPMLPath = backupAccountFolder.appendingPathComponent("Subscriptions.opml")
			if FileManager.default.fileExists(atPath: backupOPMLPath.path) {
				await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
					account.importOPML(backupOPMLPath) { result in
						if case .failure(let error) = result {
							Self.logger.error("BackupManager: importBackup OPML import failed for \(accountFolderName, privacy: .public): \(error.localizedDescription, privacy: .public)")
						}
						continuation.resume()
					}
				}
			}
		}

		Self.logger.debug("BackupManager: importBackup matched \(matchedAccountFolderNames.count, privacy: .public) account(s), \(unmatchedAccountFolderNames.count, privacy: .public) unmatched")

		return BackupImportResult(
			manifest: manifest,
			matchedAccountFolderNames: matchedAccountFolderNames,
			unmatchedAccountFolderNames: unmatchedAccountFolderNames,
			settingsApplied: shouldApplySettings,
			installedThemeFilenames: installedThemeFilenames,
			skippedThemeFilenames: skippedThemeFilenames
		)
	}
}
