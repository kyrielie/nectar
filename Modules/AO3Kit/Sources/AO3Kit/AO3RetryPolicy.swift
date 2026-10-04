//
//  AO3RetryPolicy.swift
//  AO3Kit
//
//  One retry for a work-page fetch that failed in a way a second try often
//  fixes, for interactive fetches only. A person is waiting on an
//  interactive open, so one retry after a short pause covers a blip
//  cheaply. A background fetch (prefetch) has nobody waiting and never
//  retries. Deliberately not shared with
//  AO3SearchResultsFetcher.retryOrGiveUp, which throws after several
//  attempts and sleeps up to 30 seconds, both wrong for an interactive
//  open.
//
import Foundation

/// A classified work-page fetch plus the raw response details a caller needs
/// for logging.
public struct AO3WorkPageFetch: Sendable {
	public let result: AO3WorkPageResult
	/// The response body, when one arrived. Used for the Activity Log's
	/// size message.
	public let data: Data?
	public let returnedFromCache: Bool

	public init(result: AO3WorkPageResult, data: Data? = nil, returnedFromCache: Bool = false) {
		self.result = result
		self.data = data
		self.returnedFromCache = returnedFromCache
	}

	public static func failure(_ failure: AO3FetchFailure) -> AO3WorkPageFetch {
		AO3WorkPageFetch(result: .failure(failure))
	}
}

public enum AO3RetryPolicy {

	public static let retryableStatusCodes: Set<Int> = [502, 503, 504, 525]
	public static let baseDelay: TimeInterval = 2
	public static let maxJitter: TimeInterval = 1

	/// A failure worth one more try: a gateway or availability status, or
	/// AO3's own 503 page.
	public static func isRetryable(_ failure: AO3FetchFailure) -> Bool {
		switch failure {
		case .http(let statusCode):
			return retryableStatusCodes.contains(statusCode)
		case .serviceUnavailable:
			return true
		default:
			return false
		}
	}

	/// A thrown error worth one more try.
	public static func isRetryable(_ error: Error) -> Bool {
		guard let urlError = error as? URLError else {
			return false
		}
		return urlError.code == .timedOut || urlError.code == .networkConnectionLost
	}

	public static func defaultSleep(_ seconds: TimeInterval) async {
		try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
	}

	/// Runs `attempt`; when `interactive` and the outcome is retryable, waits
	/// `baseDelay` plus up to `maxJitter` seconds and runs it once more. No
	/// retry when a shared cooldown became active in the meantime, or when
	/// the task was cancelled. A thrown error that is not retryable becomes
	/// `.network`, so callers handle one result type.
	public static func perform(
		interactive: Bool,
		url: URL,
		sleep: @Sendable (TimeInterval) async -> Void = AO3RetryPolicy.defaultSleep,
		attempt: @Sendable () async throws -> AO3WorkPageFetch
	) async -> AO3WorkPageFetch {
		let first = await runOnce(attempt)
		guard interactive, first.retryable, !Task.isCancelled else {
			return first.fetch
		}
		if await AO3RateLimit.resumeDate(for: url) != nil {
			return first.fetch
		}
		await sleep(baseDelay + Double.random(in: 0...maxJitter))
		guard !Task.isCancelled else {
			return first.fetch
		}
		return await runOnce(attempt).fetch
	}

	private static func runOnce(_ attempt: @Sendable () async throws -> AO3WorkPageFetch) async -> (fetch: AO3WorkPageFetch, retryable: Bool) {
		do {
			let fetch = try await attempt()
			if case .failure(let failure) = fetch.result {
				return (fetch, isRetryable(failure))
			}
			return (fetch, false)
		} catch {
			return (.failure(.network(error.localizedDescription)), isRetryable(error))
		}
	}
}
