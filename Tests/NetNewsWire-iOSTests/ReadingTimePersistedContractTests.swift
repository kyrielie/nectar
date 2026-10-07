//
//  ReadingTimePersistedContractTests.swift
//  NetNewsWire-iOSTests
//
//  Pins the persisted contract of Screen Time and Reading Stats: the exact
//  UserDefaults key strings, the raw values stored for the mode enums, and
//  the JSON shape of ReadingStatsDailyEntry. People's data is stored under
//  these names, so changing any of them silently orphans it (a renamed key
//  reads as "never set", a renamed raw value fails to decode).
//
//  Other tests refer to the keys through `AppDefaults.Key.*`, so a changed
//  string value would still pass them. These compare against the literals.
//  None of these tests reads or writes UserDefaults, so they cannot
//  interfere with the stateful tracker tests.
//
//  If a test here fails, the change needs a migration (read the old key or
//  value, write the new one) and an update to this file in the same commit.
//

import Foundation
import Testing
import ReadingStats
@testable import Nectar

@Suite struct ReadingTimePersistedContractTests {

	// MARK: - UserDefaults keys

	@Test func screenTimeKeyStringsAreFrozen() {
		let pairs: [(actual: String, expected: String)] = [
			(AppDefaults.Key.screenTimeEnabled, "screenTimeEnabled"),
			(AppDefaults.Key.screenTimeDailyLimitMinutesByWeekday, "screenTimeDailyLimitMinutesByWeekday"),
			(AppDefaults.Key.screenTimeDailyLimitEnabled, "screenTimeDailyLimitEnabled"),
			(AppDefaults.Key.screenTimeBedtimeEnabled, "screenTimeBedtimeEnabled"),
			(AppDefaults.Key.screenTimeBedtimeStartMinutesFromMidnight, "screenTimeBedtimeStartMinutesFromMidnight"),
			(AppDefaults.Key.screenTimeBedtimeEndMinutesFromMidnight, "screenTimeBedtimeEndMinutesFromMidnight"),
			(AppDefaults.Key.screenTimeMinutesUsedTodaySeconds, "screenTimeMinutesUsedTodaySeconds"),
			(AppDefaults.Key.screenTimeUsageDate, "screenTimeUsageDate"),
			(AppDefaults.Key.screenTimeDailyUsageHistory, "screenTimeDailyUsageHistory"),
			(AppDefaults.Key.screenTimeTakeABreakEnabled, "screenTimeTakeABreakEnabled"),
			(AppDefaults.Key.screenTimeTakeABreakMode, "screenTimeTakeABreakMode"),
			(AppDefaults.Key.screenTimeBreakReadingMinutes, "screenTimeBreakReadingMinutes"),
			(AppDefaults.Key.screenTimeBreakEnforcedMinutes, "screenTimeBreakEnforcedMinutes"),
			(AppDefaults.Key.screenTimeRecurringBreakEndDate, "screenTimeRecurringBreakEndDate"),
			(AppDefaults.Key.screenTimeSecondsSinceLastBreak, "screenTimeSecondsSinceLastBreak"),
			(AppDefaults.Key.screenTimeLastResignDate, "screenTimeLastResignDate"),
			(AppDefaults.Key.screenTimeIndicatorDisplayMode, "screenTimeIndicatorDisplayMode")
		]
		for pair in pairs {
			#expect(pair.actual == pair.expected, "Screen Time key \(pair.expected) changed to \(pair.actual)")
		}
		#expect(Set(pairs.map(\.expected)).count == pairs.count, "duplicate key in this test's own list")
	}

	@Test func readingStatsKeyStringsAreFrozen() {
		let pairs: [(actual: String, expected: String)] = [
			(AppDefaults.Key.readingStatsTrackingEnabled, "readingStatsTrackingEnabled"),
			(AppDefaults.Key.readingStatsDailyHistory, "readingStatsDailyHistory"),
			(AppDefaults.Key.readingStatsDailyWords, "readingStatsDailyWords"),
			(AppDefaults.Key.readingStatsProgressByBookKey, "readingStatsProgressByBookKey"),
			(AppDefaults.Key.readingStatsAllTimeWords, "readingStatsAllTimeWords")
		]
		for pair in pairs {
			#expect(pair.actual == pair.expected, "Reading Stats key \(pair.expected) changed to \(pair.actual)")
		}
		#expect(Set(pairs.map(\.expected)).count == pairs.count, "duplicate key in this test's own list")
	}

	// MARK: - Stored raw values

	@Test func takeABreakModeRawValuesAreFrozen() {
		#expect(TakeABreakMode.allCases.map(\.rawValue) == ["off", "reminder", "enforced"])
		#expect(TakeABreakMode(rawValue: "off") == .off)
		#expect(TakeABreakMode(rawValue: "reminder") == .reminder)
		#expect(TakeABreakMode(rawValue: "enforced") == .enforced)
	}

	@Test func screenTimeIndicatorDisplayModeRawValuesAreFrozen() {
		#expect(ScreenTimeIndicatorDisplayMode.allCases.map(\.rawValue) == ["off", "pie"])
		#expect(ScreenTimeIndicatorDisplayMode(rawValue: "off") == .off)
		#expect(ScreenTimeIndicatorDisplayMode(rawValue: "pie") == .pie)
	}

	// MARK: - ReadingStatsDailyEntry JSON shape

	@Test func dailyEntryEncodesExactlyTheSevenStoredFields() throws {
		let entry = ReadingStatsDailyEntry(
			wordsRead: 1200,
			secondsActive: 300,
			wordsByFandom: ["Fandom": 1200],
			wordsByTag: ["Tag": 1200],
			completedBookKeys: ["ao3:1"],
			worksByFandom: ["Fandom": ["ao3:1"]],
			worksByTag: ["Tag": ["ao3:1"]]
		)

		let data = try JSONEncoder().encode(entry)
		let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

		#expect(Set(object.keys) == ["wordsRead", "secondsActive", "wordsByFandom", "wordsByTag", "completedBookKeys", "worksByFandom", "worksByTag"])
	}

	@Test func dailyEntryDecodesAStoredLiteral() throws {
		let json = """
		{
		  "wordsRead": 1200,
		  "secondsActive": 300,
		  "wordsByFandom": {"Fandom": 1200},
		  "wordsByTag": {"Tag": 1200},
		  "completedBookKeys": ["ao3:1"],
		  "worksByFandom": {"Fandom": ["ao3:1"]},
		  "worksByTag": {"Tag": ["ao3:1"]}
		}
		"""

		let entry = try JSONDecoder().decode(ReadingStatsDailyEntry.self, from: Data(json.utf8))

		#expect(entry.wordsRead == 1200)
		#expect(entry.secondsActive == 300)
		#expect(entry.wordsByFandom == ["Fandom": 1200])
		#expect(entry.wordsByTag == ["Tag": 1200])
		#expect(entry.completedBookKeys == ["ao3:1"])
		#expect(entry.worksByFandom == ["Fandom": ["ao3:1"]])
		#expect(entry.worksByTag == ["Tag": ["ao3:1"]])
	}

	@Test func dailyHistoryDictionaryKeepsItsDayKeyShape() throws {
		// readingStatsDailyHistory and readingStatsDailyWords are keyed by
		// "yyyy-MM-dd" strings and stored as a JSON object, not an array.
		let history = ["2026-01-02": ReadingStatsDailyEntry(wordsRead: 5)]

		let data = try JSONEncoder().encode(history)
		let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

		#expect(Set(object.keys) == ["2026-01-02"])
	}
}
