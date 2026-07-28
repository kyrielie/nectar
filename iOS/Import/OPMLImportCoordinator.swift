//
//  OPMLImportCoordinator.swift
//  Nectar
//
//  Copyright © 2026 Ranchero Software, LLC. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers
import Account

/// Account-picker -> document-picker -> import flow, shared by every entry point that
/// wants "pick an OPML file and import it" -- the Add Feed button's long-press menu and
/// tap action sheet (`MainFeedCollectionViewController`), the empty-state Import OPML
/// button (`MainFeedCollectionViewController.importOPMLFromEmptyState`, which pre-creates
/// a `.onMyMac` account when none exists and then calls through here -- with exactly one
/// active account present, `start()` skips the account picker and goes straight to the
/// document picker), and Settings' Import OPML row (`SettingsViewController`). All three
/// previously had their own independent copy of this same three-step flow; consolidated
/// here so there's one account-picker/document-picker/import-failure-alert implementation
/// instead of three.
@MainActor
final class OPMLImportCoordinator: NSObject {

	/// Kept alive for the duration of the picker flow -- UIDocumentPickerViewController
	/// holds its delegate weakly, and there's otherwise nothing else retaining this
	/// instance between presenting the account picker and the document-picker callback.
	private static var current: OPMLImportCoordinator?

	private weak var presentingController: UIViewController?
	private var account: Account?
	private var barButtonItem: UIBarButtonItem?
	private var sourceView: UIView?
	private var sourceRect: CGRect = .zero

	/// `barButtonItem`, when the trigger is a `UIBarButtonItem` (matches the existing
	/// `popoverPresentationController?.barButtonItem = sender` pattern already used by
	/// `MainFeedCollectionViewController.add(_:)` for its action sheet) -- prefer this
	/// over `sourceView`/`sourceRect` when both are available, since it tracks the
	/// button's actual frame automatically.
	static func begin(presentingController: UIViewController, barButtonItem: UIBarButtonItem? = nil, sourceView: UIView? = nil, sourceRect: CGRect = .zero) {
		let coordinator = OPMLImportCoordinator()
		coordinator.presentingController = presentingController
		coordinator.barButtonItem = barButtonItem
		coordinator.sourceView = sourceView
		coordinator.sourceRect = sourceRect
		current = coordinator
		coordinator.start()
	}

	private func start() {
		switch AccountManager.shared.activeAccounts.count {
		case 0:
			presentingController?.presentError(title: "Error", message: NSLocalizedString("You must have at least one active account.", comment: "Missing active account"))
			Self.current = nil
		case 1:
			account = AccountManager.shared.activeAccounts.first
			presentDocumentPicker()
		default:
			presentAccountPicker()
		}
	}

	private func presentAccountPicker() {
		guard let presentingController else { Self.current = nil; return }

		let title = NSLocalizedString("Choose an account to receive the imported feeds and folders", comment: "Import Account")
		let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController {
			if let barButtonItem {
				popoverController.barButtonItem = barButtonItem
			} else {
				popoverController.sourceView = sourceView ?? presentingController.view
				popoverController.sourceRect = sourceRect
			}
		}

		for account in AccountManager.shared.sortedActiveAccounts {
			let action = UIAlertAction(title: account.nameForDisplay, style: .default) { [weak self] _ in
				self?.account = account
				self?.presentDocumentPicker()
			}
			alert.addAction(action)
		}

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in
			Self.current = nil
		})

		presentingController.present(alert, animated: true)
	}

	private func presentDocumentPicker() {
		guard let presentingController else { Self.current = nil; return }

		var contentTypes: [UTType] = []

		// Create UTType for .opml files by extension, without requiring conformance.
		// This ensures files ending in .opml can be selected no matter how OPML is
		// registered. <https://github.com/Ranchero-Software/NetNewsWire/issues/4858>
		if let opmlByExtension = UTType(filenameExtension: "opml") {
			contentTypes.append(opmlByExtension)
		}
		if let registeredOPML = UTType("org.opml.opml") {
			contentTypes.append(registeredOPML)
		}
		contentTypes.append(.xml)

		let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
		documentPicker.delegate = self
		documentPicker.modalPresentationStyle = .formSheet
		presentingController.present(documentPicker, animated: true)
	}
}

extension OPMLImportCoordinator: UIDocumentPickerDelegate {

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
		let presentingController = self.presentingController
		let account = self.account
		for url in urls {
			account?.importOPML(url) { result in
				switch result {
				case .success:
					break
				case .failure:
					let title = NSLocalizedString("Import Failed", comment: "Import Failed")
					let message = NSLocalizedString("We were unable to process the selected file.  Please ensure that it is a properly formatted OPML file.", comment: "Import Failed Message")
					presentingController?.presentError(title: title, message: message)
				}
			}
		}
		Self.current = nil
	}

	func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
		Self.current = nil
	}
}
