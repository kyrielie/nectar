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
	private var lastTick: Date?
	private var currentArticle: ArticleSnapshot?
	private var sessionBaseline: Double = 0

	private init() {}

	func start() {
		guard timer == nil else { return }
		NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: UIApplication.willResignActiveNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
		lastTick = Self.now()
		timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
	}

	func setArticle(_ article: Article?) {
		guard let article, let wordCount = article.wordCount, wordCount > 0 else {
			currentArticle = nil
			return
		}
		let key = article.bookKey.isEmpty ? article.articleID : article.bookKey
		currentArticle = ArticleSnapshot(bookKey: key, wordCount: wordCount, fandoms: article.fandoms ?? [], tags: article.additionalTags ?? [])
		sessionBaseline = AppDefaults.shared.readingStatsProgressByBookKey[key] ?? 0
	}

	func recordProgress(_ progress: Double) {
		guard AppDefaults.shared.readingStatsTrackingEnabled, let article = currentArticle else { return }
		let clamped = min(max(progress, 0), 1)
		var progressByKey = AppDefaults.shared.readingStatsProgressByBookKey
		let previous = progressByKey[article.bookKey] ?? sessionBaseline
		guard clamped > previous else { return }
		let words = Int((clamped - previous) * Double(article.wordCount))
		progressByKey[article.bookKey] = clamped
		AppDefaults.shared.readingStatsProgressByBookKey = progressByKey
		guard words > 0 else { return }
		var history = AppDefaults.shared.readingStatsDailyHistory
		let key = Self.dateKey(Self.now())
		var entry = history[key] ?? ReadingStatsDailyEntry()
		entry.wordsRead += words
		for fandom in article.fandoms { entry.wordsByFandom[fandom, default: 0] += words }
		for tag in article.tags { entry.wordsByTag[tag, default: 0] += words }
		if clamped >= 0.99 { entry.completedBookKeys.insert(article.bookKey) }
		history[key] = entry
		AppDefaults.shared.readingStatsDailyHistory = history
		AppDefaults.shared.readingStatsAllTimeWords += words
		NotificationCenter.default.post(name: .readingStatsDidChange, object: self)
	}

	@objc private func willResignActive() { tick(); lastTick = nil }
	@objc private func didBecomeActive() { lastTick = Self.now(); tick() }
	@objc private func tick() {
		guard AppDefaults.shared.readingStatsTrackingEnabled, currentArticle != nil, let previous = lastTick else { lastTick = Self.now(); return }
		let now = Self.now()
		lastTick = now
		let elapsed = max(0, Int(now.timeIntervalSince(previous).rounded(.down)))
		guard elapsed > 0 else { return }
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
}
