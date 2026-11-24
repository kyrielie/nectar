//
//  ContentHTMLCompressionTests.swift
//  ArticlesDatabaseTests
//
//  Coverage of ContentHTMLCompression:
//  (1) compress/decompress raw Data round-trip for ordinary HTML,
//  (2) nil/empty input passed through unchanged,
//  (3) decompressAny handling both Data (BLOB) and String (legacy Base64),
//  (4) decompress on non-base64 string falls back to stored string as-is,
//  (5) decompress on valid base64 that isn't valid LZFSE data falls back as-is.
//

import Testing
import Foundation
@testable import ArticlesDatabase

@Suite("ContentHTMLCompression round-trip and fallback behavior")
struct ContentHTMLCompressionTests {

	// MARK: - 1. Round-trip

	@Test("compress/decompress round-trips ordinary HTML with binary Data")
	func roundTripsOrdinaryHTML() {
		let html = "<p>Some <strong>content</strong> with unicode: café, emoji: 🎉</p>"
		let compressed = ContentHTMLCompression.compress(html)
		#expect(compressed != nil)
		#expect(ContentHTMLCompression.decompress(compressed) == html)
		#expect(ContentHTMLCompression.decompressAny(compressed) == html)
	}

	// MARK: - 2. nil/empty passthrough

	@Test("compress passes nil or empty through as nil")
	func compressPassesNilOrEmptyThrough() {
		#expect(ContentHTMLCompression.compress(nil) == nil)
		#expect(ContentHTMLCompression.compress("") == nil)
	}

	@Test("decompress passes nil through unchanged")
	func decompressPassesNilThroughUnchanged() {
		#expect(ContentHTMLCompression.decompress(nil as Data?) == nil)
		#expect(ContentHTMLCompression.decompress(nil as String?) == nil)
		#expect(ContentHTMLCompression.decompressAny(nil) == nil)
		#expect(ContentHTMLCompression.decompressAny(NSNull()) == nil)
	}

	@Test("decompress passes empty string through unchanged")
	func decompressPassesEmptyStringThroughUnchanged() {
		#expect(ContentHTMLCompression.decompress("") == "")
		#expect(ContentHTMLCompression.decompress(Data()) == nil)
	}

	// MARK: - 3. Legacy Base64 backward compatibility

	@Test("decompressAny seamlessly handles legacy Base64 string")
	func legacyBase64RoundTrip() {
		let html = "<p>Legacy fic content with chapter text</p>"
		let base64 = ContentHTMLCompression.compressBase64(html)
		#expect(base64 != nil)
		#expect(ContentHTMLCompression.decompress(base64) == html)
		#expect(ContentHTMLCompression.decompressAny(base64) == html)
	}

	// MARK: - 4. Non-base64 input falls back to the stored string as-is

	@Test("decompress on a plain non-base64 string falls back to returning it as-is")
	func decompressNonBase64FallsBackToStoredString() {
		let plainText = "not valid base64 content!"
		#expect(ContentHTMLCompression.decompress(plainText) == plainText)
		#expect(ContentHTMLCompression.decompressAny(plainText) == plainText)
	}

	// MARK: - 5. Valid base64 that isn't valid LZFSE data falls back too

	@Test("decompress on valid base64 that isn't valid LZFSE data falls back to returning the stored string as-is")
	func decompressValidBase64InvalidLZFSEFallsBackToStoredString() {
		let storedValue = Data("just plain text, never compressed".utf8).base64EncodedString()
		#expect(ContentHTMLCompression.decompress(storedValue) == storedValue)
		#expect(ContentHTMLCompression.decompressAny(storedValue) == storedValue)
	}
}
