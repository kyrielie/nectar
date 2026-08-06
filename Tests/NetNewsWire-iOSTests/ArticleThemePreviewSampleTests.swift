//
//  ArticleThemePreviewSampleTests.swift
//  NetNewsWire-iOSTests
//
//  theme-settings-implementation-plan.md §7.2: the preview's sample body
//  must itself satisfy the same structural contract real articles do
//  (Technotes/Themes.md: #bodyContainer carries the articleBody class),
//  or the preview stops being representative again the next time someone
//  edits it.
//
//  The preview no longer hand-authors header markup at all -- it runs each
//  theme's own template.html through MacroProcessor (see
//  ArticleThemePreviewWebView), so per-theme header selectors like
//  headerContainer/feedlink don't belong in this test anymore: they're only
//  ever correct for the default theme, and were exactly why Promenade/
//  Rosarivo previously rendered with an unstyled header. What's still this
//  test's job is the sample *body* content that gets substituted into
//  whichever template is active.
//
//  The sample also carries a chapter heading and a notes block (AO3's own
//  h3.title / notes-module markup) so a theme's heading and blockquote/notes
//  styling show up in the preview too, not just body-paragraph styling --
//  see sampleBodyForTesting's own doc comment for why this still isn't
//  fandom chrome.
//

import Testing
import Foundation
@testable import Nectar

@Suite struct ArticleThemePreviewSampleTests {

	@Test func sampleBodyIsFreeOfFandomChrome() {
		let sample = ArticleThemePreviewWebView.sampleBodyForTesting
		#expect(!sample.contains("ao3SyntheticPreface"))
		#expect(!sample.contains("Fandom"))
	}

	@Test func sampleBodyHasChapterHeading() {
		let sample = ArticleThemePreviewWebView.sampleBodyForTesting
		#expect(sample.contains("chapter preface group"))
		#expect(sample.contains("h3 class=\"title\""))
	}

	@Test func sampleBodyHasNotes() {
		let sample = ArticleThemePreviewWebView.sampleBodyForTesting
		#expect(sample.contains("notes module"))
	}

	@Test func sampleBodyHasSummary() {
		let sample = ArticleThemePreviewWebView.sampleBodyForTesting
		#expect(sample.contains("summary module"))
	}

	/// Summary comes before Notes, which comes before the chapter heading --
	/// matching AO3's own preface order (see sampleBodyForTesting's doc comment).
	@Test func summaryPrecedesNotesPrecedesChapterHeading() {
		let sample = ArticleThemePreviewWebView.sampleBodyForTesting
		let summaryRange = sample.range(of: "summary module")
		let notesRange = sample.range(of: "notes module")
		let chapterRange = sample.range(of: "chapter preface group")
		#expect(summaryRange != nil && notesRange != nil && chapterRange != nil)
		if let summaryRange, let notesRange, let chapterRange {
			#expect(summaryRange.lowerBound < notesRange.lowerBound)
			#expect(notesRange.lowerBound < chapterRange.lowerBound)
		}
	}

	/// Two separate <p> body paragraphs (outside the summary/notes blockquotes) are
	/// required, not just non-empty text, so paragraph spacing/indent overrides have
	/// an actual second paragraph to show space above.
	@Test func sampleBodyHasTwoParagraphs() {
		let sample = ArticleThemePreviewWebView.sampleBodyForTesting
		#expect(sample.components(separatedBy: "<p>").count - 1 == 4)
	}
}
