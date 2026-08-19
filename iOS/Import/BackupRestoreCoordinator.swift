//
//  BackupRestoreCoordinator.swift
//  Nectar
//
//  Backup/restore plan, "Suggested build order" step 6: the Restore-from-
//  Backup settings row's document-picker -> merge-options -> import flow.
//  Structured like OPMLImportCoordinator (document-picker delegate kept
//  alive via a static `current` reference, since UIDocumentPickerViewController
//  holds its delegate weakly) but with an extra step in between picking the
//  file and importing it: the merge-options screen (settings toggle, shown
//  only if the backup's own manifest says settings were included; the
//  fixed AO3 sign-in-again notice, always shown) has to be presented and
//  confirmed before BackupManager.importBackup actually runs, since the
//  settings toggle is an input to that call, not a follow-up action.
//

import UIKit
import UniformTypeIdentifiers
import ActivityLog

@MainActor
final class BackupRestoreCoordinator: NSObject {

	/// Kept alive for the duration of the picker/options flow -- same
	/// reasoning as OPMLImportCoordinator.current.
	private static var current: BackupRestoreCoordinator?

	private weak var presentingController: UIViewController?
	private var barButtonItem: UIBarButtonItem?
	private var sourceView: UIView?
	private var sourceRect: CGRect = .zero

	static func begin(presentingController: UIViewController, barButtonItem: UIBarButtonItem? = nil, sourceView: UIView? = nil, sourceRect: CGRect = .zero) {
		let coordinator = BackupRestoreCoordinator()
		coordinator.presentingController = presentingController
		coordinator.barButtonItem = barButtonItem
		coordinator.sourceView = sourceView
		coordinator.sourceRect = sourceRect
		current = coordinator
		coordinator.presentDocumentPicker()
	}

	private func presentDocumentPicker() {
		guard let presentingController else { Self.current = nil; return }

		// .zip is a system-registered UTType (unlike .opml, which
		// OPMLImportCoordinator has to look up by filename extension because
		// no such system type exists) -- no extension-based fallback needed.
		let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip], asCopy: true)
		documentPicker.delegate = self
		documentPicker.modalPresentationStyle = .formSheet
		presentingController.present(documentPicker, animated: true)
	}

	/// Reads just `manifest.json` out of the picked zip (via a throwaway
	/// unzip into its own temp directory) so the merge-options screen can
	/// decide whether to show the settings toggle, without yet touching any
	/// live data -- the real, authoritative manifest read happens again
	/// inside `BackupManager.importBackup` itself before it merges anything;
	/// this first read is purely to drive UI, so a failure here just skips
	/// straight to presenting the toggle hidden (import will then fail with
	/// a clear "not a valid backup" error if the file truly is bad).
	private func presentMergeOptions(for zipURL: URL) {
		guard let presentingController else { Self.current = nil; return }

		let settingsIncluded = (try? BackupManager.peekSettingsIncluded(zipURL: zipURL)) ?? false

		let alert = UIAlertController(
			title: NSLocalizedString("Restore from Backup", comment: "Restore from Backup"),
			message: Self.mergeOptionsMessage(settingsIncluded: settingsIncluded),
			preferredStyle: .alert
		)

		if settingsIncluded {
			let replaceSettingsTitle = NSLocalizedString("Restore, Including Settings", comment: "Restore including settings")
			alert.addAction(UIAlertAction(title: replaceSettingsTitle, style: .default) { [weak self] _ in
				self?.performImport(zipURL: zipURL, includeSettings: true)
			})
		}

		let restoreTitle = NSLocalizedString("Restore", comment: "Restore")
		alert.addAction(UIAlertAction(title: restoreTitle, style: .default) { [weak self] _ in
			self?.performImport(zipURL: zipURL, includeSettings: false)
		})

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in
			Self.current = nil
		})

		presentingController.present(alert, animated: true)
	}

	/// The fixed, non-toggleable AO3 sign-in-again notice (always shown, not
	/// conditional on anything -- Correction 5) plus, when the backup
	/// includes settings, a note that a second action below will also
	/// replace this device's preferences.
	private static func mergeOptionsMessage(settingsIncluded: Bool) -> String {
		let notice = NSLocalizedString("AO3 sign-in isn't included in backups — you'll need to sign in again after restoring.", comment: "AO3 sign-in-again notice")
		guard settingsIncluded else {
			return notice
		}
		let settingsNote = NSLocalizedString("This backup also includes Settings. You can restore your feeds and reading history only, or also replace this device's Settings with the backup's.", comment: "Settings restore note")
		return "\(settingsNote)\n\n\(notice)"
	}

	// Logged the same way exportBackupDocumentPicker logs .exportBackup
	// (Settings.md's "Suggested build order" step 9 / Definition of done) --
	// .importBackup already exists on ActivityKind, it just wasn't wired to
	// anything yet. Uses the async logActivity(owner:kind:_:) overload since
	// BackupManager.importBackup itself is async.
	private func performImport(zipURL: URL, includeSettings: Bool) {
		let presentingController = self.presentingController
		Task {
			do {
				let result = try await ActivityLog.shared.logActivity(owner: .app, kind: .importBackup) {
					try await BackupManager.importBackup(from: zipURL, includeSettings: includeSettings)
				}
				Self.presentResultAlert(result, on: presentingController)
			} catch {
				let title = NSLocalizedString("Restore Failed", comment: "Restore Failed")
				presentingController?.presentError(title: title, message: error.localizedDescription)
			}
			Self.current = nil
		}
	}

	private static func presentResultAlert(_ result: BackupImportResult, on presentingController: UIViewController?) {
		guard let presentingController else { return }

		var lines: [String] = []
		if !result.matchedAccountFolderNames.isEmpty {
			let format = NSLocalizedString("Restored %d account(s).", comment: "Restore summary — accounts restored")
			lines.append(String(format: format, result.matchedAccountFolderNames.count))
		}
		if !result.unmatchedAccountFolderNames.isEmpty {
			let format = NSLocalizedString("%d account(s) from this backup don't exist on this device and were skipped.", comment: "Restore summary — accounts skipped")
			lines.append(String(format: format, result.unmatchedAccountFolderNames.count))
		}
		if !result.installedThemeFilenames.isEmpty {
			let format = NSLocalizedString("Installed %d custom theme(s).", comment: "Restore summary — themes installed")
			lines.append(String(format: format, result.installedThemeFilenames.count))
		}
		lines.append(NSLocalizedString("AO3 sign-in isn't included in backups — you'll need to sign in again.", comment: "AO3 sign-in-again notice, restore summary"))

		let alert = UIAlertController(
			title: NSLocalizedString("Restore Complete", comment: "Restore Complete"),
			message: lines.joined(separator: "\n"),
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default))
		presentingController.present(alert, animated: true)
	}
}

extension BackupRestoreCoordinator: UIDocumentPickerDelegate {

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
		guard let zipURL = urls.first else {
			Self.current = nil
			return
		}
		presentMergeOptions(for: zipURL)
	}

	func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
		Self.current = nil
	}
}
