//
//  AnnotationRowStyleTests.swift
//  ArticlesTests
//
//  Coverage for Annotation.rowStyle: the field-driven row-style
//  derivation behind the consolidated viewer's AnnotationRow (see
//  docs/annotations.md's "Consolidated viewer" and the text-replacement
//  feature's own implementation plan, same section). Pinning this
//  mapping here, independent of the SwiftUI view that consumes it, is
//  what actually lets the plan's "every row kind... appears in both tab
//  scopes, since all six are just different combinations of three
//  independent fields" claim be verified mechanically rather than only
//  by inspection.
//

import Foundation
import Testing

@testable import Articles

@Suite struct AnnotationRowStyleTests {

	private func annotation(
		hasHighlight: Bool,
		originalText: String?,
		replacementText: String?
	) -> Annotation {
		let now = Date(timeIntervalSince1970: 1_700_000_000)
		return Annotation(
			annotationID: "annotation-1",
			articleID: "article-1",
			bookKey: nil,
			quoteExact: "quote",
			quotePrefix: "",
			quoteSuffix: "",
			startOffset: 0,
			endOffset: 5,
			color: .yellow,
			note: nil,
			hasHighlight: hasHighlight,
			originalText: originalText,
			replacementText: replacementText,
			createdAt: now,
			updatedAt: now
		)
	}

	@Test("a pure highlight (no edit fields) resolves to .highlight")
	func pureHighlightResolvesToHighlightStyle() {
		let row = annotation(hasHighlight: true, originalText: nil, replacementText: nil)
		#expect(row.rowStyle == .highlight)
	}

	@Test("an edit-only row (hasHighlight false) resolves to .edit with its text")
	func editOnlyRowResolvesToEditStyle() {
		let row = annotation(hasHighlight: false, originalText: "teh", replacementText: "the")
		#expect(row.rowStyle == .edit(originalText: "teh", replacementText: "the"))
	}

	@Test("a highlight+edit row (both hasHighlight and edit fields set) still resolves to .edit -- the color dot is handled independently by hasHighlight, not by rowStyle")
	func highlightPlusEditRowResolvesToEditStyle() {
		let row = annotation(hasHighlight: true, originalText: "stil", replacementText: "still")
		#expect(row.rowStyle == .edit(originalText: "stil", replacementText: "still"))
		// rowStyle alone doesn't tell you whether the color dot shows --
		// that's a separate, independent check the view makes directly
		// against hasHighlight (see AnnotationRow.body).
		#expect(row.hasHighlight == true)
	}

	@Test("originalText set without replacementText (should not occur per the Validity rule, but must not crash) falls back to .highlight")
	func onlyOriginalTextSetFallsBackToHighlightStyle() {
		let row = annotation(hasHighlight: true, originalText: "teh", replacementText: nil)
		#expect(row.rowStyle == .highlight)
	}

	@Test("replacementText set without originalText (should not occur per the Validity rule, but must not crash) falls back to .highlight")
	func onlyReplacementTextSetFallsBackToHighlightStyle() {
		let row = annotation(hasHighlight: true, originalText: nil, replacementText: "the")
		#expect(row.rowStyle == .highlight)
	}
}
