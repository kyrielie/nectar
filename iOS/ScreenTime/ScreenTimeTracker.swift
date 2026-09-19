import Foundation
import UIKit
import Account

@MainActor final class ScreenTimeTracker {
	static let shared = ScreenTimeTracker()
	static var now: () -> Date = { Date() }

	private var timer: Timer?
	private var lastTick: Date?
	private var isLimitLockout = false
	private var isBedtimeLockout = false
	private var secondsSinceLastBreak = 0
	private var isShowingBreak = false
	private var isRecurringBreakLockout = false
	private var recurringBreakEndDate: Date?

	enum Reason: Equatable { case limit, bedtime, recurringBreak }

	private init() {}

	func start() {
		guard timer == nil else { return }
		NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: UIApplication.willResignActiveNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
		lastTick = Self.now()
		timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
	}

	@objc private func willResignActive() { tick(); lastTick = nil }
	@objc private func didBecomeActive() { lastTick = Self.now(); tick() }

	@objc func tick() {
		guard AppDefaults.shared.screenTimeEnabled else { lastTick = Self.now(); return }
		let now = Self.now()
		defer { lastTick = now }
		guard let previous = lastTick else { return }
		rolloverIfNeeded(at: now)
		let elapsed = max(0, Int(now.timeIntervalSince(previous).rounded(.down)))
		guard elapsed > 0 else { evaluate(at: now); return }
		AppDefaults.shared.screenTimeMinutesUsedTodaySeconds += elapsed
		NotificationCenter.default.post(name: .screenTimeUsageDidChange, object: self)
		evaluate(at: now)
		evaluateRecurringBreakExpiry(at: now)
		evaluateBreak(elapsed: elapsed)
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
	func resetForTesting() {
		isLimitLockout = false
		isBedtimeLockout = false
		secondsSinceLastBreak = 0
		isShowingBreak = false
		isRecurringBreakLockout = false
		recurringBreakEndDate = nil
		lastTick = nil
	}

	/// Mirrors didBecomeActive()'s exact sequence -- lastTick is reset to
	/// `Self.now()` *before* tick() runs, so tick()'s own `elapsed`
	/// computation is always ~0 here, exactly as it is on a real resume.
	/// Tests simulating "app was backgrounded, a day passed, app resumed"
	/// should drive time forward through this helper rather than a raw
	/// tick() call: a raw tick() after jumping `now` forward by a whole day
	/// computes a huge `elapsed` (~24h) against the *old* lastTick, and
	/// since rolloverIfNeeded (called earlier in that same tick()) already
	/// zeroed the day's counter, that whole elapsed gets credited to the
	/// new day -- instantly re-triggering the limit lockout tick() was
	/// meant to clear. Production never hits that path: every day-boundary
	/// crossing goes through didBecomeActive(), never a bare tick() against
	/// a stale lastTick, so a raw tick() in a test exercises a sequence
	/// that can't actually happen.
	func simulateDidBecomeActiveForTesting() {
		lastTick = Self.now()
		tick()
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
