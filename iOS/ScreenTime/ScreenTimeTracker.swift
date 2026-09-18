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

	enum Reason: Equatable { case limit, bedtime }

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
		evaluateBreak(elapsed: elapsed)
	}

	private static let breakIntervalSeconds = 15 * 60

	private func evaluateBreak(elapsed: Int) {
		guard AppDefaults.shared.screenTimeTakeABreakEnabled else { return }
		guard !isLimitLockout, !isBedtimeLockout else {
			if isShowingBreak { isShowingBreak = false }
			return
		}
		secondsSinceLastBreak += elapsed
		guard secondsSinceLastBreak >= Self.breakIntervalSeconds, !isShowingBreak else { return }
		isShowingBreak = true
		NotificationCenter.default.post(name: .screenTimeBreakReached, object: self)
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
		let limitReached = AppDefaults.shared.screenTimeMinutesUsedTodaySeconds >= AppDefaults.shared.screenTimeDailyLimitMinutes(for: weekday) * 60
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
		return result
	}

#if DEBUG
	func resetForTesting() {
		isLimitLockout = false
		isBedtimeLockout = false
		secondsSinceLastBreak = 0
		isShowingBreak = false
		lastTick = nil
	}
#endif
}
