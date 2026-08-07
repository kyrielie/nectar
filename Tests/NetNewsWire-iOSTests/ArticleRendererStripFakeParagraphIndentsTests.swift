//
//  ArticleRendererStripFakeParagraphIndentsTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for ArticleRenderer.stripFakeParagraphIndents
//  (nectar-theme-pipeline-fixes-plan.md item #7): confirms leading
//  &nbsp;-sequence and literal-space fake indents are removed from the start
//  of paragraph content, that a `<p>` tag's own attributes survive, and that
//  the rest of the paragraph's text and unrelated whitespace are untouched.
//

import Testing
@testable import Nectar

@Suite struct ArticleRendererStripFakeParagraphIndentsTests {

	@Test func stripsLeadingNbspSequence() {
		let html = "<p>&nbsp;&nbsp;&nbsp;&nbsp;She said hello.</p>"
		let result = ArticleRenderer.stripFakeParagraphIndents(html)
		#expect(result == "<p>She said hello.</p>")
	}

	@Test func stripsLeadingLiteralSpaces() {
		let html = "<p>    Four literal spaces at the start.</p>"
		let result = ArticleRenderer.stripFakeParagraphIndents(html)
		#expect(result == "<p>Four literal spaces at the start.</p>")
	}

	@Test func preservesTagAttributes() {
		let html = "<p class=\"foo\" id=\"bar\">&nbsp;&nbsp;Indented with attributes present.</p>"
		let result = ArticleRenderer.stripFakeParagraphIndents(html)
		#expect(result == "<p class=\"foo\" id=\"bar\">Indented with attributes present.</p>")
	}

	@Test func noOpWhenNoLeadingWhitespace() {
		let html = "<p class='ao3ChapterFetchNotice'>Full text unavailable: some reason.</p>"
		let result = ArticleRenderer.stripFakeParagraphIndents(html)
		#expect(result == html)
	}

	@Test func onlyStripsImmediatelyAfterOpeningTag() {
		// Whitespace elsewhere in the document -- between block elements, not
		// right after a <p> opener -- must survive untouched.
		let html = "<div>&nbsp;&nbsp;</div><p>Real text.</p>"
		let result = ArticleRenderer.stripFakeParagraphIndents(html)
		#expect(result == html)
	}

	@Test func stripsMultipleParagraphsIndependently() {
		let html = "<p>&nbsp;&nbsp;First.</p><p>    Second.</p><p>Third, no fake indent.</p>"
		let result = ArticleRenderer.stripFakeParagraphIndents(html)
		#expect(result == "<p>First.</p><p>Second.</p><p>Third, no fake indent.</p>")
	}

	@Test func numericAndHexEntitiesAlsoStripped() {
		let html = "<p>&#160;&#xA0;Mixed numeric-entity indent.</p>"
		let result = ArticleRenderer.stripFakeParagraphIndents(html)
		#expect(result == "<p>Mixed numeric-entity indent.</p>")
	}
}
