//
//  AO3RequestCoordinatorTests.swift
//  AO3KitTests
//
//  Tests for AO3Pacer, RequestCoalescer, and AO3RequestCoordinator.
//

import Testing
import Foundation
@testable import AO3Kit

@Suite("AO3Pacer logic")
struct AO3PacerLogicTests {

	@Test("when current time is past nextAllowed, wait is zero and nextAllowed moves forward by interval")
	func paceStepWhenReady() {
		let now = ContinuousClock.now
		let nextAllowed = now.advanced(by: .seconds(-5))
		let interval = Duration.milliseconds(600)

		let step = AO3Pacer.paceStep(now: now, nextAllowed: nextAllowed, minInterval: interval)
		#expect(step.wait == .zero)
		#expect(step.nextAllowed == now.advanced(by: interval))
	}

	@Test("when current time is before nextAllowed, wait equals delta and nextAllowed increments")
	func paceStepWhenWaiting() {
		let now = ContinuousClock.now
		let nextAllowed = now.advanced(by: .milliseconds(400))
		let interval = Duration.milliseconds(600)

		let step = AO3Pacer.paceStep(now: now, nextAllowed: nextAllowed, minInterval: interval)
		#expect(step.wait == .milliseconds(400))
		#expect(step.nextAllowed == nextAllowed.advanced(by: interval))
	}
}

@Suite("RequestCoalescer deduplication")
struct RequestCoalescerTests {

	@Test("simultaneous calls for identical keys execute underlying work only once")
	func coalescesIdenticalKeys() async throws {
		let coalescer = RequestCoalescer<String, Int>()
		let executionCount = Mutex<Int>(0)

		let op: @Sendable () async throws -> Int = {
			executionCount.withLock { $0 += 1 }
			try await Task.sleep(nanoseconds: 50_000_000) // 50ms
			return 42
		}

		async let a = coalescer.shared("key1", op)
		async let b = coalescer.shared("key1", op)
		async let c = coalescer.shared("key1", op)

		let (resA, resB, resC) = try await (a, b, c)
		#expect(resA == 42)
		#expect(resB == 42)
		#expect(resC == 42)
		#expect(executionCount.withLock { $0 } == 1)
	}

	@Test("distinct keys execute independently")
	func distinctKeysRunSeparately() async throws {
		let coalescer = RequestCoalescer<String, String>()

		async let a = coalescer.shared("urlA") { "resultA" }
		async let b = coalescer.shared("urlB") { "resultB" }

		let (resA, resB) = try await (a, b)
		#expect(resA == "resultA")
		#expect(resB == "resultB")
	}

	@Test("cancelling first caller keeps in-flight entry alive for second caller")
	func cancellingFirstCallerKeepsSecondAlive() async throws {
		let coalescer = RequestCoalescer<String, String>()
		let executionCount = Mutex<Int>(0)

		let first = Task {
			try await coalescer.shared("work-1") {
				executionCount.withLock { $0 += 1 }
				try await Task.sleep(for: .milliseconds(80))
				return "done"
			}
		}

		try await Task.sleep(for: .milliseconds(15))
		let second = Task {
			try await coalescer.shared("work-1") {
				executionCount.withLock { $0 += 1 }
				return "duplicate"
			}
		}

		try await Task.sleep(for: .milliseconds(10))
		first.cancel()

		let secondResult = try await second.value
		#expect(secondResult == "done")
		#expect(executionCount.withLock { $0 } == 1)
	}
}

@Suite("AO3RequestCoordinator concurrency bounding")
struct AO3RequestCoordinatorTests {

	@Test("coordinator caps concurrent operations to limit")
	func boundsConcurrency() async throws {
		let pacer = AO3Pacer(minRequestInterval: 0.0)
		let coordinator = AO3RequestCoordinator(limit: 2, pacer: pacer)

		let activeCount = Mutex<Int>(0)
		let peakCount = Mutex<Int>(0)

		let work: @Sendable () async throws -> Void = {
			try await coordinator.withSlot {
				let current = activeCount.withLock { count -> Int in
					count += 1
					return count
				}
				peakCount.withLock { peak in
					if current > peak {
						peak = current
					}
				}
				try await Task.sleep(nanoseconds: 50_000_000) // 50ms
				activeCount.withLock { $0 -= 1 }
			}
		}

		async let t1 = work()
		async let t2 = work()
		async let t3 = work()
		async let t4 = work()

		_ = try await (t1, t2, t3, t4)

		#expect(peakCount.withLock { $0 } <= 2)
		#expect(await coordinator.availableSlots == 2)
	}

	@Test("guest and authenticated AO3RequestKeys do not coalesce")
	func guestAndAuthenticatedKeysStayIsolated() async throws {
		let coordinator = AO3RequestCoordinator(limit: 2, pacer: AO3Pacer(minRequestInterval: 0.0))
		let url = URL(string: "https://archiveofourown.org/works/12345")!
		let guestKey = AO3RequestKey(url: url, method: .get, sessionScope: .guest)
		let authKey = AO3RequestKey(url: url, method: .get, sessionScope: .authenticated)

		async let guestResult = coordinator.execute(key: guestKey, policy: .defaultPaced) {
			try await Task.sleep(for: .milliseconds(30))
			return "guest"
		}
		async let authResult = coordinator.execute(key: authKey, policy: .defaultPaced) {
			try await Task.sleep(for: .milliseconds(30))
			return "auth"
		}

		let (g, a) = try await (guestResult, authResult)
		#expect(g == "guest")
		#expect(a == "auth")
	}

	@Test("POST requests are never coalesced")
	func postRequestsDoNotCoalesce() async throws {
		let coordinator = AO3RequestCoordinator(limit: 2, pacer: AO3Pacer(minRequestInterval: 0.0))
		let url = URL(string: "https://archiveofourown.org/kudos.json")!
		let key = AO3RequestKey(url: url, method: .post, sessionScope: .guest)
		let count = Mutex<Int>(0)

		async let first: Int = coordinator.execute(key: key, policy: .defaultPaced) {
			try await Task.sleep(for: .milliseconds(25))
			return count.withLock { $0 += 1; return $0 }
		}
		async let second: Int = coordinator.execute(key: key, policy: .defaultPaced) {
			try await Task.sleep(for: .milliseconds(25))
			return count.withLock { $0 += 1; return $0 }
		}

		_ = try await (first, second)
		#expect(count.withLock { $0 } == 2)
	}

	@Test("cancelling a queued waiter does not abort other waiters")
	func cancellingWaiterLeavesOtherWaitersIntact() async throws {
		let coordinator = AO3RequestCoordinator(limit: 1, pacer: AO3Pacer(minRequestInterval: 0.0))

		let holder = Task {
			try await coordinator.withSlot {
				try await Task.sleep(for: .milliseconds(60))
				return "holder"
			}
		}
		try await Task.sleep(for: .milliseconds(10))

		let cancelledWaiter = Task {
			try await coordinator.withSlot { "cancelled" }
		}
		let liveWaiter = Task {
			try await coordinator.withSlot { "live" }
		}

		try await Task.sleep(for: .milliseconds(10))
		cancelledWaiter.cancel()

		#expect(try await holder.value == "holder")
		#expect(try await liveWaiter.value == "live")
		#expect(await coordinator.availableSlots == 1)
	}
}

// Simple test helper for thread-safe mutations in testing
private final class Mutex<T>: @unchecked Sendable {
	private var value: T
	private let lock = NSLock()

	init(_ value: T) {
		self.value = value
	}

	func withLock<R>(_ body: (inout T) -> R) -> R {
		lock.lock()
		defer { lock.unlock() }
		return body(&value)
	}
}
