//
//  CopyHighlightTextTests.swift
//  NetNewsWire-iOSTests
//
//  Direct coverage of copyText(annotation:articleAuthors:link:)
//  (AnnotationsListView.swift), the "Copy Highlight" context menu
//  action's format builder. Covers the resolved open questions from the
//  original scoping: author falls back to "Unknown" rather than a blank
//  field, chapter/link are each dropped from the attribution line (not
//  printed empty) when absent, and the note block only appears when the
//  annotation actually has one. Also covers quote whitespace
//  normalization, since the copied quote is expected to match what the
//  row itself displays (AnnotationRow.sentenceContext), not the raw,
//  possibly newline-containing quoteExact.
//

import Testing
import Foundation
@testable import Nectar
import Articles

@Suite("copyText(annotation:articleAuthors:link:)")
struct CopyHighlightTextTests {

	private func makeAnnotation(
		quoteExact: String = "a highlighted phrase",
		note: String? = nil,
		chapterTitle: String? = nil
	) -> Annotation {
		let now = Date(timeIntervalSince1970: 1_700_000_000)
		return Annotation(
			annotationID: "annotation-1",
			articleID: "article-1",
			bookKey: "ao3-work:12345",
			quoteExact: quoteExact,
			quotePrefix: "before the ",
			quoteSuffix: " after it",
			startOffset: 10,
			endOffset: 31,
			color: .yellow,
			note: note,
			chapterTitle: chapterTitle,
			createdAt: now,
			updatedAt: now
		)
	}

	@Test("full attribution: author, chapter, and link all present")
	func fullAttribution() {
		let annotation = makeAnnotation(chapterTitle: "Chapter 3: The Long Tide")
		let text = copyText(annotation: annotation, articleAuthors: "J. Smith", link: "https://example.com/work/12345")

		#expect(text == """
		"a highlighted phrase"
		-J. Smith, Chapter 3: The Long Tide, https://example.com/work/12345
		""")
	}

	@Test("no note: no trailing block, not an empty one")
	func noNoteOmitsBlock() {
		let annotation = makeAnnotation(note: nil)
		let text = copyText(annotation: annotation, articleAuthors: "J. Smith", link: nil)

		#expect(!text.contains("\n\n\"\""))
		#expect(text == """
		"a highlighted phrase"
		-J. Smith
		""")
	}

	@Test("with a note: quote line, attribution line, blank line, quoted note")
	func withNoteAppendsBlock() {
		let annotation = makeAnnotation(note: "Come back to this for the essay.")
		let text = copyText(annotation: annotation, articleAuthors: "J. Smith", link: nil)

		#expect(text == """
		"a highlighted phrase"
		-J. Smith

		"Come back to this for the essay."
		""")
	}

	@Test("nil author falls back to Unknown, not a blank field or leading comma")
	func nilAuthorFallsBackToUnknown() {
		let annotation = makeAnnotation()
		let text = copyText(annotation: annotation, articleAuthors: nil, link: nil)

		#expect(text.hasPrefix("\"a highlighted phrase\"\n-Unknown"))
		#expect(!text.contains("-,"))
	}

	@Test("nil chapter is dropped from the attribution line, not printed empty")
	func nilChapterOmitted() {
		let annotation = makeAnnotation(chapterTitle: nil)
		let text = copyText(annotation: annotation, articleAuthors: "J. Smith", link: "https://example.com")

		#expect(text.contains("-J. Smith, https://example.com"))
		#expect(!text.contains(", , "))
	}

	@Test("empty-string chapter title is treated the same as nil")
	func emptyChapterOmitted() {
		let annotation = makeAnnotation(chapterTitle: "")
		let text = copyText(annotation: annotation, articleAuthors: "J. Smith", link: nil)

		#expect(text.contains("-J. Smith"))
		#expect(!text.contains(", ,"))
	}

	@Test("nil link is dropped from the attribution line, not printed empty")
	func nilLinkOmitted() {
		let annotation = makeAnnotation(chapterTitle: "Chapter 3: The Long Tide")
		let text = copyText(annotation: annotation, articleAuthors: "J. Smith", link: nil)

		#expect(text.contains("-J. Smith, Chapter 3: The Long Tide"))
		#expect(!text.hasSuffix(","))
	}

	@Test("author, chapter, and link all nil: attribution line is just -Unknown")
	func everythingNilFallsBackToUnknownOnly() {
		let annotation = makeAnnotation(chapterTitle: nil)
		let text = copyText(annotation: annotation, articleAuthors: nil, link: nil)

		#expect(text == """
		"a highlighted phrase"
		-Unknown
		""")
	}

	@Test("empty-string note is treated as no note, same as Annotation.note's nullable-means-no-note contract")
	func emptyStringNoteOmitsBlock() {
		let annotation = makeAnnotation(note: "")
		let text = copyText(annotation: annotation, articleAuthors: "J. Smith", link: nil)

		#expect(text == """
		"a highlighted phrase"
		-J. Smith
		""")
	}

	@Test("quote whitespace is normalized the same way the row displays it")
	func quoteWhitespaceNormalized() {
		// Mirrors AnnotationRow's normalizedForDisplay: internal
		// whitespace/newlines (preserved verbatim in quoteExact for
		// anchor-resolution reasons -- see docs/annotations.md) collapse
		// to single spaces for display/copy, without trimming the ends.
		let annotation = makeAnnotation(quoteExact: "a   phrase\nwith  runs\tof whitespace")
		let text = copyText(annotation: annotation, articleAuthors: "J. Smith", link: nil)

		#expect(text.hasPrefix("\"a phrase with runs of whitespace\""))
	}
}
