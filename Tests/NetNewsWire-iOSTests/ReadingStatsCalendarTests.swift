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

	/// Sunday-first, so heatmap week alignment doesn't depend on the test
	/// machine's locale.
	private var sundayCalendar: Calendar {
		var calendar = self.calendar
		calendar.firstWeekday = 1
		return calendar
	}

	private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
		calendar.date(from: DateComponents(year: year, month: month, day: day))!
	}

	// MARK: - streakLengths (ported from Aidoku's getStreakLengths)

	@Test func streakStopsAtGap() {
		let words = ["2026-01-01": 1, "2026-01-03": 1, "2026-01-04": 1]
		let lengths = ReadingStatsCalendar.streakLengths(dailyWords: words, asOf: day(2026, 1, 4), calendar: calendar)
		#expect(lengths.current == 2)
		#expect(lengths.longest == 2)
	}

	@Test func streakNeedsTwoReadingDays() {
		let lengths = ReadingStatsCalendar.streakLengths(dailyWords: ["2026-01-03": 500], asOf: day(2026, 1, 3), calendar: calendar)
		#expect(lengths.current == 0)
		#expect(lengths.longest == 0)
	}

	@Test func currentStreakMustEndTodayOrYesterday() {
		let words = ["2026-01-01": 10, "2026-01-02": 10, "2026-01-03": 10]
		// Ended yesterday: still current.
		#expect(ReadingStatsCalendar.streakLengths(dailyWords: words, asOf: day(2026, 1, 4), calendar: calendar).current == 3)
		// Ended two days ago: no current streak, longest is kept.
		let stale = ReadingStatsCalendar.streakLengths(dailyWords: words, asOf: day(2026, 1, 5), calendar: calendar)
		#expect(stale.current == 0)
		#expect(stale.longest == 3)
	}

	@Test func zeroWordDaysDoNotCountTowardStreaks() {
		let words = ["2026-01-01": 10, "2026-01-02": 0, "2026-01-03": 10]
		let lengths = ReadingStatsCalendar.streakLengths(dailyWords: words, asOf: day(2026, 1, 3), calendar: calendar)
		#expect(lengths.longest == 0)
	}

	// MARK: - heatmapData (ported from Aidoku's getReadingHeatmapData)

	@Test func heatmapIsWeekAlignedAndEndsToday() {
		// 2026-09-19 is a Saturday. 364 days back is Sat 2025-09-20; the
		// grid then walks back to the previous Sunday, 2025-09-14.
		let asOf = day(2026, 9, 19)
		let words = ["2026-09-19": 500, "2025-09-14": 7, "2025-09-13": 99]
		let heatmap = ReadingStatsCalendar.heatmapData(dailyWords: words, asOf: asOf, calendar: sundayCalendar)
		#expect(heatmap.startDate == day(2025, 9, 14))
		#expect(heatmap.values.count == 371)
		#expect(heatmap.values.count % 7 == 0)
		#expect(heatmap.values.first == 7)
		#expect(heatmap.values.last == 500)
		// Before the grid's first day: not included.
		#expect(!heatmap.values.contains(99))
	}

	@Test func heatmapAlignmentFollowsFirstWeekday() {
		var monday = calendar
		monday.firstWeekday = 2
		let heatmap = ReadingStatsCalendar.heatmapData(dailyWords: [:], asOf: day(2026, 9, 19), calendar: monday)
		#expect(heatmap.startDate == day(2025, 9, 15))
		#expect(heatmap.values.count == 370)
	}

	// MARK: - yearlyMonthData (ported from Aidoku's getChapterYearlyReadingData)

	@Test func yearlyMonthDataBucketsWordsByYearAndMonth() {
		let words = ["2025-12-31": 100, "2026-01-01": 200, "2026-01-15": 50, "2026-03-02": 0]
		let years = ReadingStatsCalendar.yearlyMonthData(dailyWords: words, calendar: calendar)
		#expect(years.map(\.year) == [2025, 2026])
		#expect(years[0].data.december == 100)
		#expect(years[1].data.january == 250)
		#expect(years[1].data.march == 0)
		#expect(years[1].data.total == 250)
		#expect(years[1].data.maxValue == 250)
	}

	@Test func yearlyMonthDataIsEmptyWithoutActivity() {
		#expect(ReadingStatsCalendar.yearlyMonthData(dailyWords: [:], calendar: calendar).isEmpty)
		#expect(ReadingStatsCalendar.yearlyMonthData(dailyWords: ["2026-01-01": 0], calendar: calendar).isEmpty)
	}

	// MARK: - Legacy decode

	@Test func entryWithoutPerWorkMapsStillDecodes() throws {
		let json = #"{"wordsRead":10,"secondsActive":5,"wordsByFandom":{"A":10},"wordsByTag":{},"completedBookKeys":[]}"#
		let entry = try JSONDecoder().decode(ReadingStatsDailyEntry.self, from: Data(json.utf8))
		#expect(entry.wordsRead == 10)
		#expect(entry.worksByFandom.isEmpty)
		#expect(entry.worksByTag.isEmpty)
	}
}
