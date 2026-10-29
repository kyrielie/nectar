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

/// Enforces a minimum time delta between consecutive request start times.
public actor AO3Pacer {
	public static let shared = AO3Pacer()

	private var nextAllowedRequestAt: Date = .distantPast
	public var minRequestInterval: TimeInterval

	public init(minRequestInterval: TimeInterval? = nil) {
		if let minRequestInterval {
			self.minRequestInterval = minRequestInterval
		} else {
			self.minRequestInterval = Platform.isRunningUnitTests ? 0.0 : 0.6
		}
	}

	/// Pure computation extracted for testability without Task.sleep side-effects.
	public static func paceStep(
		now: Date,
		nextAllowed: Date,
		minInterval: TimeInterval
	) -> (wait: TimeInterval, nextAllowed: Date) {
		let wait = max(0, nextAllowed.timeIntervalSince(now))
		let next = max(now, nextAllowed).addingTimeInterval(minInterval)
		return (wait, next)
	}

	/// Waits until the pacing interval has elapsed before allowing execution.
	public func pace() async throws {
		let step = Self.paceStep(
			now: Date(),
			nextAllowed: nextAllowedRequestAt,
			minInterval: minRequestInterval
		)
		nextAllowedRequestAt = step.nextAllowed
		if step.wait > 0 {
			try await Task.sleep(nanoseconds: UInt64(step.wait * 1_000_000_000))
		}
	}

	/// Resets the pacer deadline (useful for test suites).
	public func reset() {
		nextAllowedRequestAt = .distantPast
	}
}

// MARK: - Request Coalescer Actor

/// Deduplicates simultaneous in-flight operations keyed by a Hashable identifier.
public actor RequestCoalescer<Key: Hashable & Sendable, Value: Sendable> {
	private var inFlight: [Key: Task<Value, Error>] = [:]

	public init() {}

	public func shared(
		_ key: Key,
		_ operation: @Sendable @escaping () async throws -> Value
	) async throws -> Value {
		if let existing = inFlight[key] {
			return try await existing.value
		}
		let task = Task {
			try await operation()
		}
		inFlight[key] = task
		defer {
			inFlight[key] = nil
		}
		return try await task.value
	}

	public var activeCount: Int {
		inFlight.count
	}
}

// MARK: - AO3 Request Coordinator Actor

/// Central concurrency gate and coordinator for requests targeting AO3.
public actor AO3RequestCoordinator {
	public static let shared = AO3RequestCoordinator(limit: 3)

	public let limit: Int
	private var available: Int
	private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []
	private let pacer: AO3Pacer
	private let coalescer = RequestCoalescer<URL, (Data, HTTPURLResponse)>()

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
			let result = try await operation()
			release()
			return result
		} catch {
			release()
			throw error
		}
	}

	/// Coalesces identical in-flight URL requests, bounds concurrency, paces requests,
	/// and executes the given network operation.
	public func execute(
		url: URL,
		operation: @Sendable @escaping () async throws -> (Data, HTTPURLResponse)
	) async throws -> (Data, HTTPURLResponse) {
		try await coalescer.shared(url) {
			try await self.withSlot {
				try await self.pacer.pace()
				let (data, response) = try await operation()
				if response.statusCode == 429 {
					Self.logger.warning("AO3RequestCoordinator received 429 for \(url.absoluteString, privacy: .public)")
					await MainActor.run {
						_ = AO3RateLimit.record(url: url, response: response)
					}
				}
				return (data, response)
			}
		}
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
				waiters.append((waiterID, continuation))
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
			if !Task.isCancelled {
				next.continuation.resume(returning: true)
				return
			} else {
				next.continuation.resume(returning: false)
			}
		}
		available = min(limit, available + 1)
	}

	private func cancelWaiter(id: UUID) {
		if let index = waiters.firstIndex(where: { $0.id == id }) {
			let waiter = waiters.remove(at: index)
			waiter.continuation.resume(returning: false)
		}
	}

	/// Current available concurrency slots.
	public var availableSlots: Int {
		available
	}
}
