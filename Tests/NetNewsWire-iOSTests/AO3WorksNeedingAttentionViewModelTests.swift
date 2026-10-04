//
//  AO3WorksNeedingAttentionViewModelTests.swift
//  NetNewsWire-iOSTests
//
//  Row state precedence, merge/sort/trim in refresh(), and the retry and
//  clear-content flows. Data and actions are injected closures, so no
//  database, account or network is involved.
//

import Testing
import Foundation
import ArticlesDatabase
@testable import Nectar

@MainActor @Suite(.serialized) struct AO3WorksNeedingAttentionViewModelTests {

	private static let base = Date(timeIntervalSince1970: 1_700_000_000)

	private static func info(
		_ articleID: String,
		title: String? = "Title",
		pendingAt: Date? = nil,
		regressionAt: Date? = nil,
		missingAt: Date? = nil,
		hasPending: Bool = false
	) -> ArticleAttentionInfo {
		ArticleAttentionInfo(articleID: articleID, title: title, bookKey: nil, pendingUpdateDetectedAt: pendingAt, wordCountRegressionFlaggedAt: regressionAt, ao3ConfirmedMissingAt: missingAt, hasPendingUpdate: hasPending)
	}

	private final class Recorder {
		var data = [AO3WorksNeedingAttentionViewModel.AccountInfo]()
		var retried = [String]()
		var cleared = [String]()
		var retryOutcome = AO3AttentionRetryOutcome.started
		var onRetry: (() -> Void)?
	}

	private func makeModel(_ recorder: Recorder) -> AO3WorksNeedingAttentionViewModel {
		AO3WorksNeedingAttentionViewModel(
			fetchAttention: { recorder.data },
			retryWork: { row in
				recorder.retried.append(row.articleID)
				recorder.onRetry?()
				return recorder.retryOutcome
			},
			clearWorkContent: { row in
				recorder.cleared.append(row.articleID)
			}
		)
	}

	// MARK: - Row state

	@Test func pendingUpdateWinsOverEveryOtherFlag() throws {
		let row = try #require(AO3AttentionRowData.make(accountID: "a", info: Self.info("1", pendingAt: Self.base, regressionAt: Self.base.addingTimeInterval(10), missingAt: Self.base.addingTimeInterval(20), hasPending: true)))

		#expect(row.state == .pendingUpdate)
		#expect(row.date == Self.base)
	}

	@Test func notFoundWinsOverRegression() throws {
		let missingAt = Self.base.addingTimeInterval(5)
		let row = try #require(AO3AttentionRowData.make(accountID: "a", info: Self.info("1", regressionAt: Self.base, missingAt: missingAt)))

		#expect(row.state == .notFound)
		#expect(row.date == missingAt)
	}

	@Test func regressionAlone() throws {
		let row = try #require(AO3AttentionRowData.make(accountID: "a", info: Self.info("1", regressionAt: Self.base)))

		#expect(row.state == .regressionFlagged)
		#expect(row.date == Self.base)
	}

	@Test func noFlagMakesNoRow() {
		#expect(AO3AttentionRowData.make(accountID: "a", info: Self.info("1")) == nil)
	}

	@Test func missingTitleFallsBackToUntitled() throws {
		for title in [nil, ""] as [String?] {
			let row = try #require(AO3AttentionRowData.make(accountID: "a", info: Self.info("1", title: title, missingAt: Self.base)))
			#expect(row.title == NSLocalizedString("Untitled", comment: "Article title"))
		}
	}

	@Test func rowIDIncludesTheAccount() throws {
		let first = try #require(AO3AttentionRowData.make(accountID: "a", info: Self.info("1", missingAt: Self.base)))
		let second = try #require(AO3AttentionRowData.make(accountID: "b", info: Self.info("1", missingAt: Self.base)))

		#expect(first.id != second.id)
	}

	// MARK: - refresh

	@Test func hasLoadedFlipsAfterTheFirstRefresh() async {
		let recorder = Recorder()
		let model = makeModel(recorder)
		#expect(!model.hasLoaded)

		await model.refresh()

		#expect(model.hasLoaded)
		#expect(model.rows.isEmpty)
	}

	@Test func refreshMergesAccountsNewestFirst() async {
		let recorder = Recorder()
		recorder.data = [
			("a", [Self.info("old", missingAt: Self.base), Self.info("newest", missingAt: Self.base.addingTimeInterval(300))]),
			("b", [Self.info("middle", regressionAt: Self.base.addingTimeInterval(100))])
		]
		let model = makeModel(recorder)

		await model.refresh()

		#expect(model.rows.map(\.articleID) == ["newest", "middle", "old"])
		#expect(model.rows.map(\.accountID) == ["a", "b", "a"])
	}

	@Test func refreshTrimsToTheDisplayLimitKeepingTheNewest() async {
		let recorder = Recorder()
		let infos = (0..<130).map { Self.info("w\($0)", missingAt: Self.base.addingTimeInterval(Double($0))) }
		recorder.data = [("a", infos)]
		let model = makeModel(recorder)

		await model.refresh()

		#expect(model.rows.count == model.displayLimit)
		#expect(model.rows.first?.articleID == "w129")
		#expect(model.rows.last?.articleID == "w30")
	}

	// MARK: - retry

	@Test func retryStartedSetsNoticeAndReloads() async throws {
		let recorder = Recorder()
		recorder.data = [("a", [Self.info("1", missingAt: Self.base)])]
		recorder.onRetry = { recorder.data = [("a", [])] }
		let model = makeModel(recorder)
		await model.refresh()
		let row = try #require(model.rows.first)

		await model.retryNow(row)

		#expect(recorder.retried == ["1"])
		#expect(model.notice != nil)
		#expect(model.rows.isEmpty)
	}

	@Test func retryNoticesDifferByOutcome() async throws {
		let recorder = Recorder()
		recorder.data = [("a", [Self.info("1", missingAt: Self.base)])]
		let model = makeModel(recorder)
		await model.refresh()
		let row = try #require(model.rows.first)

		var notices = [String]()
		for outcome in [AO3AttentionRetryOutcome.started, .notStarted, .unavailable] {
			recorder.retryOutcome = outcome
			model.notice = nil
			await model.retryNow(row)
			notices.append(try #require(model.notice))
		}

		#expect(Set(notices).count == 3)
	}

	// MARK: - clear content

	@Test func clearContentRemovesOnlyThatRow() async throws {
		let recorder = Recorder()
		recorder.data = [("a", [Self.info("1", missingAt: Self.base), Self.info("2", missingAt: Self.base.addingTimeInterval(1))])]
		let model = makeModel(recorder)
		await model.refresh()
		let row = try #require(model.rows.first { $0.articleID == "1" })

		await model.clearContent(row)

		#expect(recorder.cleared == ["1"])
		#expect(model.rows.map(\.articleID) == ["2"])
	}
}
