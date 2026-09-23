import AO3Kit
//
//  AddFeedViewController.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 4/16/19.
//  Copyright © 2019 Ranchero Software, LLC. All rights reserved.
//

import UIKit
import Account
import RSCore
import RSTree
import RSParser

final class AddFeedViewController: UITableViewController {
	@IBOutlet var addButton: UIBarButtonItem!
	@IBOutlet var urlTextField: UITextField!
	@IBOutlet var urlTextFieldToSuperViewConstraint: NSLayoutConstraint!
	@IBOutlet var nameTextField: UITextField!

	static let preferredContentSizeForFormSheetDisplay = CGSize(width: 460.0, height: 400.0)

	private var folderLabel = ""
	private var userCancelled = false
	/// Set by the "Add Anyway" action of the long-URL warning so the
	/// re-entrant `add(_:)` doesn't warn a second time. Cleared when the
	/// URL text changes and after every attempt.
	private var userAcceptedLongAO3URL = false

	private let activityIndicator = UIActivityIndicatorView(style: .medium)

	var initialFeed: String?
	var initialFeedName: String?

	var container: Container?

	override func viewDidLoad() {
        super.viewDidLoad()

		if initialFeed == nil, let urlString = UIPasteboard.general.string {
			if urlString.mayBeURL {
				initialFeed = urlString.normalizedURL
			}
		}

		urlTextField.autocorrectionType = .no
		urlTextField.autocapitalizationType = .none
		urlTextField.text = initialFeed
		urlTextField.delegate = self

		if initialFeed != nil {
			addButton.isEnabled = true
		}

		nameTextField.text = initialFeedName
		nameTextField.delegate = self

		if let defaultContainer = AddFeedDefaultContainer.defaultContainer {
			container = defaultContainer
		} else {
			addButton.isEnabled = false
		}

		updateFolderLabel()

		tableView.register(UINib(nibName: "AddFeedSelectFolderTableViewCell", bundle: nil), forCellReuseIdentifier: "AddFeedSelectFolderTableViewCell")

		NotificationCenter.default.addObserver(self, selector: #selector(textDidChange(_:)), name: UITextField.textDidChangeNotification, object: urlTextField)

		if initialFeed == nil {
			urlTextField.becomeFirstResponder()
		}
	}

	@IBAction func cancel(_ sender: Any) {
		userCancelled = true
		dismiss(animated: true)
	}

	@IBAction func add(_ sender: Any) {

		let urlString = urlTextField.text ?? ""
		let normalizedURLString = urlString.normalizedURL

		guard !normalizedURLString.isEmpty, let url = URL(string: normalizedURLString) else {
			return
		}

		guard let container = container else { return }

		var account: Account?
		if let containerAccount = container as? Account {
			account = containerAccount
		} else if let containerFolder = container as? Folder, let containerAccount = containerFolder.account {
			account = containerAccount
		}

		if account!.hasFeed(withURL: url.absoluteString) {
			presentError(AccountError.createErrorAlreadySubscribed)
 			return
		}

		// A filtered AO3 URL past AO3FilterURLLength.limit may get its
		// filters silently dropped. Warn first; the person can still
		// continue, in which case the fetched page is checked (and the
		// feed not kept) if AO3 did drop them. Exactly at the limit there
		// is no warning -- only that same check.
		if AO3FilterURLLength.exceedsLimit(url), !userAcceptedLongAO3URL {
			presentAO3LongURLWarning()
			return
		}

		addButton.isEnabled = false
		addButton.customView = activityIndicator
		addButton.customView?.isHidden = false
		activityIndicator.startAnimating()

		let feedName = (nameTextField.text?.isEmpty ?? true) ? nil : nameTextField.text

		BatchUpdate.shared.start()

		account!.createFeed(url: url.absoluteString, name: feedName, container: container, validateFeed: true) { result in

			BatchUpdate.shared.end()
			self.userAcceptedLongAO3URL = false

			switch result {
			case .success(let feed):
				self.dismiss(animated: true)
				NotificationCenter.default.post(name: .UserDidAddFeed, object: self, userInfo: [UserInfoKey.feed: feed])
			case .failure(let error):
				self.addButton.isEnabled = true
				self.activityIndicator.stopAnimating()
				self.addButton.customView = nil

				// AO3 search-results feeds: the feed was already created
				// and added (see LocalAccountDelegate.createFeed's AO3
				// branch) even though this specific fetch came back
				// Cloudflare-challenged. Offer the WKWebView fallback as
				// an opt-in prompt (Workstream C) rather than the generic
				// error alert, since retrying "for real" is one tap away
				// and the feed the person just added is otherwise stuck
				// empty until they separately notice and retry.
				if case AccountError.ao3CloudflareChallenge(let challengedURL, let addedFeed) = error {
					self.presentAO3VerificationPrompt(challengedURL: challengedURL, feed: addedFeed, account: account!)
					return
				}

				// AO3 served its unfiltered listing. The feed was already
				// removed by LocalAccountDelegate.createFeed.
				if let accountError = error as? AccountError, case .ao3FiltersNotApplied = accountError {
					self.presentAO3FiltersNotApplied(accountError)
					return
				}

				self.presentError(error)
			}

		}

	}

	/// Opt-in prompt for Workstream C's WKWebView fallback -- shown instead
	/// of presenting the challenge solver automatically. Declining leaves
	/// the feed added-but-empty, same as today's pre-fallback behavior;
	/// the person can retry later (e.g. once "load more"/paginator UI
	/// exists) without losing the subscription.
	private func presentAO3VerificationPrompt(challengedURL: URL, feed: Feed, account: Account) {
		let alert = UIAlertController(
			title: NSLocalizedString("AO3 Needs Verification", comment: "AO3 Cloudflare challenge prompt title"),
			message: NSLocalizedString("The shelf was added, but AO3 needs you to verify you're not a bot before its results can load. Verify now?", comment: "AO3 Cloudflare challenge prompt message"),
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("Not Now", comment: "Decline AO3 verification"), style: .cancel) { [weak self] _ in
			self?.dismiss(animated: true)
			NotificationCenter.default.post(name: .UserDidAddFeed, object: self, userInfo: [UserInfoKey.feed: feed])
		})
		alert.addAction(UIAlertAction(title: NSLocalizedString("Verify", comment: "Accept AO3 verification"), style: .default) { [weak self] _ in
			guard let self else { return }
			Task { @MainActor in
				let coordinator = AO3SearchResultsFetchCoordinator()
				let outcome = await coordinator.presentSolverAndRetry(challengedURL: challengedURL, feedURL: feed.url, feed: feed, account: account, advancePageTo: 1, updatesFeedName: true, presentingViewController: self)
				// Same rule as the headless add path: a feed whose page turned
				// out to be AO3's unfiltered listing is not kept. Unlike that
				// path the feed already exists in the tree here, so it is
				// removed now, and the sheet stays open with the error.
				if case .filtersNotApplied = outcome {
					if let container = self.container {
						account.removeFeed(feed, from: container) { _ in }
					}
					self.presentAO3FiltersNotApplied(AccountError.ao3FiltersNotApplied(feed: feed))
					return
				}
				self.dismiss(animated: true)
				NotificationCenter.default.post(name: .UserDidAddFeed, object: self, userInfo: [UserInfoKey.feed: feed])
			}
		})
		present(alert, animated: true)
	}

	private func presentAO3LongURLWarning() {
		let limit = NumberFormatter.localizedString(from: NSNumber(value: AO3FilterURLLength.limit), number: .decimal)
		let messageFormat = NSLocalizedString("This URL is longer than %@ characters. AO3 may ignore the search’s filters and show its unfiltered “Latest Works” listing instead. If that happens, the shelf won’t be added.", comment: "AO3 long filter URL warning message")
		let alert = UIAlertController(
			title: NSLocalizedString("AO3 Search URL Is Very Long", comment: "AO3 long filter URL warning title"),
			message: String(format: messageFormat, limit),
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel adding a long AO3 URL"), style: .cancel))
		alert.addAction(UIAlertAction(title: NSLocalizedString("Add Anyway", comment: "Add a long AO3 URL despite the warning"), style: .default) { [weak self] _ in
			guard let self else { return }
			self.userAcceptedLongAO3URL = true
			self.add(self)
		})
		present(alert, animated: true)
	}

	/// `presentError(_:)` shows only `localizedDescription`, which would
	/// drop this error's recovery suggestion, so both are folded into one
	/// message here.
	private func presentAO3FiltersNotApplied(_ error: AccountError) {
		let message = [error.errorDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
		presentError(title: NSLocalizedString("AO3 Filters Not Applied", comment: "AO3 filters not applied alert title"), message: message)
	}

	@objc func textDidChange(_ note: Notification) {
		userAcceptedLongAO3URL = false
		updateUI()
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if indexPath.row == 2 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "AddFeedSelectFolderTableViewCell", for: indexPath) as? AddFeedSelectFolderTableViewCell
			cell!.detailLabel.text = folderLabel
			return cell!
		} else {
			return super.tableView(tableView, cellForRowAt: indexPath)
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if indexPath.row == 2 {
			let navController = UIStoryboard.add.instantiateViewController(withIdentifier: "AddFeedFolderNavViewController") as! UINavigationController
			navController.modalPresentationStyle = .currentContext
			let folderViewController = navController.topViewController as! AddFeedFolderViewController
			folderViewController.delegate = self
			folderViewController.initialContainer = container
			present(navController, animated: true)
		}
	}

}

// MARK: AddFeedFolderViewControllerDelegate

extension AddFeedViewController: AddFeedFolderViewControllerDelegate {
	func didSelect(container: Container) {
		self.container = container
		updateFolderLabel()
		AddFeedDefaultContainer.saveDefaultContainer(container)
	}
}

// MARK: UITextFieldDelegate

extension AddFeedViewController: UITextFieldDelegate {

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}

}

// MARK: Private

private extension AddFeedViewController {

	func updateUI() {
		addButton.isEnabled = (urlTextField.text?.mayBeURL ?? false)
	}

	func updateFolderLabel() {
		if let containerName = (container as? DisplayNameProvider)?.nameForDisplay {
			if container is Folder {
				folderLabel = "\(container?.account?.nameForDisplay ?? "") / \(containerName)"
			} else {
				folderLabel = containerName
			}
			tableView.reloadData()
		}
	}
}
