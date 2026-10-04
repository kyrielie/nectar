//
//  AO3WorkPageClassifier.swift
//  AO3Kit
//
//  Turns a fetched work page (body plus HTTP status) into either extracted
//  content or one typed AO3FetchFailure. One classifier serves both the
//  anonymous and the authenticated chapter fetch paths, so the two cannot
//  disagree about what a page means.
//
import Foundation

public enum AO3WorkPageResult: Sendable {
	case success(AO3ChapterExtractionResult)
	case failure(AO3FetchFailure)
}

public enum AO3WorkPageClassifier {

	/// `statusCode` is nil when no HTTP status is known. Evaluation order:
	/// 429, then 404/410 (positive evidence of a missing work), then a
	/// Cloudflare challenge on a non-2xx status (a 403 challenge page must
	/// not become `.http(403)`; a 2xx challenge is caught by the extractor
	/// after it rules out a real work), then 5xx (`.serviceUnavailable` when the body
	/// carries AO3's 503 page), then other non-2xx, then an empty body, and
	/// only then the extractor.
	public static func classify(data: Data?, statusCode: Int?) -> AO3WorkPageResult {
		if statusCode == 429 {
			return .failure(.rateLimited(until: nil))
		}
		if statusCode == 404 || statusCode == 410 {
			return .failure(.workMissing)
		}

		let html: String? = {
			guard let data, !data.isEmpty else {
				return nil
			}
			return String(data: data, encoding: .utf8)
		}()

		// A non-2xx challenge page is checked before the generic status
		// handling. A 2xx body is left to the extractor, which tests for a
		// real work first, so a story that happens to contain a challenge
		// marker phrase is not mistaken for an interstitial.
		let statusIsOK = statusCode.map { (200...299).contains($0) } ?? true
		if !statusIsOK, let html, AO3CloudflareChallenge.isChallengePage(html) {
			return .failure(.challenge)
		}

		if let statusCode, !statusIsOK {
			if (500...599).contains(statusCode), let html,
			   AO3HTMLHelpers.isServiceUnavailablePage(foldedHTML: AO3HTMLHelpers.foldedForCopyMatching(html)) {
				return .failure(.serviceUnavailable)
			}
			return .failure(.http(statusCode))
		}

		guard let data, !data.isEmpty else {
			return .failure(.http(statusCode ?? -1))
		}
		guard let html else {
			return .failure(.unrecognizedPage)
		}

		switch AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html) {
		case .success(let result):
			return .success(result)
		case .adultContentGate:
			return .failure(.adultGate)
		case .registrationRequired:
			return .failure(.registrationRequired)
		case .cloudflareChallenge:
			return .failure(.challenge)
		case .serviceUnavailable:
			return .failure(.serviceUnavailable)
		case .hiddenUntilRevealed:
			return .failure(.hiddenUntilRevealed)
		case .workNotFound:
			return .failure(.workMissing)
		case .permissionDenied:
			return .failure(.permissionDenied)
		case .unrecognizedPage:
			return .failure(.unrecognizedPage)
		}
	}

	/// True for a page that is an interstitial rather than AO3 content (a
	/// Cloudflare challenge, or AO3's 503 page). Used to veto caching, so a
	/// transient block is never replayed from `Downloader`'s cache. A real
	/// work page that merely contains a marker phrase in its text is not an
	/// interstitial: when a marker matches, the page is only vetoed if the
	/// extractor does not find a real work in it.
	public static func isInterstitial(_ html: String) -> Bool {
		guard AO3CloudflareChallenge.isChallengePage(html)
			|| AO3HTMLHelpers.isServiceUnavailablePage(foldedHTML: AO3HTMLHelpers.foldedForCopyMatching(html)) else {
			return false
		}
		if case .success = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html) {
			return false
		}
		return true
	}
}
