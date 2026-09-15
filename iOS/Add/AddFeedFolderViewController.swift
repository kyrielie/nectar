//
//  AddFeedFolderViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 11/16/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import RSCore
import Account

@MainActor protocol AddFeedFolderViewControllerDelegate {
	func didSelect(container: Container)
}

final class AddFeedFolderViewController: UITableViewController {

	var delegate: AddFeedFolderViewControllerDelegate?
	var initialContainer: Container?

	/// When set, only this account's own folders are listed (no account
	/// row at all, from this account or any other) -- for callers that
	/// have already chosen an account elsewhere in their own UI (e.g.
	/// `AO3LinkListImportView`'s account picker) and just need "pick one
	/// of *this* account's folders", not "pick any account or folder in
	/// the app". `nil` (Add Feed's own usage) keeps the original
	/// every-account behavior.
	var accountFilter: Account?

	/// One row per account or folder, in flattened tree-walk order, each
	/// carrying its own nesting depth (0 = account, 1 = top-level folder,
	/// up to 3 = a folder nested to `nested-folders.md`'s cap) so the
	/// cell can indent itself accordingly. Replaces this controller's
	/// former flat `containers = [account] + account.sortedFolders`
	/// list, which only ever reached one folder level deep and made
	/// folders nested inside folders unreachable from this picker even
	/// though the rest of the app (drag-and-drop, the sidebar,
	/// `Folder.pathNames`) has supported up to 3 levels since
	/// `nested-folders.md` landed.
	private struct Row {
		let container: Container
		let depth: Int
	}

	private var rows = [Row]()

    override func viewDidLoad() {
        super.viewDidLoad()

		if let accountFilter {
			// The account itself is still offered as a row (depth 0),
			// same as the every-account branch below -- it's the
			// account's own top-level/root container, not another
			// account to filter out. Omitting it (as an earlier version
			// of this branch did) meant a caller that scoped the picker
			// to a single account with no *sub*folders yet -- only a
			// root the caller displays under a custom name, e.g. "the
			// account itself" -- saw an empty list, even though Add
			// Feed's own (unfiltered) picker shows that same row fine.
			// Only *other* accounts are excluded here.
			rows.append(Row(container: accountFilter, depth: 0))
			appendFolderRows(of: accountFilter, depth: 1)
		} else {
			let sortedActiveAccounts = AccountManager.shared.sortedActiveAccounts
			for account in sortedActiveAccounts {
				rows.append(Row(container: account, depth: 0))
				appendFolderRows(of: account, depth: 1)
			}
		}
    }

	/// Recurses into `container.sortedFolders` one level at a time,
	/// stopping at `depth > 3` as a defensive floor matching the cap
	/// `nested-folders.md` already enforces at folder-creation time
	/// elsewhere (OPML import, `ensureFolder(withFolderNames:)`,
	/// drag-and-drop) -- a folder deeper than that shouldn't exist to
	/// walk into, but this doesn't assume that invariant holds.
	private func appendFolderRows(of container: Container, depth: Int) {
		guard depth <= 3, let sortedFolders = container.sortedFolders else {
			return
		}
		for folder in sortedFolders {
			rows.append(Row(container: folder, depth: depth))
			appendFolderRows(of: folder, depth: depth + 1)
		}
	}

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let row = rows[indexPath.row]
		let container = row.container
		let cell: AddComboTableViewCell = {
			if container is Account {
				return tableView.dequeueReusableCell(withIdentifier: "AccountCell", for: indexPath) as! AddComboTableViewCell
			} else {
				return tableView.dequeueReusableCell(withIdentifier: "FolderCell", for: indexPath) as! AddComboTableViewCell
			}
		}()

		cell.setIndentationDepth(row.depth)

		if let smallIconProvider = container as? SmallIconProvider {
			cell.icon?.image = smallIconProvider.smallIcon?.image
		}

		if let displayNameProvider = container as? DisplayNameProvider {
			cell.label?.text = displayNameProvider.nameForDisplay
		}

		if let compContainer = initialContainer, container === compContainer {
			cell.accessoryType = .checkmark
		} else {
			cell.accessoryType = .none
		}

        return cell
    }

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let container = rows[indexPath.row].container

		if let account = container as? Account, account.behaviors.contains(.disallowFeedInRootFolder) {
			tableView.selectRow(at: nil, animated: false, scrollPosition: .none)
		} else {
			let cell = tableView.cellForRow(at: indexPath)
			cell?.accessoryType = .checkmark
			delegate?.didSelect(container: container)
			dismiss()
		}
	}

	// MARK: Actions

	@IBAction func cancel(_ sender: Any) {
		dismiss()
	}

}

private extension AddFeedFolderViewController {

	func dismiss() {
		dismiss(animated: true)
	}

}
