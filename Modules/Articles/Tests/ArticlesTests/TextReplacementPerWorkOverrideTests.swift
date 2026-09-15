//
//  TextReplacementPerWorkOverrideTests.swift
//  ArticlesTests
//
//  Coverage for TextReplacementPerWorkOverride: a per-work override
//  correctly takes precedence over the global table for that one work and
//  doesn't leak into any other work's replacement pass -- the exact
//  requirement the plan's "Tests" section calls out under "Per-work
//  override," verified end to end through
//  TextReplacementRuleEngine.findMatches so the precedence claim is
//  checked against real matching behavior, not just against the merged
//  table's row order.
//

import Foundation
import Testing

@testable import Articles

@Suite struct TextReplacementPerWorkOverrideTests {

	private let globalTable = TextReplacementRuleTable(rules: [
		TextReplacementRule(input: "Y/N", output: "Alex")
	])

	@Test func tableForBookKeyReturnsNilWhenNoOverrideExists() {
		let override = TextReplacementPerWorkOverride()
		#expect(override.table(forBookKey: "work-1") == nil)
	}

	@Test func tableForBookKeyReturnsNilForNilBookKey() {
		var override = TextReplacementPerWorkOverride()
		override.setTable(TextReplacementRuleTable(rules: [TextReplacementRule(input: "Y/N", output: "Jordan")]), forBookKey: "work-1")
		#expect(override.table(forBookKey: nil) == nil)
	}

	@Test func setTableThenTableForBookKeyRoundTrips() {
		var override = TextReplacementPerWorkOverride()
		let table = TextReplacementRuleTable(rules: [TextReplacementRule(input: "Y/N", output: "Jordan")])
		override.setTable(table, forBookKey: "work-1")
		#expect(override.table(forBookKey: "work-1") == table)
	}

	@Test func setTableWithEmptyRulesClearsAnyExistingOverride() {
		var override = TextReplacementPerWorkOverride()
		override.setTable(TextReplacementRuleTable(rules: [TextReplacementRule(input: "Y/N", output: "Jordan")]), forBookKey: "work-1")
		override.setTable(TextReplacementRuleTable(rules: []), forBookKey: "work-1")
		#expect(override.table(forBookKey: "work-1") == nil)
		#expect(override.hasOverride(forBookKey: "work-1") == false)
	}

	@Test func hasOverrideIsFalseForAWorkWithNoOverrideSet() {
		let override = TextReplacementPerWorkOverride()
		#expect(override.hasOverride(forBookKey: "work-1") == false)
	}

	@Test func hasOverrideIsTrueOnlyForTheWorkItWasSetFor() {
		var override = TextReplacementPerWorkOverride()
		override.setTable(TextReplacementRuleTable(rules: [TextReplacementRule(input: "Y/N", output: "Jordan")]), forBookKey: "work-1")
		#expect(override.hasOverride(forBookKey: "work-1") == true)
		#expect(override.hasOverride(forBookKey: "work-2") == false)
	}

	// MARK: mergedReaderInsertTable / precedence

	@Test func mergedTableReturnsGlobalUnchangedWhenNoOverrideExistsForThisWork() {
		let override = TextReplacementPerWorkOverride()
		let merged = override.mergedReaderInsertTable(forBookKey: "work-1", global: globalTable)
		#expect(merged == globalTable)
	}

	@Test func mergedTableReturnsGlobalUnchangedForNilBookKey() {
		var override = TextReplacementPerWorkOverride()
		override.setTable(TextReplacementRuleTable(rules: [TextReplacementRule(input: "Y/N", output: "Jordan")]), forBookKey: "work-1")
		let merged = override.mergedReaderInsertTable(forBookKey: nil, global: globalTable)
		#expect(merged == globalTable)
	}

	@Test("a per-work override takes precedence over the global table for that work's own matches")
	func overrideTakesPrecedenceOverGlobalTableForItsOwnWork() {
		var override = TextReplacementPerWorkOverride()
		override.setTable(TextReplacementRuleTable(rules: [TextReplacementRule(input: "Y/N", output: "Jordan")]), forBookKey: "work-1")

		let merged = override.mergedReaderInsertTable(forBookKey: "work-1", global: globalTable)
		let matches = TextReplacementRuleEngine.findMatches(applying: merged, to: "Hey Y/N, over here.")

		#expect(matches.count == 1)
		#expect(matches.first?.replacementText == "Jordan")
	}

	@Test("an override set for one work does not leak into another work's replacement pass")
	func overrideDoesNotLeakIntoAnotherWork() {
		var override = TextReplacementPerWorkOverride()
		override.setTable(TextReplacementRuleTable(rules: [TextReplacementRule(input: "Y/N", output: "Jordan")]), forBookKey: "work-1")

		// A different work, no override of its own -- must fall back to the
		// global table's replacement, not work-1's.
		let mergedForOtherWork = override.mergedReaderInsertTable(forBookKey: "work-2", global: globalTable)
		let matches = TextReplacementRuleEngine.findMatches(applying: mergedForOtherWork, to: "Hey Y/N, over here.")

		#expect(matches.count == 1)
		#expect(matches.first?.replacementText == "Alex")
	}

	@Test("a per-work override with multiple rules only overrides the tokens it defines, leaving the rest of the global table active")
	func overridePartiallyOverlappingGlobalTableOnlyOverridesItsOwnTokens() {
		let global = TextReplacementRuleTable(rules: [
			TextReplacementRule(input: "Y/N", output: "Alex"),
			TextReplacementRule(input: "L/N", output: "Smith")
		])
		var override = TextReplacementPerWorkOverride()
		// This work only overrides Y/N -- L/N should still resolve via the
		// global table's own row.
		override.setTable(TextReplacementRuleTable(rules: [TextReplacementRule(input: "Y/N", output: "Jordan")]), forBookKey: "work-1")

		let merged = override.mergedReaderInsertTable(forBookKey: "work-1", global: global)
		let matches = TextReplacementRuleEngine.findMatches(applying: merged, to: "Y/N met L/N.")

		let byOriginal = Dictionary(uniqueKeysWithValues: matches.map { ($0.originalText, $0.replacementText) })
		#expect(byOriginal["Y/N"] == "Jordan")
		#expect(byOriginal["L/N"] == "Smith")
	}
}
