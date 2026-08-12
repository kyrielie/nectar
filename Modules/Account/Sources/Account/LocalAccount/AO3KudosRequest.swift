//
//  AO3KudosRequest.swift
//  Account
//
//  Nectar AO3 direct-reading support, Task 6 ("kudos-on-like") -- see
//  nectar-ao3-features-plan-FINAL.md. Pure request-shape/response-parsing
//  logic, kept separate from AO3KudosFetcher's actual networking the same
//  way AO3ChapterHTMLExtractor (RSParser, pure) is kept separate from
//  AO3ChapterFetcher (Account, networking) -- lets the request/response
//  shape be unit tested against fixture data with no network involved.
//
//  Endpoint, header names, and the kudo[...] form-field names are
//  cross-checked against (not ported from) ArmindoFlores/ao3_api's
//  (MIT-licensed) utils.kudos() for the general shape -- see the plan
//  document's licensing note at its top. Per that note, this was
//  reverse-engineered against the actual shape rather than copied.
//

import Foundation
import RSWeb

enum AO3KudosOutcome: Sendable, Equatable {
	/// The POST landed and created a new kudos (HTTP 201).
	case success
	/// AO3 reports this identity (pseud/user id for a logged-in kudos, IP
	/// for a guest one) has already left kudos here. Treated the same as
	/// `.success` for storage purposes (a kudos exists either way) --
	/// distinguished only so callers can log it distinctly. This is AO3's
	/// own idempotent response to a duplicate attempt, not something this
	/// app pre-checks for -- see Task 6's "Duplicate detection" note.
	case alreadyKudosed
	/// The authenticity_token was rejected (expired, or scoped to a
	/// different session than the one the request's Cookie header names).
	/// Not retried automatically here -- a future attempt naturally gets a
	/// freshly scraped token from whatever page fetch triggers it next.
	case authError
	/// `commentable_id` didn't resolve to a work AO3 recognizes --
	/// shouldn't happen for a workID this app just successfully fetched a
	/// page for, but it's a documented AO3 failure mode.
	case invalidWork
	case rateLimited
	case otherFailure(message: String)
}

enum AO3KudosRequest {

	/// AO3's kudos endpoint -- the `.js` (XHR) endpoint the work page's own
	/// kudos button actually posts to, matching `ao3_api`'s
	/// `utils.kudos()`, as opposed to the plain `/kudos` redirect-based
	/// endpoint AO3 also exposes for non-JS form submission (not what's
	/// reverse-engineered here).
	static let url = URL(string: "https://archiveofourown.org/kudos.js")!

	/// Builds the POST request for leaving kudos on `workID`, using
	/// `csrfToken` scraped from a real fetch of the work's own page (see
	/// `AO3ChapterHTMLExtractor.csrfToken(root:)`) -- never invented
	/// client-side, per Task 6's plan. `cookieHeaderValue` is passed
	/// through as-is (nil for a guest attempt); this function doesn't
	/// decide guest vs. authenticated, only shapes the request for
	/// whichever the caller already decided -- see `AO3KudosManager`.
	static func makeRequest(workID: String, csrfToken: String, cookieHeaderValue: String?) -> URLRequest {
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue(csrfToken, forHTTPHeaderField: "x-csrf-token")
		request.setValue("XMLHttpRequest", forHTTPHeaderField: "x-requested-with")
		request.setValue("https://archiveofourown.org/works/\(workID)", forHTTPHeaderField: "referer")
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		if let cookieHeaderValue {
			request.setValue(cookieHeaderValue, forHTTPHeaderField: "Cookie")
		}
		if let userAgentHeaders = UserAgent.headers() {
			for (field, value) in userAgentHeaders {
				guard let field = field as? String else { continue }
				request.setValue(value, forHTTPHeaderField: field)
			}
		}

		request.httpBody = formURLEncodedBody([
			"authenticity_token": csrfToken,
			"kudo[commentable_id]": workID,
			"kudo[commentable_type]": "Work"
		])
		return request
	}

	/// Interprets the response per AO3's documented kudos.js contract: 201
	/// on success, 422 with a JSON `errors` object distinguishing
	/// "already kudosed" from an auth/token problem from an invalid work
	/// id, 429 on rate limit. See this file's header comment for where
	/// this contract comes from.
	static func outcome(statusCode: Int, data: Data?) -> AO3KudosOutcome {
		switch statusCode {
		case HTTPResponseCode.created:
			return .success
		case HTTPResponseCode.tooManyRequests:
			return .rateLimited
		case HTTPResponseCode.unprocessableContentWebDAV:
			return outcomeFor422(data: data)
		default:
			return .otherFailure(message: "Unexpected HTTP status code from AO3 (\(statusCode))")
		}
	}

	private static func outcomeFor422(data: Data?) -> AO3KudosOutcome {
		guard let data,
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let errors = json["errors"] as? [String: Any] else {
			return .otherFailure(message: "AO3 rejected the kudos request (HTTP 422)")
		}
		if errors["auth_error"] != nil {
			return .authError
		}
		if errors["user_id"] != nil || errors["ip_address"] != nil {
			return .alreadyKudosed
		}
		if errors["no_commentable"] != nil {
			return .invalidWork
		}
		return .otherFailure(message: "AO3 rejected the kudos request (HTTP 422)")
	}

	/// `application/x-www-form-urlencoded` body, percent-encoding both
	/// keys and values -- `kudo[commentable_id]` itself needs its own
	/// brackets encoded to be a well-formed form field name.
	private static func formURLEncodedBody(_ params: [String: String]) -> Data {
		var allowed = CharacterSet.urlQueryAllowed
		allowed.remove(charactersIn: "+&=[]")
		let pairs = params.map { key, value -> String in
			let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
			let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
			return "\(encodedKey)=\(encodedValue)"
		}
		return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
	}
}
