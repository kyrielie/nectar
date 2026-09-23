import Articles
//
//  TextReplacementOffsetShift.swift
//  Articles
//
//  Pure offset-shift arithmetic for the local diff/override layer text
//  replacement is built on top of (see docs/annotations.md, "Applying
//  edits" and "Reverting an edit"). Deliberately has no ArticlesDatabase
//  dependency -- it operates purely on in-memory [Annotation] values, the
//  same reasoning Annotation itself lives in this module for (see that
//  type's own doc comment). The actual database writes this feeds
//  (reanchorAnnotation/setAnnotationEditFields) are orchestrated by
//  Account, which calls into this type to compute what those writes
//  should be.
//

import Foundation

public enum TextReplacementOffsetShift {

	/// A single row's recomputed anchor after an edit shifts the text
	/// underneath it. Mirrors reanchorAnnotation's parameter shape (plus
	/// annotationID to identify which row this is for).
	public struct ShiftedAnchor: Sendable, Equatable {
		public let annotationID: String
		public let startOffset: Int
		public let endOffset: Int
		public let quoteExact: String
		public let quotePrefix: String
		public let quoteSuffix: String
		public let chapterTitle: String?
	}

	/// Thrown when a proposed edit's span overlaps an existing annotation
	/// row's span -- blocked at edit-creation time rather than silently
	/// applied or silently orphaned, since the app itself is making this
	/// change and can prevent the conflict outright. See docs/annotations.md,
	/// "Applying edits": a manual edit's own span (the highlight it was
	/// created against) never conflicts with itself -- this is checked
	/// against *other* rows only, by the caller excluding the edited row's
	/// own annotationID from `otherAnnotations` before calling
	/// shiftedAnchors(for:in:).
	public struct OverlapError: Error, Sendable, Equatable {
		public let conflictingAnnotationID: String
	}

	/// Checks whether an edit spanning [startOffset, endOffset) in
	/// original-stored-text coordinates overlaps any row in
	/// `otherAnnotations` (which must already exclude the row being edited,
	/// if any). Two spans overlap when neither is entirely before or
	/// entirely after the other; touching at a single boundary point
	/// (one's endOffset equals the other's startOffset) is not an overlap.
	public static func firstOverlap(startOffset: Int, endOffset: Int, in otherAnnotations: [Annotation]) -> Annotation? {
		otherAnnotations.first { other in
			startOffset < other.endOffset && other.startOffset < endOffset
		}
	}

	/// Computes the new anchor for every row in `otherAnnotations` (which
	/// must already exclude the edited row itself) whose span lies at or
	/// after `editEndOffset` in the *original*, pre-edit coordinate space --
	/// see "Applying edits" in docs/annotations.md. Each shifted row's
	/// offsets move by `delta` (replacementText.count - originalText.count,
	/// positive for a lengthening edit, negative for a shortening one, zero
	/// for a same-length correction that still needs a chapterTitle
	/// recompute if it crosses a heading), and its quoteExact/quotePrefix/
	/// quoteSuffix/chapterTitle are re-sliced against `newText` -- the full
	/// document text *after* this edit has been applied -- at the row's new
	/// offsets, the same recomputation the JS re-anchor path performs on
	/// every render (buildHeadingIndex/nearestChapterTitle), reused here so
	/// there's exactly one implementation of "recompute a selector at a
	/// given offset," not two.
	///
	/// Rows entirely before `editEndOffset` (in the original coordinate
	/// space) are unaffected and are not included in the result -- nothing
	/// about their own stored offsets changed.
	///
	/// `sliceQuote` performs the actual quoteExact/quotePrefix/quoteSuffix/
	/// chapterTitle extraction against `newText` -- passed in as a closure
	/// (rather than this type reimplementing NLTokenizer/heading-index
	/// logic) since that extraction is naturally a JS-side (or, on the
	/// Swift side, an NSString-based) operation the caller already has
	/// direct access to via annotations.js's own buildHeadingIndex/
	/// nearestChapterTitle -- see Account's orchestration of this.
	public static func shiftedAnchors(
		editEndOffset: Int,
		delta: Int,
		otherAnnotations: [Annotation],
		sliceQuote: (_ startOffset: Int, _ endOffset: Int) -> (quoteExact: String, quotePrefix: String, quoteSuffix: String, chapterTitle: String?)
	) -> [ShiftedAnchor] {
		guard delta != 0 else {
			// A same-length edit never changes any other row's offsets --
			// nothing downstream needs to move, and nothing needs a
			// chapterTitle recompute purely from this shift (a same-length
			// edit doesn't change which side of a heading boundary any
			// other row falls on, since no text moved). Returning early
			// here keeps a zero-delta edit (as unusual as that is for a
			// person-facing correction) a true no-op for every other row,
			// matching "Applying edits"'s framing of delta as the sole
			// driver of downstream shifts.
			return []
		}

		return otherAnnotations
			.filter { $0.startOffset >= editEndOffset }
			.map { annotation in
				let newStart = annotation.startOffset + delta
				let newEnd = annotation.endOffset + delta
				let sliced = sliceQuote(newStart, newEnd)
				return ShiftedAnchor(
					annotationID: annotation.annotationID,
					startOffset: newStart,
					endOffset: newEnd,
					quoteExact: sliced.quoteExact,
					quotePrefix: sliced.quotePrefix,
					quoteSuffix: sliced.quoteSuffix,
					chapterTitle: sliced.chapterTitle
				)
			}
	}

	/// The inverse shift, for reverting an edit (docs/annotations.md,
	/// "Reverting an edit"): re-shifts every row whose offset was computed
	/// relative to the reverted edit's presence, scoped to rows whose
	/// offset is after the reverted edit's *original* position (before it
	/// was ever applied) -- adding back the length delta instead of
	/// subtracting it. `revertedEditOriginalEndOffset` is the edit's
	/// startOffset/endOffset as they were before the edit was first
	/// applied (i.e. the position in the fully-original, pre-edit text),
	/// not its current (possibly further-shifted-by-later-edits) stored
	/// position. `otherAnnotations` must exclude the row being reverted.
	public static func shiftedAnchorsForRevert(
		revertedEditOriginalEndOffset: Int,
		delta: Int,
		otherAnnotations: [Annotation],
		sliceQuote: (_ startOffset: Int, _ endOffset: Int) -> (quoteExact: String, quotePrefix: String, quoteSuffix: String, chapterTitle: String?)
	) -> [ShiftedAnchor] {
		shiftedAnchors(
			editEndOffset: revertedEditOriginalEndOffset,
			delta: -delta,
			otherAnnotations: otherAnnotations,
			sliceQuote: sliceQuote
		)
	}

	/// Sorts a set of edit rows into descending-offset application order
	/// (rightmost/latest edit first) -- see docs/annotations.md, "Applying
	/// edits": processing right-to-left means an earlier edit's stored
	/// offset is never invalidated by a later edit shifting the text
	/// underneath it. Exposed as a standalone, testable function so the
	/// ordering requirement itself is pinned by a test (ascending order
	/// asserted to produce wrong results), not just documented in prose --
	/// see TextReplacementOffsetShiftTests.
	public static func descendingApplicationOrder(_ edits: [Annotation]) -> [Annotation] {
		edits.sorted { $0.startOffset > $1.startOffset }
	}
}
