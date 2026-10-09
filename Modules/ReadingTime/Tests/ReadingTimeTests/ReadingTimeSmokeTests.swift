import Testing
@testable import ReadingTime

@Test func readingTimeCalendarHasMaximumDaySpan() {
	#expect(ReadingTimeCalendar.maxBedtimeWindowSpanMinutes == 720)
}
