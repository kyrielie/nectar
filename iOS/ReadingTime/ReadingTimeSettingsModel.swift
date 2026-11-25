//
//  ReadingTimeSettingsModel.swift
//  NetNewsWire-iOS
//
//  Observable state behind `ReadingTimeSettingsView`: owns Reading Time
//  preferences, bedtime-span clamping confirmations, and lockout status
//  notifications.
//

import Foundation
import ReadingTime

@MainActor final class ReadingTimeSettingsModel: ObservableObject {

	struct PendingConfirmation: Identifiable {
		enum Kind { case readingTimeEnable, bedtimeSpan }
		let id = UUID()
		let kind: Kind
		let message: String
		let revert: () -> Void
	}

	@Published var enabled: Bool {
		didSet {
			guard !isUpdating else { return }
			AppDefaults.shared.readingTimeEnabled = enabled
		}
	}

	@Published var dailyLimitEnabled: Bool {
		didSet {
			guard !isUpdating else { return }
			AppDefaults.shared.readingTimeDailyLimitEnabled = dailyLimitEnabled
		}
	}

	@Published var indicatorEnabled: Bool {
		didSet {
			guard !isUpdating else { return }
			AppDefaults.shared.readingTimeIndicatorDisplayMode = indicatorEnabled ? .pie : .off
		}
	}

	@Published var bedtimeEnabled: Bool {
		didSet {
			guard !isUpdating else { return }
			AppDefaults.shared.readingTimeBedtimeEnabled = bedtimeEnabled
		}
	}

	@Published var start: Date
	@Published var end: Date
	@Published var limits: [Int: Int]

	@Published var takeABreakMode: TakeABreakMode {
		didSet {
			guard !isUpdating else { return }
			AppDefaults.shared.readingTimeTakeABreakMode = takeABreakMode
		}
	}

	@Published var breakReadingMinutes: Int {
		didSet {
			guard !isUpdating else { return }
			AppDefaults.shared.readingTimeBreakReadingMinutes = breakReadingMinutes
		}
	}

	@Published var breakEnforcedMinutes: Int {
		didSet {
			guard !isUpdating else { return }
			AppDefaults.shared.readingTimeBreakEnforcedMinutes = breakEnforcedMinutes
		}
	}

	@Published private(set) var activeLockoutReasons: Set<ReadingTimeTracker.Reason>
	@Published var pendingConfirmation: PendingConfirmation?

	private var isUpdating = false
	nonisolated(unsafe) private var observers = [NSObjectProtocol]()

	init(notificationCenter: NotificationCenter = .default) {
		self.enabled = AppDefaults.shared.readingTimeEnabled
		self.dailyLimitEnabled = AppDefaults.shared.readingTimeDailyLimitEnabled
		self.indicatorEnabled = AppDefaults.shared.readingTimeIndicatorDisplayMode != .off
		self.bedtimeEnabled = AppDefaults.shared.readingTimeBedtimeEnabled
		self.start = Self.minutesDate(AppDefaults.shared.readingTimeBedtimeStartMinutesFromMidnight)
		self.end = Self.minutesDate(AppDefaults.shared.readingTimeBedtimeEndMinutesFromMidnight)
		self.limits = AppDefaults.shared.readingTimeDailyLimitMinutesByWeekday
		self.takeABreakMode = AppDefaults.shared.readingTimeTakeABreakMode
		self.breakReadingMinutes = AppDefaults.shared.readingTimeBreakReadingMinutes
		self.breakEnforcedMinutes = AppDefaults.shared.readingTimeBreakEnforcedMinutes
		self.activeLockoutReasons = ReadingTimeTracker.shared.activeReasons

		let limitObserver = notificationCenter.addObserver(forName: .readingTimeLimitReached, object: nil, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.activeLockoutReasons = ReadingTimeTracker.shared.activeReasons
			}
		}
		let clearObserver = notificationCenter.addObserver(forName: .readingTimeEnforcementDidClear, object: nil, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.activeLockoutReasons = []
			}
		}
		observers = [limitObserver, clearObserver]
	}

	deinit {
		for observer in observers {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	func refreshLockoutReasons() {
		activeLockoutReasons = ReadingTimeTracker.shared.activeReasons
	}

	func setDailyLimitMinutes(_ newValue: Int, for weekday: Int) {
		limits[weekday] = newValue
		AppDefaults.shared.setReadingTimeDailyLimitMinutes(newValue, for: weekday)
	}

	func updateBedtimeStart(_ value: Date) {
		let newStart = Self.minutes(value)
		let oldStart = AppDefaults.shared.readingTimeBedtimeStartMinutesFromMidnight
		let span = ReadingTimeCalendar.bedtimeWindowSpanMinutes(startMinutes: newStart, endMinutes: Self.minutes(end))
		AppDefaults.shared.readingTimeBedtimeStartMinutesFromMidnight = newStart
		if span > ReadingTimeCalendar.maxBedtimeWindowSpanMinutes {
			let clampedEnd = AppDefaults.shared.readingTimeBedtimeEndMinutesFromMidnight
			end = Self.minutesDate(clampedEnd)
			pendingConfirmation = PendingConfirmation(
				kind: .bedtimeSpan,
				message: "Bedtime can't be longer than 12 hours, so the end time was moved to \(Self.timeString(end)). Reading will be blocked for the full 12 hours.",
				revert: { [weak self] in
					self?.start = Self.minutesDate(oldStart)
					AppDefaults.shared.readingTimeBedtimeStartMinutesFromMidnight = oldStart
				}
			)
		}
	}

	func updateBedtimeEnd(_ value: Date) {
		let newEnd = Self.minutes(value)
		let oldEnd = AppDefaults.shared.readingTimeBedtimeEndMinutesFromMidnight
		let span = ReadingTimeCalendar.bedtimeWindowSpanMinutes(startMinutes: Self.minutes(start), endMinutes: newEnd)
		AppDefaults.shared.readingTimeBedtimeEndMinutesFromMidnight = newEnd
		if span > ReadingTimeCalendar.maxBedtimeWindowSpanMinutes {
			let clampedStart = AppDefaults.shared.readingTimeBedtimeStartMinutesFromMidnight
			start = Self.minutesDate(clampedStart)
			pendingConfirmation = PendingConfirmation(
				kind: .bedtimeSpan,
				message: "Bedtime can't be longer than 12 hours, so the start time was moved to \(Self.timeString(start)). Reading will be blocked for the full 12 hours.",
				revert: { [weak self] in
					self?.end = Self.minutesDate(oldEnd)
					AppDefaults.shared.readingTimeBedtimeEndMinutesFromMidnight = oldEnd
				}
			)
		}
	}

	private static func minutes(_ date: Date) -> Int {
		let c = Calendar.current.dateComponents([.hour, .minute], from: date)
		return (c.hour ?? 0) * 60 + (c.minute ?? 0)
	}

	private static func minutesDate(_ value: Int) -> Date {
		Calendar.current.date(from: DateComponents(hour: value / 60, minute: value % 60)) ?? Date()
	}

	private static func timeString(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.timeStyle = .short
		return formatter.string(from: date)
	}
}
