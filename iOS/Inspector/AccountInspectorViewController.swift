//
//  AccountInspectorViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 5/17/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import RSCore
import Account

final class AccountInspectorViewController: UITableViewController {
	static let preferredContentSizeForFormSheetDisplay = CGSize(width: 460.0, height: 400.0)

	@IBOutlet var nameTextField: UITextField!
	@IBOutlet var activeSwitch: UISwitch!
	@IBOutlet var deleteAccountButton: VibrantButton!
	@IBOutlet var syncContentSwitch: UISwitch!
	@IBOutlet var limitationsAndSolutionsButton: UIButton!

	var isModal = false
	weak var account: Account?

    override func viewDidLoad() {
        super.viewDidLoad()

		guard let account = account else { return }

		nameTextField.placeholder = account.defaultName
		nameTextField.text = account.name
		nameTextField.delegate = self
		activeSwitch.isOn = account.isActive

		navigationItem.title = account.nameForDisplay

		// Nectar only ever has `.onMyMac` accounts; these controls were
		// cloudKit-only and are now permanently unreachable. Left wired to the
		// storyboard as hidden no-ops rather than touching Interface Builder XML.
		syncContentSwitch.isHidden = true
		limitationsAndSolutionsButton.isHidden = true

		if isModal {
			let doneBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
			navigationItem.leftBarButtonItem = doneBarButtonItem
		}

		tableView.register(ImageHeaderView.self, forHeaderFooterViewReuseIdentifier: "SectionHeader")

	}

	override func viewWillDisappear(_ animated: Bool) {
		account?.name = nameTextField.text
		account?.isActive = activeSwitch.isOn
	}

	// Unreachable: sync-content section is never shown (see displayedSections),
	// but the action stays wired so the storyboard connection isn't left dangling.
	@IBAction func syncContentSwitchDidChange(_ sender: UISwitch) {}

	@objc func done() {
		dismiss(animated: true)
	}

	// Unreachable: the credentials section is never shown (see displayedSections)
	// now that only `.onMyMac` accounts exist; kept as a no-op for the storyboard wiring.
	@IBAction func credentials(_ sender: Any) {}

	@IBAction func deleteAccount(_ sender: Any) {
		guard account != nil else {
			return
		}

		let title = NSLocalizedString("Remove Account", comment: "Remove Account")
		let message = NSLocalizedString("Are you sure you want to remove this account? This cannot be undone.", comment: "Remove Account")
		let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel)
		alertController.addAction(cancelAction)

		let markTitle = NSLocalizedString("Remove", comment: "Remove")
		let markAction = UIAlertAction(title: markTitle, style: .destructive) { [weak self] _ in
			guard let self, let account = self.account else {
				return
			}
			AccountManager.shared.deleteAccount(account)
			if self.isModal {
				self.dismiss(animated: true)
			} else {
				self.navigationController?.popViewController(animated: true)
			}
		}
		alertController.addAction(markAction)
		alertController.preferredAction = markAction

		present(alertController, animated: true)
	}

	// Unreachable: limitationsAndSolutionsButton is permanently hidden now that
	// cloudKit accounts no longer exist; kept as a no-op for the storyboard wiring.
	@IBAction func openLimitationsAndSolutions(_ sender: Any) {}
}

// MARK: - Table View

extension AccountInspectorViewController {

	/// Sections as laid out in the storyboard. `.credentials` and `.syncContent`
	/// are cloudKit/Feedly-only and unreachable now that only `.onMyMac`
	/// accounts exist, but the raw values are left as-is since they still
	/// correspond to real (unused) sections in the storyboard.
	enum StoryboardSection: Int {
		case nameAndActive = 0
		case deleteAccount = 2
	}

	/// The storyboard sections to display, in order, for the current account.
	///
	/// - Default account: name/active only
	/// - Any other (additional local) account: name/active, delete
	var displayedSections: [StoryboardSection] {
		guard let account else {
			return []
		}
		if account == AccountManager.shared.defaultAccount {
			return [.nameAndActive]
		}
		return [.nameAndActive, .deleteAccount]
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		displayedSections.count
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		let storyboardIndex = displayedSections[section].rawValue
		return super.tableView(tableView, numberOfRowsInSection: storyboardIndex)
	}

	override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		if displayedSections[section] == .nameAndActive {
			return ImageHeaderView.rowHeight
		}
		let storyboardIndex = displayedSections[section].rawValue
		return super.tableView(tableView, heightForHeaderInSection: storyboardIndex)
	}

	override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		guard let account else {
			return nil
		}
		if displayedSections[section] == .nameAndActive {
			let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SectionHeader") as! ImageHeaderView
			headerView.imageView.image = Assets.accountImage(account.type)
			return headerView
		}
		let storyboardIndex = displayedSections[section].rawValue
		return super.tableView(tableView, viewForHeaderInSection: storyboardIndex)
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let storyboardIndex = displayedSections[indexPath.section].rawValue
		return super.tableView(tableView, cellForRowAt: IndexPath(row: indexPath.row, section: storyboardIndex))
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		let storyboardIndex = displayedSections[section].rawValue
		return super.tableView(tableView, titleForFooterInSection: storyboardIndex)
	}

	override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
		if indexPath.section > 0 {
			return true
		}
		return false
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
	}
}

// MARK: UITextFieldDelegate

extension AccountInspectorViewController: UITextFieldDelegate {

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
}
