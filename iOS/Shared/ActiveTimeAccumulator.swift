import Foundation

/// Tracks active (foregrounded) wall-clock time with a hard signal for
/// "currently active" rather than inferring it from a nullable
/// timestamp, a per-tick cap to bound clock jumps and suspend/resume
/// gaps, and a carried sub-second remainder so short resign/active
/// cycles don't lose time to flooring.
@MainActor final class ActiveTimeAccumulator {
	private var isActive: Bool
	private var lastTick: Date?
	private var remainder: TimeInterval = 0
	private let maxCreditPerTick: TimeInterval

	/// - Parameters:
	///   - isActive: seed value, pass `UIApplication.shared.applicationState != .background`.
	///   - maxCreditPerTick: hard cap in seconds on what a single `tick(now:)` call can credit. Default 5.
	init(isActive: Bool, maxCreditPerTick: TimeInterval = 5) {
		self.isActive = isActive
		self.maxCreditPerTick = maxCreditPerTick
	}

	/// Call from `willResignActive`. Stops crediting immediately;
	/// caller should call `tick(now:)` once more *before* this to flush
	/// any pending elapsed time, matching today's `tick(); lastTick = nil` order.
	func resignActive() {
		isActive = false
		lastTick = nil
	}

	/// Call from `didBecomeActive`. Resets the reference point so the
	/// next `tick(now:)` measures from here, not from whatever was
	/// backgrounded before.
	func becomeActive(now: Date) {
		isActive = true
		lastTick = now
	}

	/// Returns whole seconds to credit this call, or nil if nothing
	/// should be credited (inactive, or elapsed rounds to zero seconds
	/// after adding the carried remainder).
	func tick(now: Date) -> Int? {
		guard isActive else { return nil }
		defer { lastTick = now }
		guard let previous = lastTick else { return nil }
		let rawElapsed = now.timeIntervalSince(previous)
		guard rawElapsed > 0 else { return nil }
		let capped = min(rawElapsed, maxCreditPerTick)
		remainder += capped
		let whole = Int(remainder.rounded(.down))
		remainder -= Double(whole)
		return whole > 0 ? whole : nil
	}

#if DEBUG
	func resetForTesting(isActive: Bool) {
		self.isActive = isActive
		lastTick = nil
		remainder = 0
	}
#endif
}
