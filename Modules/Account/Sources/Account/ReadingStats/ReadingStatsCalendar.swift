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
