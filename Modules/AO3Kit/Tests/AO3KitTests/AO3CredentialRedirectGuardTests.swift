//
//  AO3CredentialRedirectGuardTests.swift
//  AO3Kit
//
//  D6: the host/scheme gate (AO3AuthenticatedFetcher.shouldSendSession) and
//  the redirect guard (AO3CredentialRedirectGuard) are both thin wrappers
//  around AO3Link.mayReceiveSession -- AO3LinkTests already covers that
//  function exhaustively, so this only needs to confirm both wrappers
//  actually forward to it, not re-cover every host/scheme case.
//
//  The redirect guard's delegate method takes a URLSession and
//  URLSessionTask, but never reads either argument -- the decision comes
//  entirely from newRequest.url -- so a real session/task isn't needed to
//  exercise it (matching the plan's own note that this only requires the
//  pure decision function, not a live session).
//

import Foundation
import Testing
@testable import AO3Kit

private func url(_ string: String) -> URL {
	URL(string: string)!
}

@Suite struct AO3CredentialRedirectGuardTests {

	private func redirectDecision(to newURLString: String) -> URLRequest? {
		let guardDelegate = AO3CredentialRedirectGuard()
		let session = URLSession(configuration: .ephemeral)
		let task = session.dataTask(with: url("https://archiveofourown.org/works/1"))
		let response = HTTPURLResponse(url: url("https://archiveofourown.org/works/1"), statusCode: 302, httpVersion: nil, headerFields: nil)!
		let newRequest = URLRequest(url: url(newURLString))

		var result: URLRequest?
		let semaphore = DispatchSemaphore(value: 0)
		guardDelegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: newRequest) { request in
			result = request
			semaphore.signal()
		}
		semaphore.wait()
		task.cancel()
		return result
	}

	@Test func allowsRedirectToCredentialHost() {
		#expect(redirectDecision(to: "https://www.archiveofourown.org/works/1") != nil)
	}

	@Test func blocksRedirectOffAO3() {
		#expect(redirectDecision(to: "https://evil.example/works/1") == nil)
	}

	@Test func blocksRedirectToNonCredentialAO3Host() {
		// insecure./download. and the raw IPs are recognized AO3 hosts but
		// not credential hosts -- see AO3Link.credentialHosts's own doc
		// comment for why. A redirect to one of these must still be
		// blocked, the same as a redirect off AO3 entirely.
		#expect(redirectDecision(to: "https://insecure.archiveofourown.org/works/1") == nil)
	}

	@Test func blocksRedirectDowngradingToHTTP() {
		#expect(redirectDecision(to: "http://archiveofourown.org/works/1") == nil)
	}
}

@Suite struct AO3AuthenticatedFetcherShouldSendSessionTests {

	@Test func matchesMayReceiveSessionForCredentialHost() {
		#expect(AO3AuthenticatedFetcher.shouldSendSession(to: url("https://archiveofourown.org/works/1")))
	}

	@Test func matchesMayReceiveSessionForNonCredentialHost() {
		#expect(!AO3AuthenticatedFetcher.shouldSendSession(to: url("https://evil.example/works/1")))
	}
}
