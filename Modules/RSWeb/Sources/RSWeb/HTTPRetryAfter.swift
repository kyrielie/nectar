//
//  HTTPRetryAfter.swift
//  RSWeb
//
//  Parses an HTTP Retry-After header value, which RFC 7231 allows to be
//  either a non-negative number of seconds or an HTTP date.
//

import Foundation

public enum HTTPRetryAfter {

	/// Seconds to wait before retrying, measured from `now`. Returns nil
	/// when `value` is neither a positive number of seconds nor an
	/// IMF-fixdate in the future (for example "Wed, 21 Oct 2026 07:28:00 GMT").
	/// Callers decide on any clamp or default.
	public static func seconds(from value: String, now: Date = Date()) -> TimeInterval? {
		let trimmed = value.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else {
			return nil
		}

		// delay-seconds is digits only. Checking for that explicitly keeps
		// "inf", "nan" and exponent forms that TimeInterval("...") would
		// accept from being treated as a number of seconds.
		if trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) {
			guard let seconds = TimeInterval(trimmed), seconds.isFinite, seconds > 0 else {
				return nil
			}
			return seconds
		}

		// DateFormatter is not Sendable, so build one per call rather than
		// sharing a static. This runs once per 429, so the cost is irrelevant.
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
		guard let date = formatter.date(from: trimmed) else {
			return nil
		}
		let seconds = date.timeIntervalSince(now)
		return seconds > 0 ? seconds : nil
	}
}
