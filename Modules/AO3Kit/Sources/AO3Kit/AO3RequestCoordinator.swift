//
//  AO3RequestCoordinator.swift
//  AO3Kit
//
//  Centralized politeness actor layer for AO3 networking:
//  - Pacing: enforces a minimum 0.6s delay between outgoing requests
//  - Concurrency Bounding: caps simultaneous requests to at most 3 slots
//  - Coalescing: deduplicates in-flight requests for identical URLs
//  - Rate Limiting: respects HTTP 429 cooldowns across all endpoints
//

import Foundation
import os
import RSCore

// MARK: - AO3 Pacer Actor

/// Enforces a minimum monotonic time delta between consecutive request start times.
public actor AO3Pacer {
	public static let shared = AO3Pacer()

	private var nextAllowedRequestAt: ContinuousClock.Instant?
	public var minRequestInterval: Duration

	public init(minRequestInterval: Duration? = nil) {
		if let minRequestInterval {
			self.minRequestInterval = minRequestInterval
		} else {
			self.minRequestInterval = Platform.isRunningUnitTests ? .zero : .milliseconds(600)
		}
	}

	public init(minRequestInterval: TimeInterval) {
		self.minRequestInterval = .seconds(minRequestInterval)
	}

	/// Pure computation extracted for testability without Task.sleep side-effects.
	public static func paceStep(
		now: ContinuousClock.Instant,
		nextAllowed: ContinuousClock.Instant?,
		minInterval: Duration
	) -> (wait: Duration, nextAllowed: ContinuousClock.Instant) {
		let baseline = nextAllowed ?? now
		let wait = now < baseline ? (baseline - now) : .zero
		let anchor = max(now, baseline)
		let next = anchor.advanced(by: minInterval)
		return (wait, next)
	}

	/// Waits until the pacing interval has elapsed before allowing execution.
	public func pace() async throws {
		let step = Self.paceStep(
			now: ContinuousClock.now,
			nextAllowed: nextAllowedRequestAt,
			minInterval: minRequestInterval
		)
		nextAllowedRequestAt = step.nextAllowed
		if step.wait > .zero {
			try await Task.sleep(for: step.wait)
		}
	}

	/// Resets the pacer deadline (useful for test suites).
	public func reset() {
		nextAllowedRequestAt = nil
	}
}

// MARK: - Request Identity & Policy

public enum AO3HTTPMethod: String, Hashable, Sendable {
	case get = "GET"
	case post = "POST"
}

public enum AO3SessionScope: Hashable, Sendable {
	case guest
	case authenticated
	case clearanceCookie
}

public struct AO3RequestKey: Hashable, Sendable {
	public let url: URL
	public let method: AO3HTTPMethod
	public let sessionScope: AO3SessionScope

	public init(
		url: URL,
		method: AO3HTTPMethod = .get,
		sessionScope: AO3SessionScope = .guest
	) {
		self.url = url
		self.method = method
		self.sessionScope = sessionScope
	}
}

public struct AO3ExecutionPolicy: Sendable {
	public let coalesce: Bool
	public let pace: Bool

	public init(coalesce: Bool = true, pace: Bool = true) {
		self.coalesce = coalesce
		self.pace = pace
	}

	public static let defaultPaced = AO3ExecutionPolicy(coalesce: true, pace: true)
	public static let uncoalescedPaced = AO3ExecutionPolicy(coalesce: false, pace: true)
	public static let uncoalescedUnpaced = AO3ExecutionPolicy(coalesce: false, pace: false)
}

// MARK: - Request Coalescer Actor

/// Deduplicates simultaneous in-flight operations keyed by a Hashable identifier.
/// Retains the in-flight entry until the underlying task finishes or all joined callers cancel.
public actor RequestCoalescer<Key: Hashable & Sendable, Value: Sendable> {
	private struct Entry {
		let id: UUID
		let task: Task<Value, Error>
		var waiters: Int
	}

	private var inFlight: [Key: Entry] = [:]

	public init() {}

	public func shared(
		_ key: Key,
		_ operation: @Sendable @escaping () async throws -> Value
	) async throws -> Value {
		let entryID: UUID
		let task: Task<Value, Error>

		if var existing = inFlight[key] {
			existing.waiters += 1
			inFlight[key] = existing
			entryID = existing.id
			task = existing.task
		} else {
			let newID = UUID()
			let newTask = Task {
				try await operation()
			}
			inFlight[key] = Entry(id: newID, task: newTask, waiters: 1)
			entryID = newID
			task = newTask
		}

		return try await withTaskCancellationHandler {
			defer {
				releaseWaiter(key: key, entryID: entryID, cancelled: false)
			}
			return try await task.value
		} onCancel: {
			Task {
				await releaseWaiter(key: key, entryID: entryID, cancelled: true)
			}
		}
	}

	private func releaseWaiter(key: Key, entryID: UUID, cancelled: Bool) {
		guard var entry = inFlight[key], entry.id == entryID else {
			return
		}
		if !cancelled {
			// Underlying task completed normally (or threw): remove the completed entry.
			inFlight[key] = nil
			return
		}
		entry.waiters = max(0, entry.waiters - 1)
		if entry.waiters == 0 {
			entry.task.cancel()
			inFlight[key] = nil
		} else {
			inFlight[key] = entry
		}
	}

	public var activeCount: Int {
		inFlight.count
	}
}

// MARK: - AO3 Request Coordinator Actor

/// Central concurrency gate and coordinator for requests targeting AO3.
public actor AO3RequestCoordinator {
	public static let shared = AO3RequestCoordinator(limit: 3)

	private struct CoalescedBox: @unchecked Sendable {
		let value: Any
	}

	private final class WaiterRecord {
		let id: UUID
		var isCancelled = false
		let continuation: CheckedContinuation<Bool, Never>

		init(id: UUID, continuation: CheckedContinuation<Bool, Never>) {
			self.id = id
			self.continuation = continuation
		}
	}

	public let limit: Int
	private var available: Int
	private var waiters: [WaiterRecord] = []
	private let pacer: AO3Pacer
	private let coalescer = RequestCoalescer<AO3RequestKey, CoalescedBox>()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.kyrielie.nectar", category: "AO3RequestCoordinator")

	public init(limit: Int = 3, pacer: AO3Pacer = .shared) {
		precondition(limit >= 1, "AO3RequestCoordinator limit must be >= 1")
		self.limit = limit
		self.available = limit
		self.pacer = pacer
	}

	/// Executes a unit of work within an acquired concurrency slot.
	public func withSlot<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
		guard await acquire() else {
			throw CancellationError()
		}
		do {
			try Task.checkCancellation()
			let result = try await operation()
			release()
			return result
		} catch {
			release()
			throw error
		}
	}

	/// Typed execution entry point with scoped coalescing, slot bounding, and optional pacing.
	/// Non-idempotent HTTP methods (e.g. POST) are never coalesced.
	public func execute<T: Sendable>(
		key: AO3RequestKey,
		policy: AO3ExecutionPolicy = .defaultPaced,
		operation: @Sendable @escaping () async throws -> T
	) async throws -> T {
		let runInSlot: @Sendable () async throws -> T = {
			try await self.withSlot {
				if policy.pace {
					try await self.pacer.pace()
				}
				let result = try await operation()
				if let (_, response) = result as? (Data, HTTPURLResponse), response.statusCode == 429 {
					Self.logger.warning("AO3RequestCoordinator received 429 for \(key.url.absoluteString, privacy: .public)")
					await MainActor.run {
						_ = AO3RateLimit.record(url: key.url, response: response)
					}
				}
				return result
			}
		}

		if policy.coalesce && key.method == .get {
			let boxed = try await coalescer.shared(key) {
				let value = try await runInSlot()
				return CoalescedBox(value: value)
			}
			guard let typed = boxed.value as? T else {
				throw CancellationError()
			}
			return typed
		}
		return try await runInSlot()
	}

	/// Convenience overload for legacy URL-only callers (defaults to GET + authenticated scope).
	public func execute(
		url: URL,
		operation: @Sendable @escaping () async throws -> (Data, HTTPURLResponse)
	) async throws -> (Data, HTTPURLResponse) {
		try await execute(
			key: AO3RequestKey(url: url, method: .get, sessionScope: .authenticated),
			policy: .defaultPaced,
			operation: operation
		)
	}

	private func acquire() async -> Bool {
		if Task.isCancelled {
			return false
		}
		if available > 0 {
			available -= 1
			return true
		}

		let waiterID = UUID()
		return await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				let record = WaiterRecord(id: waiterID, continuation: continuation)
				waiters.append(record)
			}
		} onCancel: {
			Task { [weak self] in
				await self?.cancelWaiter(id: waiterID)
			}
		}
	}

	private func release() {
		while !waiters.isEmpty {
			let next = waiters.removeFirst()
			if !next.isCancelled {
				next.continuation.resume(returning: true)
				return
			}
		}
		available = min(limit, available + 1)
	}

	private func cancelWaiter(id: UUID) {
		if let index = waiters.firstIndex(where: { $0.id == id }) {
			let waiter = waiters.remove(at: index)
			waiter.isCancelled = true
			waiter.continuation.resume(returning: false)
		}
	}

	/// Current available concurrency slots.
	public var availableSlots: Int {
		available
	}
}
