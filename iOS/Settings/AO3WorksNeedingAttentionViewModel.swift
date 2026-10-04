//
//  AO3WorksNeedingAttentionViewModel.swift
//  NetNewsWire-iOS
//
//  Backs the AO3 Works Needing Attention screen: works with a pending
//  content update, a feed-derived word-count regression flag, or a
//  confirmed-missing flag. Modeled on ManageStorageViewModel: `refresh()`
//  gathers a bounded list per account, merges it newest first, and trims it.
//
//  Every source of data and every action is an injected closure, so tests
//  need no database, accounts or network.
//
//  See docs/ao3-works-needing-attention.md.
//

import Foundation
import Observation
import Account
import ArticlesDatabase

enum AO3AttentionState: Sendable, Equatable {
	/// An unresolved pending content update waiting for the person to
	/// review it. Wins over the other states, since reviewing it is the
	/// next step and refetching is blocked until then.
	case pendingUpdate
	/// AO3 confirmed the work missing (HTTP 404/410 or its explicit
	/// not-found copy).
	case notFound
	/// A feed report claimed far fewer words than the stored text, so
	/// auto-fetch is paused for this work.
	case regressionFlagged
}

struct AO3AttentionRowData: Identifiable, Equatable, Sendable {
	let accountID: String
	let articleID: String
	let title: String
	let state: AO3AttentionState
	/// When the state's flag was set, used for sorting and display.
	let date: Date

	var id: String { "\(accountID)|\(articleID)" }

	/// nil when `info` carries no flag at all, which the query never
	/// returns but a caller could construct.
	static func make(accountID: String, info: ArticleAttentionInfo) -> AO3AttentionRowData? {
		let state: AO3AttentionState
		let date: Date?
		if info.hasPendingUpdate {
			state = .pendingUpdate
			date = info.pendingUpdateDetectedAt ?? info.ao3ConfirmedMissingAt ?? info.wordCountRegressionFlaggedAt
		} else if let missingAt = info.ao3ConfirmedMissingAt {
			state = .notFound
			date = missingAt
		} else if let flaggedAt = info.wordCountRegressionFlaggedAt {
			state = .regressionFlagged
			date = flaggedAt
		} else {
			return nil
		}
		let title = info.title?.isEmpty == false ? info.title! : NSLocalizedString("Untitled", comment: "Article title")
		return AO3AttentionRowData(accountID: accountID, articleID: info.articleID, title: title, state: state, date: date ?? .distantPast)
	}
}

/// What happened when the person asked to retry a work.
enum AO3AttentionRetryOutcome: Sendable, Equatable {
	/// A fetch started.
	case started
	/// Nothing started: the 60 second floor swallowed it, the work is not
	/// allowed to fetch from AO3 (an Ambrosia work with updates off), or it
	/// has no single AO3 page to fetch.
	case notStarted
	/// The account or article no longer exists.
	case unavailable
}

@MainActor @Observable final class AO3WorksNeedingAttentionViewModel {

	typealias AccountInfo = (accountID: String, info: [ArticleAttentionInfo])

	private(set) var rows = [AO3AttentionRowData]()
	private(set) var hasLoaded = false
	/// A message for the person after Retry Now, or nil.
	var notice: String?

	let displayLimit = 100
	private static let perAccountFetchLimit = 200

	@ObservationIgnored private let fetchAttention: @MainActor () async -> [AccountInfo]
	@ObservationIgnored private let retryWork: @MainActor (AO3AttentionRowData) async -> AO3AttentionRetryOutcome
	@ObservationIgnored private let clearWorkContent: @MainActor (AO3AttentionRowData) async -> Void

	init(
		fetchAttention: (@MainActor () async -> [AccountInfo])? = nil,
		retryWork: (@MainActor (AO3AttentionRowData) async -> AO3AttentionRetryOutcome)? = nil,
		clearWorkContent: (@MainActor (AO3AttentionRowData) async -> Void)? = nil
	) {
		let limit = Self.perAccountFetchLimit
		self.fetchAttention = fetchAttention ?? {
			var result = [AccountInfo]()
			for account in AccountManager.shared.sortedAccounts {
				result.append((account.accountID, await account.fetchAO3AttentionInfo(limit: limit)))
			}
			return result
		}
		self.retryWork = retryWork ?? Self.defaultRetry
		self.clearWorkContent = clearWorkContent ?? Self.defaultClearContent
	}

	/// Reloads every account's list, merged newest first and trimmed to
	/// `displayLimit`. `Self.perAccountFetchLimit` applies per account before the
	/// merge, so one large account cannot starve a smaller one.
	func refresh() async {
		var all = [AO3AttentionRowData]()
		for entry in await fetchAttention() {
			all.append(contentsOf: entry.info.compactMap { AO3AttentionRowData.make(accountID: entry.accountID, info: $0) })
		}
		all.sort { $0.date > $1.date }
		if all.count > displayLimit {
			all.removeLast(all.count - displayLimit)
		}
		rows = all
		hasLoaded = true
	}

	/// Clears the work's flags and asks the fetcher to check it now, then
	/// reloads the list and sets `notice` to say what happened. Not offered
	/// for a pending update, which `AO3ChapterFetcher.checkForUpdates`
	/// refuses until it is reviewed.
	func retryNow(_ row: AO3AttentionRowData) async {
		let outcome = await retryWork(row)
		switch outcome {
		case .started:
			notice = NSLocalizedString("Nectar is checking AO3 for this work now.", comment: "Works Needing Attention: retry started")
		case .notStarted:
			notice = NSLocalizedString("Nothing was started. Nectar may have already checked this work in the last minute, or it isn't set to fetch updates from AO3. Try again shortly.", comment: "Works Needing Attention: retry did not start")
		case .unavailable:
			notice = NSLocalizedString("This work is no longer available.", comment: "Works Needing Attention: account or article is gone")
		}
		await refresh()
	}

	/// Clears the work's stored content, same Account call Manage Storage
	/// uses, and drops the row without a full reload.
	func clearContent(_ row: AO3AttentionRowData) async {
		await clearWorkContent(row)
		rows.removeAll { $0.id == row.id }
	}

	// MARK: - Defaults

	private static func defaultRetry(_ row: AO3AttentionRowData) async -> AO3AttentionRetryOutcome {
		guard row.state != .pendingUpdate,
		      let account = AccountManager.shared.existingAccount(accountID: row.accountID) else {
			return .unavailable
		}
		// Both flags go: either one can be what stops auto-fetch, and a
		// successful fetch would clear them anyway. A failed or throttled
		// one leaves them cleared, which is the point of "retry".
		await account.clearAO3ConfirmedMissingAsync(forArticleID: row.articleID)
		await account.clearWordCountRegressionFlagAsync(forArticleID: row.articleID)
		guard let article = await account.fetchArticlesAsync(.articleIDs([row.articleID])).first else {
			return .unavailable
		}
		return AO3ChapterFetcher.shared.checkForUpdates(for: article) ? .started : .notStarted
	}

	private static func defaultClearContent(_ row: AO3AttentionRowData) async {
		guard let account = AccountManager.shared.existingAccount(accountID: row.accountID) else {
			return
		}
		await account.clearContent(articleIDs: [row.articleID])
	}
}
