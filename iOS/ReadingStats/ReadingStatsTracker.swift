import Foundation
import UIKit
import Articles
import Account

@MainActor final class ReadingStatsTracker {
	static let shared = ReadingStatsTracker()
	static var now: () -> Date = { Date() }

	struct ArticleSnapshot: Sendable {
		let bookKey: String
		let wordCount: Int
		let fandoms: [String]
		let tags: [String]
	}

	private var timer: Timer?
	private let activeTime = ActiveTimeAccumulator(isActive: UIApplication.shared.applicationState != .background)
	private var currentArticle: ArticleSnapshot?
	private var sessionBaseline: Double = 0

	// Session state (Phase 3c): credit is tracked per-session net
	// displacement from where the session started, not against a
	// persistent all-time high-water mark -- so re-reading a finished
	// work credits again. sessionStartProgress == nil means no session is
	// currently open (nothing to credit progress against).
	private var sessionStartProgress: Double?
	private var sessionCreditedWords: Int = 0

	// Timestamp of the last recordProgress(_:) call. Doubles as the
	// per-sample-cap elapsed-time reference (3b) and the interaction-gate/
	// idle-session-end reference (3d/3c) -- both use the same 180s idle
	// threshold so they can't disagree about what "idle" means.
	private var lastSampleDate: Date?

	/// Reading is credited using a plausible-fast-skimming upper bound so a
	/// TOC jump, scroll-to-bottom, or scrollbar drag can't credit every
	/// word it skips over. Also used as the interaction/idle-session
	/// threshold's implicit pairing constant is separate (see idleSessionThresholdSeconds).
	private static let maxWordsPerMinute = 500.0

	/// Starting constant, not a researched value -- no source confirms an
	/// exact idle threshold for this app's reading patterns. Used both to
	/// end a session with no recent scroll sample (3c) and to gate
	/// per-tick secondsActive credit on recent interaction (3d).
	private static let idleSessionThresholdSeconds: TimeInterval = 180

	private init() {}

	func start() {
		guard timer == nil else { return }
		NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: UIApplication.willResignActiveNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
		if UIApplication.shared.applicationState != .background {
			activeTime.becomeActive(now: Self.now())
		}
		timer = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
		RunLoop.current.add(timer!, forMode: .common)
	}

	/// Called with a non-provisional article to start (or continue) a
	/// session; called with `nil` or a different bookKey to end one.
	/// `WebViewController` withholds `recordProgress` calls while its own
	/// `isContentProvisional` guard is set, so a session never starts
	/// against stub content -- that's enforced at the call site, not here.
	func setArticle(_ article: Article?) {
		guard let article, let wordCount = article.wordCount, wordCount > 0 else {
			endSession()
			currentArticle = nil
			return
		}
		let key = article.bookKey.isEmpty ? article.articleID : article.bookKey
		if key != currentArticle?.bookKey {
			endSession()
		}
		currentArticle = ArticleSnapshot(bookKey: key, wordCount: wordCount, fandoms: article.fandoms ?? [], tags: article.additionalTags ?? [])
		// Baseline seeds from whichever is further along: the persisted
		// all-time high-water mark, or the article's own persisted reading
		// progress (covers a fresh install / re-sync where the high-water
		// mark dictionary hasn't caught up yet).
		sessionBaseline = max(
			AppDefaults.shared.readingStatsProgressByBookKey[key] ?? 0,
			article.status.readingProgress ?? 0
		)
		startSessionIfNeeded()
	}

	private func startSessionIfNeeded() {
		guard sessionStartProgress == nil else { return }
		sessionStartProgress = sessionBaseline
		sessionCreditedWords = 0
	}

	private func endSession() {
		sessionStartProgress = nil
		sessionCreditedWords = 0
		lastSampleDate = nil
	}

	func recordProgress(_ progress: Double) {
		guard AppDefaults.shared.readingStatsTrackingEnabled,
		      let article = currentArticle else { return }
		startSessionIfNeeded()
		guard let sessionStart = sessionStartProgress else { return }
		let clamped = min(max(progress, 0), 1)
		let now = Self.now()
		let elapsedSinceLastSample = lastSampleDate.map { now.timeIntervalSince($0) } ?? 0
		let isFirstSampleThisSession = lastSampleDate == nil
		lastSampleDate = now

		let netDisplacement = max(0, clamped - sessionStart)
		let totalWordsForSession = Int(netDisplacement * Double(article.wordCount))
		let deltaWords = max(0, totalWordsForSession - sessionCreditedWords)

		// Per-sample cap (3b): bound the credit by a plausible reading
		// speed over the elapsed time since the last sample, except on
		// the session's first sample, where there's no meaningful elapsed
		// time yet and capping would wrongly zero out legitimate
		// baseline-seeded credit from setArticle's sessionBaseline.
		let maxWordsForElapsed = (elapsedSinceLastSample / 60.0) * Self.maxWordsPerMinute
		let words = isFirstSampleThisSession ? deltaWords : min(deltaWords, Int(max(maxWordsForElapsed, 0)))
		guard words > 0 else { return }

		sessionCreditedWords += words
		// Persist current absolute position for baseline-seeding on the
		// *next* session/app launch. This dictionary no longer means "the
		// position this session started crediting from" -- it's purely
		// "the furthest absolute position ever reached."
		var progressByKey = AppDefaults.shared.readingStatsProgressByBookKey
		progressByKey[article.bookKey] = max(progressByKey[article.bookKey] ?? 0, clamped)
		AppDefaults.shared.readingStatsProgressByBookKey = progressByKey

		var history = AppDefaults.shared.readingStatsDailyHistory
		let key = Self.dateKey(now)
		var entry = history[key] ?? ReadingStatsDailyEntry()
		entry.wordsRead += words
		for fandom in article.fandoms { entry.wordsByFandom[fandom, default: 0] += words }
		for tag in article.tags { entry.wordsByTag[tag, default: 0] += words }
		if clamped >= 0.99 {
			entry.completedBookKeys.insert(article.bookKey)
			for fandom in article.fandoms { entry.worksByFandom[fandom, default: []].insert(article.bookKey) }
			for tag in article.tags { entry.worksByTag[tag, default: []].insert(article.bookKey) }
		}
		history[key] = entry
		AppDefaults.shared.readingStatsDailyHistory = history
		AppDefaults.shared.readingStatsAllTimeWords += words
		NotificationCenter.default.post(name: .readingStatsDidChange, object: self)
	}

	@objc private func willResignActive() {
		tick()
		activeTime.resignActive()
		endSession()
	}
	@objc private func didBecomeActive() { activeTime.becomeActive(now: Self.now()); tick() }
	@objc private func tick() {
		guard AppDefaults.shared.readingStatsTrackingEnabled, currentArticle != nil else { return }
		let now = Self.now()
		// Idle-session end (3c): no scroll sample in the idle window means
		// the session is over even though the app is still foregrounded
		// (e.g. the reader is sitting open, unscrolled, while the person
		// does something else). The *next* recordProgress call opens a
		// fresh session via startSessionIfNeeded().
		if let lastSample = lastSampleDate, now.timeIntervalSince(lastSample) > Self.idleSessionThresholdSeconds {
			endSession()
		}
		guard let elapsed = activeTime.tick(now: now) else { return }
		// Interaction-gated seconds (3d): only credit active time if
		// there's been a scroll sample within the idle window -- sitting
		// on a long, unscrolled viewport stops crediting reading time
		// until the next scroll.
		guard let lastSample = lastSampleDate, now.timeIntervalSince(lastSample) <= Self.idleSessionThresholdSeconds else { return }
		var history = AppDefaults.shared.readingStatsDailyHistory
		let key = Self.dateKey(now)
		var entry = history[key] ?? ReadingStatsDailyEntry()
		entry.secondsActive += elapsed
		history[key] = entry
		AppDefaults.shared.readingStatsDailyHistory = history
		NotificationCenter.default.post(name: .readingStatsDidChange, object: self)
	}

	private static func dateKey(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter.string(from: date)
	}

#if DEBUG
	func resetForTesting() {
		currentArticle = nil
		sessionBaseline = 0
		sessionStartProgress = nil
		sessionCreditedWords = 0
		lastSampleDate = nil
		activeTime.resetForTesting(isActive: UIApplication.shared.applicationState != .background)
	}
#endif
}
