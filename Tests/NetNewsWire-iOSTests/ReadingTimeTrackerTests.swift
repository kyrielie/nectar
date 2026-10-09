//
//  ReadingTimeTrackerTests.swift
//  NetNewsWire-iOSTests
//
//  Regression coverage for three compounding bugs in the old scalar
//  isEnforced/enforcementReason lockout logic (see the Reading Time bug-fix
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
//  which is the only place that posts .readingTimeEnforcementDidClear.
//
//  ReadingTimeCalendarTests.swift covers only the pure date-math helpers in
//  Account, in isolation; this file exercises the tracker itself, which is
//  a singleton (ReadingTimeTracker.shared) -- resetState() clears both
//  AppDefaults state and the tracker's own in-memory flags via
//  resetForTesting() so tests don't leak into each other regardless of
//  run order. Time is driven deterministically through the
//  ReadingTimeTracker.now injection point rather than by sleeping.
//
//  .serialized: every test drives the same shared singleton and the same
//  handful of AppDefaults keys, so parallel execution could interleave
//  one test's reset/drive/assert sequence with another's.
//

import Testing
import Foundation
@testable import Nectar

@Suite(.serialized) @MainActor struct ReadingTimeTrackerTests {

	private func resetState() {
		AppDefaults.shared.readingTimeEnabled = true
		AppDefaults.shared.readingTimeDailyLimitEnabled = true
		AppDefaults.shared.readingTimeBedtimeEnabled = false
		AppDefaults.shared.readingTimeDailyLimitMinutesByWeekday = [1: 120, 2: 120, 3: 120, 4: 120, 5: 120, 6: 120, 7: 120]
		AppDefaults.shared.readingTimeMinutesUsedTodaySeconds = 0
		AppDefaults.shared.readingTimeUsageDate = nil
		AppDefaults.shared.readingTimeDailyUsageHistory = [:]
		AppDefaults.shared.readingTimeTakeABreakMode = .off
		AppDefaults.shared.readingTimeBreakReadingMinutes = 15
		AppDefaults.shared.readingTimeBreakEnforcedMinutes = 15
		ReadingTimeTracker.shared.resetForTesting()
		ReadingTimeTracker.now = { Date() }
	}

	/// Teardown counterpart to `resetState()`. These tests run inside the
	/// Nectar.app host and write to its real UserDefaults, so ending on
	/// `resetState()` (which turns Reading Time on) would leave it on for the
	/// next launch of the app on the same simulator. Removing the keys lets
	/// the registered defaults (Reading Time off) apply again.
	private func cleanupState() {
		resetState()
		for key in [
			AppDefaults.Key.readingTimeEnabled, AppDefaults.Key.readingTimeDailyLimitEnabled,
			AppDefaults.Key.readingTimeBedtimeEnabled, AppDefaults.Key.readingTimeDailyLimitMinutesByWeekday,
			AppDefaults.Key.readingTimeMinutesUsedTodaySeconds, AppDefaults.Key.readingTimeUsageDate,
			AppDefaults.Key.readingTimeDailyUsageHistory, AppDefaults.Key.readingTimeTakeABreakMode,
			AppDefaults.Key.readingTimeBreakReadingMinutes, AppDefaults.Key.readingTimeBreakEnforcedMinutes
		] {
			AppDefaults.store.removeObject(forKey: key)
		}
	}

	/// Sets the same limit for every weekday, bypassing the >=60 floor
	/// enforced by `setReadingTimeDailyLimitMinutes` -- these tests need
	/// short limits to run fast, and go directly through the raw
	/// dictionary so Section 2's floor doesn't have to be worked around
	/// via calendar-day counts.
	private func setDailyLimit(_ minutes: Int) {
		var limits = AppDefaults.shared.readingTimeDailyLimitMinutesByWeekday
		for weekday in 1...7 { limits[weekday] = minutes }
		AppDefaults.shared.readingTimeDailyLimitMinutesByWeekday = limits
	}

	/// Drives `ReadingTimeTracker.shared` forward from `start` to `end`,
	/// ticking once per second the way the real timer would, without
	/// actually sleeping.
	private func drive(from start: Date, to end: Date) {
		var current = start
		ReadingTimeTracker.now = { current }
		ReadingTimeTracker.shared.tick()
		while current < end {
			current = current.addingTimeInterval(1)
			ReadingTimeTracker.now = { current }
			ReadingTimeTracker.shared.tick()
		}
	}

	/// Matches Calendar.current, which is what evaluate() and
	/// ReadingTimeCalendar.isWithinBedtimeWindow both actually use in
	/// production (their `calendar` parameter defaults to .current, and
	/// nothing here overrides it). A hardcoded UTC calendar built dates
	/// that could land on a different local calendar day, or a different
	/// local minutes-from-midnight, than the CI runner's own timezone
	/// computes for that same Date -- e.g. a UTC "1:30am" landing on the
	/// previous local day/time, so isWithinBedtimeWindow's minutes-from-
	/// midnight comparison never matched the intended bedtime window and
	/// bedtimeReached stayed false. Tests need to build dates in whatever
	/// calendar production will actually read them back in, not a fixed
	/// one of the test's own choosing.
	private func testCalendar() -> Calendar {
		.current
	}

	// MARK: - Bug 1

	@Test func limitLockout_bedtimeEndingDoesNotClearIt() {
		resetState()
		defer { cleanupState() }

		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 0))!

		setDailyLimit(1) // 1 minute -- 60s threshold, reached quickly
		AppDefaults.shared.readingTimeBedtimeEnabled = true
		AppDefaults.shared.readingTimeBedtimeStartMinutesFromMidnight = 60 // 1:00am
		AppDefaults.shared.readingTimeBedtimeEndMinutesFromMidnight = 120 // 2:00am

		drive(from: start, to: start.addingTimeInterval(61))
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.limit))

		nonisolated(unsafe) var clearFired = false
		let observer = NotificationCenter.default.addObserver(forName: .readingTimeEnforcementDidClear, object: nil, queue: nil) { _ in clearFired = true }
		defer { NotificationCenter.default.removeObserver(observer) }

		let intoBedtime = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 1, minute: 30))!
		drive(from: start.addingTimeInterval(61), to: intoBedtime)
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.bedtime))
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.limit))

		let pastBedtime = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 2, minute: 1))!
		drive(from: intoBedtime, to: pastBedtime)

		#expect(!ReadingTimeTracker.shared.activeReasons.contains(.bedtime))
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.limit))
		#expect(!clearFired)
	}

	// MARK: - Bug 2

	@Test func bedtimeLockout_dayRolloverDoesNotAffectIt_ifStillWithinWindow() {
		resetState()
		defer { cleanupState() }

		let calendar = testCalendar()

		AppDefaults.shared.readingTimeBedtimeEnabled = true
		AppDefaults.shared.readingTimeBedtimeStartMinutesFromMidnight = 22 * 60 // 10pm
		AppDefaults.shared.readingTimeBedtimeEndMinutesFromMidnight = 7 * 60 // 7am, crosses midnight

		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0))!
		let lateNight = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 0))!
		drive(from: start, to: lateNight)
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.bedtime))

		// Advance to the next calendar day, still inside the (overnight) window.
		let earlyNextDay = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 1, minute: 0))!
		ReadingTimeTracker.now = { earlyNextDay }
		ReadingTimeTracker.shared.tick()

		#expect(ReadingTimeTracker.shared.activeReasons.contains(.bedtime))
	}

	// MARK: - Bug 3

	@Test func limitLockout_clearsOnDayRollover_andPostsNotification() {
		resetState()
		defer { cleanupState() }

		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		setDailyLimit(1)
		drive(from: start, to: start.addingTimeInterval(61))
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.limit))

		nonisolated(unsafe) var clearFireCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .readingTimeEnforcementDidClear, object: nil, queue: nil) { _ in clearFireCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		let nextDay = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 12, minute: 0, second: 0))!
		ReadingTimeTracker.now = { nextDay }
		ReadingTimeTracker.shared.simulateDidBecomeActiveForTesting()

		#expect(!ReadingTimeTracker.shared.activeReasons.contains(.limit))
		#expect(AppDefaults.shared.readingTimeMinutesUsedTodaySeconds == 0)
		#expect(clearFireCount == 1)
	}

	@Test func limitLockout_clearsOnDayRollover_evenWhenElapsedIsZero() {
		resetState()
		defer { cleanupState() }

		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		setDailyLimit(1)
		drive(from: start, to: start.addingTimeInterval(61))
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.limit))

		nonisolated(unsafe) var clearFireCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .readingTimeEnforcementDidClear, object: nil, queue: nil) { _ in clearFireCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		// simulateDidBecomeActiveForTesting reproduces didBecomeActive()'s
		// exact ordering: lastTick is set to the new `now` before tick()
		// runs, so elapsed == 0 inside that tick() -- this is the "even
		// when elapsed is zero" case this test is named for.
		let nextDay = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 12, minute: 0, second: 0))!
		ReadingTimeTracker.now = { nextDay }
		ReadingTimeTracker.shared.simulateDidBecomeActiveForTesting()

		#expect(!ReadingTimeTracker.shared.activeReasons.contains(.limit))
		#expect(clearFireCount == 1)
	}

	// MARK: - Combined

	@Test func bothLockoutsActiveSimultaneously_clearingOneLeavesOtherActive() {
		resetState()
		defer { cleanupState() }

		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 21, minute: 58))!

		setDailyLimit(1)
		AppDefaults.shared.readingTimeBedtimeEnabled = true
		AppDefaults.shared.readingTimeBedtimeStartMinutesFromMidnight = 22 * 60
		AppDefaults.shared.readingTimeBedtimeEndMinutesFromMidnight = 23 * 60

		nonisolated(unsafe) var clearFireCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .readingTimeEnforcementDidClear, object: nil, queue: nil) { _ in clearFireCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		let bothActive = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 22, minute: 1))!
		drive(from: start, to: bothActive)
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.limit))
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.bedtime))

		let afterWindow = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 1))!
		drive(from: bothActive, to: afterWindow)
		#expect(!ReadingTimeTracker.shared.activeReasons.contains(.bedtime))
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.limit))
		#expect(clearFireCount == 0)

		let nextDay = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 23, minute: 1))!
		ReadingTimeTracker.now = { nextDay }
		ReadingTimeTracker.shared.simulateDidBecomeActiveForTesting()
		#expect(ReadingTimeTracker.shared.activeReasons.isEmpty)
		#expect(clearFireCount == 1)
	}

	// MARK: - No spurious notifications

	@Test func freshRollover_withNoPriorLockout_postsNoNotifications() {
		resetState()
		defer { cleanupState() }

		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		nonisolated(unsafe) var limitReachedFired = false
		nonisolated(unsafe) var clearFired = false
		let limitObserver = NotificationCenter.default.addObserver(forName: .readingTimeLimitReached, object: nil, queue: nil) { _ in limitReachedFired = true }
		let clearObserver = NotificationCenter.default.addObserver(forName: .readingTimeEnforcementDidClear, object: nil, queue: nil) { _ in clearFired = true }
		defer {
			NotificationCenter.default.removeObserver(limitObserver)
			NotificationCenter.default.removeObserver(clearObserver)
		}

		ReadingTimeTracker.now = { start }
		ReadingTimeTracker.shared.tick()

		let nextDay = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 12, minute: 0, second: 0))!
		ReadingTimeTracker.now = { nextDay }
		ReadingTimeTracker.shared.simulateDidBecomeActiveForTesting()

		#expect(!limitReachedFired)
		#expect(!clearFired)
	}

	// MARK: - Take a break

	@Test func breakReminder_firesAfter15MinutesOfContinuousUse() {
		resetState()
		defer { cleanupState() }

		AppDefaults.shared.readingTimeTakeABreakMode = .reminder
		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		nonisolated(unsafe) var breakReachedCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .readingTimeBreakReached, object: nil, queue: nil) { _ in breakReachedCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		drive(from: start, to: start.addingTimeInterval(15 * 60))

		#expect(breakReachedCount == 1)
		#expect(AppDefaults.shared.readingTimeMinutesUsedTodaySeconds >= 15 * 60)
	}

	@Test func breakReminder_resetsCountdownOnDismiss() {
		resetState()
		defer { cleanupState() }

		AppDefaults.shared.readingTimeTakeABreakMode = .reminder
		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		nonisolated(unsafe) var breakReachedCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .readingTimeBreakReached, object: nil, queue: nil) { _ in breakReachedCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		let firstBreak = start.addingTimeInterval(15 * 60)
		drive(from: start, to: firstBreak)
		#expect(breakReachedCount == 1)

		ReadingTimeTracker.shared.dismissBreak()

		let tenMinutesLater = firstBreak.addingTimeInterval(10 * 60)
		drive(from: firstBreak, to: tenMinutesLater)
		#expect(breakReachedCount == 1)

		let fifteenMinutesAfterDismiss = firstBreak.addingTimeInterval(15 * 60)
		drive(from: tenMinutesLater, to: fifteenMinutesAfterDismiss)
		#expect(breakReachedCount == 2)
	}

	@Test func breakReminder_suppressedDuringLockout() {
		resetState()
		defer { cleanupState() }

		AppDefaults.shared.readingTimeTakeABreakMode = .reminder
		setDailyLimit(1) // 60s limit, reached well before the 15-minute break mark
		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		nonisolated(unsafe) var breakReachedCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .readingTimeBreakReached, object: nil, queue: nil) { _ in breakReachedCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		drive(from: start, to: start.addingTimeInterval(61))
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.limit))

		drive(from: start.addingTimeInterval(61), to: start.addingTimeInterval(16 * 60))
		#expect(breakReachedCount == 0)
	}

	@Test func breakReminder_disabledByDefault() {
		resetState()
		defer { cleanupState() }
		// readingTimeTakeABreakMode left at its default (.off).

		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		nonisolated(unsafe) var breakReachedCount = 0
		let observer = NotificationCenter.default.addObserver(forName: .readingTimeBreakReached, object: nil, queue: nil) { _ in breakReachedCount += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		drive(from: start, to: start.addingTimeInterval(16 * 60))

		#expect(breakReachedCount == 0)
	}

	@Test func breakEnforced_locksOutAfterReadingIntervalAndClearsAfterBreakDuration() {
		resetState()
		defer { cleanupState() }

		AppDefaults.shared.readingTimeTakeABreakMode = .enforced
		AppDefaults.shared.readingTimeBreakReadingMinutes = 15
		AppDefaults.shared.readingTimeBreakEnforcedMinutes = 5
		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		nonisolated(unsafe) var limitReachedFired = false
		nonisolated(unsafe) var clearFired = false
		let reachedObserver = NotificationCenter.default.addObserver(forName: .readingTimeLimitReached, object: nil, queue: nil) { _ in limitReachedFired = true }
		let clearObserver = NotificationCenter.default.addObserver(forName: .readingTimeEnforcementDidClear, object: nil, queue: nil) { _ in clearFired = true }
		defer {
			NotificationCenter.default.removeObserver(reachedObserver)
			NotificationCenter.default.removeObserver(clearObserver)
		}

		let breakStart = start.addingTimeInterval(15 * 60)
		drive(from: start, to: breakStart)
		#expect(limitReachedFired)
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.recurringBreak))
		#expect(!clearFired)

		drive(from: breakStart, to: breakStart.addingTimeInterval(5 * 60))
		#expect(clearFired)
		#expect(!ReadingTimeTracker.shared.activeReasons.contains(.recurringBreak))
	}

	@Test func breakEnforced_doesNotStartUnderAnExistingLimitLockout() {
		resetState()
		defer { cleanupState() }

		AppDefaults.shared.readingTimeTakeABreakMode = .enforced
		AppDefaults.shared.readingTimeBreakReadingMinutes = 15
		setDailyLimit(1) // 60s limit, reached well before the 15-minute break mark
		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!

		drive(from: start, to: start.addingTimeInterval(61))
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.limit))

		drive(from: start.addingTimeInterval(61), to: start.addingTimeInterval(16 * 60))
		#expect(!ReadingTimeTracker.shared.activeReasons.contains(.recurringBreak))
	}

	// MARK: - ActiveTimeAccumulator wiring (background credit, clamping, lockout pause)

	@Test func suspendedBackgroundTime_isNotCredited() {
		resetState()
		defer { cleanupState() }

		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!
		ReadingTimeTracker.now = { start }
		ReadingTimeTracker.shared.tick()

		// Simulate resign, then a long real-world gap (suspend), then resume --
		// no tick() calls happen while backgrounded, mirroring a suspended process.
		ReadingTimeTracker.shared.willResignActiveForTesting()
		let fourHoursLater = start.addingTimeInterval(4 * 60 * 60)
		ReadingTimeTracker.now = { fourHoursLater }
		ReadingTimeTracker.shared.simulateDidBecomeActiveForTesting()

		#expect(AppDefaults.shared.readingTimeMinutesUsedTodaySeconds < 10)
	}

	@Test func forwardClockJumpMidForeground_isCappedPerTick() {
		resetState()
		defer { cleanupState() }

		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!
		ReadingTimeTracker.now = { start }
		ReadingTimeTracker.shared.tick()

		// No resign/active cycle -- a single tick() call far in the future,
		// simulating a clock jump without a suspend.
		let muchLater = start.addingTimeInterval(600)
		ReadingTimeTracker.now = { muchLater }
		ReadingTimeTracker.shared.tick()

		#expect(AppDefaults.shared.readingTimeMinutesUsedTodaySeconds <= 5)
	}

	@Test func lockoutPause_usageDoesNotAccrueWhileLockedOut() {
		resetState()
		defer { cleanupState() }

		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!
		setDailyLimit(1)
		drive(from: start, to: start.addingTimeInterval(61))
		#expect(ReadingTimeTracker.shared.activeReasons.contains(.limit))

		let usedAtLockout = AppDefaults.shared.readingTimeMinutesUsedTodaySeconds
		drive(from: start.addingTimeInterval(61), to: start.addingTimeInterval(120))
		#expect(AppDefaults.shared.readingTimeMinutesUsedTodaySeconds == usedAtLockout)
	}

	@Test func breakPersistence_survivesForceQuit_expiredBreakClearsOnRelaunch() {
		resetState()
		defer { cleanupState() }

		let calendar = testCalendar()
		let past = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!
		AppDefaults.shared.readingTimeRecurringBreakEndDate = past
		ReadingTimeTracker.now = { past.addingTimeInterval(60) }
		ReadingTimeTracker.shared.start()
		defer { ReadingTimeTracker.shared.resetForTesting() }

		#expect(!ReadingTimeTracker.shared.activeReasons.contains(.recurringBreak))
		#expect(AppDefaults.shared.readingTimeRecurringBreakEndDate == nil)
	}

	@Test func breakPersistence_survivesForceQuit_activeBreakStaysLockedOnRelaunch() {
		resetState()
		defer { cleanupState() }

		let calendar = testCalendar()
		let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!
		AppDefaults.shared.readingTimeRecurringBreakEndDate = now.addingTimeInterval(300)
		ReadingTimeTracker.now = { now }
		ReadingTimeTracker.shared.start()
		defer { ReadingTimeTracker.shared.resetForTesting() }

		#expect(ReadingTimeTracker.shared.activeReasons.contains(.recurringBreak))
	}

	@Test func awayReset_clearsSecondsSinceLastBreakAfterLongEnoughAway() {
		resetState()
		defer { cleanupState() }

		AppDefaults.shared.readingTimeBreakEnforcedMinutes = 5
		let calendar = testCalendar()
		let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12, minute: 0, second: 0))!
		AppDefaults.shared.readingTimeSecondsSinceLastBreak = 500
		AppDefaults.shared.readingTimeLastResignDate = start

		let farEnoughAway = start.addingTimeInterval(6 * 60)
		ReadingTimeTracker.now = { farEnoughAway }
		ReadingTimeTracker.shared.simulateDidBecomeActiveForTesting()

		#expect(AppDefaults.shared.readingTimeSecondsSinceLastBreak == 0)
	}
}
