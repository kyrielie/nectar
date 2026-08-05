//
//  TestHelpers.swift
//  RSParserTests
//
//  Created by Brent Simmons on 4/20/26.
//

import Foundation
import RSParser

/// Load a fixture from `Tests/RSParserTests/Resources/` and wrap it in a
/// `ParserData` with the given pretend-source URL. Used by tests across all
/// parser suites (feeds, HTML, OPML) — kept at the top of the test target so
/// its location doesn't depend on where the first caller happens to live.
func parserData(_ filename: String, _ fileExtension: String, _ url: String) -> ParserData {
	let resourcePath = "Resources/\(filename)"
	let path = Bundle.module.path(forResource: resourcePath, ofType: fileExtension)!
	let data = try! Data(contentsOf: URL(fileURLWithPath: path))
	return ParserData(url: url, data: data)
}

/// Load a fixture from `Tests/RSParserTests/Resources/` as a raw `String`,
/// for consumers (like `AO3ChapterHTMLExtractor`) that parse HTML text
/// directly rather than through a `ParserData`/URL-bearing entry point.
func htmlFixtureString(_ filename: String) -> String {
	// `filename` already includes its extension at every call site (e.g.
	// "ao3-work-multi-chapter.html"), so `ofType` must be nil here — passing
	// an extension as well makes Bundle look for a doubled extension
	// ("....html.html") and return nil.
	let resourcePath = "Resources/\(filename)"
	let path = Bundle.module.path(forResource: resourcePath, ofType: nil)!
	return try! String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
}
