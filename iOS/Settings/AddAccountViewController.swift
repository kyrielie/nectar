//
//  AddAccountViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 5/16/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import Account
import UIKit
import RSCore

protocol AddAccountDismissDelegate: UIViewController {
	func dismiss()
}

// Ambrosia Reader: local-only fork. Every non-local AccountType onboarding
// path is stripped here; the enum cases themselves are left alone in
// Account.swift since removing them would touch too much shared code for
// no benefit. "Add Ambrosia Library" (paired local account, see Phase 4)
// will be added here as an additional local.sectionContent entry once it
// exists; for now this offers exactly one flow: a plain local account.
final class AddAccountViewController: UITableViewController, AddAccountDismissDelegate {

	private enum AddAccountSections: Int, CaseIterable {
		case local = 0

		var sectionHeader: String {
			switch self {
			case .local:
				return NSLocalizedString("Local", comment: "Local Account")
			}
		}

		var sectionFooter: String {
			switch self {
			case .local:
				return NSLocalizedString("Local accounts do not sync your feeds across devices", comment: "Local Account")
			}
		}

		var sectionContent: [AccountType] {
			switch self {
			case .local:
				return [.onMyMac]
			}
		}
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return AddAccountSections.allCases.count
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if section == AddAccountSections.local.rawValue {
			return AddAccountSections.local.sectionContent.count
		}

		return 0
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch section {
		case AddAccountSections.local.rawValue:
			return AddAccountSections.local.sectionHeader
		default:
			return nil
		}
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		switch section {
		case AddAccountSections.local.rawValue:
			return AddAccountSections.local.sectionFooter
		default:
			return nil
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsAccountTableViewCell", for: indexPath) as! SettingsComboTableViewCell

		switch indexPath.section {
		case AddAccountSections.local.rawValue:
			cell.comboNameLabel?.text = AddAccountSections.local.sectionContent[indexPath.row].displayName
			cell.comboImage?.image = Assets.accountImage(.onMyMac)
		default:
			return cell
		}
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

		switch indexPath.section {
		case AddAccountSections.local.rawValue:
			let type = AddAccountSections.local.sectionContent[indexPath.row]
			presentController(for: type)
		default:
			return
		}
	}

	private func presentController(for accountType: AccountType) {
		switch accountType {
		case .onMyMac:
			let navController = UIStoryboard.account.instantiateViewController(withIdentifier: "LocalAccountNavigationViewController") as! UINavigationController
			navController.modalPresentationStyle = .currentContext
			let addViewController = navController.topViewController as! LocalAccountViewController
			addViewController.delegate = self
			present(navController, animated: true)
		default:
			// Ambrosia Reader is local-only; every other AccountType's
			// onboarding path has been removed. This case is unreachable
			// because sectionContent above only ever offers .onMyMac.
			assertionFailure("Unsupported account type in Ambrosia Reader fork: \(accountType)")
		}
	}

	func dismiss() {
		navigationController?.popViewController(animated: false)
	}

}
