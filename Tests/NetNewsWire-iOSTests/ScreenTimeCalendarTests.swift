import Foundation
import Testing
import ScreenTime

@Suite struct ScreenTimeCalendarTests {
	private var calendar: Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(secondsFromGMT: 0)!
		return calendar
	}

	@Test func wraparoundBedtimeWindow() {
		let calendar = self.calendar
		let late = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23))!
		let early = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 3))!
		let noon = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 12))!
		#expect(ScreenTimeCalendar.isWithinBedtimeWindow(late, startMinutes: 22 * 60, endMinutes: 7 * 60, calendar: calendar))
		#expect(ScreenTimeCalendar.isWithinBedtimeWindow(early, startMinutes: 22 * 60, endMinutes: 7 * 60, calendar: calendar))
		#expect(!ScreenTimeCalendar.isWithinBedtimeWindow(noon, startMinutes: 22 * 60, endMinutes: 7 * 60, calendar: calendar))
	}

	@Test func usageDayIsCalendarBased() {
		let calendar = self.calendar
		let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 59))!
		let second = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 0, minute: 1))!
		#expect(!ScreenTimeCalendar.isSameUsageDay(first, second, calendar: calendar))
	}
}
