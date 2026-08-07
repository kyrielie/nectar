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
//  It also carries a preface block (#ao3SyntheticPreface / dl.tags), but
//  pared down to just Warnings and Chapters -- enough to exercise the
//  preface's own dt/dd grid styling without turning the preview into a
//  full fandom-tag showcase.
//

import Testing
import Foundation
@testable import Nectar

@Suite struct ArticleThemePreviewSampleTests {

	@Test func sampleBodyHasPrefaceWithWarningsAndChaptersOnly() {
		let sample = ArticleThemePreviewWebView.sampleBodyForTesting
		#expect(sample.contains("ao3SyntheticPreface"))
		#expect(sample.contains("dl class=\"tags\""))
		#expect(sample.contains("Warnings:"))
		#expect(sample.contains("Chapters:"))
	}

	@Test func sampleBodyIsFreeOfFandomChrome() {
		let sample = ArticleThemePreviewWebView.sampleBodyForTesting
		#expect(!sample.contains("Fandom"))
		#expect(!sample.contains("Rating:"))
		#expect(!sample.contains("Category:"))
	}

	/// The preface block precedes Summary, which precedes Notes, which
	/// precedes the chapter heading -- matching AO3's own preface order (see
	/// sampleBodyForTesting's doc comment).
	@Test func prefacePrecedesSummaryPrecedesNotesPrecedesChapterHeading() {
		let sample = ArticleThemePreviewWebView.sampleBodyForTesting
		let prefaceRange = sample.range(of: "ao3SyntheticPreface")
		let summaryRange = sample.range(of: "summary module")
		let notesRange = sample.range(of: "notes module")
		let chapterRange = sample.range(of: "chapter preface group")
		#expect(prefaceRange != nil && summaryRange != nil && notesRange != nil && chapterRange != nil)
		if let prefaceRange, let summaryRange, let notesRange, let chapterRange {
			#expect(prefaceRange.lowerBound < summaryRange.lowerBound)
			#expect(summaryRange.lowerBound < notesRange.lowerBound)
			#expect(notesRange.lowerBound < chapterRange.lowerBound)
		}
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

	/// Two separate <p> body paragraphs (outside the summary/notes blockquotes) are
	/// required, not just non-empty text, so paragraph spacing/indent overrides have
	/// an actual second paragraph to show space above.
	@Test func sampleBodyHasTwoParagraphs() {
		let sample = ArticleThemePreviewWebView.sampleBodyForTesting
		#expect(sample.components(separatedBy: "<p>").count - 1 == 4)
	}
}
