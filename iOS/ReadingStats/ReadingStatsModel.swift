//
//  ReadingStatsModel.swift
//  NetNewsWire-iOS
//
//  Observable state behind `ReadingStatsView`: owns tracking toggle,
//  period/metric selection, and live stats reloading after reset.
//

import Foundation
import ReadingStats

@MainActor final class ReadingStatsModel: ObservableObject {

	@Published var trackingEnabled: Bool {
		didSet {
			AppDefaults.shared.readingStatsTrackingEnabled = trackingEnabled
		}
	}

	@Published var isMonthlyPeriod = false
	@Published var statsMetric: StatsMetric = .words

	@Published private(set) var dailyHistory: [String: ReadingStatsDailyEntry]
	@Published private(set) var dailyWords: [String: Int]
	@Published private(set) var allTimeWords: Int

	init() {
		self.trackingEnabled = AppDefaults.shared.readingStatsTrackingEnabled
		self.dailyHistory = AppDefaults.shared.readingStatsDailyHistory
		self.dailyWords = AppDefaults.shared.readingStatsDailyWordCounts
		self.allTimeWords = AppDefaults.shared.readingStatsAllTimeWords
	}

	var totals: ReadingStatsTotals {
		let end = Date()
		let start = Calendar.current.date(byAdding: .day, value: isMonthlyPeriod ? -29 : -6, to: Calendar.current.startOfDay(for: end)) ?? end
		return ReadingStatsCalendar.totals(history: dailyHistory, range: start...end, calendar: .current)
	}

	var streaks: (current: Int, longest: Int) {
		ReadingStatsCalendar.streakLengths(dailyWords: dailyWords)
	}

	var yearlyMonthData: [ReadingYearlyMonthData] {
		ReadingStatsCalendar.yearlyMonthData(dailyWords: dailyWords)
	}

	var fandomSlices: [(name: String, value: Int)] {
		let source = statsMetric == .works ? totals.worksByFandom : totals.byFandom
		let sorted = source.sorted { $0.value > $1.value }
		guard sorted.count > 4 else { return sorted.map { ($0.key, $0.value) } }
		let top = sorted.prefix(4).map { ($0.key, $0.value) }
		let other = sorted.dropFirst(4).reduce(0) { $0 + $1.value }
		return other > 0 ? top + [("Other", other)] : top
	}

	var topTags: [(name: String, value: Int)] {
		let source = statsMetric == .works ? totals.worksByTag : totals.byTag
		let sorted = source.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
		return Array(sorted.prefix(5).map { ($0.key, $0.value) })
	}

	func reload() {
		dailyHistory = AppDefaults.shared.readingStatsDailyHistory
		dailyWords = AppDefaults.shared.readingStatsDailyWordCounts
		allTimeWords = AppDefaults.shared.readingStatsAllTimeWords
	}

	func resetReadingStats() {
		AppDefaults.shared.resetReadingStats()
		reload()
	}
}
