//
//  TextReplacementQuoteConversionTests.swift
//  ArticlesTests
//
//  Category 2's own dedicated test corpus, per the plan's "Docs and
//  tests" list: "balanced-pair detection correctly converts genuine
//  dialogue spans and correctly leaves contractions/possessives
//  untouched -- needs its own dedicated test corpus of tricky cases
//  (nested quotes, a contraction immediately adjacent to a real quote
//  boundary, an unpaired `'` with no matching close)."
//

import Foundation
import Testing

@testable import Articles

@Suite struct TextReplacementQuoteConversionTests {

	@Test func convertsSimpleDialogueSpan() {
		let text = "She said 'hello there' and smiled."
		let matches = TextReplacementQuoteConversion.findMatches(in: text)

		#expect(matches.count == 1)
		#expect(matches[0].originalText == "'hello there'")
		#expect(matches[0].replacementText == "\"hello there\"")
	}

	@Test func leavesLoneContractionUntouched() {
		let text = "I don't think that's going to work."
		let matches = TextReplacementQuoteConversion.findMatches(in: text)

		#expect(matches.isEmpty)
	}

	@Test func leavesLonePossessiveUntouched() {
		let text = "Sarah's coat was on the chair."
		let matches = TextReplacementQuoteConversion.findMatches(in: text)

		#expect(matches.isEmpty)
	}

	/// The plan's own named tricky case: a contraction sitting inside a
	/// real dialogue span, immediately adjacent to the span's own
	/// closing boundary reasoning shouldn't misfire on. The contraction
	/// apostrophe is followed by a letter (not whitespace/punctuation),
	/// so it's never treated as a closing-candidate; only the genuine
	/// trailing `'` after "happy" is.
	@Test func convertsDialogueContainingAnInternalContraction() {
		let text = "'She's happy' said Tom."
		let matches = TextReplacementQuoteConversion.findMatches(in: text)

		#expect(matches.count == 1)
		#expect(matches[0].originalText == "'She's happy'")
		#expect(matches[0].replacementText == "\"She's happy\"")
	}

	/// A contraction immediately adjacent to a real quote boundary --
	/// the closing quote of one span sits right next to an unrelated
	/// contraction in the surrounding prose, and the two must not be
	/// confused for each other.
	@Test func leavesAdjacentContractionAloneNextToARealClosingQuote() {
		let text = "'Go home,' she said, 'it's late.'"
		let matches = TextReplacementQuoteConversion.findMatches(in: text)

		#expect(matches.count == 2)
		#expect(matches[0].originalText == "'Go home,'")
		#expect(matches[1].originalText == "'it's late.'")
		#expect(matches[1].replacementText == "\"it's late.\"")
	}

	@Test func leavesUnpairedOpeningQuoteUntouched() {
		let text = "She started, 'but never finished the thought."
		let matches = TextReplacementQuoteConversion.findMatches(in: text)

		#expect(matches.isEmpty)
	}

	/// Nested quotes: a quote-within-a-quote, conventionally rendered
	/// with double marks inside a single-quote dialogue span in British
	/// typesetting. Only the outer `'...'` pair is a candidate; the
	/// literal `"..."` content inside it is left untouched as content,
	/// never treated as a boundary.
	@Test func convertsOuterSpanOfANestedQuoteLeavingInnerDoubleQuotesIntact() {
		let text = "'She said \"hello\" to me' Tom recalled."
		let matches = TextReplacementQuoteConversion.findMatches(in: text)

		#expect(matches.count == 1)
		#expect(matches[0].originalText == "'She said \"hello\" to me'")
		#expect(matches[0].replacementText == "\"She said \"hello\" to me\"")
	}

	@Test func rejectsSingleWordSpanWithNoWhitespaceAsImplausibleDialogue() {
		let text = "The word 'yes' was all he said."
		let matches = TextReplacementQuoteConversion.findMatches(in: text)

		#expect(matches.isEmpty)
	}

	@Test func handlesMultipleDialogueSpansInOneParagraph() {
		let text = "'Come here,' she said. 'I need to tell you something.'"
		let matches = TextReplacementQuoteConversion.findMatches(in: text)

		#expect(matches.count == 2)
		#expect(matches[0].originalText == "'Come here,'")
		#expect(matches[1].originalText == "'I need to tell you something.'")
	}

	@Test func returnsNoMatchesForEmptyText() {
		#expect(TextReplacementQuoteConversion.findMatches(in: "").isEmpty)
	}

	@Test func returnsNoMatchesForTextWithNoApostrophes() {
		let text = "Plain prose with no quotes at all."
		#expect(TextReplacementQuoteConversion.findMatches(in: text).isEmpty)
	}

	@Test func dialogueOpeningAtStartOfTextIsRecognized() {
		let text = "'Wait for me,' he called out."
		let matches = TextReplacementQuoteConversion.findMatches(in: text)

		#expect(matches.count == 1)
		#expect(matches[0].startOffset == 0)
	}

	// MARK: - Leading elisions (Part 6)

	@Test func leavesLeadingElisionCauseUntouched() {
		let text = "I stayed 'cause I said so."
		#expect(TextReplacementQuoteConversion.findMatches(in: text).isEmpty)
	}

	@Test func leavesLeadingElisionTilUntouched() {
		let text = "Wait 'til tomorrow."
		#expect(TextReplacementQuoteConversion.findMatches(in: text).isEmpty)
	}

	@Test func leavesLeadingElisionEmUntouched() {
		let text = "Bring 'em on."
		#expect(TextReplacementQuoteConversion.findMatches(in: text).isEmpty)
	}

	@Test func leavesLeadingElisionTwasUntouched() {
		let text = "'Twas the night before Christmas."
		#expect(TextReplacementQuoteConversion.findMatches(in: text).isEmpty)
	}

	@Test func leavesLeadingElisionTisUntouched() {
		let text = "'Tis a shame, truly."
		#expect(TextReplacementQuoteConversion.findMatches(in: text).isEmpty)
	}

	@Test func leavesLeadingElisionNUntouched() {
		let text = "Fish 'n' chips for dinner."
		#expect(TextReplacementQuoteConversion.findMatches(in: text).isEmpty)
	}

	@Test func leavesLeadingElisionRoundUntouched() {
		let text = "They gathered 'round midnight."
		#expect(TextReplacementQuoteConversion.findMatches(in: text).isEmpty)
	}

	@Test func leavesLeadingElisionBoutUntouched() {
		let text = "Talk to me 'bout time."
		#expect(TextReplacementQuoteConversion.findMatches(in: text).isEmpty)
	}

	@Test func leavesLeadingElisionFraidUntouched() {
		let text = "I'm 'fraid not."
		#expect(TextReplacementQuoteConversion.findMatches(in: text).isEmpty)
	}

	@Test func leavesLeadingElisionCourseUntouched() {
		let text = "Of 'course, she agreed."
		#expect(TextReplacementQuoteConversion.findMatches(in: text).isEmpty)
	}

	@Test func leavesLeadingElisionKayUntouched() {
		let text = "'Kay then, let's go."
		#expect(TextReplacementQuoteConversion.findMatches(in: text).isEmpty)
	}

	@Test func leavesDecadeElisionUntouched() {
		let text = "It happened back in the '80s."
		#expect(TextReplacementQuoteConversion.findMatches(in: text).isEmpty)
	}

	/// The elision check must not swallow genuine dialogue whose opening
	/// word happens to share no overlap with the exception list -- a
	/// sanity check that the new check is scoped to the fixed word list,
	/// not accidentally broadened to reject dialogue generally.
	@Test func stillConvertsGenuineDialogueAfterElisionCheckIsAdded() {
		let text = "She said 'hello there' and smiled."
		let matches = TextReplacementQuoteConversion.findMatches(in: text)

		#expect(matches.count == 1)
		#expect(matches[0].originalText == "'hello there'")
		#expect(matches[0].replacementText == "\"hello there\"")
	}
}
