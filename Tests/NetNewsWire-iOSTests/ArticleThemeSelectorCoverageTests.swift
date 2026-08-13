//
//  ArticleThemeSelectorCoverageTests.swift
//  NetNewsWire-iOSTests
//
//  theme-settings-implementation-plan.md §7.1: catches the class of bug
//  this codebase has hit repeatedly -- CSS written against a selector that
//  sounds plausible (.headerBar, .articleContent, #nnwFooter) but doesn't
//  exist in the real default template.html, so the rule silently no-ops.
//  Confirmed by reading Shared/Article Rendering/template.html directly
//  which classes are real; this test fails the build if that ever
//  regresses, and separately guards ArticleThemeOverrides.cssOverrideBlock
//  against reintroducing the specific invented selectors an earlier,
//  unverified plan proposed (.articleContent, .barContent, #nnwFooter,
//  .headerBar, .datelineBar -- real only in some hand-written themes'
//  own bundles, never in the default template).
//

import Testing
import Foundation
@testable import Nectar

@Suite struct ArticleThemeSelectorCoverageTests {

	/// Every class/id ArticleThemeOverrides.cssOverrideBlock or core.css's
	/// theme-facing rules reference must exist in the default template.html, or the
	/// override silently no-ops against the shipped default theme. This doesn't catch
	/// custom themes with nonstandard markup (docs/nnwtheme-format.md's "Custom
	/// template.html" section covers that constraint separately, at the
	/// .articleBody-must-survive level) -- it catches an override written against a
	/// selector nobody checked against real markup.
	@Test func coreOverrideSelectorsExistInDefaultTemplate() throws {
		let template = try Self.readRepoFile("Shared/Article Rendering/template.html")

		let requiredSelectors = [
			"articleBody", "headerContainer", "headerTable", "header",
			"feedlink", "articleTitle", "articleDateline", "articleDatelineTitle",
			"externalLink", "bodyContainer"
		]
		for selector in requiredSelectors {
			#expect(template.contains(selector), "'\(selector)' is expected in the default template.html but was not found")
		}
	}

	/// Fully-populated overrides shouldn't reference selectors that don't exist in the
	/// default template -- guards against reintroducing the invented selectors an
	/// earlier, unverified draft of this feature proposed.
	@Test func cssOverrideBlockDoesNotReferenceInventedSelectors() {
		var overrides = ArticleThemeOverrides()
		overrides.serifFontFamilyName = "Georgia"
		overrides.sansFontFamilyName = "Helvetica"
		overrides.fontSize = 18
		overrides.lineHeight = 1.5
		overrides.paragraphSpacing = 1.2
		overrides.paragraphIndent = 1.0
		overrides.marginHorizontal = 20
		overrides.marginTop = 10
		overrides.justifyText = true
		overrides.hyphenate = true
		overrides.textColorHex = "#111111"
		overrides.backgroundColorHex = "#eeeeee"
		overrides.linkColorHex = "#0000ff"
		let css = overrides.cssOverrideBlock

		let inventedSelectors = [".articleContent", ".barContent", "#nnwFooter", ".headerBar", ".datelineBar"]
		for invented in inventedSelectors {
			#expect(!css.contains(invented), "cssOverrideBlock emitted invented selector \(invented)")
		}
	}

	/// Walks up from this test file's own path to find the repo root, then reads the
	/// given repo-relative file. Bundle.main inside a test target is the test
	/// runner's bundle, not the app's, so it can't be used to locate source-tree
	/// files like template.html that aren't copied into any test bundle.
	private static func readRepoFile(_ relativePath: String) throws -> String {
		var url = URL(fileURLWithPath: #filePath)
		while url.pathComponents.count > 1 {
			url.deleteLastPathComponent()
			let candidate = url.appendingPathComponent(relativePath)
			if FileManager.default.fileExists(atPath: candidate.path) {
				return try String(contentsOf: candidate, encoding: .utf8)
			}
		}
		fatalError("Could not locate \(relativePath) by walking up from \(#filePath)")
	}
}
