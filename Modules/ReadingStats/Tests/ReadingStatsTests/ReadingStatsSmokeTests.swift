import Testing
@testable import ReadingStats

@Test func readingStatsEntryDefaultsAreEmpty() {
	#expect(ReadingStatsDailyEntry().wordsRead == 0)
}
