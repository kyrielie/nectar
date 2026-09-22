import Testing
@testable import ScreenTime

@Test func screenTimeCalendarHasMaximumDaySpan() {
	#expect(ScreenTimeCalendar.maxBedtimeWindowSpanMinutes == 720)
}
