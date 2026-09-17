import Foundation

public struct ReadingStatsDailyEntry: Codable, Sendable, Equatable {
	public var wordsRead: Int
	public var secondsActive: Int
	public var wordsByFandom: [String: Int]
	public var wordsByTag: [String: Int]
	public var completedBookKeys: Set<String>

	public init(wordsRead: Int = 0, secondsActive: Int = 0, wordsByFandom: [String: Int] = [:], wordsByTag: [String: Int] = [:], completedBookKeys: Set<String> = []) {
		self.wordsRead = wordsRead
		self.secondsActive = secondsActive
		self.wordsByFandom = wordsByFandom
		self.wordsByTag = wordsByTag
		self.completedBookKeys = completedBookKeys
	}
}

public struct ReadingStatsTotals: Sendable, Equatable {
	public let wordsRead: Int
	public let secondsActive: Int
	public let worksCompleted: Int
	public let byFandom: [String: Int]
	public let byTag: [String: Int]

	public var wordsPerHour: Double {
		secondsActive > 0 ? Double(wordsRead) / (Double(secondsActive) / 3600.0) : 0
	}
}

public enum ReadingStatsCalendar {
	public static func currentStreak(history: [String: ReadingStatsDailyEntry], asOf: Date, calendar: Calendar = .current) -> Int {
		let formatter = keyFormatter(calendar)
		let activeDays = Set(history.compactMap { key, entry in entry.wordsRead > 0 ? key : nil })
		var day = calendar.startOfDay(for: asOf)
		if !activeDays.contains(formatter.string(from: day)), let latest = activeDays.compactMap({ formatter.date(from: $0) }).max() {
			day = calendar.startOfDay(for: latest)
		}
		var count = 0
		while activeDays.contains(formatter.string(from: day)) {
			count += 1
			guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
			day = previous
		}
		return count
	}

	public static func totals(history: [String: ReadingStatsDailyEntry], range: ClosedRange<Date>, calendar: Calendar = .current) -> ReadingStatsTotals {
		let formatter = keyFormatter(calendar)
		var words = 0
		var seconds = 0
		var works = Set<String>()
		var fandoms = [String: Int]()
		var tags = [String: Int]()
		for (key, entry) in history {
			guard let date = formatter.date(from: key), range.contains(date) else { continue }
			words += entry.wordsRead
			seconds += entry.secondsActive
			works.formUnion(entry.completedBookKeys)
			for (name, value) in entry.wordsByFandom { fandoms[name, default: 0] += value }
			for (name, value) in entry.wordsByTag { tags[name, default: 0] += value }
		}
		return ReadingStatsTotals(wordsRead: words, secondsActive: seconds, worksCompleted: works.count, byFandom: fandoms, byTag: tags)
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
