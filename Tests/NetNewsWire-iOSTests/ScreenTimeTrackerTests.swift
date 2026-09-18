//
//  ScreenTimeTrackerTests.swift
//  NetNewsWire-iOSTests
//
//  Regression coverage for three compounding bugs in the old scalar
//  isEnforced/enforcementReason lockout logic (see the Screen Time bug-fix
//  plan, Section 1, for the full trace):
//
//  Bug 1 -- .limit always won over .bedtime, and had no clear condition
//  except day rollover, so a limit lockout was unaffected by bedtime
//  starting or ending.
//  Bug 2 -- rolloverIfNeeded only auto-cleared .limit, never .bedtime, so
//  a bedtime lockout survived a day rollover even outside its window.
//  Bug 3 -- rolloverIfNeeded mutated lock state directly and posted no
//  notification, so SceneDelegate's overlay never got a .hide() call even
//  though the app was internally unlocked.
//
//  The fix tracks isLimitLockout/isBedtimeLockout independently and
//  funnels every clear through evaluate()'s wasLocked/isLocked comparison,
//  which is the only place that posts .screenTimeEnforcementDidClear.
//
//  ScreenTimeCalendarTests.swift covers only the pure date-math helpers in
//  Account, in isolation; this file exercises the tracker itself, which is
//  a singleton (ScreenTimeTracker.shared) -- resetState() clears both
//  AppDefaults state and the tracker's own in-memory flags via
//  resetForTesting() so tests don't leak into each other regardless of
//  run order. Time is driven deterministically through the
//  ScreenTimeTracker.now injection point rather than by sleeping.
//
//  .serialized: every test drives the same shared singleton and the same
//  handful of AppDefaults keys, so parallel execution could interleave
//  one test's reset/drive/assert sequence with another's.
//

import Testing
import Foundation
@testable import Nectar

@Suite(.serialized) @MainActor struct ScreenTimeTrackerTests {

	private func resetState() {
		AppDefaults.shared.screenTimeEnabled = true
		AppDefaults.shared.screenTimeBedtimeEnabled = false
		AppDefaults.shared.screenTimeDailyLimitMinutesByWeekday = [1: 120, 2: 120, 3: 120, 4: 120, 5: 120, 6: 120, 7: 120]
		AppDefaults.shared.screenTimeMinutesUsedTodaySeconds = 0
		AppDefaults.shared.screenTimeUsageDate = nil
		AppDefaults.shared.screenTimeDailyUsageHistory = [:]
		AppDefaults.shared.screenTimeTakeABreakEnabled = false
		ScreenTimeTracker.shared.resetForTesting()
		ScreenTimeTracker.now = { Date() }
	}

	/// Sets the same limit for every weekday, bypassing the >=60 floor
	/// enforced by `setScreenTimeDailyLimitMinutes` -- these tests need
	/// short limits to run fast, and go directly through the raw
	/// dictionary so Section 2's floor doesn't have to be worked around
	/// via calendar-day counts.
	private func setDailyLimit(_ minutes: Int) {
		var limits = AppDefaults.shared.screenTimeDailyLimitMinutesByWeekday
		for weekday in 1...7 { limits[weekday] = minutes }
		AppDefaults.shared.screenTimeDailyLimitMinutesByWeekday = limits
	}

	/// Drives `ScreenTimeTracker.shared` forward from `start` to `end`,
	/// ticking once per second the way the real timer would, without
	/// actually sleeping.
	private func drive(from start: Date, to end: Date) {
		var current = start
		ScreenTimeTracker.now = { current }
		ScreenTimeTracker.shared.tick()
		while current < end {
			current = current.addingTimeInterval(1)
			ScreenTimeTracker.now = { current }
			ScreenTimeTracker.shared.tick()
		}
	}

	private func utcCalendar() -> Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(secondsFromGMT: 0)!
		return calendar
	}

	// MARK: - Bug 1

	@Test func limitLockout_bedtimeEndingDoesNotClearIt() {
		resetState()
		defer { resetState() }

		let calendar = utcCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 0))!

		setDailyLimit(1) // 1 minute -- 60s threshold, reached quickly
		AppDefaults.shared.screenTimeBedtimeEnabled = true
		AppDefaults.shared.screenTimeBedtimeStartMinutesFromMidnight = 60 // 1:00am
		AppDefaults.shared.screenTimeBedtimeEndMinutesFromMidnight = 120 // 2:00am

		drive(from: start, to: start.addingTimeInterval(61))
		#expect(ScreenTimeTracker.shared.activeReasons.contains(.limit))

		nonisolated(unsafe) var clearFired = false
		let observer = NotificationCenter.default.addObserver(forName: .screenTimeEnforcementDidClear, object: nil, queue: nil) { _ in clearFired = true }
		defer { NotificationCenter.default.removeObserver(observer) }

		let intoBedtime = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 1, minute: 30))!
		drive(from: start.addingTimeInterval(61), to: intoBedtime)
		#expect(ScreenTimeTracker.shared.activeReasons.contains(.bedtime))
		#expect(ScreenTimeTracker.shared.activeReasons.contains(.limit))

		let pastBedtime = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 2, minute: 1))!
		drive(from: intoBedtime, to: pastBedtime)

		#expect(!ScreenTimeTracker.shared.activeReasons.contains(.bedtime))
		#expect(ScreenTimeTracker.shared.activeReasons.contains(.limit))
		#expect(!clearFired)
	}

	// MARK: - Bug 2

	@Test func bedtimeLockout_dayRolloverDoesNotAffectIt_ifStillWithinWindow() {
		resetState()
		defer { resetState() }

		let calendar = utcCalendar()

		AppDefaults.shared.screenTimeBedtimeEnabled = true
		AppDefaults.shared.screenTimeBedtimeStartMinutesFromMidnight = 22 * 60 // 10pm
		AppDefaults.shared.screenTimeBedtimeEndMinutesFromMidnight = 7 * 60 // 7am, crosses midnight

		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0))!
		let lateNight = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 0))!
		drive(from: start, to: lateNight)
		#expect(ScreenTimeTracker.shared.activeReasons.contains(.bedtime))

		// Advance to the next calendar day, still inside the (overnight) window.
		let earlyNextDay = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 1, minute: 0))!
		ScreenTimeTracker.now = { earlyNextDay }
		ScreenTimeTracker.shared.tick()

		#expect(ScreenTimeTracker.shared.activeReasons.contains(.bedtime))
	}

	// MARK: - Bug 3

	@Test func limitLockout_clearsOnDayRollover_andPostsNotification() {
		resetState()
		defer { resetState() }

		let calendar = utcCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		setDailyLimit(1)
		drive(from: start, to: start.addingTimeInterval(61))
		#expect(ScreenTimeTracker.shared.activeReasons.contains(.limit))

		nonisolated(unsafe) var clearFireCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .screenTimeEnforcementDidClear, object: nil, queue: nil) { _ in clearFireCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		let nextDay = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 12, minute: 0, second: 0))!
		ScreenTimeTracker.now = { nextDay }
		ScreenTimeTracker.shared.tick()

		#expect(!ScreenTimeTracker.shared.activeReasons.contains(.limit))
		#expect(AppDefaults.shared.screenTimeMinutesUsedTodaySeconds == 0)
		#expect(clearFireCount == 1)
	}

	@Test func limitLockout_clearsOnDayRollover_evenWhenElapsedIsZero() {
		resetState()
		defer { resetState() }

		let calendar = utcCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		setDailyLimit(1)
		drive(from: start, to: start.addingTimeInterval(61))
		#expect(ScreenTimeTracker.shared.activeReasons.contains(.limit))

		nonisolated(unsafe) var clearFireCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .screenTimeEnforcementDidClear, object: nil, queue: nil) { _ in clearFireCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		// Reproduce didBecomeActive()'s exact ordering: lastTick is set to
		// the new `now` *before* tick() runs, so elapsed == 0 inside tick().
		let nextDay = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 12, minute: 0, second: 0))!
		ScreenTimeTracker.now = { nextDay }
		ScreenTimeTracker.shared.tick() // sets lastTick = nextDay via its own defer
		ScreenTimeTracker.shared.tick() // elapsed == 0 on this call

		#expect(!ScreenTimeTracker.shared.activeReasons.contains(.limit))
		#expect(clearFireCount == 1)
	}

	// MARK: - Combined

	@Test func bothLockoutsActiveSimultaneously_clearingOneLeavesOtherActive() {
		resetState()
		defer { resetState() }

		let calendar = utcCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 21, minute: 58))!

		setDailyLimit(1)
		AppDefaults.shared.screenTimeBedtimeEnabled = true
		AppDefaults.shared.screenTimeBedtimeStartMinutesFromMidnight = 22 * 60
		AppDefaults.shared.screenTimeBedtimeEndMinutesFromMidnight = 23 * 60

		nonisolated(unsafe) var clearFireCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .screenTimeEnforcementDidClear, object: nil, queue: nil) { _ in clearFireCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		let bothActive = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 22, minute: 1))!
		drive(from: start, to: bothActive)
		#expect(ScreenTimeTracker.shared.activeReasons.contains(.limit))
		#expect(ScreenTimeTracker.shared.activeReasons.contains(.bedtime))

		let afterWindow = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 1))!
		drive(from: bothActive, to: afterWindow)
		#expect(!ScreenTimeTracker.shared.activeReasons.contains(.bedtime))
		#expect(ScreenTimeTracker.shared.activeReasons.contains(.limit))
		#expect(clearFireCount == 0)

		let nextDay = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 23, minute: 1))!
		ScreenTimeTracker.now = { nextDay }
		ScreenTimeTracker.shared.tick()
		#expect(ScreenTimeTracker.shared.activeReasons.isEmpty)
		#expect(clearFireCount == 1)
	}

	// MARK: - No spurious notifications

	@Test func freshRollover_withNoPriorLockout_postsNoNotifications() {
		resetState()
		defer { resetState() }

		let calendar = utcCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		nonisolated(unsafe) var limitReachedFired = false
		nonisolated(unsafe) var clearFired = false
		let limitObserver = NotificationCenter.default.addObserver(forName: .screenTimeLimitReached, object: nil, queue: nil) { _ in limitReachedFired = true }
		let clearObserver = NotificationCenter.default.addObserver(forName: .screenTimeEnforcementDidClear, object: nil, queue: nil) { _ in clearFired = true }
		defer {
			NotificationCenter.default.removeObserver(limitObserver)
			NotificationCenter.default.removeObserver(clearObserver)
		}

		ScreenTimeTracker.now = { start }
		ScreenTimeTracker.shared.tick()

		let nextDay = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 12, minute: 0, second: 0))!
		ScreenTimeTracker.now = { nextDay }
		ScreenTimeTracker.shared.tick()

		#expect(!limitReachedFired)
		#expect(!clearFired)
	}

	// MARK: - Take a break

	@Test func breakReminder_firesAfter15MinutesOfContinuousUse() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.screenTimeTakeABreakEnabled = true
		let calendar = utcCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		nonisolated(unsafe) var breakReachedCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .screenTimeBreakReached, object: nil, queue: nil) { _ in breakReachedCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		drive(from: start, to: start.addingTimeInterval(15 * 60))

		#expect(breakReachedCount == 1)
		#expect(AppDefaults.shared.screenTimeMinutesUsedTodaySeconds >= 15 * 60)
	}

	@Test func breakReminder_resetsCountdownOnDismiss() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.screenTimeTakeABreakEnabled = true
		let calendar = utcCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		nonisolated(unsafe) var breakReachedCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .screenTimeBreakReached, object: nil, queue: nil) { _ in breakReachedCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		let firstBreak = start.addingTimeInterval(15 * 60)
		drive(from: start, to: firstBreak)
		#expect(breakReachedCount == 1)

		ScreenTimeTracker.shared.dismissBreak()

		let tenMinutesLater = firstBreak.addingTimeInterval(10 * 60)
		drive(from: firstBreak, to: tenMinutesLater)
		#expect(breakReachedCount == 1)

		let fifteenMinutesAfterDismiss = firstBreak.addingTimeInterval(15 * 60)
		drive(from: tenMinutesLater, to: fifteenMinutesAfterDismiss)
		#expect(breakReachedCount == 2)
	}

	@Test func breakReminder_suppressedDuringLockout() {
		resetState()
		defer { resetState() }

		AppDefaults.shared.screenTimeTakeABreakEnabled = true
		setDailyLimit(1) // 60s limit, reached well before the 15-minute break mark
		let calendar = utcCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		nonisolated(unsafe) var breakReachedCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .screenTimeBreakReached, object: nil, queue: nil) { _ in breakReachedCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		drive(from: start, to: start.addingTimeInterval(61))
		#expect(ScreenTimeTracker.shared.activeReasons.contains(.limit))

		drive(from: start.addingTimeInterval(61), to: start.addingTimeInterval(16 * 60))
		#expect(breakReachedCount == 0)
	}

	@Test func breakReminder_disabledByDefault() {
		resetState()
		defer { resetState() }
		// screenTimeTakeABreakEnabled left at its default (false).

		let calendar = utcCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		nonisolated(unsafe) var breakReachedCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .screenTimeBreakReached, object: nil, queue: nil) { _ in breakReachedCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		drive(from: start, to: start.addingTimeInterval(16 * 60))

		#expect(breakReachedCount == 0)
	}
}
