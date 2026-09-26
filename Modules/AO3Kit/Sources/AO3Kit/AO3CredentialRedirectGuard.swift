//
//  AO3CredentialRedirectGuard.swift
//  AO3Kit
//
//  D6 of the AO3 link/host unification: a cookie-authenticated request
//  (AO3AuthenticatedFetcher.fetch, AO3KudosFetcher.leaveKudos) attaches a
//  Cookie header by hand rather than relying on a cookie-jar URLSession
//  (see both files' own header comments for why), so URLSession's default
//  "follow every redirect" behavior would otherwise resend that header to
//  wherever a 3xx response's Location points -- including off AO3 entirely,
//  if a compromised or misconfigured intermediate ever returned one.
//
//  Rather than strip the header on a same-request basis (URLSession gives
//  no API to edit headers on a followed redirect, only to replace the
//  request outright or refuse to follow it), this delegate blocks the
//  redirect outright unless the new destination still qualifies as a
//  credential host. AO3's own same-host redirects (http -> https, www. ->
//  apex, both already in `AO3Link.credentialHosts`) still proceed normally.
//  Blocking means completing with `nil`, which hands the 3xx response
//  itself back to the caller instead of following it -- every existing
//  caller already treats a non-2xx status as a handled failure (see
//  AO3ChapterFetcher's statusIsOK checks, AO3SearchResultsFetcher's own,
//  and AO3KudosRequest.outcome(statusCode:data:)'s default branch), so a
//  blocked redirect fails the same way a plain error response already does,
//  not in some new untested way.
//

import Foundation

public final class AO3CredentialRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {

	public override init() {}

	public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
		guard let newURL = request.url, AO3Link.mayReceiveSession(newURL) else {
			completionHandler(nil)
			return
		}
		completionHandler(request)
	}
}
