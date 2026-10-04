//
//  AO3RetryPolicyTests.swift
//  AO3KitTests
//
import Foundation
import Testing
@testable import AO3Kit

@Suite struct AO3RetryPolicyTests {

	private static let url = URL(string: "https://archiveofourown.org/works/1")!

	private final class Counter: @unchecked Sendable {
		var attempts = 0
		var sleeps = [TimeInterval]()
	}

	private static func fetch(_ failure: AO3FetchFailure) -> AO3WorkPageFetch {
		.failure(failure)
	}

	@Test func retryableFailures() {
		#expect(AO3RetryPolicy.isRetryable(.http(502)))
		#expect(AO3RetryPolicy.isRetryable(.http(503)))
		#expect(AO3RetryPolicy.isRetryable(.http(504)))
		#expect(AO3RetryPolicy.isRetryable(.http(525)))
		#expect(AO3RetryPolicy.isRetryable(.serviceUnavailable))
		#expect(!AO3RetryPolicy.isRetryable(.http(500)))
		#expect(!AO3RetryPolicy.isRetryable(.http(403)))
		#expect(!AO3RetryPolicy.isRetryable(.rateLimited(until: nil)))
		#expect(!AO3RetryPolicy.isRetryable(.challenge))
		#expect(!AO3RetryPolicy.isRetryable(.workMissing))
	}

	@Test func retryableErrors() {
		#expect(AO3RetryPolicy.isRetryable(URLError(.timedOut)))
		#expect(AO3RetryPolicy.isRetryable(URLError(.networkConnectionLost)))
		#expect(!AO3RetryPolicy.isRetryable(URLError(.notConnectedToInternet)))
		#expect(!AO3RetryPolicy.isRetryable(NSError(domain: "x", code: 1)))
	}

	@Test func interactiveRetriesOnceThenReturnsTheSecondResult() async {
		let counter = Counter()
		let result = await AO3RetryPolicy.perform(interactive: true, url: Self.url, sleep: { counter.sleeps.append($0) }) {
			counter.attempts += 1
			return counter.attempts == 1 ? Self.fetch(.http(503)) : Self.fetch(.http(502))
		}

		#expect(counter.attempts == 2)
		#expect(counter.sleeps.count == 1)
		if let delay = counter.sleeps.first {
			#expect((2.0...3.0).contains(delay))
		}
		if case .failure(let failure) = result.result {
			#expect(failure == .http(502))
		} else {
			Issue.record("expected the second attempt's failure")
		}
	}

	@Test func backgroundNeverRetries() async {
		let counter = Counter()
		_ = await AO3RetryPolicy.perform(interactive: false, url: Self.url, sleep: { counter.sleeps.append($0) }) {
			counter.attempts += 1
			return Self.fetch(.http(503))
		}

		#expect(counter.attempts == 1)
		#expect(counter.sleeps.isEmpty)
	}

	@Test func nonRetryableFailureIsNotRetried() async {
		let counter = Counter()
		_ = await AO3RetryPolicy.perform(interactive: true, url: Self.url, sleep: { counter.sleeps.append($0) }) {
			counter.attempts += 1
			return Self.fetch(.http(403))
		}

		#expect(counter.attempts == 1)
	}

	@Test func timeoutIsRetriedAndRecoversOnTheSecondAttempt() async {
		let counter = Counter()
		let result = await AO3RetryPolicy.perform(interactive: true, url: Self.url, sleep: { counter.sleeps.append($0) }) {
			counter.attempts += 1
			if counter.attempts == 1 {
				throw URLError(.timedOut)
			}
			return Self.fetch(.unrecognizedPage)
		}

		#expect(counter.attempts == 2)
		if case .failure(let failure) = result.result {
			#expect(failure == .unrecognizedPage)
		} else {
			Issue.record("expected the second attempt's failure")
		}
	}

	@Test func nonRetryableThrownErrorBecomesNetworkFailure() async {
		let counter = Counter()
		let result = await AO3RetryPolicy.perform(interactive: true, url: Self.url, sleep: { counter.sleeps.append($0) }) {
			counter.attempts += 1
			throw URLError(.notConnectedToInternet)
		}

		#expect(counter.attempts == 1)
		if case .failure(.network) = result.result {
		} else {
			Issue.record("expected .network")
		}
	}
}
