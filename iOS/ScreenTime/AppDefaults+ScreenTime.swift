//
//  AppDefaults+ScreenTime.swift
//  NetNewsWire
//
//  Screen Time's persisted settings and bookkeeping, split out of
//  AppDefaults.swift so the feature's keys, properties, and mode enums live
//  next to ScreenTimeTracker and ScreenTimeSettingsView. A pure move: key
//  strings, property names, and behavior are unchanged, so no UserDefaults
//  migration is involved. `AppDefaults.decode`/`encode` (internal, in
//  AppDefaults.swift) back the Codable-valued properties.
//

import Foundation

extension AppDefaults.Key {
	static let screenTimeEnabled = "screenTimeEnabled"
	static let screenTimeDailyLimitMinutesByWeekday = "screenTimeDailyLimitMinutesByWeekday"
	static let screenTimeDailyLimitEnabled = "screenTimeDailyLimitEnabled"
	static let screenTimeBedtimeEnabled = "screenTimeBedtimeEnabled"
	static let screenTimeBedtimeStartMinutesFromMidnight = "screenTimeBedtimeStartMinutesFromMidnight"
	static let screenTimeBedtimeEndMinutesFromMidnight = "screenTimeBedtimeEndMinutesFromMidnight"
	static let screenTimeMinutesUsedTodaySeconds = "screenTimeMinutesUsedTodaySeconds"
	static let screenTimeUsageDate = "screenTimeUsageDate"
	static let screenTimeDailyUsageHistory = "screenTimeDailyUsageHistory"
	static let screenTimeTakeABreakEnabled = "screenTimeTakeABreakEnabled"
	static let screenTimeTakeABreakMode = "screenTimeTakeABreakMode"
	static let screenTimeBreakReadingMinutes = "screenTimeBreakReadingMinutes"
	static let screenTimeBreakEnforcedMinutes = "screenTimeBreakEnforcedMinutes"
	static let screenTimeRecurringBreakEndDate = "screenTimeRecurringBreakEndDate"
	static let screenTimeSecondsSinceLastBreak = "screenTimeSecondsSinceLastBreak"
	static let screenTimeLastResignDate = "screenTimeLastResignDate"
	static let screenTimeIndicatorDisplayMode = "screenTimeIndicatorDisplayMode"
}

/// See `AppDefaults.screenTimeTakeABreakMode`'s doc comment.
enum TakeABreakMode: String, CaseIterable, Sendable {
	case off
	case reminder
	case enforced
}

/// See `AppDefaults.screenTimeIndicatorDisplayMode`'s doc comment.
enum ScreenTimeIndicatorDisplayMode: String, CaseIterable, Sendable {
	case off
	case pie
}

extension AppDefaults {

	var screenTimeEnabled: Bool {
		get { AppDefaults.bool(for: Key.screenTimeEnabled) }
		set { AppDefaults.setBool(for: Key.screenTimeEnabled, newValue) }
	}

	var screenTimeDailyLimitMinutesByWeekday: [Int: Int] {
		get { AppDefaults.decode([Int: Int].self, key: Key.screenTimeDailyLimitMinutesByWeekday, default: [:]) }
		set { AppDefaults.encode(newValue, key: Key.screenTimeDailyLimitMinutesByWeekday) }
	}

	func screenTimeDailyLimitMinutes(for weekday: Int) -> Int {
		screenTimeDailyLimitMinutesByWeekday[weekday] ?? 120
	}

	func setScreenTimeDailyLimitMinutes(_ minutes: Int, for weekday: Int) {
		var limits = screenTimeDailyLimitMinutesByWeekday
		limits[weekday] = max(60, minutes)
		screenTimeDailyLimitMinutesByWeekday = limits
	}

	/// Independent of `screenTimeDailyLimitMinutesByWeekday` itself, so
	/// the limit can be turned off without losing the configured minutes
	/// per weekday -- symmetric with `screenTimeBedtimeEnabled` below.
	/// Default true preserves the pre-existing always-on behavior.
	var screenTimeDailyLimitEnabled: Bool {
		get { AppDefaults.bool(for: Key.screenTimeDailyLimitEnabled) }
		set { AppDefaults.setBool(for: Key.screenTimeDailyLimitEnabled, newValue) }
	}

	var screenTimeBedtimeEnabled: Bool {
		get { AppDefaults.bool(for: Key.screenTimeBedtimeEnabled) }
		set { AppDefaults.setBool(for: Key.screenTimeBedtimeEnabled, newValue) }
	}

	var screenTimeBedtimeStartMinutesFromMidnight: Int {
		get { AppDefaults.int(for: Key.screenTimeBedtimeStartMinutesFromMidnight) }
		set {
			let currentEnd = screenTimeBedtimeEndMinutesFromMidnight
			if ScreenTimeCalendar.bedtimeWindowSpanMinutes(startMinutes: newValue, endMinutes: currentEnd) > ScreenTimeCalendar.maxBedtimeWindowSpanMinutes {
				AppDefaults.setInt(for: Key.screenTimeBedtimeEndMinutesFromMidnight, (newValue + ScreenTimeCalendar.maxBedtimeWindowSpanMinutes) % 1440)
			}
			AppDefaults.setInt(for: Key.screenTimeBedtimeStartMinutesFromMidnight, newValue)
		}
	}

	var screenTimeBedtimeEndMinutesFromMidnight: Int {
		get { AppDefaults.int(for: Key.screenTimeBedtimeEndMinutesFromMidnight) }
		set {
			let currentStart = screenTimeBedtimeStartMinutesFromMidnight
			if ScreenTimeCalendar.bedtimeWindowSpanMinutes(startMinutes: currentStart, endMinutes: newValue) > ScreenTimeCalendar.maxBedtimeWindowSpanMinutes {
				AppDefaults.setInt(for: Key.screenTimeBedtimeStartMinutesFromMidnight, ((newValue - ScreenTimeCalendar.maxBedtimeWindowSpanMinutes) % 1440 + 1440) % 1440)
			}
			AppDefaults.setInt(for: Key.screenTimeBedtimeEndMinutesFromMidnight, newValue)
		}
	}

	var screenTimeMinutesUsedTodaySeconds: Int {
		get { AppDefaults.int(for: Key.screenTimeMinutesUsedTodaySeconds) }
		set { AppDefaults.setInt(for: Key.screenTimeMinutesUsedTodaySeconds, newValue) }
	}

	var screenTimeUsageDate: Date? {
		get { AppDefaults.date(for: Key.screenTimeUsageDate) }
		set { AppDefaults.setDate(for: Key.screenTimeUsageDate, newValue) }
	}

	/// Trimmed to 35 days (5 Sunday-aligned weeks) on every write, so a
	/// full month of week navigation in ScreenTimeSettingsView's weekly
	/// summary always has data available regardless of which day of the
	/// week "today" falls on. Every rollover write in ScreenTimeTracker
	/// goes through this same setter, so trimming here is sufficient --
	/// there's no separate trim-on-rollover step.
	var screenTimeDailyUsageHistory: [String: Int] {
		get { AppDefaults.decode([String: Int].self, key: Key.screenTimeDailyUsageHistory, default: [:]) }
		set { AppDefaults.encode(Dictionary(uniqueKeysWithValues: newValue.sorted { $0.key < $1.key }.suffix(35)), key: Key.screenTimeDailyUsageHistory) }
	}

	/// Take a Break has three modes, not a bool: `.off`, `.reminder` (a
	/// dismissible nudge every `screenTimeBreakReadingMinutes`, no block --
	/// the only mode that used to exist), and `.enforced` (same recurring
	/// trigger, but blocks reading for `screenTimeBreakEnforcedMinutes`
	/// the way a daily limit or bedtime does -- see ScreenTimeTracker's
	/// `.recurringBreak` lockout reason).
	var screenTimeTakeABreakMode: TakeABreakMode {
		get {
			if let raw = AppDefaults.string(for: Key.screenTimeTakeABreakMode), let mode = TakeABreakMode(rawValue: raw) {
				return mode
			}
			// Migration for anyone upgrading with the old bool-only setting
			// already turned on: preserve their reminders rather than
			// silently reverting them to off. No legacy value stored means
			// this is a fresh install, which registers "off" below.
			return AppDefaults.bool(for: Key.screenTimeTakeABreakEnabled) ? .reminder : .off
		}
		set { AppDefaults.setString(for: Key.screenTimeTakeABreakMode, newValue.rawValue) }
	}

	/// The recurring "reading time" interval before a break (of either
	/// enforced kind) triggers. Was a hardcoded 15-minute constant on
	/// ScreenTimeTracker; now user-configurable, matching the daily-limit
	/// timer picker.
	var screenTimeBreakReadingMinutes: Int {
		get { max(1, AppDefaults.int(for: Key.screenTimeBreakReadingMinutes)) }
		set { AppDefaults.setInt(for: Key.screenTimeBreakReadingMinutes, max(1, newValue)) }
	}

	/// How long an `.enforced` break blocks reading for once triggered.
	/// Unused in `.reminder`/`.off` modes.
	var screenTimeBreakEnforcedMinutes: Int {
		get { max(1, AppDefaults.int(for: Key.screenTimeBreakEnforcedMinutes)) }
		set { AppDefaults.setInt(for: Key.screenTimeBreakEnforcedMinutes, max(1, newValue)) }
	}

	/// Persisted mirror of `ScreenTimeTracker`'s in-memory
	/// `recurringBreakEndDate`, so an active enforced break survives a
	/// force-quit instead of silently clearing.
	var screenTimeRecurringBreakEndDate: Date? {
		get { AppDefaults.date(for: Key.screenTimeRecurringBreakEndDate) }
		set { AppDefaults.setDate(for: Key.screenTimeRecurringBreakEndDate, newValue) }
	}

	/// Persisted mirror of `ScreenTimeTracker`'s in-memory
	/// `secondsSinceLastBreak`.
	var screenTimeSecondsSinceLastBreak: Int {
		get { AppDefaults.int(for: Key.screenTimeSecondsSinceLastBreak) }
		set { AppDefaults.setInt(for: Key.screenTimeSecondsSinceLastBreak, newValue) }
	}

	/// Timestamp of the last `willResignActive`, used on the next
	/// `didBecomeActive` to detect time spent away from the app long
	/// enough to count as a break, closing the force-quit loophole.
	var screenTimeLastResignDate: Date? {
		get { AppDefaults.date(for: Key.screenTimeLastResignDate) }
		set { AppDefaults.setDate(for: Key.screenTimeLastResignDate, newValue) }
	}

	/// Whether the Screen Time pie indicator shows in fullscreen reading,
	/// independent of `pageCounterDisplayMode`. Default `.pie` preserves
	/// today's always-on-when-conditions-met behavior for existing users.
	var screenTimeIndicatorDisplayMode: ScreenTimeIndicatorDisplayMode {
		get { ScreenTimeIndicatorDisplayMode(rawValue: AppDefaults.string(for: Key.screenTimeIndicatorDisplayMode) ?? "") ?? .pie }
		set { AppDefaults.setString(for: Key.screenTimeIndicatorDisplayMode, newValue.rawValue) }
	}
}
