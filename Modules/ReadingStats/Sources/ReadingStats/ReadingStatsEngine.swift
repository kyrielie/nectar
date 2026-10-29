//
//  ReadingStatsEngine.swift
//  ReadingStats
//
//  Headless accounting engine for Reading Stats: session displacement tracking,
//  reading speed bounding (500 wpm cap), re-reading credit calculation, and
//  idle session expiration. Pure Swift with zero UIKit dependencies.
//

import Foundation

public struct ReadingStatsArticle: Sendable, Equatable {
	public let bookKey: String
	public let wordCount: Int
	public let fandoms: [String]
	public let tags: [String]

	public init(bookKey: String, wordCount: Int, fandoms: [String] = [], tags: [String] = []) {
		self.bookKey = bookKey
		self.wordCount = wordCount
		self.fandoms = fandoms
		self.tags = tags
	}
}

public struct ReadingStatsSession: Sendable, Equatable {
	public var article: ReadingStatsArticle?
	public var sessionBaseline: Double = 0
	public var sessionStartProgress: Double?
	public var sessionCreditedWords: Int = 0
	public var lastSampleDate: Date?

	public init(
		article: ReadingStatsArticle? = nil,
		sessionBaseline: Double = 0,
		sessionStartProgress: Double? = nil,
		sessionCreditedWords: Int = 0,
		lastSampleDate: Date? = nil
	) {
		self.article = article
		self.sessionBaseline = sessionBaseline
		self.sessionStartProgress = sessionStartProgress
		self.sessionCreditedWords = sessionCreditedWords
		self.lastSampleDate = lastSampleDate
	}

	public var isSessionActive: Bool {
		sessionStartProgress != nil
	}

	public mutating func endSession() {
		sessionStartProgress = nil
		sessionCreditedWords = 0
		lastSampleDate = nil
	}
}

public struct ReadingStatsCreditResult: Sendable, Equatable {
	public let words: Int
	public let isCompleted: Bool
	public let clampedProgress: Double

	public init(words: Int, isCompleted: Bool, clampedProgress: Double) {
		self.words = words
		self.isCompleted = isCompleted
		self.clampedProgress = clampedProgress
	}
}

public enum ReadingStatsEngine {

	/// Upper bound on credited reading speed (500 words/minute) to prevent
	/// instant TOC jumps or scrollbar flings from awarding words they skip over.
	public static let maxWordsPerMinute: Double = 500.0

	/// Idle session threshold (180 seconds). A reader sitting unscrolled for
	/// longer than this pauses active time credit and ends the current session.
	public static let idleSessionThresholdSeconds: TimeInterval = 180.0

	/// Threshold fraction at which an article is counted as completed (99%).
	public static let completionThreshold: Double = 0.99

	/// Computes the initial baseline for an article session.
	/// If a book was previously completed, and the reader starts at a low position
	/// (< 0.2), this is recognized as a re-read and seeded from the low position
	/// rather than clamping at 1.0.
	public static func computeBaseline(
		articleReadingProgress: Double?,
		persistedHighWaterMark: Double?
	) -> Double {
		let highWater = persistedHighWaterMark ?? 0
		let current = articleReadingProgress ?? 0

		// Re-read detection: if the book was already completed, but the current
		// position is near the beginning (< 0.2), re-seed from the current position.
		if highWater >= completionThreshold && current < 0.2 {
			return current
		}

		return max(highWater, current)
	}

	/// Processes a scroll progress sample against the session, applying net displacement
	/// and speed bounding. Returns a credit result if words were earned.
	public static func processSample(
		session: inout ReadingStatsSession,
		progress: Double,
		now: Date,
		persistedHighWaterMark: Double?
	) -> ReadingStatsCreditResult? {
		guard let article = session.article, article.wordCount > 0 else {
			return nil
		}

		// Ensure session start is initialized
		if session.sessionStartProgress == nil {
			session.sessionStartProgress = session.sessionBaseline
			session.sessionCreditedWords = 0
		}

		let clamped = min(max(progress, 0), 1)

		// Re-read mid-session recovery: if session was seeded at 1.0 because readingProgress
		// was unknown at open time, but the first sample arrives near the beginning (< 0.2),
		// reset the session start to the low re-read position so credit can accrue.
		if let start = session.sessionStartProgress,
		   start >= completionThreshold,
		   clamped < 0.2,
		   (persistedHighWaterMark ?? 0) >= completionThreshold {
			session.sessionStartProgress = clamped
			session.sessionBaseline = clamped
			session.sessionCreditedWords = 0
		}

		guard let sessionStart = session.sessionStartProgress else {
			return nil
		}

		let elapsedSinceLastSample = session.lastSampleDate.map { now.timeIntervalSince($0) } ?? 0
		let isFirstSampleThisSession = session.lastSampleDate == nil
		session.lastSampleDate = now

		let netDisplacement = max(0, clamped - sessionStart)
		let totalWordsForSession = Int(netDisplacement * Double(article.wordCount))
		let deltaWords = max(0, totalWordsForSession - session.sessionCreditedWords)

		// Per-sample cap: bound credit by plausible reading speed over elapsed time,
		// except on the session's first sample.
		let maxWordsForElapsed = (elapsedSinceLastSample / 60.0) * maxWordsPerMinute
		let words = isFirstSampleThisSession ? deltaWords : min(deltaWords, Int(max(maxWordsForElapsed, 0)))

		guard words > 0 else {
			return nil
		}

		session.sessionCreditedWords += words
		let isCompleted = clamped >= completionThreshold

		return ReadingStatsCreditResult(
			words: words,
			isCompleted: isCompleted,
			clampedProgress: clamped
		)
	}

	/// Evaluates whether an idle session should expire.
	public static func shouldEndIdleSession(session: ReadingStatsSession, now: Date) -> Bool {
		guard let lastSample = session.lastSampleDate else { return false }
		return now.timeIntervalSince(lastSample) > idleSessionThresholdSeconds
	}

	/// Checks if user interaction occurred recently enough to credit active seconds.
	public static func isInteractionActive(session: ReadingStatsSession, now: Date) -> Bool {
		guard let lastSample = session.lastSampleDate else { return false }
		return now.timeIntervalSince(lastSample) <= idleSessionThresholdSeconds
	}

	/// Standard date key for daily entries (yyyy-MM-dd).
	public static func dateKey(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter.string(from: date)
	}
}
