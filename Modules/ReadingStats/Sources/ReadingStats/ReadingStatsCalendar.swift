import Foundation

public struct ReadingStatsDailyEntry: Codable, Sendable, Equatable {
	public var wordsRead: Int
	public var secondsActive: Int
	public var wordsByFandom: [String: Int]
	public var wordsByTag: [String: Int]
	public var completedBookKeys: Set<String>
	public var worksByFandom: [String: Set<String>]
	public var worksByTag: [String: Set<String>]

	public init(wordsRead: Int = 0, secondsActive: Int = 0, wordsByFandom: [String: Int] = [:], wordsByTag: [String: Int] = [:], completedBookKeys: Set<String> = [], worksByFandom: [String: Set<String>] = [:], worksByTag: [String: Set<String>] = [:]) {
		self.wordsRead = wordsRead
		self.secondsActive = secondsActive
		self.wordsByFandom = wordsByFandom
		self.wordsByTag = wordsByTag
		self.completedBookKeys = completedBookKeys
		self.worksByFandom = worksByFandom
		self.worksByTag = worksByTag
	}

	private enum CodingKeys: String, CodingKey {
		case wordsRead, secondsActive, wordsByFandom, wordsByTag, completedBookKeys, worksByFandom, worksByTag
	}

	// Custom decode so one entry missing worksByFandom/worksByTag (i.e. any
	// day predating this migration) doesn't fail the whole dictionary's
	// decode -- AppDefaults.decode uses `try?` across the *entire*
	// [String: ReadingStatsDailyEntry] dictionary, so a single entry
	// throwing here would silently wipe all 35 days of history for every
	// user on first launch post-upgrade, not just lose the new fields for
	// old days. worksByFandom/worksByTag default to [:] for pre-migration
	// entries instead -- old days simply have no per-work breakdown.
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		wordsRead = try container.decode(Int.self, forKey: .wordsRead)
		secondsActive = try container.decode(Int.self, forKey: .secondsActive)
		wordsByFandom = try container.decode([String: Int].self, forKey: .wordsByFandom)
		wordsByTag = try container.decode([String: Int].self, forKey: .wordsByTag)
		completedBookKeys = try container.decode(Set<String>.self, forKey: .completedBookKeys)
		worksByFandom = try container.decodeIfPresent([String: Set<String>].self, forKey: .worksByFandom) ?? [:]
		worksByTag = try container.decodeIfPresent([String: Set<String>].self, forKey: .worksByTag) ?? [:]
	}
}

public struct ReadingStatsTotals: Sendable, Equatable {
	public let wordsRead: Int
	public let secondsActive: Int
	public let worksCompleted: Int
	public let byFandom: [String: Int]
	public let byTag: [String: Int]
	public let worksByFandom: [String: Int]
	public let worksByTag: [String: Int]

	public var wordsPerHour: Double {
		secondsActive > 0 ? Double(wordsRead) / (Double(secondsActive) / 3600.0) : 0
	}
}

// MARK: - Streaks graph / monthly stats
//
// The day-heatmap, month-of-year bar chart, and streak-counting logic below
// are adapted from Aidoku (https://github.com/Aidoku/Aidoku), specifically
// `Aidoku/Core/Library/Models/Insights/HeatmapData.swift`,
// `Aidoku/Core/Library/Models/Insights/YearlyMonthData.swift`, and the
// `getStreakLengths`/`getReadingHeatmapData`/`getChapterYearlyReadingData`
// methods of `Aidoku/Core/Database/CoreDataManager+ReadingSession.swift`.
// Copyright (c) the Aidoku authors (those source files' headers credit
// Skitty), licensed under GPL-3.0 (see the LICENSE file at the root of
// that repository). Adapted here to read from a day-keyed
// `[String: Int]` of words read (see `AppDefaults.readingStatsDailyWordCounts`)
// rather than a Core Data `ReadingSession` entity, and to count words
// rather than manga pages/chapters -- the day-bucketing this app already
// does made Aidoku's own history-scanning and per-day-Set deduplication
// in `getStreakLengths`/`getReadingHeatmapData` unnecessary, since a single
// dictionary lookup already gives one value per day. Per GPL-3.0, this file
// (and the ported SwiftUI views alongside it) are themselves GPL-3.0-
// licensed -- see THIRD-PARTY-NOTICES.md for the full notice and what that
// means for the surrounding MIT-licensed project.

/// One calendar month, 1-indexed to match `Calendar.component(.month:)`.
public enum ReadingMonth: Int, CaseIterable, Sendable, Identifiable {
	public var id: Int { rawValue }
	case january = 1, february, march, april, may, june, july, august, september, october, november, december
}

/// Word counts for each month of a single year. Ported from Aidoku's
/// `MonthData` (there: chapter-completion counts per month).
public struct ReadingMonthData: Sendable, Equatable {
	public var january = 0, february = 0, march = 0, april = 0, may = 0, june = 0
	public var july = 0, august = 0, september = 0, october = 0, november = 0, december = 0

	public init() {}

	public func value(for month: ReadingMonth) -> Int {
		switch month {
		case .january: january
		case .february: february
		case .march: march
		case .april: april
		case .may: may
		case .june: june
		case .july: july
		case .august: august
		case .september: september
		case .october: october
		case .november: november
		case .december: december
		}
	}

	public var maxValue: Int {
		[january, february, march, april, may, june, july, august, september, october, november, december].max() ?? 0
	}

	public var total: Int {
		[january, february, march, april, may, june, july, august, september, october, november, december].reduce(0, +)
	}

	public static func += (lhs: inout ReadingMonthData, rhs: ReadingMonthData) {
		lhs.january += rhs.january; lhs.february += rhs.february; lhs.march += rhs.march
		lhs.april += rhs.april; lhs.may += rhs.may; lhs.june += rhs.june
		lhs.july += rhs.july; lhs.august += rhs.august; lhs.september += rhs.september
		lhs.october += rhs.october; lhs.november += rhs.november; lhs.december += rhs.december
	}
}

public struct ReadingYearlyMonthData: Sendable, Equatable, Identifiable {
	public var id: Int { year }
	public let year: Int
	public let data: ReadingMonthData

	public init(year: Int, data: ReadingMonthData) {
		self.year = year
		self.data = data
	}
}

/// A year-long, week-aligned grid of daily word counts, for the GitHub-
/// style activity heatmap. Ported from Aidoku's `HeatmapData`.
public struct ReadingHeatmapData: Hashable, Sendable {
	public let startDate: Date
	public let values: [Int]

	public init(startDate: Date, values: [Int]) {
		self.startDate = startDate
		self.values = values
	}

	/// Walks back 364 days from today, then further back to the most
	/// recent `calendar.firstWeekday` on or before that date, so the grid
	/// always starts on a week boundary -- ported verbatim from Aidoku's
	/// `HeatmapData.getDaysAndStartDate()`.
	public static func daysAndStartDate(asOf: Date, calendar: Calendar) -> (totalDays: Int, startDate: Date) {
		let today = calendar.startOfDay(for: asOf)
		let initialStartDate = calendar.date(byAdding: .day, value: -364, to: today)!
		let weekday = calendar.component(.weekday, from: initialStartDate)
		let firstWeekday = calendar.firstWeekday
		let daysToSubtract = (weekday - firstWeekday + 7) % 7
		let alignedStartDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: initialStartDate)!
		let totalDays = 365 + daysToSubtract
		return (totalDays, alignedStartDate)
	}

	public static func empty(asOf: Date = Date(), calendar: Calendar = .current) -> ReadingHeatmapData {
		let (totalDays, startDate) = daysAndStartDate(asOf: asOf, calendar: calendar)
		return ReadingHeatmapData(startDate: startDate, values: Array(repeating: 0, count: totalDays))
	}
}

extension ReadingStatsCalendar {
	/// Ported from Aidoku's `CoreDataManager.getStreakLengths` -- the
	/// day-diff/consecutive-run loop and the "current streak must end
	/// today or yesterday" check are unchanged. Aidoku required at least
	/// 2 distinct reading days to report any streak at all (a lone day
	/// doesn't feel like a "streak"); kept here for the same reason. As in
	/// Aidoku, `current` can be 1 when the latest run is a single day and
	/// an older run of 2+ exists; callers treat `current <= 1` as "no
	/// current streak".
	public static func streakLengths(dailyWords: [String: Int], asOf: Date = Date(), calendar: Calendar = .current) -> (current: Int, longest: Int) {
		let formatter = keyFormatter(calendar)
		let days = dailyWords.compactMap { key, words in words > 0 ? formatter.date(from: key) : nil }.sorted()
		guard days.count >= 2 else { return (0, 0) }

		var current = 1
		var longest = 1
		for i in 1..<days.count {
			let prev = calendar.startOfDay(for: days[i - 1])
			let curr = calendar.startOfDay(for: days[i])
			let diff = calendar.dateComponents([.day], from: prev, to: curr).day ?? 0
			if diff == 1 {
				current += 1
				longest = max(longest, current)
			} else {
				current = 1
			}
		}

		let today = calendar.startOfDay(for: asOf)
		let lastDay = calendar.startOfDay(for: days.last!)
		let diff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
		let isCurrent = (diff == 0 || diff == 1) && longest >= 2

		return (current: isCurrent ? current : 0, longest: longest >= 2 ? longest : 0)
	}

	/// Ported from Aidoku's `CoreDataManager.getReadingHeatmapData`, minus
	/// the Core Data fetch/day-Set dedup -- `dailyWords` is already one
	/// value per day, so each day's cell value is just that day's words.
	public static func heatmapData(dailyWords: [String: Int], asOf: Date = Date(), calendar: Calendar = .current) -> ReadingHeatmapData {
		let (totalDays, startDate) = ReadingHeatmapData.daysAndStartDate(asOf: asOf, calendar: calendar)
		let formatter = keyFormatter(calendar)
		let values = (0..<totalDays).map { offset -> Int in
			let date = calendar.date(byAdding: .day, value: offset, to: startDate)!
			return dailyWords[formatter.string(from: date)] ?? 0
		}
		return ReadingHeatmapData(startDate: startDate, values: values)
	}

	/// Ported from Aidoku's `CoreDataManager.getChapterYearlyReadingData`
	/// -- there, a nested `[year: [month: chapterCount]]` dictionary built
	/// from per-chapter completion; here, a words-per-month sum straight
	/// off each day's words, since this app's history is already
	/// day-bucketed rather than needing chapter-level grouping and
	/// completion-threshold logic first.
	public static func yearlyMonthData(dailyWords: [String: Int], calendar: Calendar = .current) -> [ReadingYearlyMonthData] {
		let formatter = keyFormatter(calendar)
		var yearlyMonthWords: [Int: [Int: Int]] = [:]
		for (key, words) in dailyWords {
			guard words > 0, let date = formatter.date(from: key) else { continue }
			let comps = calendar.dateComponents([.year, .month], from: date)
			guard let year = comps.year, let month = comps.month else { continue }
			yearlyMonthWords[year, default: [:]][month, default: 0] += words
		}
		return yearlyMonthWords.keys.sorted().map { year in
			var data = ReadingMonthData()
			data.january = yearlyMonthWords[year]?[1] ?? 0
			data.february = yearlyMonthWords[year]?[2] ?? 0
			data.march = yearlyMonthWords[year]?[3] ?? 0
			data.april = yearlyMonthWords[year]?[4] ?? 0
			data.may = yearlyMonthWords[year]?[5] ?? 0
			data.june = yearlyMonthWords[year]?[6] ?? 0
			data.july = yearlyMonthWords[year]?[7] ?? 0
			data.august = yearlyMonthWords[year]?[8] ?? 0
			data.september = yearlyMonthWords[year]?[9] ?? 0
			data.october = yearlyMonthWords[year]?[10] ?? 0
			data.november = yearlyMonthWords[year]?[11] ?? 0
			data.december = yearlyMonthWords[year]?[12] ?? 0
			return ReadingYearlyMonthData(year: year, data: data)
		}
	}
}

public enum ReadingStatsCalendar {
	public static func totals(history: [String: ReadingStatsDailyEntry], range: ClosedRange<Date>, calendar: Calendar = .current) -> ReadingStatsTotals {
		let formatter = keyFormatter(calendar)
		var words = 0
		var seconds = 0
		var works = Set<String>()
		var fandoms = [String: Int]()
		var tags = [String: Int]()
		var worksByFandomSets = [String: Set<String>]()
		var worksByTagSets = [String: Set<String>]()
		for (key, entry) in history {
			guard let date = formatter.date(from: key), range.contains(date) else { continue }
			words += entry.wordsRead
			seconds += entry.secondsActive
			works.formUnion(entry.completedBookKeys)
			for (name, value) in entry.wordsByFandom { fandoms[name, default: 0] += value }
			for (name, value) in entry.wordsByTag { tags[name, default: 0] += value }
			for (name, keys) in entry.worksByFandom { worksByFandomSets[name, default: []].formUnion(keys) }
			for (name, keys) in entry.worksByTag { worksByTagSets[name, default: []].formUnion(keys) }
		}
		// Union-then-count, not a per-day sum: the same completed work can
		// appear in more than one day's entry within the range (e.g.
		// finished once but the 99% sample landed at a day-boundary edge
		// case, or the person re-finishes it inside the same range), and
		// summing per-day counts would double-count it.
		let worksByFandom = worksByFandomSets.mapValues(\.count)
		let worksByTag = worksByTagSets.mapValues(\.count)
		return ReadingStatsTotals(wordsRead: words, secondsActive: seconds, worksCompleted: works.count, byFandom: fandoms, byTag: tags, worksByFandom: worksByFandom, worksByTag: worksByTag)
	}

	private static func keyFormatter(_ calendar: Calendar) -> DateFormatter {
		let formatter = DateFormatter()
		formatter.calendar = calendar
		formatter.timeZone = calendar.timeZone
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}
}
