//
//  ReadingStatsTrackerAccountingTests.swift
//  NetNewsWire-iOSTests
//
//  Regression coverage for Phase 3 of the Reading Stats fix plan: baseline
//  seeding from persisted reading progress, the per-sample reading-speed
//  cap, the per-session net-displacement credit model (replacing the old
//  persistent-high-water-mark model, which never re-credited a finished
//  work), and the worksByFandom/worksByTag migration.
//
//  Time is driven deterministically through ReadingStatsTracker.now, the
//  same injection point ScreenTimeTrackerTests uses for its sibling
//  tracker. .serialized: every test drives the same shared singleton.
//

import Testing
import Foundation
import Articles
import ReadingStats
@testable import Nectar
@testable import Account

@Suite(.serialized) @MainActor struct ReadingStatsTrackerAccountingTests {

	private func resetState() {
		AppDefaults.shared.readingStatsTrackingEnabled = true
		AppDefaults.shared.readingStatsDailyHistory = [:]
		AppDefaults.shared.readingStatsDailyWords = [:]
		AppDefaults.shared.readingStatsProgressByBookKey = [:]
		AppDefaults.shared.readingStatsAllTimeWords = 0
		ReadingStatsTracker.shared.resetForTesting()
		ReadingStatsTracker.shared.setArticle(nil)
		ReadingStatsTracker.now = { Date() }
	}

	private func makeArticle(bookKey: String, wordCount: Int, readingProgress: Double? = nil) -> Article {
		let articleID = "test-article-id-\(UUID().uuidString)"
		let dateArrived = Date(timeIntervalSince1970: 1_500_000_000)
		let status = ArticleStatus(articleID: articleID, read: false, starred: false, dateArrived: dateArrived, readingProgress: readingProgress)
		return Article(
			accountID: "test-account-id",
			articleID: articleID,
			feedID: "test-feed-id",
			uniqueID: "test-unique-id",
			title: "Test Title",
			contentHTML: "<p>content</p>",
			contentText: nil,
			markdown: nil,
			url: nil,
			externalURL: nil,
			summary: nil,
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			wordCount: wordCount,
			fandoms: ["Test Fandom"],
			additionalTags: ["Fluff"],
			bookKey: bookKey,
			status: status
		)
	}

	@Test func baselineSeeding_usesArticleStatusReadingProgress_whenNoPersistedHighWaterMark() {
		resetState()
		defer { resetState() }

		let start = Date(timeIntervalSince1970: 1_700_000_000)
		ReadingStatsTracker.now = { start }

		// No persisted readingStatsProgressByBookKey entry, but the article
		// itself already reports 40% read (e.g. via a fresh sync).
		let article = makeArticle(bookKey: "book-1", wordCount: 10_000, readingProgress: 0.4)
		ReadingStatsTracker.shared.setArticle(article)

		// First sample just past the baseline: only the small net movement
		// should be credited, not the entire 0...0.41 jump.
		ReadingStatsTracker.shared.recordProgress(0.41)

		#expect(AppDefaults.shared.readingStatsAllTimeWords <= 200)
	}

	@Test func perSampleCap_hugeInstantaneousJumpIsCapped() {
		resetState()
		defer { resetState() }

		let start = Date(timeIntervalSince1970: 1_700_000_000)
		ReadingStatsTracker.now = { start }
		let article = makeArticle(bookKey: "book-2", wordCount: 100_000)
		ReadingStatsTracker.shared.setArticle(article)

		// First sample of the session establishes lastSampleDate with no cap.
		ReadingStatsTracker.shared.recordProgress(0.01)
		let afterFirst = AppDefaults.shared.readingStatsAllTimeWords

		// Second sample: a TOC-jump-style huge instantaneous move, no time
		// elapsed. Credited words must be capped near zero, not the full jump.
		ReadingStatsTracker.shared.recordProgress(0.9)
		let creditedForJump = AppDefaults.shared.readingStatsAllTimeWords - afterFirst

		#expect(creditedForJump < 100)
	}

	/// Reading Stats counts a work as completed on the same predicate
	/// WebViewController uses to mark it read (ReadingProgressEvaluator's
	/// completion threshold). Driving the tracker with values derived from
	/// that constant means this fails if either side is changed alone.
	@Test func completion_isCountedAtTheSharedThreshold() {
		resetState()
		defer { resetState() }

		let start = Date(timeIntervalSince1970: 1_700_000_000)
		ReadingStatsTracker.now = { start }
		let article = makeArticle(bookKey: "book-threshold-at", wordCount: 1_000)
		ReadingStatsTracker.shared.setArticle(article)
		ReadingStatsTracker.shared.recordProgress(ReadingProgressEvaluator.completionThreshold)

		let history = AppDefaults.shared.readingStatsDailyHistory
		#expect(history.values.contains { $0.completedBookKeys.contains("book-threshold-at") })
	}

	@Test func completion_isNotCountedJustBelowTheSharedThreshold() {
		resetState()
		defer { resetState() }

		let start = Date(timeIntervalSince1970: 1_700_000_000)
		ReadingStatsTracker.now = { start }
		let article = makeArticle(bookKey: "book-threshold-below", wordCount: 1_000)
		ReadingStatsTracker.shared.setArticle(article)
		ReadingStatsTracker.shared.recordProgress(ReadingProgressEvaluator.completionThreshold - 0.001)

		// Words are credited (so the completion branch is actually reached),
		// but the work isn't counted as completed.
		#expect(AppDefaults.shared.readingStatsAllTimeWords > 0)
		let history = AppDefaults.shared.readingStatsDailyHistory
		#expect(!history.values.contains { $0.completedBookKeys.contains("book-threshold-below") })
	}

	/// NOTE ON PLAN DISCREPANCY: the plan's own 3c prose claims re-reading a
	/// finished work "now credits again" because "sessionStart resets to
	/// the low re-read position at the start of the new session" -- but
	/// the literal 3a formula (`max(persisted, article.status.readingProgress)`)
	/// contradicts that: `readingStatsProgressByBookKey` only ever grows
	/// (via `max` in recordProgress), so once a book reaches 1.0 there,
	/// every future session's baseline re-seeds at 1.0 regardless of where
	/// the reader actually re-starts, permanently blocking re-read credit
	/// for that book. This test pins the plan's *literal* code's actual
	/// behavior (no re-read credit once persisted progress hits 1.0), not
	/// the prose's claimed behavior -- flagged for follow-up, see the
	/// implementation notes.
	@Test func sessionReread_literalPlanFormula_doesNotCreditAfterFullCompletion() {
		resetState()
		defer { resetState() }

		let start = Date(timeIntervalSince1970: 1_700_000_000)
		ReadingStatsTracker.now = { start }
		let article = makeArticle(bookKey: "book-3", wordCount: 1_000)
		ReadingStatsTracker.shared.setArticle(article)
		ReadingStatsTracker.shared.recordProgress(1.0) // finishes the work

		let history = AppDefaults.shared.readingStatsDailyHistory
		let key = history.keys.first
		#expect(key.flatMap { history[$0]?.completedBookKeys.contains("book-3") } == true)

		ReadingStatsTracker.shared.setArticle(nil)
		let later = start.addingTimeInterval(60)
		ReadingStatsTracker.now = { later }
		ReadingStatsTracker.shared.setArticle(article) // status.readingProgress still nil in this fixture
		let beforeReread = AppDefaults.shared.readingStatsAllTimeWords
		ReadingStatsTracker.shared.recordProgress(0.5)

		// As specified, this does NOT credit -- see the NOTE above.
		#expect(AppDefaults.shared.readingStatsAllTimeWords == beforeReread)
	}

	@Test func migration_preMigrationHistoryDecodesWithEmptyWorksBreakdown() {
		resetState()
		defer { resetState() }

		let json = """
		{"2026-01-01":{"wordsRead":500,"secondsActive":120,"wordsByFandom":{"Test Fandom":500},"wordsByTag":{"Fluff":500},"completedBookKeys":["book-x"]}}
		"""
		AppDefaults.store.set(json, forKey: "readingStatsDailyHistory")

		let history = AppDefaults.shared.readingStatsDailyHistory
		#expect(!history.isEmpty)
		let entry = history["2026-01-01"]
		#expect(entry?.wordsRead == 500)
		#expect(entry?.worksByFandom.isEmpty == true)
		#expect(entry?.worksByTag.isEmpty == true)
	}

	// MARK: - Daily words store (feeds Streaks/Monthly)

	@Test func recordProgress_writesDailyWordsStore() {
		resetState()
		defer { resetState() }

		let start = Date(timeIntervalSince1970: 1_700_000_000)
		ReadingStatsTracker.now = { start }
		let article = makeArticle(bookKey: "book-daily", wordCount: 100_000)
		ReadingStatsTracker.shared.setArticle(article)
		ReadingStatsTracker.shared.recordProgress(0.01)

		let credited = AppDefaults.shared.readingStatsAllTimeWords
		#expect(credited > 0)
		let daily = AppDefaults.shared.readingStatsDailyWords
		#expect(daily.count == 1)
		#expect(daily.values.reduce(0, +) == credited)
	}

	@Test func dailyWordCounts_takeTheLargerOfStoreAndHistory() {
		resetState()
		defer { resetState() }

		// A day recorded before the daily store existed, a day the store
		// only partly saw (the day of the upgrade), and a store-only day.
		AppDefaults.shared.readingStatsDailyHistory = [
			"2026-01-01": ReadingStatsDailyEntry(wordsRead: 100),
			"2026-01-02": ReadingStatsDailyEntry(wordsRead: 80)
		]
		AppDefaults.shared.readingStatsDailyWords = ["2026-01-02": 30, "2026-01-03": 60]

		let merged = AppDefaults.shared.readingStatsDailyWordCounts
		#expect(merged == ["2026-01-01": 100, "2026-01-02": 80, "2026-01-03": 60])
	}

	@Test func dailyWordsStore_keepsOnlyTheLast371Days() {
		resetState()
		defer { resetState() }

		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(secondsFromGMT: 0)!
		let formatter = DateFormatter()
		formatter.calendar = calendar
		formatter.timeZone = calendar.timeZone
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		let first = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
		let keys = (0..<400).map { formatter.string(from: calendar.date(byAdding: .day, value: $0, to: first)!) }
		AppDefaults.shared.readingStatsDailyWords = Dictionary(uniqueKeysWithValues: keys.map { ($0, 1) })

		let stored = AppDefaults.shared.readingStatsDailyWords
		#expect(stored.count == 371)
		#expect(stored[keys[0]] == nil)
		#expect(stored[keys[399]] == 1)
	}

	@Test func resetReadingStats_clearsDailyWordsStore() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.readingStatsDailyWords = ["2026-01-01": 10]
		AppDefaults.shared.resetReadingStats()
		#expect(AppDefaults.shared.readingStatsDailyWords.isEmpty)
	}
}
