//
//  ManageStorageViewModel.swift
//  NetNewsWire
//
//  Manual, size-sorted cleanup tool -- not a retention policy. There is no
//  automatic eviction of archived article content; see Task 5 of
//  nectar-ao3-features-plan-FINAL.md for the reasoning.
//

import Foundation
import Account
import ArticlesDatabase

struct ManageStorageRowData {
	let accountID: String
	let articleID: String
	let title: String
	let bookKey: String?
	let storedContentHTMLSize: Int
}

@MainActor final class ManageStorageViewModel {

	/// Largest N articles by stored `contentHTML` size, across every
	/// account, sorted descending. `limit` is applied per-account before
	/// merging, then again after merging, so a single huge account can't
	/// starve the combined list of a smaller account's largest rows.
	private(set) var rows = [ManageStorageRowData]()

	/// Sum of every account's stored `contentHTML` size -- an honest number
	/// since it's the compressed size actually on disk, not a decompressed
	/// estimate.
	private(set) var totalStoredContentHTMLSize = 0

	private let perAccountFetchLimit = 200
	let displayLimit = 100

	func refresh() async {
		var allRows = [ManageStorageRowData]()
		var total = 0

		for account in AccountManager.shared.sortedAccounts {
			let info = await account.fetchArticleStorageInfo(limit: perAccountFetchLimit)
			for item in info {
				allRows.append(ManageStorageRowData(
					accountID: account.accountID,
					articleID: item.articleID,
					title: item.title?.isEmpty == false ? item.title! : NSLocalizedString("Untitled", comment: "Article title"),
					bookKey: item.bookKey,
					storedContentHTMLSize: item.storedContentHTMLSize
				))
			}
			total += await account.fetchTotalContentHTMLSize()
		}

		allRows.sort { $0.storedContentHTMLSize > $1.storedContentHTMLSize }
		if allRows.count > displayLimit {
			allRows.removeLast(allRows.count - displayLimit)
		}

		rows = allRows
		totalStoredContentHTMLSize = total
	}

	/// Deletes the article (same as any existing per-article delete path --
	/// removes the row entirely) and removes it from `rows`/adjusts the
	/// total so the screen doesn't need a full `refresh()` after every
	/// delete.
	func delete(_ row: ManageStorageRowData) async {
		guard let account = AccountManager.shared.existingAccount(accountID: row.accountID) else {
			return
		}
		await account.delete(articleIDs: [row.articleID])

		rows.removeAll { $0.articleID == row.articleID && $0.accountID == row.accountID }
		totalStoredContentHTMLSize -= row.storedContentHTMLSize
	}
}
