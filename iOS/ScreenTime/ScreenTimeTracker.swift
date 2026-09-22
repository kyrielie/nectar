import Foundation
import ScreenTime
import UIKit
import Account

@MainActor final class ScreenTimeTracker {
	static let shared = ScreenTimeTracker()
	static var now: () -> Date = { Date() }

	private let ticker = ForegroundTicker()
	private let activeTime = ActiveTimeAccumulator(isActive: UIApplication.shared.applicationState != .background)
	private var isLimitLockout = false
	private var isBedtimeLockout = false
	private var isShowingBreak = false
	private var isRecurringBreakLockout = false

	/// In-memory mirror of `AppDefaults.shared.screenTimeSecondsSinceLastBreak`.
	/// Persisted so time away from the app (including a force-quit) is
	/// accounted for -- see `didBecomeActive`'s away-reset check.
	private var secondsSinceLastBreak: Int {
		get { AppDefaults.shared.screenTimeSecondsSinceLastBreak }
		set { AppDefaults.shared.screenTimeSecondsSinceLastBreak = newValue }
	}

	/// In-memory mirror of `AppDefaults.shared.screenTimeRecurringBreakEndDate`.
	private var recurringBreakEndDate: Date? {
		get { AppDefaults.shared.screenTimeRecurringBreakEndDate }
		set { AppDefaults.shared.screenTimeRecurringBreakEndDate = newValue }
	}

	enum Reason: Equatable { case limit, bedtime, recurringBreak }

	private init() {}

	func start() {
		ticker.start(target: self, tick: #selector(tick), willResignActive: #selector(willResignActive), didBecomeActive: #selector(didBecomeActive)) {
			if UIApplication.shared.applicationState != .background {
				activeTime.becomeActive(now: Self.now())
			}
			// Closes the force-quit loophole: read any persisted enforced break
			// back into memory rather than defaulting to "not locked." An
			// end date already in the past is cleared via the same expiry path.
			if let endDate = recurringBreakEndDate {
				if endDate > Self.now() {
					isRecurringBreakLockout = true
				} else {
					recurringBreakEndDate = nil
					secondsSinceLastBreak = 0
				}
			}
		}
	}

	@objc private func willResignActive() {
		tick()
		activeTime.resignActive()
		AppDefaults.shared.screenTimeLastResignDate = Self.now()
	}

	@objc private func didBecomeActive() {
		let now = Self.now()
		evaluateRecurringBreakExpiry(at: now) // clears an expired persisted break first
		if let lastResign = AppDefaults.shared.screenTimeLastResignDate,
		   now.timeIntervalSince(lastResign) >= TimeInterval(AppDefaults.shared.screenTimeBreakEnforcedMinutes * 60) {
			secondsSinceLastBreak = 0
			if isShowingBreak { dismissBreak() }
		}
		activeTime.becomeActive(now: now)
		tick()
	}

	@objc func tick() {
		guard AppDefaults.shared.screenTimeEnabled else { return }
		let now = Self.now()
		rolloverIfNeeded(at: now)
		// Don't credit usage seconds while an enforcement overlay from
		// *this* tick's prior state is already showing -- see the
		// lockout-pause fix below. Read the flags before evaluate(at:)
		// runs, since evaluate() is what would flip them for this tick.
		// Includes isRecurringBreakLockout alongside the daily-limit/bedtime
		// flags: an active enforced break is exactly the same kind of
		// "reading is already blocked" state as the other two, so it needs
		// the same pause -- without it, screenTimeMinutesUsedTodaySeconds
		// kept accruing (and .screenTimeUsageDidChange kept firing once a
		// second) for the entire break-enforced window, even though the
		// overlay was up and nothing was actually being read.
		let wasLockedBeforeThisTick = isLimitLockout || isBedtimeLockout || isRecurringBreakLockout
		if let elapsed = activeTime.tick(now: now) {
			if !wasLockedBeforeThisTick {
				AppDefaults.shared.screenTimeMinutesUsedTodaySeconds += elapsed
				NotificationCenter.default.post(name: .screenTimeUsageDidChange, object: self)
			}
			evaluate(at: now)
			evaluateRecurringBreakExpiry(at: now)
			if !wasLockedBeforeThisTick {
				evaluateBreak(elapsed: elapsed)
			}
		} else {
			evaluate(at: now)
			evaluateRecurringBreakExpiry(at: now)
		}
	}

	private func evaluateBreak(elapsed: Int) {
		let mode = AppDefaults.shared.screenTimeTakeABreakMode
		guard mode != .off else { return }
		// A daily-limit or bedtime lockout takes priority: don't start (or
		// keep counting toward) a recurring break underneath a stricter
		// lockout that's already blocking reading for an unrelated reason.
		guard !isLimitLockout, !isBedtimeLockout else {
			if isShowingBreak { isShowingBreak = false }
			return
		}
		guard !isRecurringBreakLockout else { return }
		secondsSinceLastBreak += elapsed
		let intervalSeconds = AppDefaults.shared.screenTimeBreakReadingMinutes * 60
		guard secondsSinceLastBreak >= intervalSeconds else { return }

		switch mode {
		case .off:
			break
		case .reminder:
			guard !isShowingBreak else { return }
			isShowingBreak = true
			NotificationCenter.default.post(name: .screenTimeBreakReached, object: self)
		case .enforced:
			isRecurringBreakLockout = true
			recurringBreakEndDate = Self.now().addingTimeInterval(TimeInterval(AppDefaults.shared.screenTimeBreakEnforcedMinutes * 60))
			// Reuses the same enforcement-overlay notifications the daily
			// limit and bedtime lockouts post -- SceneDelegate's overlay
			// show/hide wiring already keys off `activeReasons`, which now
			// includes `.recurringBreak` (see `activeReasons` below), so
			// no separate presentation path is needed.
			NotificationCenter.default.post(name: .screenTimeLimitReached, object: self, userInfo: ["reason": String(describing: Reason.recurringBreak)])
		}
	}

	/// Enforced breaks end after a fixed duration rather than a dismiss
	/// tap, so -- unlike the daily-limit/bedtime lockouts, which clear the
	/// moment their underlying condition (usage under the limit, outside
	/// the bedtime window) stops being true -- this needs its own
	/// elapsed-time check each tick.
	private func evaluateRecurringBreakExpiry(at date: Date) {
		guard isRecurringBreakLockout, let endDate = recurringBreakEndDate, date >= endDate else { return }
		isRecurringBreakLockout = false
		recurringBreakEndDate = nil
		secondsSinceLastBreak = 0
		NotificationCenter.default.post(name: .screenTimeEnforcementDidClear, object: self)
	}

	func dismissBreak() {
		guard isShowingBreak else { return }
		isShowingBreak = false
		secondsSinceLastBreak = 0
		NotificationCenter.default.post(name: .screenTimeBreakDidClear, object: self)
	}

	func rolloverIfNeeded(at date: Date) {
		guard let usageDate = AppDefaults.shared.screenTimeUsageDate else {
			AppDefaults.shared.screenTimeUsageDate = date
			return
		}
		guard !ScreenTimeCalendar.isSameUsageDay(usageDate, date) else { return }
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		var history = AppDefaults.shared.screenTimeDailyUsageHistory
		history[formatter.string(from: usageDate)] = AppDefaults.shared.screenTimeMinutesUsedTodaySeconds / 60
		AppDefaults.shared.screenTimeDailyUsageHistory = history
		AppDefaults.shared.screenTimeMinutesUsedTodaySeconds = 0
		AppDefaults.shared.screenTimeUsageDate = date
	}

	private func evaluate(at date: Date) {
		let calendar = Calendar.current
		let weekday = calendar.component(.weekday, from: date)
		let limitReached = AppDefaults.shared.screenTimeDailyLimitEnabled && AppDefaults.shared.screenTimeMinutesUsedTodaySeconds >= AppDefaults.shared.screenTimeDailyLimitMinutes(for: weekday) * 60
		let bedtimeReached = AppDefaults.shared.screenTimeBedtimeEnabled && ScreenTimeCalendar.isWithinBedtimeWindow(date, startMinutes: AppDefaults.shared.screenTimeBedtimeStartMinutesFromMidnight, endMinutes: AppDefaults.shared.screenTimeBedtimeEndMinutesFromMidnight)

		let wasLocked = isLimitLockout || isBedtimeLockout

		if limitReached, !isLimitLockout {
			isLimitLockout = true
			NotificationCenter.default.post(name: .screenTimeLimitReached, object: self, userInfo: ["reason": String(describing: Reason.limit)])
		} else if !limitReached, isLimitLockout {
			isLimitLockout = false
		}
		if bedtimeReached, !isBedtimeLockout {
			isBedtimeLockout = true
			NotificationCenter.default.post(name: .screenTimeLimitReached, object: self, userInfo: ["reason": String(describing: Reason.bedtime)])
		}
		if !bedtimeReached, isBedtimeLockout {
			isBedtimeLockout = false
		}

		let isLocked = isLimitLockout || isBedtimeLockout
		if wasLocked, !isLocked {
			NotificationCenter.default.post(name: .screenTimeEnforcementDidClear, object: self)
		}
	}

	var activeReasons: Set<Reason> {
		var result: Set<Reason> = []
		if isLimitLockout { result.insert(.limit) }
		if isBedtimeLockout { result.insert(.bedtime) }
		if isRecurringBreakLockout { result.insert(.recurringBreak) }
		return result
	}

#if DEBUG
	/// Also tears down the ticker's timer and NotificationCenter observers
	/// (`ForegroundTicker.stopForTesting(target:)`) rather than leaving them
	/// running -- `start()` is guarded by `ticker.isRunning` so it only runs
	/// its one-time setup (observer registration, reading a persisted
	/// `recurringBreakEndDate` back in) once per process. Without this, any
	/// test after the first to call `start()` would hit that guard and
	/// silently no-op, never re-running the break-persistence read-back
	/// logic `start()` is actually testing. This is a #if DEBUG test-only
	/// reset, not a deinit path: it exists so a test-created observer
	/// registration from a prior `start()` call doesn't leak into the next
	/// test.
	func resetForTesting() {
		ticker.stopForTesting(target: self)
		isLimitLockout = false
		isBedtimeLockout = false
		secondsSinceLastBreak = 0
		isShowingBreak = false
		isRecurringBreakLockout = false
		recurringBreakEndDate = nil
		AppDefaults.shared.screenTimeLastResignDate = nil
		activeTime.resetForTesting(isActive: UIApplication.shared.applicationState != .background)
	}

	/// Calls the real `didBecomeActive()` rather than re-implementing part
	/// of its sequence -- a prior version here only replayed the
	/// `activeTime.becomeActive(now:)`/`tick()` pair and skipped
	/// `didBecomeActive()`'s away-time reset check entirely, so tests
	/// exercising that check (via this helper) silently exercised nothing.
	/// Tests simulating "app was backgrounded, a day passed, app resumed"
	/// should drive time forward through this helper rather than a raw
	/// tick() call: `ActiveTimeAccumulator.tick(now:)` returns nil while
	/// inactive rather than crediting against a stale timestamp, so a bare
	/// tick() with no preceding becomeActive(now:) call has no reference
	/// point to measure from.
	func simulateDidBecomeActiveForTesting() {
		didBecomeActive()
	}

	/// Exposes the private `willResignActive()` sequence for tests that
	/// need to simulate a resign/suspend without a real notification.
	func willResignActiveForTesting() {
		willResignActive()
	}
#endif
}

extension ScreenTimeTracker {
	/// SF Symbol name and friendly copy for the current lockout reason(s).
	/// Used by both the status banner in ScreenTimeSettingsView and
	/// ScreenTimeEnforcementOverlay -- previously the overlay kept its own
	/// separate, differently-worded `text(for:)` switch over the same
	/// cases, which let the two surfaces' wording drift out of sync;
	/// they're now unified onto this one function. Returns nil when
	/// there's nothing to show (`reasons` empty).
	///
	/// Daily-limit and bedtime lockouts take priority in the message over
	/// a concurrent recurring break: `.recurringBreak` only shows on its
	/// own, since it can't outrank a stricter lockout that's also active
	/// (see evaluateBreak's guard against starting a break under an
	/// existing limit/bedtime lockout) -- the rare case where a limit or
	/// bedtime starts *while* an enforced break is already showing just
	/// takes over the message, which is the same "stricter reason wins"
	/// behavior the two-case switch already had.
	static func lockoutStatus(for reasons: Set<Reason>, bedtimeEndMinutesFromMidnight: Int) -> (systemImageName: String, message: String)? {
		let endTime = Self.timeString(minutesFromMidnight: bedtimeEndMinutesFromMidnight)
		switch (reasons.contains(.limit), reasons.contains(.bedtime)) {
		case (true, true):
			return ("bed.double.fill", "It's bedtime, and today's reading time is up too. More time tomorrow, after \(endTime).")
		case (true, false):
			return ("clock.fill", "Today's reading time is up. More time starts tomorrow.")
		case (false, true):
			return ("bed.double.fill", "It's bedtime. Reading resumes at \(endTime).")
		case (false, false):
			return reasons.contains(.recurringBreak) ? ("pause.circle.fill", "Taking a break. Reading resumes shortly.") : nil
		}
	}

	private static func timeString(minutesFromMidnight: Int) -> String {
		let date = Calendar.current.date(from: DateComponents(hour: minutesFromMidnight / 60, minute: minutesFromMidnight % 60)) ?? Date()
		let formatter = DateFormatter()
		formatter.timeStyle = .short
		return formatter.string(from: date)
	}
}
