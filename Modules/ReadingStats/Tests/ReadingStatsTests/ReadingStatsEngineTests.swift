//
//  ReadingStatsEngineTests.swift
//  ReadingStatsTests
//
//  Unit tests for ReadingStatsEngine headless accounting: baseline computation,
//  speed bounding, re-reading credit calculation, and idle session expiration.
//

import Foundation
import Testing
@testable import ReadingStats

@Suite struct ReadingStatsEngineTests {

	// MARK: - Baseline Computation

	@Test func computeBaseline_forNewArticle_isZero() {
		let baseline = ReadingStatsEngine.computeBaseline(
			articleReadingProgress: nil,
			persistedHighWaterMark: nil
		)
		#expect(baseline == 0.0)
	}

	@Test func computeBaseline_preservesHighWaterMarkWhenHigher() {
		let baseline = ReadingStatsEngine.computeBaseline(
			articleReadingProgress: 0.3,
			persistedHighWaterMark: 0.6
		)
		#expect(baseline == 0.6)
	}

	@Test func computeBaseline_usesCurrentProgressWhenHigher() {
		let baseline = ReadingStatsEngine.computeBaseline(
			articleReadingProgress: 0.7,
			persistedHighWaterMark: 0.4
		)
		#expect(baseline == 0.7)
	}

	@Test func computeBaseline_reReadDetection_resetsToLowPositionWhenCompleted() {
		// Book previously finished (1.0). Re-opening at the beginning (0.0 or 0.05).
		let baselineAtZero = ReadingStatsEngine.computeBaseline(
			articleReadingProgress: 0.0,
			persistedHighWaterMark: 1.0
		)
		#expect(baselineAtZero == 0.0)

		let baselineAtFivePercent = ReadingStatsEngine.computeBaseline(
			articleReadingProgress: 0.05,
			persistedHighWaterMark: 0.99
		)
		#expect(baselineAtFivePercent == 0.05)
	}

	@Test func computeBaseline_completedWorkOpenedInMiddle_maintainsHighWaterMark() {
		// Book finished (1.0), but opened at 0.5 (>= 0.2)
		let baseline = ReadingStatsEngine.computeBaseline(
			articleReadingProgress: 0.5,
			persistedHighWaterMark: 1.0
		)
		#expect(baseline == 1.0)
	}

	// MARK: - Speed Bounding and Sample Processing

	@Test func processSample_returnsNilWhenArticleIsMissingOrEmpty() {
		var session = ReadingStatsSession()
		let now = Date(timeIntervalSince1970: 1_700_000_000)

		#expect(ReadingStatsEngine.processSample(session: &session, progress: 0.5, now: now, persistedHighWaterMark: nil) == nil)

		session.article = ReadingStatsArticle(bookKey: "empty", wordCount: 0)
		#expect(ReadingStatsEngine.processSample(session: &session, progress: 0.5, now: now, persistedHighWaterMark: nil) == nil)
	}

	@Test func processSample_firstSampleIsExemptFromSpeedCap() {
		var session = ReadingStatsSession()
		session.article = ReadingStatsArticle(bookKey: "test", wordCount: 1_000)
		session.sessionBaseline = 0.0

		let now = Date(timeIntervalSince1970: 1_700_000_000)
		let result = ReadingStatsEngine.processSample(
			session: &session,
			progress: 0.5,
			now: now,
			persistedHighWaterMark: 0.0
		)

		// First sample gets full delta without speed cap
		#expect(result?.words == 500)
		#expect(result?.isCompleted == false)
		#expect(result?.clampedProgress == 0.5)
		#expect(session.sessionCreditedWords == 500)
		#expect(session.lastSampleDate == now)
	}

	@Test func processSample_subsequentSampleSpeedIsBoundedBy500WPM() {
		var session = ReadingStatsSession()
		session.article = ReadingStatsArticle(bookKey: "test", wordCount: 10_000)
		session.sessionBaseline = 0.0

		let t0 = Date(timeIntervalSince1970: 1_700_000_000)
		_ = ReadingStatsEngine.processSample(session: &session, progress: 0.0, now: t0, persistedHighWaterMark: 0.0)

		// Rapid jump 30 seconds later to 50% (5,000 words delta)
		// Max words in 30s at 500 wpm = (30 / 60) * 500 = 250 words
		let t1 = t0.addingTimeInterval(30)
		let result = ReadingStatsEngine.processSample(
			session: &session,
			progress: 0.5,
			now: t1,
			persistedHighWaterMark: 0.0
		)

		#expect(result?.words == 250)
		#expect(session.sessionCreditedWords == 250)
	}

	@Test func processSample_allowsFullCreditWhenSufficientTimeElapsed() {
		var session = ReadingStatsSession()
		session.article = ReadingStatsArticle(bookKey: "test", wordCount: 1_000)
		session.sessionBaseline = 0.0

		let t0 = Date(timeIntervalSince1970: 1_700_000_000)
		_ = ReadingStatsEngine.processSample(session: &session, progress: 0.0, now: t0, persistedHighWaterMark: 0.0)

		// 120 seconds later, read to 50% (500 words).
		// Max words in 120s at 500 wpm = 1,000 words, so full 500 words are awarded.
		let t1 = t0.addingTimeInterval(120)
		let result = ReadingStatsEngine.processSample(
			session: &session,
			progress: 0.5,
			now: t1,
			persistedHighWaterMark: 0.0
		)

		#expect(result?.words == 500)
		#expect(session.sessionCreditedWords == 500)
	}

	// MARK: - Re-Reading Credit Flow

	@Test func processSample_reReadRecovery_creditsWordsWhenRestartingCompletedWork() {
		// Simulate opening an already completed work where readingProgress was unknown at open time
		var session = ReadingStatsSession()
		session.article = ReadingStatsArticle(bookKey: "reread-work", wordCount: 2_000)
		session.sessionBaseline = 1.0
		session.sessionStartProgress = 1.0

		let t0 = Date(timeIntervalSince1970: 1_700_000_000)
		// First scroll sample arrives at beginning (0.02 < 0.2)
		let initialSample = ReadingStatsEngine.processSample(
			session: &session,
			progress: 0.02,
			now: t0,
			persistedHighWaterMark: 1.0
		)

		// Session start should have recovered to 0.02
		#expect(session.sessionStartProgress == 0.02)
		#expect(session.sessionCreditedWords == 0)
		#expect(initialSample == nil) // net displacement from 0.02 to 0.02 is 0 words

		// 120 seconds later, user reads forward to 0.52 (50% progress = 1,000 words)
		// At 500 wpm for 120s, max words = 1,000.
		let t1 = t0.addingTimeInterval(120)
		let readSample = ReadingStatsEngine.processSample(
			session: &session,
			progress: 0.52,
			now: t1,
			persistedHighWaterMark: 1.0
		)

		#expect(readSample?.words == 1_000)
		#expect(readSample?.isCompleted == false)
		#expect(session.sessionCreditedWords == 1_000)
	}

	@Test func processSample_marksCompletionAtThreshold() {
		var session = ReadingStatsSession()
		session.article = ReadingStatsArticle(bookKey: "finishing-work", wordCount: 1_000)
		session.sessionBaseline = 0.8

		let t0 = Date(timeIntervalSince1970: 1_700_000_000)
		let result = ReadingStatsEngine.processSample(
			session: &session,
			progress: 0.995,
			now: t0,
			persistedHighWaterMark: 0.8
		)

		#expect(result?.isCompleted == true)
		#expect(result?.clampedProgress == 0.995)
	}

	// MARK: - Idle Session and Interaction Gating

	@Test func idleSessionAndInteractionGating_behavesCorrectlyAroundThreshold() {
		var session = ReadingStatsSession()
		let t0 = Date(timeIntervalSince1970: 1_700_000_000)

		#expect(ReadingStatsEngine.shouldEndIdleSession(session: session, now: t0) == false)
		#expect(ReadingStatsEngine.isInteractionActive(session: session, now: t0) == false)

		session.lastSampleDate = t0

		// Within threshold (180s)
		let withinThreshold = t0.addingTimeInterval(180)
		#expect(ReadingStatsEngine.shouldEndIdleSession(session: session, now: withinThreshold) == false)
		#expect(ReadingStatsEngine.isInteractionActive(session: session, now: withinThreshold) == true)

		// Exceeded threshold (> 180s)
		let pastThreshold = t0.addingTimeInterval(180.1)
		#expect(ReadingStatsEngine.shouldEndIdleSession(session: session, now: pastThreshold) == true)
		#expect(ReadingStatsEngine.isInteractionActive(session: session, now: pastThreshold) == false)
	}

	// MARK: - Date Formatting

	@Test func dateKey_formatsPOSIXDateString() {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(secondsFromGMT: 0)!
		let components = DateComponents(year: 2026, month: 10, day: 28, hour: 12)
		let date = calendar.date(from: components)!

		#expect(ReadingStatsEngine.dateKey(date) == "2026-10-28")
	}
}
