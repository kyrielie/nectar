//
//  ForegroundTickerTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for ForegroundTicker, the timer/observer lifecycle shared by
//  ReadingStatsTracker and ScreenTimeTracker. Uses a throwaway target rather
//  than either shared tracker so nothing here touches their singleton state,
//  and deliberately does not post UIApplication's resign/become-active
//  notifications: the app's real trackers observe those in the test host.
//

import Testing
import Foundation
@testable import Nectar

@Suite(.serialized) @MainActor struct ForegroundTickerTests {

	@MainActor private final class Target: NSObject {
		@objc func tick() {}
		@objc func willResign() {}
		@objc func didBecome() {}
	}

	private func startTicker(_ ticker: ForegroundTicker, target: Target, prepare: () -> Void) {
		ticker.start(
			target: target,
			tick: #selector(Target.tick),
			willResignActive: #selector(Target.willResign),
			didBecomeActive: #selector(Target.didBecome),
			prepare: prepare
		)
	}

	@Test func start_marksRunning_andRunsPrepareOnce_acrossRepeatedStarts() {
		let ticker = ForegroundTicker()
		let target = Target()
		defer { ticker.stopForTesting(target: target) }

		var prepareCount = 0
		#expect(!ticker.isRunning)
		startTicker(ticker, target: target) { prepareCount += 1 }
		startTicker(ticker, target: target) { prepareCount += 1 }

		#expect(ticker.isRunning)
		#expect(prepareCount == 1)
	}

	@Test func stopForTesting_clearsRunning_andAllowsPrepareToRunAgain() {
		let ticker = ForegroundTicker()
		let target = Target()
		defer { ticker.stopForTesting(target: target) }

		var prepareCount = 0
		startTicker(ticker, target: target) { prepareCount += 1 }
		ticker.stopForTesting(target: target)
		#expect(!ticker.isRunning)

		startTicker(ticker, target: target) { prepareCount += 1 }
		#expect(ticker.isRunning)
		#expect(prepareCount == 2)
	}
}
