//
//  ArticleSeriesEntryTests.swift
//  ArticlesTests
//
//  Created for the Nectar fork -- inline series navigation, Phase 1.
//

import Foundation
import Testing

@testable import Articles

@Suite struct ArticleSeriesEntryTests {

	/// Confirms 1c: adding previousWorkURL/nextWorkURL to the Codable
	/// struct round-trips cleanly through JSONEncoder/JSONDecoder --
	/// this is the shape `series`'s TEXT column (ArticlesDatabase) is
	/// encoded/decoded through.
	@Test func roundTripsThroughJSONWithNavigationFieldsSet() throws {
		let original = ArticleSeriesEntry(name: "Some Series", index: 3, ao3ID: "12345", previousWorkURL: "https://archiveofourown.org/works/111", nextWorkURL: "https://archiveofourown.org/works/222")

		let data = try JSONEncoder().encode(original)
		let decoded = try JSONDecoder().decode(ArticleSeriesEntry.self, from: data)

		#expect(decoded == original)
		#expect(decoded.previousWorkURL == "https://archiveofourown.org/works/111")
		#expect(decoded.nextWorkURL == "https://archiveofourown.org/works/222")
	}

	/// The actual backward-compatibility guarantee existing database rows
	/// depend on: a `series` JSON blob persisted *before* this change --
	/// three keys only (name/index/ao3ID) -- must still decode cleanly,
	/// with the two new fields defaulting to nil rather than throwing.
	/// `ArticleSeriesEntry` doesn't customize `init(from:)`, so this relies
	/// on `JSONDecoder`'s default behavior of treating a missing key as
	/// nil for an `Optional` property -- confirmed here rather than
	/// assumed.
	@Test func decodesPreExistingThreeKeyPayloadWithNilNavigationFields() throws {
		let legacyJSON = """
		{"name":"Some Series","index":3,"ao3ID":"12345"}
		""".data(using: .utf8)!

		let decoded = try JSONDecoder().decode(ArticleSeriesEntry.self, from: legacyJSON)

		#expect(decoded.name == "Some Series")
		#expect(decoded.index == 3)
		#expect(decoded.ao3ID == "12345")
		#expect(decoded.previousWorkURL == nil)
		#expect(decoded.nextWorkURL == nil)
	}

	/// Same guarantee, but for a series entry that also predates ao3ID
	/// ever being nil-able in practice -- confirms a legacy payload with
	/// `ao3ID` explicitly null still decodes, unaffected by this change.
	@Test func decodesPreExistingPayloadWithNullAo3ID() throws {
		let legacyJSON = """
		{"name":"Calibre-only Series","index":1,"ao3ID":null}
		""".data(using: .utf8)!

		let decoded = try JSONDecoder().decode(ArticleSeriesEntry.self, from: legacyJSON)

		#expect(decoded.name == "Calibre-only Series")
		#expect(decoded.index == 1)
		#expect(decoded.ao3ID == nil)
		#expect(decoded.previousWorkURL == nil)
		#expect(decoded.nextWorkURL == nil)
	}

	/// The three-arg initializer (every pre-existing call site in the
	/// codebase -- AO3SeriesNavigatorTests, Article+Database's non-AO3
	/// paths) must still compile and produce nil navigation fields via
	/// the new parameters' defaults.
	@Test func threeArgInitializerDefaultsNavigationFieldsToNil() {
		let entry = ArticleSeriesEntry(name: "Some Series", index: 1, ao3ID: nil)

		#expect(entry.previousWorkURL == nil)
		#expect(entry.nextWorkURL == nil)
	}
}
