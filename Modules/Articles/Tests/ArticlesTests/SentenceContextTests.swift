//
//  SentenceContextTests.swift
//  ArticlesTests
//
//  Coverage for SentenceContext.sentence(quotePrefix:quoteExact:quoteSuffix:),
//  extracted out of AnnotationsListView.AnnotationRow's former
//  sentenceContext computed property (see that type's own header
//  comment). This is regression coverage for the extraction itself, not
//  new behavior: every case here is hand-traced against the exact
//  algorithm that used to live inline in AnnotationRow, confirming the
//  move to plain String/Range<String.Index> (dropping AttributedString/
//  color, which now live only in the iOS-target caller) didn't change
//  the underlying text/range math. Per the feature's own implementation
//  plan's "Tests" section: "correctly reconstructs the surrounding
//  sentence, matches AnnotationsListView's existing (pre-extraction)
//  behavior exactly for the highlight case," and "never called from the
//  offset-shift/delta-math or DOM-range-resolution code paths -- only
//  originalText/replacementText/quoteExact are" (true by construction:
//  this type has no dependency on TextReplacementOffsetShift/
//  TextReplacementRuleTable, and nothing in those types calls this one).
//

import Foundation
import Testing

@testable import Articles

@Suite struct SentenceContextTests {

	@Test("reconstructs the full sentence around the quote from prefix/exact/suffix")
	func reconstructsSurroundingSentence() {
		let result = SentenceContext.sentence(
			quotePrefix: "She turned toward the door, hoping ",
			quoteExact: "he'd still be",
			quoteSuffix: " there when she looked back."
		)
		#expect(result.text == "She turned toward the door, hoping he'd still be there when she looked back.")
	}

	@Test("quoteRange locates exactly the quoteExact substring within the reconstructed sentence")
	func quoteRangeLocatesTheQuote() throws {
		let result = SentenceContext.sentence(
			quotePrefix: "She turned toward the door, hoping ",
			quoteExact: "he'd still be",
			quoteSuffix: " there when she looked back."
		)
		let range = try #require(result.quoteRange)
		#expect(String(result.text[range]) == "he'd still be")
	}

	@Test("only the sentence containing the quote is returned, not the whole prefix/suffix span")
	func clipsToTheContainingSentenceOnly() throws {
		let result = SentenceContext.sentence(
			quotePrefix: "It was raining outside. She turned toward the door, hoping ",
			quoteExact: "he'd still be",
			quoteSuffix: " there. The kettle had gone cold an hour ago."
		)
		// NLTokenizer's sentence unit includes the trailing whitespace
		// after terminal punctuation as part of the preceding sentence's
		// token, rather than assigning it to the start of the next
		// sentence -- hence the trailing space here. Confirmed against
		// the actual xcodebuild test run, not assumed: an earlier version
		// of this test asserted no trailing space, based on a naive
		// period-split trace that doesn't reflect NLTokenizer's real
		// boundary placement.
		#expect(result.text == "She turned toward the door, hoping he'd still be there. ")
		let range = try #require(result.quoteRange)
		#expect(String(result.text[range]) == "he'd still be")
	}

	@Test("internal whitespace runs (including newlines) collapse to single spaces, matching the pre-extraction behavior")
	func normalizesInternalWhitespace() {
		let result = SentenceContext.sentence(
			quotePrefix: "Line one\nwith a  break, hoping ",
			quoteExact: "he'd\tstill be",
			quoteSuffix: " there  when she looked back."
		)
		#expect(!result.text.contains("\n"))
		#expect(!result.text.contains("\t"))
		#expect(!result.text.contains("  "))
	}

	@Test("empty quoteExact returns an empty result with no quoteRange")
	func emptyQuoteReturnsEmptyResult() {
		let result = SentenceContext.sentence(quotePrefix: "before ", quoteExact: "", quoteSuffix: " after")
		#expect(result.text.isEmpty)
		#expect(result.quoteRange == nil)
	}

	@Test("a quote that recurs earlier in the prefix still resolves to the real, later occurrence")
	func recurringQuoteResolvesToRealOccurrence() throws {
		// "the door" appears once as an unrelated earlier mention and once
		// as the actual highlighted phrase -- the search-hint-offset logic
		// (8 characters of slack past prefix.count) exists specifically so
		// the real occurrence wins over the earlier one.
		let result = SentenceContext.sentence(
			quotePrefix: "She remembered the door from before. Now she stood at ",
			quoteExact: "the door",
			quoteSuffix: " again, waiting."
		)
		let range = try #require(result.quoteRange)
		// The resolved range must fall within the second sentence, not the
		// first -- i.e. its lower bound comes after "before. ".
		let secondSentenceStart = result.text.range(of: "Now she stood at")?.lowerBound
		#expect(secondSentenceStart != nil)
		if let secondSentenceStart {
			#expect(range.lowerBound >= secondSentenceStart)
		}
	}

	@Test("no matching sentence boundary falls back to the full combined text with the quote still located")
	func fallsBackToCombinedTextWhenTokenizerFindsNoBoundary() throws {
		// A string with no terminal punctuation at all is still one
		// "sentence" as far as NLTokenizer is concerned; this just
		// confirms that case doesn't crash or drop the quote range.
		let result = SentenceContext.sentence(
			quotePrefix: "before ",
			quoteExact: "middle",
			quoteSuffix: " after"
		)
		#expect(result.text == "before middle after")
		let range = try #require(result.quoteRange)
		#expect(String(result.text[range]) == "middle")
	}

	@Test("normalizedForDisplay collapses whitespace without trimming the ends")
	func normalizedForDisplayDoesNotTrim() {
		let normalized = SentenceContext.normalizedForDisplay(" a   phrase\nwith  runs\tof whitespace ")
		#expect(normalized == " a phrase with runs of whitespace ")
	}
}
