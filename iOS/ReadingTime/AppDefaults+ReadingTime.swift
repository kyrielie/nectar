//
//  AppDefaults+ReadingTime.swift
//  NetNewsWire
//
//  Reading Time's persisted settings and bookkeeping, split out of
//  AppDefaults.swift so the feature's keys, properties, and mode enums live
//  next to ReadingTimeTracker and ReadingTimeSettingsView. Formerly Screen Time.
//  Property and type names use "readingTime", but the stored key strings keep
//  their original "screenTime" prefix (and `ToolbarFunction.readingTimeRemaining`
//  keeps the raw value "screenTimeRemaining"), so no UserDefaults migration is
//  involved. Do not change those strings. `AppDefaults.decode`/`encode` (internal, in
//  AppDefaults.swift) back the Codable-valued properties.
//

import Foundation
import ReadingTime
import Account

extension AppDefaults.Key {
	static let readingTimeEnabled = "screenTimeEnabled"
	static let readingTimeDailyLimitMinutesByWeekday = "screenTimeDailyLimitMinutesByWeekday"
	static let readingTimeDailyLimitEnabled = "screenTimeDailyLimitEnabled"
	static let readingTimeBedtimeEnabled = "screenTimeBedtimeEnabled"
	static let readingTimeBedtimeStartMinutesFromMidnight = "screenTimeBedtimeStartMinutesFromMidnight"
	static let readingTimeBedtimeEndMinutesFromMidnight = "screenTimeBedtimeEndMinutesFromMidnight"
	static let readingTimeMinutesUsedTodaySeconds = "screenTimeMinutesUsedTodaySeconds"
	static let readingTimeUsageDate = "screenTimeUsageDate"
	static let readingTimeDailyUsageHistory = "screenTimeDailyUsageHistory"
	static let readingTimeTakeABreakEnabled = "screenTimeTakeABreakEnabled"
	static let readingTimeTakeABreakMode = "screenTimeTakeABreakMode"
	static let readingTimeBreakReadingMinutes = "screenTimeBreakReadingMinutes"
	static let readingTimeBreakEnforcedMinutes = "screenTimeBreakEnforcedMinutes"
	static let readingTimeRecurringBreakEndDate = "screenTimeRecurringBreakEndDate"
	static let readingTimeSecondsSinceLastBreak = "screenTimeSecondsSinceLastBreak"
	static let readingTimeLastResignDate = "screenTimeLastResignDate"
	static let readingTimeIndicatorDisplayMode = "screenTimeIndicatorDisplayMode"
}

/// See `AppDefaults.readingTimeTakeABreakMode`'s doc comment.
enum TakeABreakMode: String, CaseIterable, Sendable {
	case off
	case reminder
	case enforced
}

/// See `AppDefaults.readingTimeIndicatorDisplayMode`'s doc comment.
enum ReadingTimeIndicatorDisplayMode: String, CaseIterable, Sendable {
	case off
	case pie
}

extension AppDefaults {

	var readingTimeEnabled: Bool {
		get { AppDefaults.bool(for: Key.readingTimeEnabled) }
		set { AppDefaults.setBool(for: Key.readingTimeEnabled, newValue) }
	}

	var readingTimeDailyLimitMinutesByWeekday: [Int: Int] {
		get { AppDefaults.decode([Int: Int].self, key: Key.readingTimeDailyLimitMinutesByWeekday, default: [:]) }
		set { AppDefaults.encode(newValue, key: Key.readingTimeDailyLimitMinutesByWeekday) }
	}

	func readingTimeDailyLimitMinutes(for weekday: Int) -> Int {
		readingTimeDailyLimitMinutesByWeekday[weekday] ?? 120
	}

	func setReadingTimeDailyLimitMinutes(_ minutes: Int, for weekday: Int) {
		var limits = readingTimeDailyLimitMinutesByWeekday
		limits[weekday] = max(60, minutes)
		readingTimeDailyLimitMinutesByWeekday = limits
	}

	/// Independent of `readingTimeDailyLimitMinutesByWeekday` itself, so
	/// the limit can be turned off without losing the configured minutes
	/// per weekday -- symmetric with `readingTimeBedtimeEnabled` below.
	/// Default true preserves the pre-existing always-on behavior.
	var readingTimeDailyLimitEnabled: Bool {
		get { AppDefaults.bool(for: Key.readingTimeDailyLimitEnabled) }
		set { AppDefaults.setBool(for: Key.readingTimeDailyLimitEnabled, newValue) }
	}

	var readingTimeBedtimeEnabled: Bool {
		get { AppDefaults.bool(for: Key.readingTimeBedtimeEnabled) }
		set { AppDefaults.setBool(for: Key.readingTimeBedtimeEnabled, newValue) }
	}

	var readingTimeBedtimeStartMinutesFromMidnight: Int {
		get { AppDefaults.int(for: Key.readingTimeBedtimeStartMinutesFromMidnight) }
		set {
			let currentEnd = readingTimeBedtimeEndMinutesFromMidnight
			if ReadingTimeCalendar.bedtimeWindowSpanMinutes(startMinutes: newValue, endMinutes: currentEnd) > ReadingTimeCalendar.maxBedtimeWindowSpanMinutes {
				AppDefaults.setInt(for: Key.readingTimeBedtimeEndMinutesFromMidnight, (newValue + ReadingTimeCalendar.maxBedtimeWindowSpanMinutes) % 1440)
			}
			AppDefaults.setInt(for: Key.readingTimeBedtimeStartMinutesFromMidnight, newValue)
		}
	}

	var readingTimeBedtimeEndMinutesFromMidnight: Int {
		get { AppDefaults.int(for: Key.readingTimeBedtimeEndMinutesFromMidnight) }
		set {
			let currentStart = readingTimeBedtimeStartMinutesFromMidnight
			if ReadingTimeCalendar.bedtimeWindowSpanMinutes(startMinutes: currentStart, endMinutes: newValue) > ReadingTimeCalendar.maxBedtimeWindowSpanMinutes {
				AppDefaults.setInt(for: Key.readingTimeBedtimeStartMinutesFromMidnight, ((newValue - ReadingTimeCalendar.maxBedtimeWindowSpanMinutes) % 1440 + 1440) % 1440)
			}
			AppDefaults.setInt(for: Key.readingTimeBedtimeEndMinutesFromMidnight, newValue)
		}
	}

	var readingTimeMinutesUsedTodaySeconds: Int {
		get { AppDefaults.int(for: Key.readingTimeMinutesUsedTodaySeconds) }
		set { AppDefaults.setInt(for: Key.readingTimeMinutesUsedTodaySeconds, newValue) }
	}

	var readingTimeUsageDate: Date? {
		get { AppDefaults.date(for: Key.readingTimeUsageDate) }
		set { AppDefaults.setDate(for: Key.readingTimeUsageDate, newValue) }
	}

	/// Trimmed to 35 days (5 Sunday-aligned weeks) on every write, so a
	/// full month of week navigation in ReadingTimeSettingsView's weekly
	/// summary always has data available regardless of which day of the
	/// week "today" falls on. Every rollover write in ReadingTimeTracker
	/// goes through this same setter, so trimming here is sufficient --
	/// there's no separate trim-on-rollover step.
	var readingTimeDailyUsageHistory: [String: Int] {
		get { AppDefaults.decode([String: Int].self, key: Key.readingTimeDailyUsageHistory, default: [:]) }
		set { AppDefaults.encode(Dictionary(uniqueKeysWithValues: newValue.sorted { $0.key < $1.key }.suffix(35)), key: Key.readingTimeDailyUsageHistory) }
	}

	/// Take a Break has three modes, not a bool: `.off`, `.reminder` (a
	/// dismissible nudge every `readingTimeBreakReadingMinutes`, no block --
	/// the only mode that used to exist), and `.enforced` (same recurring
	/// trigger, but blocks reading for `readingTimeBreakEnforcedMinutes`
	/// the way a daily limit or bedtime does -- see ReadingTimeTracker's
	/// `.recurringBreak` lockout reason).
	var readingTimeTakeABreakMode: TakeABreakMode {
		get {
			if let raw = AppDefaults.string(for: Key.readingTimeTakeABreakMode), let mode = TakeABreakMode(rawValue: raw) {
				return mode
			}
			// Migration for anyone upgrading with the old bool-only setting
			// already turned on: preserve their reminders rather than
			// silently reverting them to off. No legacy value stored means
			// this is a fresh install, which registers "off" below.
			return AppDefaults.bool(for: Key.readingTimeTakeABreakEnabled) ? .reminder : .off
		}
		set { AppDefaults.setString(for: Key.readingTimeTakeABreakMode, newValue.rawValue) }
	}

	/// The recurring "reading time" interval before a break (of either
	/// enforced kind) triggers. Was a hardcoded 15-minute constant on
	/// ReadingTimeTracker; now user-configurable, matching the daily-limit
	/// timer picker.
	var readingTimeBreakReadingMinutes: Int {
		get { max(1, AppDefaults.int(for: Key.readingTimeBreakReadingMinutes)) }
		set { AppDefaults.setInt(for: Key.readingTimeBreakReadingMinutes, max(1, newValue)) }
	}

	/// How long an `.enforced` break blocks reading for once triggered.
	/// Unused in `.reminder`/`.off` modes.
	var readingTimeBreakEnforcedMinutes: Int {
		get { max(1, AppDefaults.int(for: Key.readingTimeBreakEnforcedMinutes)) }
		set { AppDefaults.setInt(for: Key.readingTimeBreakEnforcedMinutes, max(1, newValue)) }
	}

	/// Persisted mirror of `ReadingTimeTracker`'s in-memory
	/// `recurringBreakEndDate`, so an active enforced break survives a
	/// force-quit instead of silently clearing.
	var readingTimeRecurringBreakEndDate: Date? {
		get { AppDefaults.date(for: Key.readingTimeRecurringBreakEndDate) }
		set { AppDefaults.setDate(for: Key.readingTimeRecurringBreakEndDate, newValue) }
	}

	/// Persisted mirror of `ReadingTimeTracker`'s in-memory
	/// `secondsSinceLastBreak`.
	var readingTimeSecondsSinceLastBreak: Int {
		get { AppDefaults.int(for: Key.readingTimeSecondsSinceLastBreak) }
		set { AppDefaults.setInt(for: Key.readingTimeSecondsSinceLastBreak, newValue) }
	}

	/// Timestamp of the last `willResignActive`, used on the next
	/// `didBecomeActive` to detect time spent away from the app long
	/// enough to count as a break, closing the force-quit loophole.
	var readingTimeLastResignDate: Date? {
		get { AppDefaults.date(for: Key.readingTimeLastResignDate) }
		set { AppDefaults.setDate(for: Key.readingTimeLastResignDate, newValue) }
	}

	/// Whether the Reading Time pie indicator shows in fullscreen reading,
	/// independent of `pageCounterDisplayMode`. Default `.pie` preserves
	/// today's always-on-when-conditions-met behavior for existing users.
	var readingTimeIndicatorDisplayMode: ReadingTimeIndicatorDisplayMode {
		get { ReadingTimeIndicatorDisplayMode(rawValue: AppDefaults.string(for: Key.readingTimeIndicatorDisplayMode) ?? "") ?? .pie }
		set { AppDefaults.setString(for: Key.readingTimeIndicatorDisplayMode, newValue.rawValue) }
	}
}
