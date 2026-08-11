//
//  TestingURLProtocol.swift
//  RSWeb
//
//  Created by Brent Simmons on 6/16/26.
//

import Foundation

public final class TestingURLProtocol: URLProtocol {

	/// A canned response for a request whose URL contains a given substring.
	public struct Response: Sendable {
		public var statusCode: Int
		public var data: Data?

		public init(statusCode: Int = 200, data: Data? = nil) {
			self.statusCode = statusCode
			self.data = data
		}
	}

	/// Maps a URL substring to the response to return for matching requests.
	/// Populated by tests; consulted per request, so it may change between requests.
	nonisolated(unsafe) public static var responses = [String: Response]()

	/// URLs actually requested through this protocol. Useful for tests that
	/// need to distinguish "no network request" from a cached response.
	nonisolated(unsafe) public static var requestedURLs = [URL]()

	/// Clears all registered responses. Call between tests.
	public static func reset() {
		responses = [:]
		requestedURLs = []
	}

	public override static func canInit(with request: URLRequest) -> Bool {
		true
	}

	public override static func canonicalRequest(for request: URLRequest) -> URLRequest {
		request
	}

	public override func startLoading() {

		guard let url = request.url else {
			client?.urlProtocol(self, didFailWithError: URLError(.badURL))
			return
		}
		Self.requestedURLs.append(url)

		let urlString = url.absoluteString
		let match = Self.responses
			.filter { urlString.contains($0.key) }
			.max { $0.key.count < $1.key.count }?
			.value

		let httpResponse = HTTPURLResponse(url: url, statusCode: match?.statusCode ?? 200, httpVersion: "HTTP/1.1", headerFields: nil)!
		client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)

		if let data = match?.data {
			client?.urlProtocol(self, didLoad: data)
		}

		client?.urlProtocolDidFinishLoading(self)
	}

	public override func stopLoading() {
	}
}
