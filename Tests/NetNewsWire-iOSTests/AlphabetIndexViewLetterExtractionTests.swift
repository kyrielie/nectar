//
//  AlphabetIndexViewLetterExtractionTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for Part 12's index-letter extraction
//  (AlphabetIndexView.indexLetters(sections:sortOrder:)), the pure
//  function backing the Contacts-style A-Z index strip on
//  AnnotationsListView's list. Constructs AnnotationsListView.BookSection
//  values directly with an empty chapterGroups -- indexLetters never
//  reads chapterGroups (it works only from title/authors), so an empty
//  array is a legitimate stand-in and avoids needing AnnotationGroup's
//  own (private) initializer here.
//

import Testing
import Foundation
@testable import Nectar

@Suite struct AlphabetIndexViewLetterExtractionTests {

	private func section(id: String, title: String, authors: String? = nil) -> AnnotationsListView.BookSection {
		AnnotationsListView.BookSection(bookOrArticleID: id, title: title, authors: authors, chapterGroups: [])
	}

	@Test("title sort: first letter of each section's title, uppercased")
	func titleSortUppercasesFirstLetter() {
		let sections = [
			section(id: "1", title: "apple book"),
			section(id: "2", title: "Banana Book")
		]
		let letters = AlphabetIndexView.indexLetters(sections: sections, sortOrder: .title)
		#expect(letters.map(\.character) == ["A", "B"])
	}

	@Test("title sort: a title starting with a digit falls into the # bucket")
	func digitLeadingTitleFallsIntoHashBucket() {
		let sections = [section(id: "1", title: "1632")]
		let letters = AlphabetIndexView.indexLetters(sections: sections, sortOrder: .title)
		#expect(letters.map(\.character) == ["#"])
	}

	@Test("title sort: a title starting with punctuation falls into the # bucket")
	func punctuationLeadingTitleFallsIntoHashBucket() {
		let sections = [section(id: "1", title: "\"Quoted Title\"")]
		let letters = AlphabetIndexView.indexLetters(sections: sections, sortOrder: .title)
		#expect(letters.map(\.character) == ["#"])
	}

	@Test("duplicate first letters collapse to one entry")
	func duplicateFirstLettersCollapse() {
		let sections = [
			section(id: "1", title: "Alpha"),
			section(id: "2", title: "Apex"),
			section(id: "3", title: "Ant-Man")
		]
		let letters = AlphabetIndexView.indexLetters(sections: sections, sortOrder: .title)
		#expect(letters.map(\.character) == ["A"])
	}

	@Test("# sorts first, ahead of every letter")
	func hashBucketSortsFirst() {
		let sections = [
			section(id: "1", title: "Zebra"),
			section(id: "2", title: "1984"),
			section(id: "3", title: "Alpha")
		]
		let letters = AlphabetIndexView.indexLetters(sections: sections, sortOrder: .title)
		#expect(letters.map(\.character) == ["#", "A", "Z"])
	}

	@Test("author sort: keys off authors, not title")
	func authorSortUsesAuthorsField() {
		let sections = [
			section(id: "1", title: "Zebra Book", authors: "Alice Author"),
			section(id: "2", title: "Apple Book", authors: "Zara Zephyr")
		]
		let letters = AlphabetIndexView.indexLetters(sections: sections, sortOrder: .author)
		#expect(letters.map(\.character) == ["A", "Z"])
	}

	@Test("author sort: a section with no resolvable author contributes no letter")
	func authorSortSkipsSectionsWithNoAuthor() {
		let sections = [
			section(id: "1", title: "Some Book", authors: nil),
			section(id: "2", title: "Another Book", authors: "Bob Writer")
		]
		let letters = AlphabetIndexView.indexLetters(sections: sections, sortOrder: .author)
		#expect(letters.map(\.character) == ["B"])
	}

	@Test("empty sections list produces no letters")
	func emptySectionsProducesNoLetters() {
		#expect(AlphabetIndexView.indexLetters(sections: [], sortOrder: .title).isEmpty)
	}

	@Test("each letter's sectionID points at the first matching section in list order")
	func letterSectionIDPointsAtFirstMatch() {
		let sections = [
			section(id: "first-alpha", title: "Alpha One"),
			section(id: "second-alpha", title: "Alpha Two")
		]
		let letters = AlphabetIndexView.indexLetters(sections: sections, sortOrder: .title)
		#expect(letters.first?.sectionID == "first-alpha")
	}
}
