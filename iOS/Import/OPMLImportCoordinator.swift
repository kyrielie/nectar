//
//  OPMLImportCoordinator.swift
//  Nectar
//
//  Copyright © 2026 Ranchero Software, LLC. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers
import Account

/// Account-picker -> document-picker -> import flow, shared by any entry point that
/// wants "pick an OPML file and import it" without duplicating the multi-account
/// picker/import-failure-alert logic.
///
/// Scoped narrower than the plan originally sketched: `SettingsViewController`'s own
/// existing `importOPML(sourceView:sourceRect:)` chain is left as-is rather than
/// refactored to call through here, since that code already works and re-plumbing it
/// carries real regression risk without a build/test pass available while writing this.
/// This coordinator is a second, independent implementation of the same three-step
/// flow, used only by the new Add Feed button entry points (§12) below. If the
/// duplication between this file and `SettingsViewController`'s OPML extension becomes
/// a maintenance problem, that refactor is still worth doing as a separate, dedicated
/// pass -- flag if wanted.
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
