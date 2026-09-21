import Foundation
import UIKit

/// The one-second timer and the resign/become-active observer wiring that
/// `ReadingStatsTracker` and `ScreenTimeTracker` each need. Each tracker
/// owns one (composition, not a base class).
///
/// This deliberately owns only the lifecycle. What happens inside `tick`,
/// `willResignActive`, and `didBecomeActive` stays with the owner, because
/// the two trackers differ in ways that matter: `ScreenTimeTracker.tick()`
/// must evaluate bedtime and break expiry even on a tick that credits no
/// foreground time, while `ReadingStatsTracker.tick()` returns early in that
/// case. A shared template `tick()` would have to encode that difference, and
/// the accounting logic in both trackers is correct as written.
///
/// Callbacks are selector-based, matching what the trackers did inline before:
/// the owner passes `#selector`s for its own `@objc` methods, and this type
/// hands them to `NotificationCenter` and `Timer`.
@MainActor final class ForegroundTicker {
	private var timer: Timer?

	/// True once `start(...)` has run and until `stopForTesting(target:)`.
	var isRunning: Bool {
		timer != nil
	}

	/// One-time setup, guarded so a second call is a no-op: register the
	/// resign/become-active observers, run `prepare`, then start the timer in
	/// `.common` run-loop mode so ticks keep firing during scroll tracking.
	///
	/// `prepare` runs after the observers are registered and before the timer
	/// exists, which is the point in `start()` where each tracker did its own
	/// one-time work (seeding `ActiveTimeAccumulator`, and for
	/// `ScreenTimeTracker`, reading a persisted enforced break back in).
	/// Because of the `isRunning` guard it runs once per process, not once per
	/// `start()` call.
	func start(
		target: AnyObject,
		tick: Selector,
		willResignActive: Selector,
		didBecomeActive: Selector,
		prepare: () -> Void = {}
	) {
		guard timer == nil else {
			return
		}
		NotificationCenter.default.addObserver(target, selector: willResignActive, name: UIApplication.willResignActiveNotification, object: nil)
		NotificationCenter.default.addObserver(target, selector: didBecomeActive, name: UIApplication.didBecomeActiveNotification, object: nil)
		prepare()
		let newTimer = Timer(timeInterval: 1, target: target, selector: tick, userInfo: nil, repeats: true)
		RunLoop.current.add(newTimer, forMode: .common)
		timer = newTimer
	}

#if DEBUG
	/// Removes `target`'s observers and invalidates the timer so the next
	/// `start(...)` runs its one-time setup again. Without this, any test
	/// after the first to call a tracker's `start()` would hit the
	/// `isRunning` guard and silently skip the setup it is trying to test.
	func stopForTesting(target: AnyObject) {
		NotificationCenter.default.removeObserver(target)
		timer?.invalidate()
		timer = nil
	}
#endif
}
