//
//  ContentHTMLCompressionTests.swift
//  ArticlesDatabaseTests
//
//  Nectar cleanup plan v2, Phase 3d: pure-function coverage of
//  ContentHTMLCompression, no database needed. Four cases, matching the
//  plan's numbering: (1) compress/decompress round-trip for ordinary HTML,
//  (2) nil/empty input passed through unchanged by both functions, (3)
//  decompress on non-base64 input falls back to the stored string as-is,
//  (4) decompress on valid base64 that isn't valid LZFSE data also falls
//  back to the stored string, not a throw/crash.
//

import Testing
import Foundation
@testable import ArticlesDatabase

@Suite("ContentHTMLCompression round-trip and fallback behavior")
struct ContentHTMLCompressionTests {

	// MARK: - 1. Round-trip

	@Test("compress/decompress round-trips ordinary HTML")
	func roundTripsOrdinaryHTML() {
		let html = "<p>Some <strong>content</strong> with unicode: café, emoji: 🎉</p>"
		let compressed = ContentHTMLCompression.compress(html)
		#expect(compressed != nil)
		#expect(compressed != html, "compressed form should differ from the original for non-trivial input")
		#expect(ContentHTMLCompression.decompress(compressed) == html)
	}

	// MARK: - 2. nil/empty passthrough

	@Test("compress passes nil through unchanged")
	func compressPassesNilThroughUnchanged() {
		#expect(ContentHTMLCompression.compress(nil) == nil)
	}

	@Test("compress passes empty string through unchanged")
	func compressPassesEmptyStringThroughUnchanged() {
		#expect(ContentHTMLCompression.compress("") == "")
	}

	@Test("decompress passes nil through unchanged")
	func decompressPassesNilThroughUnchanged() {
		#expect(ContentHTMLCompression.decompress(nil) == nil)
	}

	@Test("decompress passes empty string through unchanged")
	func decompressPassesEmptyStringThroughUnchanged() {
		#expect(ContentHTMLCompression.decompress("") == "")
	}

	// MARK: - 3. Non-base64 input falls back to the stored string as-is

	@Test("decompress on a plain non-base64 string falls back to returning it as-is")
	func decompressNonBase64FallsBackToStoredString() {
		// Contains characters outside the base64 alphabet (space, !), so
		// Data(base64Encoded:) reliably returns nil rather than happening
		// to parse -- this is the "row written before compression landed"
		// compatibility shim, not a crash or nil.
		let plainText = "not valid base64 content!"
		#expect(ContentHTMLCompression.decompress(plainText) == plainText)
	}

	// MARK: - 4. Valid base64 that isn't valid LZFSE data falls back too

	@Test("decompress on valid base64 that isn't valid LZFSE data falls back to returning the stored string as-is")
	func decompressValidBase64InvalidLZFSEFallsBackToStoredString() {
		// Valid base64 (decodes cleanly to bytes), but those bytes are
		// plain UTF-8 text, not LZFSE-compressed data -- exercises the
		// second `guard let ... try?` separately from case 3's decode failure.
		let storedValue = Data("just plain text, never compressed".utf8).base64EncodedString()
		#expect(ContentHTMLCompression.decompress(storedValue) == storedValue)
	}
}
