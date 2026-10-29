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

	@Test("when current time is past nextAllowed, wait is 0 and nextAllowed moves forward by interval")
	func paceStepWhenReady() {
		let now = Date(timeIntervalSince1970: 100.0)
		let nextAllowed = Date(timeIntervalSince1970: 95.0)
		let interval: TimeInterval = 0.6

		let step = AO3Pacer.paceStep(now: now, nextAllowed: nextAllowed, minInterval: interval)
		#expect(step.wait == 0)
		#expect(step.nextAllowed == Date(timeIntervalSince1970: 100.6))
	}

	@Test("when current time is before nextAllowed, wait equals delta and nextAllowed increments")
	func paceStepWhenWaiting() {
		let now = Date(timeIntervalSince1970: 100.0)
		let nextAllowed = Date(timeIntervalSince1970: 100.4)
		let interval: TimeInterval = 0.6

		let step = AO3Pacer.paceStep(now: now, nextAllowed: nextAllowed, minInterval: interval)
		#expect(abs(step.wait - 0.4) < 0.001)
		#expect(step.nextAllowed == Date(timeIntervalSince1970: 101.0))
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
				activeCount.withLock {
					$0 += 1
					peakCount.withLock { peak in
						if activeCount.withLock({ $0 }) > peak {
							peak = activeCount.withLock { $0 }
						}
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
