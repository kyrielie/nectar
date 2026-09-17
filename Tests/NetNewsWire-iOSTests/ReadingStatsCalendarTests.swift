import Foundation
import Testing
import Account

@Suite struct ReadingStatsCalendarTests {
	private var calendar: Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(secondsFromGMT: 0)!
		return calendar
	}

	@Test func totalsMergeDailyBuckets() {
		let history = [
			"2026-01-01": ReadingStatsDailyEntry(wordsRead: 100, secondsActive: 60, wordsByFandom: ["A": 100], wordsByTag: ["x": 100], completedBookKeys: ["one"]),
			"2026-01-02": ReadingStatsDailyEntry(wordsRead: 50, secondsActive: 60, wordsByFandom: ["A": 50], wordsByTag: ["x": 50], completedBookKeys: ["two"])
		]
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
		let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 23))!
		let totals = ReadingStatsCalendar.totals(history: history, range: start...end, calendar: calendar)
		#expect(totals.wordsRead == 150)
		#expect(totals.worksCompleted == 2)
		#expect(totals.byFandom["A"] == 150)
		#expect(totals.wordsPerHour == 4500)
	}

	@Test func streakStopsAtGap() {
		let history = ["2026-01-01": ReadingStatsDailyEntry(wordsRead: 1), "2026-01-03": ReadingStatsDailyEntry(wordsRead: 1)]
		let asOf = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3))!
		#expect(ReadingStatsCalendar.currentStreak(history: history, asOf: asOf, calendar: calendar) == 1)
	}
}
