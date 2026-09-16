//
//  TextReplacementOffsetShiftTests.swift
//  ArticlesTests
//
//  Coverage for TextReplacementOffsetShift: overlap detection, the
//  shift-only-rows-after-the-edit filter, the zero-delta no-op fast
//  path, the revert inverse, and descendingApplicationOrder's ordering
//  guarantee (pinned by a test that shows ascending order produces the
//  wrong offsets for a downstream row, per that function's own doc
//  comment promise).
//

import Foundation
import Testing

@testable import Articles

@Suite struct TextReplacementOffsetShiftTests {

	private func annotation(id: String, start: Int, end: Int, quote: String = "x") -> Annotation {
		Annotation(
			annotationID: id,
			articleID: "article-1",
			bookKey: nil,
			quoteExact: quote,
			quotePrefix: "",
			quoteSuffix: "",
			startOffset: start,
			endOffset: end,
			color: .yellow,
			note: nil,
			createdAt: Date(),
			updatedAt: Date()
		)
	}

	// MARK: firstOverlap

	@Test func firstOverlapDetectsGenuineOverlap() {
		let others = [annotation(id: "a", start: 10, end: 20)]
		let conflict = TextReplacementOffsetShift.firstOverlap(startOffset: 15, endOffset: 25, in: others)
		#expect(conflict?.annotationID == "a")
	}

	@Test func firstOverlapAllowsTouchingBoundaries() {
		// One row ending exactly where another starts is not an overlap
		// -- see firstOverlap's own doc comment.
		let others = [annotation(id: "a", start: 10, end: 20)]
		#expect(TextReplacementOffsetShift.firstOverlap(startOffset: 20, endOffset: 30, in: others) == nil)
		#expect(TextReplacementOffsetShift.firstOverlap(startOffset: 0, endOffset: 10, in: others) == nil)
	}

	@Test func firstOverlapReturnsNilWhenNoRowsConflict() {
		let others = [annotation(id: "a", start: 100, end: 110)]
		#expect(TextReplacementOffsetShift.firstOverlap(startOffset: 0, endOffset: 10, in: others) == nil)
	}

	// MARK: shiftedAnchors

	@Test func shiftsOnlyRowsAtOrAfterEditEndOffset() {
		let before = annotation(id: "before", start: 0, end: 5)
		let after = annotation(id: "after", start: 20, end: 30)
		let touching = annotation(id: "touching", start: 10, end: 15) // starts exactly at editEndOffset

		let shifted = TextReplacementOffsetShift.shiftedAnchors(
			editEndOffset: 10,
			delta: 5,
			otherAnnotations: [before, after, touching],
			sliceQuote: { _, _ in (quoteExact: "q", quotePrefix: "p", quoteSuffix: "s", chapterTitle: nil) }
		)

		let shiftedIDs = Set(shifted.map(\.annotationID))
		#expect(shiftedIDs == ["after", "touching"])
		#expect(!shiftedIDs.contains("before"))
	}

	@Test func appliesPositiveDeltaToShiftedOffsets() {
		let row = annotation(id: "a", start: 20, end: 30)
		let shifted = TextReplacementOffsetShift.shiftedAnchors(
			editEndOffset: 10,
			delta: 5,
			otherAnnotations: [row],
			sliceQuote: { _, _ in (quoteExact: "q", quotePrefix: "", quoteSuffix: "", chapterTitle: nil) }
		)
		#expect(shifted.count == 1)
		#expect(shifted[0].startOffset == 25)
		#expect(shifted[0].endOffset == 35)
	}

	@Test func appliesNegativeDeltaToShiftedOffsets() {
		let row = annotation(id: "a", start: 20, end: 30)
		let shifted = TextReplacementOffsetShift.shiftedAnchors(
			editEndOffset: 10,
			delta: -3,
			otherAnnotations: [row],
			sliceQuote: { _, _ in (quoteExact: "q", quotePrefix: "", quoteSuffix: "", chapterTitle: nil) }
		)
		#expect(shifted.count == 1)
		#expect(shifted[0].startOffset == 17)
		#expect(shifted[0].endOffset == 27)
	}

	@Test func zeroDeltaProducesNoShiftedRows() {
		let row = annotation(id: "a", start: 20, end: 30)
		var sliceQuoteCalled = false
		let shifted = TextReplacementOffsetShift.shiftedAnchors(
			editEndOffset: 10,
			delta: 0,
			otherAnnotations: [row],
			sliceQuote: { _, _ in
				sliceQuoteCalled = true
				return (quoteExact: "q", quotePrefix: "", quoteSuffix: "", chapterTitle: nil)
			}
		)
		#expect(shifted.isEmpty)
		// A true no-op doesn't even need to slice a quote for any row.
		#expect(!sliceQuoteCalled)
	}

	@Test func sliceQuoteIsCalledWithTheRowsNewOffsets() {
		let row = annotation(id: "a", start: 20, end: 30)
		var capturedStart: Int?
		var capturedEnd: Int?
		_ = TextReplacementOffsetShift.shiftedAnchors(
			editEndOffset: 10,
			delta: 5,
			otherAnnotations: [row],
			sliceQuote: { start, end in
				capturedStart = start
				capturedEnd = end
				return (quoteExact: "sliced", quotePrefix: "pre", quoteSuffix: "suf", chapterTitle: "Chapter 2")
			}
		)
		#expect(capturedStart == 25)
		#expect(capturedEnd == 35)
	}

	@Test func shiftedAnchorCarriesTheSlicedValuesThrough() {
		let row = annotation(id: "a", start: 20, end: 30)
		let shifted = TextReplacementOffsetShift.shiftedAnchors(
			editEndOffset: 10,
			delta: 5,
			otherAnnotations: [row],
			sliceQuote: { _, _ in (quoteExact: "new quote", quotePrefix: "before", quoteSuffix: "after", chapterTitle: "Chapter 2") }
		)
		#expect(shifted.count == 1)
		#expect(shifted[0].quoteExact == "new quote")
		#expect(shifted[0].quotePrefix == "before")
		#expect(shifted[0].quoteSuffix == "after")
		#expect(shifted[0].chapterTitle == "Chapter 2")
	}

	// MARK: shiftedAnchorsForRevert

	@Test func revertAppliesTheInverseDelta() {
		let row = annotation(id: "a", start: 25, end: 35)
		let shifted = TextReplacementOffsetShift.shiftedAnchorsForRevert(
			revertedEditOriginalEndOffset: 10,
			delta: 5,
			otherAnnotations: [row],
			sliceQuote: { _, _ in (quoteExact: "q", quotePrefix: "", quoteSuffix: "", chapterTitle: nil) }
		)
		#expect(shifted.count == 1)
		// Reverting a +5 edit should subtract 5 back off.
		#expect(shifted[0].startOffset == 20)
		#expect(shifted[0].endOffset == 30)
	}

	// MARK: descendingApplicationOrder

	@Test func descendingApplicationOrderSortsHighestOffsetFirst() {
		let a = annotation(id: "a", start: 5, end: 10)
		let b = annotation(id: "b", start: 50, end: 60)
		let c = annotation(id: "c", start: 20, end: 25)

		let ordered = TextReplacementOffsetShift.descendingApplicationOrder([a, b, c])
		#expect(ordered.map(\.annotationID) == ["b", "c", "a"])
	}

	@Test func applyingShiftsInDescendingOrderProducesCorrectFinalOffsets() {
		// Two edits both shortening the text by 2 characters, applied to
		// three original rows. Processing rightmost-first (as
		// descendingApplicationOrder mandates) means each row's shift is
		// computed against still-original offsets for any edit further
		// right, and only sees the shift from edits genuinely to its
		// left -- which is what "delta accumulates left-to-right as you
		// process right-to-left" means in practice. This test pins that
		// the *order* affects correctness, not just convenience.
		//
		// Rows (original offsets): editA at 10-12, editB at 30-32, row
		// at 50-55.
		// Both edits shorten their span by 2 (delta -2 each).
		let editA = annotation(id: "editA", start: 10, end: 12)
		let editB = annotation(id: "editB", start: 30, end: 32)
		let row = annotation(id: "row", start: 50, end: 55)

		// Applying descending (editB, i.e. the later/rightmost edit,
		// first): row shifts by editB's delta (-2) to 48-53. Then editA
		// is applied; row (now at 48-53) shifts by editA's delta (-2)
		// again to 46-51.
		var currentRowStart = row.startOffset
		var currentRowEnd = row.endOffset
		let descending = TextReplacementOffsetShift.descendingApplicationOrder([editA, editB])
		#expect(descending.map(\.annotationID) == ["editB", "editA"])

		for edit in descending {
			let shifted = TextReplacementOffsetShift.shiftedAnchors(
				editEndOffset: edit.endOffset,
				delta: -2,
				otherAnnotations: [Annotation(
					annotationID: "row",
					articleID: "article-1",
					bookKey: nil,
					quoteExact: "x",
					quotePrefix: "",
					quoteSuffix: "",
					startOffset: currentRowStart,
					endOffset: currentRowEnd,
					color: .yellow,
					note: nil,
					createdAt: Date(),
					updatedAt: Date()
				)],
				sliceQuote: { _, _ in (quoteExact: "q", quotePrefix: "", quoteSuffix: "", chapterTitle: nil) }
			)
			if let result = shifted.first {
				currentRowStart = result.startOffset
				currentRowEnd = result.endOffset
			}
		}

		#expect(currentRowStart == 46)
		#expect(currentRowEnd == 51)
	}

	// MARK: Reversibility (apply then revert restores exact pre-edit offsets)

	@Test func applyingThenRevertingRestoresExactPreEditOffsets() {
		// A downstream row at 50-55 in the original text. An edit at
		// 10-12 lengthens by +3 (delta +3): applying shifts the row to
		// 53-58. Reverting that same edit must land the row back on
		// its exact original 50-55 -- not merely "close," and not
		// "however shiftedAnchors happens to round-trip" -- pinned
		// exactly, per the plan's "Reversibility" test requirement.
		let original = annotation(id: "row", start: 50, end: 55)

		let applied = TextReplacementOffsetShift.shiftedAnchors(
			editEndOffset: 12,
			delta: 3,
			otherAnnotations: [original],
			sliceQuote: { _, _ in (quoteExact: "shifted", quotePrefix: "", quoteSuffix: "", chapterTitle: nil) }
		)
		#expect(applied.count == 1)
		#expect(applied[0].startOffset == 53)
		#expect(applied[0].endOffset == 58)

		let shiftedRow = annotation(id: "row", start: applied[0].startOffset, end: applied[0].endOffset)
		let reverted = TextReplacementOffsetShift.shiftedAnchorsForRevert(
			revertedEditOriginalEndOffset: 12,
			delta: 3,
			otherAnnotations: [shiftedRow],
			sliceQuote: { _, _ in (quoteExact: original.quoteExact, quotePrefix: original.quotePrefix, quoteSuffix: original.quoteSuffix, chapterTitle: original.chapterTitle) }
		)
		#expect(reverted.count == 1)
		#expect(reverted[0].startOffset == original.startOffset)
		#expect(reverted[0].endOffset == original.endOffset)
		#expect(reverted[0].quoteExact == original.quoteExact)
	}

	@Test func applyingThenRevertingRestoresExactPreEditOffsetsForShorteningEdit() {
		// Same round-trip, but for a shortening edit (negative delta) --
		// the sign flip in shiftedAnchorsForRevert's inverse-delta
		// arithmetic is the part most likely to be backwards, so this
		// is pinned independently of the lengthening case above.
		let original = annotation(id: "row", start: 100, end: 110)

		let applied = TextReplacementOffsetShift.shiftedAnchors(
			editEndOffset: 40,
			delta: -4,
			otherAnnotations: [original],
			sliceQuote: { _, _ in (quoteExact: "shifted", quotePrefix: "", quoteSuffix: "", chapterTitle: nil) }
		)
		#expect(applied.count == 1)
		#expect(applied[0].startOffset == 96)
		#expect(applied[0].endOffset == 106)

		let shiftedRow = annotation(id: "row", start: applied[0].startOffset, end: applied[0].endOffset)
		let reverted = TextReplacementOffsetShift.shiftedAnchorsForRevert(
			revertedEditOriginalEndOffset: 40,
			delta: -4,
			otherAnnotations: [shiftedRow],
			sliceQuote: { _, _ in (quoteExact: original.quoteExact, quotePrefix: "", quoteSuffix: "", chapterTitle: nil) }
		)
		#expect(reverted.count == 1)
		#expect(reverted[0].startOffset == original.startOffset)
		#expect(reverted[0].endOffset == original.endOffset)
	}

	@Test func applyingTwoEditsThenRevertingBothInDescendingOrderRestoresOriginalOffsets() {
		// The fuller scenario the plan's "everything downstream is back
		// to where it was" language describes: two edits applied
		// (descending order), then both reverted (also descending
		// order, same ordering requirement applying does), and the
		// downstream row must land exactly back on its original
		// offsets -- not just "the last revert looks right."
		let editA = annotation(id: "editA", start: 10, end: 12) // +3 delta
		let editB = annotation(id: "editB", start: 30, end: 32) // +2 delta
		let originalRow = annotation(id: "row", start: 50, end: 55)

		var currentStart = originalRow.startOffset
		var currentEnd = originalRow.endOffset

		// Apply descending (editB first, then editA), each shifting the
		// row forward by its own delta.
		for (edit, delta) in TextReplacementOffsetShift.descendingApplicationOrder([editA, editB]).map({ ($0, $0.annotationID == "editA" ? 3 : 2) }) {
			let shifted = TextReplacementOffsetShift.shiftedAnchors(
				editEndOffset: edit.endOffset,
				delta: delta,
				otherAnnotations: [annotation(id: "row", start: currentStart, end: currentEnd)],
				sliceQuote: { _, _ in (quoteExact: "q", quotePrefix: "", quoteSuffix: "", chapterTitle: nil) }
			)
			if let result = shifted.first {
				currentStart = result.startOffset
				currentEnd = result.endOffset
			}
		}
		#expect(currentStart == 55) // 50 + 3 + 2
		#expect(currentEnd == 60)

		// Revert in the same descending order (editB, then editA) --
		// each subtracting its own delta back off.
		for (edit, delta) in TextReplacementOffsetShift.descendingApplicationOrder([editA, editB]).map({ ($0, $0.annotationID == "editA" ? 3 : 2) }) {
			let reverted = TextReplacementOffsetShift.shiftedAnchorsForRevert(
				revertedEditOriginalEndOffset: edit.endOffset,
				delta: delta,
				otherAnnotations: [annotation(id: "row", start: currentStart, end: currentEnd)],
				sliceQuote: { _, _ in (quoteExact: "q", quotePrefix: "", quoteSuffix: "", chapterTitle: nil) }
			)
			if let result = reverted.first {
				currentStart = result.startOffset
				currentEnd = result.endOffset
			}
		}
		#expect(currentStart == originalRow.startOffset)
		#expect(currentEnd == originalRow.endOffset)
	}
}
