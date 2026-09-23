//
//  TextReplacementRuleTableTests.swift
//  ArticlesTests
//
//  Coverage for TextReplacementRuleEngine.findMatches(applying:to:): word-
//  boundary/case-insensitive token matching, cross-rule overlap
//  resolution (earlier rule wins), and the empty-output skip that makes
//  an unfilled reader-insert placeholder rule inert by construction. See
//  the plan's "Word/placeholder replacement" section for the false-
//  positive guard this is meant to pin.
//

import Foundation
import Testing

@testable import AnnotationsKit

@Suite struct TextReplacementRuleTableTests {

	// MARK: word-boundary matching

	@Test func matchesWholeWordOnly() {
		let table = TextReplacementRuleTable(rules: [
			TextReplacementRule(input: "teh", output: "the")
		])
		let text = "I saw teh cat, but not tehcnically a dog."
		let matches = TextReplacementRuleEngine.findMatches(applying: table, to: text)

		// "tehcnically" contains "teh" as a substring but not as a
		// standalone token -- the \btoken\b boundary must exclude it.
		#expect(matches.count == 1)
		#expect(matches[0].originalText == "teh")
		#expect(matches[0].startOffset == 6)
		#expect(matches[0].endOffset == 9)
	}

	@Test func matchingIsCaseInsensitive() {
		let table = TextReplacementRuleTable(rules: [
			TextReplacementRule(input: "teh", output: "the")
		])
		let text = "Teh dog ran. TEH cat slept."
		let matches = TextReplacementRuleEngine.findMatches(applying: table, to: text)

		#expect(matches.count == 2)
		#expect(matches[0].originalText == "Teh")
		#expect(matches[1].originalText == "TEH")
		// The replacement is always the rule's configured output, not a
		// case-matched variant of it.
		#expect(matches[0].replacementText == "the")
		#expect(matches[1].replacementText == "the")
	}

	@Test func splitsCommaSeparatedInputTokensAndMatchesAny() {
		let table = TextReplacementRuleTable(rules: [
			TextReplacementRule(input: "YN, FN", output: "Alex")
		])
		let text = "Hello, YN! How are you, FN?"
		let matches = TextReplacementRuleEngine.findMatches(applying: table, to: text)

		#expect(matches.count == 2)
		#expect(matches[0].originalText == "YN")
		#expect(matches[1].originalText == "FN")
		#expect(matches.allSatisfy { $0.replacementText == "Alex" })
	}

	@Test func parenthesizedTokenNeverMatchesBecauseWordBoundaryFailsOnPunctuation() {
		// \b is a transition between a word and a non-word character.
		// "(" and ")" are themselves non-word characters, so \b can
		// never anchor immediately next to them when the character on
		// the *other* side (typically whitespace) is also non-word --
		// a token like "(Y/N)" (as opposed to bare "Y/N") therefore
		// never matches at all under this engine's \btoken\b scheme,
		// regardless of how the token is escaped. Pinned here as
		// documented, real behavior rather than an assumed edge case,
		// since a person configuring a parenthesized rule (mirroring
		// the reference userscript's own default table shape) would
		// otherwise silently get zero matches with no explanation.
		let table = TextReplacementRuleTable(rules: [
			TextReplacementRule(input: "(Y/N)", output: "Alex")
		])
		let text = "Hello, (Y/N)!"
		let matches = TextReplacementRuleEngine.findMatches(applying: table, to: text)

		#expect(matches.isEmpty)
	}

	@Test func regexEscapesInputTokens() {
		// A token containing regex-special characters (parentheses,
		// slash) must be matched literally, not interpreted as a
		// pattern -- covered implicitly above via "(Y/N)", but this
		// pins it against a token whose unescaped interpretation would
		// behave very differently (a bare "." matching any character).
		let table = TextReplacementRuleTable(rules: [
			TextReplacementRule(input: "a.b", output: "AB")
		])
		let text = "This has a.b in it, but not axb or a-b."
		let matches = TextReplacementRuleEngine.findMatches(applying: table, to: text)

		#expect(matches.count == 1)
		#expect(matches[0].originalText == "a.b")
	}

	// MARK: overlap resolution

	@Test func earlierRuleWinsOnOverlap() {
		// Both rules' tokens can match inside "cat nap"; the first
		// rule in the table ("cat nap", the wider span) claims it, so
		// the second rule's narrower, overlapping "nap" candidate is
		// dropped -- table order decides the winner here, not text
		// order or span width.
		let table = TextReplacementRuleTable(rules: [
			TextReplacementRule(input: "cat nap", output: "nap time"),
			TextReplacementRule(input: "nap", output: "snooze")
		])
		let text = "The cat nap was long."
		let matches = TextReplacementRuleEngine.findMatches(applying: table, to: text)

		#expect(matches.count == 1)
		#expect(matches[0].originalText == "cat nap")
		#expect(matches[0].replacementText == "nap time")
	}

	@Test func overlapWinnerIsDeterminedByTableOrderNotSpanWidth() {
		// Same two candidate spans as above, but with the narrower
		// rule listed first in the table: it claims "nap" before the
		// wider "cat nap" rule ever gets a chance to match, so the
		// wider rule's candidate (which would overlap the already-
		// claimed "nap") is dropped instead.
		let table = TextReplacementRuleTable(rules: [
			TextReplacementRule(input: "nap", output: "snooze"),
			TextReplacementRule(input: "cat nap", output: "nap time")
		])
		let text = "The cat nap was long."
		let matches = TextReplacementRuleEngine.findMatches(applying: table, to: text)

		#expect(matches.count == 1)
		#expect(matches[0].originalText == "nap")
		#expect(matches[0].replacementText == "snooze")
	}

	@Test func laterRuleStillMatchesWhenSpansDontOverlap() {
		let table = TextReplacementRuleTable(rules: [
			TextReplacementRule(input: "teh", output: "the"),
			TextReplacementRule(input: "alot", output: "a lot")
		])
		let text = "I have teh alot of homework."
		let matches = TextReplacementRuleEngine.findMatches(applying: table, to: text)

		#expect(matches.count == 2)
		#expect(matches.map(\.originalText) == ["teh", "alot"])
	}

	@Test func resultsAreSortedByDocumentOrderRegardlessOfRuleOrder() {
		let table = TextReplacementRuleTable(rules: [
			TextReplacementRule(input: "alot", output: "a lot"),
			TextReplacementRule(input: "teh", output: "the")
		])
		// "teh" appears before "alot" in the text even though its rule
		// is declared second in the table.
		let text = "I have teh alot of homework."
		let matches = TextReplacementRuleEngine.findMatches(applying: table, to: text)

		#expect(matches.map(\.originalText) == ["teh", "alot"])
		#expect(matches[0].startOffset < matches[1].startOffset)
	}

	// MARK: empty-output skip

	@Test func ruleWithEmptyOutputNeverMatches() {
		let table = TextReplacementRuleTable.defaultReaderInsertTable
		let text = "Hello, Y/N! Nice to meet you, L/N."
		let matches = TextReplacementRuleEngine.findMatches(applying: table, to: text)

		#expect(matches.isEmpty)
	}

	@Test func emptyOutputRuleDoesNotBlockAnOverlappingFilledRule() {
		// An inert placeholder rule must not "claim" a span it never
		// actually matches against -- a later, filled-in rule for the
		// same token should still match normally.
		let table = TextReplacementRuleTable(rules: [
			TextReplacementRule(input: "YN", output: ""),
			TextReplacementRule(input: "YN", output: "Alex")
		])
		let text = "Hello, YN!"
		let matches = TextReplacementRuleEngine.findMatches(applying: table, to: text)

		#expect(matches.count == 1)
		#expect(matches[0].replacementText == "Alex")
	}

	// MARK: misc

	@Test func emptyTextProducesNoMatches() {
		let table = TextReplacementRuleTable.defaultTypoTable
		#expect(TextReplacementRuleEngine.findMatches(applying: table, to: "").isEmpty)
	}

	@Test func ruleWithBlankInputProducesNoMatches() {
		let table = TextReplacementRuleTable(rules: [
			TextReplacementRule(input: "  , ,  ", output: "the")
		])
		let text = "This text has nothing special in it."
		#expect(TextReplacementRuleEngine.findMatches(applying: table, to: text).isEmpty)
	}
}
