//
//  SentenceContext.swift
//  Articles
//
//  Extracted out of AnnotationsListView.AnnotationRow.sentenceContext as
//  part of the text-replacement feature's step 3/step 8 (see the
//  feature's own implementation plan and docs/annotations.md, "Annotations
//  list") -- needed by both the existing highlight row style and the
//  consolidated viewer's row rendering, so it can no longer live as one
//  view's private computed property.
//
//  Deliberately returns plain String + Range<String.Index>, not
//  AttributedString -- this module has no SwiftUI/UIKit dependency (see
//  Package.swift), the same reasoning TextReplacementOffsetShift/
//  TextReplacementRuleTable live here for. The caller (AnnotationRow)
//  wraps the result in AttributedString and applies its own
//  palette/color-scheme-aware backgroundColor; this type only does the
//  pure text reconstruction and quote-location math.
//
//  Never called from the offset-shift/delta-math or DOM-range-resolution
//  code paths -- those operate on originalText/replacementText/quoteExact
//  directly, at different (canonicalized whole-document) offsets than
//  this type's output, which is display-only reconstruction from the
//  already-captured quotePrefix/quoteExact/quoteSuffix selector.
//

import Foundation
import NaturalLanguage

public enum SentenceContext {

	/// The result of reconstructing the sentence surrounding a highlight:
	/// the sentence text itself, and the range of `quoteExact` within it
	/// (nil if the quote couldn't be located, or trivially the whole
	/// string when reconstruction returned only the raw quote as a
	/// fallback).
	public struct Result: Sendable, Equatable {
		public let text: String
		public let quoteRange: Range<String.Index>?

		public init(text: String, quoteRange: Range<String.Index>?) {
			self.text = text
			self.quoteRange = quoteRange
		}
	}

	/// The full sentence surrounding a highlight, built from the stored
	/// quotePrefix/quoteExact/quoteSuffix selector (see docs/annotations.md)
	/// rather than just the raw quote -- gives real reading context
	/// instead of a mid-sentence fragment. Each of the three pieces is
	/// whitespace-normalized independently before concatenation, then the
	/// quote's location within the concatenation is found by direct
	/// search rather than by offsetting quotePrefix's length in:
	/// quotePrefix/quoteExact/quoteSuffix are three independently-sliced
	/// UTF-16 substrings on the JS side, and if a slice boundary lands
	/// mid-grapheme-cluster, decoding and re-concatenating them in Swift
	/// can merge or split a Character differently than the JS side
	/// counted it -- so a Character count carried over from one string
	/// doesn't reliably locate a position in the concatenation of a
	/// different pair of strings. Searching for the literal quote text
	/// sidesteps that: the concatenation is built to contain the quote by
	/// construction, so the search always succeeds absent a coincidental
	/// earlier recurrence of the same text inside the prefix.
	public static func sentence(quotePrefix: String, quoteExact: String, quoteSuffix: String) -> Result {
		let prefix = normalizedForDisplay(quotePrefix)
		let quote = normalizedForDisplay(quoteExact)
		let suffix = normalizedForDisplay(quoteSuffix)
		let combined = prefix + quote + suffix

		guard !combined.isEmpty, !quote.isEmpty else {
			return Result(text: quote, quoteRange: nil)
		}

		// A grapheme-boundary mismatch (see doc comment above) can only be
		// off by a character or two, never by prefix's whole length -- 8
		// characters of slack is generous cover for that while still
		// skipping past an earlier, unrelated recurrence of `quote` inside
		// a long quotePrefix.
		let searchHintOffset = max(0, prefix.count - 8)
		let searchStart = combined.index(combined.startIndex, offsetBy: searchHintOffset, limitedBy: combined.endIndex) ?? combined.startIndex
		let quoteRange = combined.range(of: quote, range: searchStart..<combined.endIndex) ?? combined.range(of: quote)
		guard let quoteRange else {
			return Result(text: combined, quoteRange: nil)
		}
		let quoteStart = quoteRange.lowerBound
		let quoteEnd = quoteRange.upperBound

		let tokenizer = NLTokenizer(unit: .sentence)
		tokenizer.string = combined
		var sentenceRange = combined.startIndex..<combined.endIndex
		tokenizer.enumerateTokens(in: combined.startIndex..<combined.endIndex) { range, _ in
			if range.contains(quoteStart) || range.lowerBound == quoteStart {
				sentenceRange = range
				return false
			}
			return true
		}

		let sentenceString = String(combined[sentenceRange])

		let clippedStart = max(quoteStart, sentenceRange.lowerBound)
		let clippedEnd = min(quoteEnd, sentenceRange.upperBound)
		guard clippedStart < clippedEnd else {
			return Result(text: sentenceString, quoteRange: nil)
		}

		// Re-base clippedStart/clippedEnd from `combined`-relative indices
		// onto `sentenceString`-relative indices.
		let startDistance = combined.distance(from: sentenceRange.lowerBound, to: clippedStart)
		let endDistance = combined.distance(from: sentenceRange.lowerBound, to: clippedEnd)
		guard
			let localStart = sentenceString.index(sentenceString.startIndex, offsetBy: startDistance, limitedBy: sentenceString.endIndex),
			let localEnd = sentenceString.index(sentenceString.startIndex, offsetBy: endDistance, limitedBy: sentenceString.endIndex)
		else {
			return Result(text: sentenceString, quoteRange: nil)
		}

		return Result(text: sentenceString, quoteRange: localStart..<localEnd)
	}

	/// Collapses runs of whitespace (including the newlines/indentation
	/// annotations.js's buildTextIndex deliberately leaves untouched,
	/// since its offsets have to stay byte-exact against the source HTML
	/// for anchor resolution -- see docs/annotations.md's "Anchor
	/// resolution") down to a single space, for display only. Doesn't
	/// trim the ends, so quotePrefix/quoteExact/quoteSuffix still
	/// concatenate cleanly. Public (not private) so copyText's own
	/// normalization in the iOS target can share exactly this rule
	/// rather than a hand-maintained duplicate.
	public static func normalizedForDisplay(_ string: String) -> String {
		string.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
	}
}
