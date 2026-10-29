import Foundation
import ReadingStats
import UIKit
import Articles
import Account

@MainActor final class ReadingStatsTracker {
	static let shared = ReadingStatsTracker()
	static var now: () -> Date = { Date() }
	static var maxWordsPerMinute: Double { ReadingStatsEngine.maxWordsPerMinute }

	typealias ArticleSnapshot = ReadingStatsArticle

	private let ticker = ForegroundTicker()
	private let activeTime = ActiveTimeAccumulator(isActive: UIApplication.shared.applicationState != .background)
	private var session = ReadingStatsSession()

	private init() {}

	func start() {
		ticker.start(target: self, tick: #selector(tick), willResignActive: #selector(willResignActive), didBecomeActive: #selector(didBecomeActive)) {
			if UIApplication.shared.applicationState != .background {
				activeTime.becomeActive(now: Self.now())
			}
		}
	}

	/// Called with a non-provisional article to start (or continue) a
	/// session; called with `nil` or a different bookKey to end one.
	/// `WebViewController` withholds `recordProgress` calls while its own
	/// `isContentProvisional` guard is set, so a session never starts
	/// against stub content -- that's enforced at the call site, not here.
	func setArticle(_ article: Article?) {
		guard let article, let wordCount = article.wordCount, wordCount > 0 else {
			session.endSession()
			session.article = nil
			return
		}
		let key = article.bookKey.isEmpty ? article.articleID : article.bookKey
		if key != session.article?.bookKey {
			session.endSession()
		}
		session.article = ReadingStatsArticle(
			bookKey: key,
			wordCount: wordCount,
			fandoms: article.fandoms ?? [],
			tags: article.additionalTags ?? []
		)
		let persistedHighWater = AppDefaults.shared.readingStatsProgressByBookKey[key]
		session.sessionBaseline = ReadingStatsEngine.computeBaseline(
			articleReadingProgress: article.status.readingProgress,
			persistedHighWaterMark: persistedHighWater
		)
		if session.sessionStartProgress == nil {
			session.sessionStartProgress = session.sessionBaseline
			session.sessionCreditedWords = 0
		}
	}

	func recordProgress(_ progress: Double) {
		guard AppDefaults.shared.readingStatsTrackingEnabled,
		      let article = session.article else { return }

		let now = Self.now()
		let persistedHighWater = AppDefaults.shared.readingStatsProgressByBookKey[article.bookKey]

		guard let result = ReadingStatsEngine.processSample(
			session: &session,
			progress: progress,
			now: now,
			persistedHighWaterMark: persistedHighWater
		) else { return }

		let words = result.words
		let clamped = result.clampedProgress

		// Persist high water mark
		var progressByKey = AppDefaults.shared.readingStatsProgressByBookKey
		progressByKey[article.bookKey] = max(progressByKey[article.bookKey] ?? 0, clamped)
		AppDefaults.shared.readingStatsProgressByBookKey = progressByKey

		var history = AppDefaults.shared.readingStatsDailyHistory
		let key = ReadingStatsEngine.dateKey(now)
		var entry = history[key] ?? ReadingStatsDailyEntry()
		entry.wordsRead += words
		for fandom in article.fandoms { entry.wordsByFandom[fandom, default: 0] += words }
		for tag in article.tags { entry.wordsByTag[tag, default: 0] += words }

		if result.isCompleted {
			entry.completedBookKeys.insert(article.bookKey)
			for fandom in article.fandoms { entry.worksByFandom[fandom, default: []].insert(article.bookKey) }
			for tag in article.tags { entry.worksByTag[tag, default: []].insert(article.bookKey) }
		}
		history[key] = entry
		AppDefaults.shared.readingStatsDailyHistory = history
		var dailyWords = AppDefaults.shared.readingStatsDailyWords
		dailyWords[key, default: 0] += words
		AppDefaults.shared.readingStatsDailyWords = dailyWords
		AppDefaults.shared.readingStatsAllTimeWords += words
		NotificationCenter.default.post(name: .readingStatsDidChange, object: self)
	}

	@objc private func willResignActive() {
		tick()
		activeTime.resignActive()
		session.endSession()
	}

	@objc private func didBecomeActive() {
		activeTime.becomeActive(now: Self.now())
		tick()
	}

	@objc private func tick() {
		guard AppDefaults.shared.readingStatsTrackingEnabled, session.article != nil else { return }
		let now = Self.now()

		// Idle-session end: no scroll sample in the idle window means
		// the session is over even though the app is still foregrounded.
		if ReadingStatsEngine.shouldEndIdleSession(session: session, now: now) {
			session.endSession()
		}

		guard let elapsed = activeTime.tick(now: now) else { return }

		// Interaction-gated seconds: only credit active time if
		// there's been a scroll sample within the idle window.
		guard ReadingStatsEngine.isInteractionActive(session: session, now: now) else { return }

		var history = AppDefaults.shared.readingStatsDailyHistory
		let key = ReadingStatsEngine.dateKey(now)
		var entry = history[key] ?? ReadingStatsDailyEntry()
		entry.secondsActive += elapsed
		history[key] = entry
		AppDefaults.shared.readingStatsDailyHistory = history
		NotificationCenter.default.post(name: .readingStatsDidChange, object: self)
	}

#if DEBUG
	func resetForTesting() {
		session = ReadingStatsSession()
		activeTime.resetForTesting(isActive: UIApplication.shared.applicationState != .background)
	}
#endif
}
