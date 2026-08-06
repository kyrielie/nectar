//
//  ArticleThemePreviewSampleTests.swift
//  NetNewsWire-iOSTests
//
//  theme-settings-implementation-plan.md §7.2: the preview's sample body
//  must itself satisfy the same structural contract real articles do
//  (Technotes/Themes.md: #bodyContainer carries the articleBody class),
//  or the preview stops being representative again the next time someone
//  edits it. sampleBodyForTesting is `internal` (not `private`) purely so
//  this test can see it -- see CodingGuidelines on not weakening access
//  control for reasons beyond test visibility.
//

import Testing
import Foundation
@testable import Nectar

@Suite struct ArticleThemePreviewSampleTests {

	@Test func sampleBodyHasArticleBodyWrapper() {
		let sample = ArticleThemePreviewWebView.sampleBodyForTesting
		#expect(sample.contains("id=\"bodyContainer\""))
		#expect(sample.contains("class=\"articleBody\""))
		#expect(sample.contains("ao3SyntheticPreface"))
	}

	/// Every selector ArticleThemeSelectorCoverageTests requires to exist in the real
	/// default template.html should also appear somewhere in the preview sample --
	/// otherwise an override that's correctly wired against real markup could still
	/// show "no visible change" in Settings' live preview, the exact symptom that
	/// motivated fixing sampleBody in the first place.
	@Test func sampleBodyCoversCoreOverrideSelectors() {
		let sample = ArticleThemePreviewWebView.sampleBodyForTesting
		let expectedSelectors = [
			"articleBody", "headerContainer", "headerTable", "header",
			"feedlink", "articleTitle", "articleDatelineTitle", "bodyContainer"
		]
		for selector in expectedSelectors {
			#expect(sample.contains(selector), "Preview sampleBody is missing '\(selector)', present in the real default template.html")
		}
	}
}
