//
//  AO3WorkPageClassifierTests.swift
//  AO3KitTests
//
//  The failure-page bodies below are synthetic, built from copy AO3 is known
//  to use. They have not been compared against live captures; replace them
//  with real fixtures when captured.
//
import Foundation
import Testing
@testable import AO3Kit

@Suite struct AO3WorkPageClassifierTests {

	private static func data(_ html: String) -> Data {
		Data(html.utf8)
	}

	private static let challengeHTML = "<html><head><title>Just a moment...</title></head><body></body></html>"
	private static let unavailableHTML = "<html><body><h2 class=\"heading\">Error 503 - Service unavailable</h2></body></html>"
	private static let betaHTML = "<html><body><p>This site is in beta. Things may break or crash without notice.</p></body></html>"
	private static let hiddenHTML = "<html><body><p>This work is part of an ongoing challenge and will be revealed soon!</p></body></html>"
	private static let notFoundCopyHTML = "<html><body><div class=\"flash error\">Sorry, we couldn&#x27;t find the work you were looking for.</div></body></html>"
	private static let permissionHTML = "<html><body><div class=\"flash error\">Sorry, you don&#39;t have permission to access the page you were trying to reach.</div></body></html>"

	private static func failure(_ result: AO3WorkPageResult) -> AO3FetchFailure? {
		if case .failure(let failure) = result {
			return failure
		}
		return nil
	}

	// MARK: - Extractor outcomes

	@Test func extractorRecognizesChallenge() {
		guard case .cloudflareChallenge = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: Self.challengeHTML) else {
			Issue.record("Expected .cloudflareChallenge")
			return
		}
	}

	@Test func extractorRecognizesServiceUnavailableHeadingAndBetaBanner() {
		for html in [Self.unavailableHTML, Self.betaHTML] {
			guard case .serviceUnavailable = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html) else {
				Issue.record("Expected .serviceUnavailable")
				return
			}
		}
	}

	@Test func extractorRecognizesHiddenUntilRevealed() {
		guard case .hiddenUntilRevealed = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: Self.hiddenHTML) else {
			Issue.record("Expected .hiddenUntilRevealed")
			return
		}
	}

	@Test func extractorMatchesEveryApostropheSpelling() {
		for apostrophe in ["'", "&#x27;", "&#39;", "\u{2019}"] {
			let html = "<html><body>Sorry, we couldn\(apostrophe)t find the work you were looking for.</body></html>"
			guard case .workNotFound = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html) else {
				Issue.record("Expected .workNotFound for apostrophe \(apostrophe)")
				return
			}
		}
	}

	@Test func extractorRecognizesPermissionDenied() {
		guard case .permissionDenied = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: Self.permissionHTML) else {
			Issue.record("Expected .permissionDenied")
			return
		}
	}

	@Test func registrationRequiredWinsOverLaterChecks() {
		let html = "<html><body><div id=\"signin\"><p>This work is only available to registered users of the Archive.</p></div>Just a moment...</body></html>"
		guard case .registrationRequired = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html) else {
			Issue.record("Expected .registrationRequired")
			return
		}
	}

	// MARK: - Classifier

	@Test func status429IsRateLimited() {
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: nil, statusCode: 429)) == .rateLimited(until: nil))
	}

	@Test func status404And410AreWorkMissing() {
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: nil, statusCode: 404)) == .workMissing)
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: Self.data("<html></html>"), statusCode: 410)) == .workMissing)
	}

	@Test func challengeOn403IsChallengeNotHTTP() {
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: Self.data(Self.challengeHTML), statusCode: 403)) == .challenge)
	}

	@Test func challengeOn200IsChallenge() {
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: Self.data(Self.challengeHTML), statusCode: 200)) == .challenge)
	}

	@Test func serviceUnavailableBodyOn200And503() {
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: Self.data(Self.unavailableHTML), statusCode: 200)) == .serviceUnavailable)
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: Self.data(Self.unavailableHTML), statusCode: 503)) == .serviceUnavailable)
	}

	@Test func plain5xxIsHTTP() {
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: Self.data("<html></html>"), statusCode: 502)) == .http(502))
	}

	@Test func other4xxIsHTTP() {
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: nil, statusCode: 403)) == .http(403))
	}

	@Test func emptyBodyIsHTTP() {
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: Data(), statusCode: 200)) == .http(200))
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: nil, statusCode: nil)) == .http(-1))
	}

	@Test func unrecognizedPageOn200IsNotMissingEvidence() {
		let failure = Self.failure(AO3WorkPageClassifier.classify(data: Self.data("<html><body><p>Something new.</p></body></html>"), statusCode: 200))
		#expect(failure == .unrecognizedPage)
		#expect(failure?.evidencesMissing == false)
	}

	@Test func explicitNotFoundCopyIsMissingEvidence() {
		let failure = Self.failure(AO3WorkPageClassifier.classify(data: Self.data(Self.notFoundCopyHTML), statusCode: 200))
		#expect(failure == .workMissing)
		#expect(failure?.evidencesMissing == true)
	}

	@Test func gatesMapToTheirFailures() {
		let adult = htmlFixtureString("ao3-work-adult-content-gate.html")
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: Self.data(adult), statusCode: 200)) == .adultGate)
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: Self.data(Self.hiddenHTML), statusCode: 200)) == .hiddenUntilRevealed)
		#expect(Self.failure(AO3WorkPageClassifier.classify(data: Self.data(Self.permissionHTML), statusCode: 200)) == .permissionDenied)
	}

	@Test func realWorkPageContainingChallengePhraseStillSucceeds() {
		let html = htmlFixtureString("ao3-work-multi-chapter.html").replacingOccurrences(of: "</body>", with: "<p>Just a moment...</p></body>")
		guard case .success = AO3WorkPageClassifier.classify(data: Self.data(html), statusCode: 200) else {
			Issue.record("Expected .success")
			return
		}
	}

	@Test func realWorkPageWithMarkerPhraseIsNotAnInterstitial() {
		let html = htmlFixtureString("ao3-work-multi-chapter.html").replacingOccurrences(of: "</body>", with: "<p>Just a moment...</p></body>")
		#expect(!AO3WorkPageClassifier.isInterstitial(html))
	}

	@Test func isInterstitial() {
		#expect(AO3WorkPageClassifier.isInterstitial(Self.challengeHTML))
		#expect(AO3WorkPageClassifier.isInterstitial(Self.unavailableHTML))
		#expect(AO3WorkPageClassifier.isInterstitial(Self.betaHTML))
		#expect(!AO3WorkPageClassifier.isInterstitial("<html><body>An ordinary page.</body></html>"))
	}
}

@Suite struct AO3FetchFailureTests {

	@Test func existingMessagesAreReusedVerbatim() {
		#expect(AO3FetchFailure.rateLimited(until: nil).localizedMessage == "AO3 rate limit hit -- backing off before retrying")
		#expect(AO3FetchFailure.challenge.localizedMessage == "Blocked by a Cloudflare challenge -- try again later")
		#expect(AO3FetchFailure.signInRequired.localizedMessage == "This shelf requires a signed-in AO3 account")
		#expect(AO3FetchFailure.listingRestricted.localizedMessage == "Restricted to registered AO3 users")
		#expect(AO3FetchFailure.registrationRequired.localizedMessage == "This work is only available to registered AO3 users")
		#expect(AO3FetchFailure.filtersNotApplied.localizedMessage == "AO3 ignored this search's filters (URL too long)")
		#expect(AO3FetchFailure.sessionEnded.localizedMessage == "Signed out of AO3 -- sign in again in Settings to read this work")
		#expect(AO3FetchFailure.unrecognizedPage.localizedMessage == "No chapter content found (gated or removed work)")
		#expect(AO3FetchFailure.http(502).localizedMessage == "Could not reach AO3 (HTTP 502)")
	}

	@Test func onlyWorkMissingEvidencesMissing() {
		#expect(AO3FetchFailure.workMissing.evidencesMissing)
		#expect(!AO3FetchFailure.unrecognizedPage.evidencesMissing)
		#expect(!AO3FetchFailure.http(404).evidencesMissing)
	}

	@Test func transientClassification() {
		#expect(AO3FetchFailure.http(503).isTransient)
		#expect(!AO3FetchFailure.http(403).isTransient)
		#expect(AO3FetchFailure.network("x").isTransient)
		#expect(AO3FetchFailure.unrecognizedPage.isTransient)
		#expect(!AO3FetchFailure.workMissing.isTransient)
		#expect(!AO3FetchFailure.sessionEnded.isTransient)
	}

	@Test func searchOutcomeMapping() {
		let url = URL(string: "https://archiveofourown.org/works")!
		#expect(AO3SearchResultsFetchOutcome.registrationRequired.failure == .listingRestricted)
		#expect(AO3SearchResultsFetchOutcome.rateLimited.failure == .rateLimited(until: nil))
		#expect(AO3SearchResultsFetchOutcome.cloudflareChallenge(challengedURL: url).failure == .challenge)
		#expect(AO3SearchResultsFetchOutcome.notSignedIn.failure == .signInRequired)
		#expect(AO3SearchResultsFetchOutcome.filtersNotApplied.failure == .filtersNotApplied)
		#expect(AO3SearchResultsFetchOutcome.noResults(pageTitle: nil, totalPages: nil).failure == nil)
	}
}
