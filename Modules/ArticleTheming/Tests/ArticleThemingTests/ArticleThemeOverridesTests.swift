//
//  ArticleThemeOverridesTests.swift
//  ArticleThemingTests
//
//  Exercises ArticleThemeOverrides.cssOverrideBlock(themeCSS:) directly:
//  ArticleTheme needs Bundle.main resources and is not usable in this target
//  (see ArticleThemingSmokeTests), so the theme CSS is passed in as a string.
//

import Testing
import Foundation
@testable import ArticleTheming

struct ArticleThemeOverridesTests {

	private static let tokenizedThemeCSS = ":root { --gx: 20px; --nnw-bg: #fff; }"
	private static let legacyThemeCSS = "body { padding: 0 16px; }"

	/// Splits a CSS string into the selector lists that precede each `{`.
	private static func selectorLists(in css: String) -> [String] {
		css.components(separatedBy: "{").dropLast().map { chunk in
			let afterBrace = chunk.components(separatedBy: "}").last ?? chunk
			return afterBrace.trimmingCharacters(in: .whitespacesAndNewlines)
		}
	}

	@Test func emptyOverridesProduceEmptyString() {
		let overrides = ArticleThemeOverrides()
		#expect(overrides.isEmpty)
		#expect(overrides.cssOverrideBlock(themeCSS: Self.tokenizedThemeCSS).isEmpty)
		#expect(overrides.cssOverrideBlock(themeCSS: nil).isEmpty)
		#expect(overrides.cssOverrideBlock.isEmpty)
	}

	@Test func isEmptyIsFalseForAnySingleProperty() {
		#expect(!ArticleThemeOverrides(fontSize: 18).isEmpty)
		#expect(!ArticleThemeOverrides(marginHorizontal: 10).isEmpty)
		#expect(!ArticleThemeOverrides(linkColorDarkHex: "#abcdef").isEmpty)
	}

	@Test func propertyWithoutThemeCSSMatchesNilThemeCSS() {
		let overrides = ArticleThemeOverrides(fontSize: 18, textColorHex: "#111111")
		#expect(overrides.cssOverrideBlock == overrides.cssOverrideBlock(themeCSS: nil))
	}

	@Test func fontSizeEmitsProseSizeVariableWithoutImportant() {
		let css = ArticleThemeOverrides(fontSize: 18).cssOverrideBlock(themeCSS: nil)
		#expect(css.contains("--nnw-prose-size: 18.0px;"))
		#expect(!css.contains("--nnw-prose-size: 18.0px !important"))
		// Legacy rule stays for untokenized themes.
		#expect(css.contains("font-size: 18.0px !important;"))
	}

	@Test func colorOverridesEmitImportantTokens() {
		let overrides = ArticleThemeOverrides(textColorHex: "#111111", backgroundColorHex: "#eeeeee", linkColorHex: "#0000ff")
		let css = overrides.cssOverrideBlock(themeCSS: nil)
		#expect(css.contains("--nnw-bg: #eeeeee !important;"))
		#expect(css.contains("--nnw-ink: #111111 !important;"))
		#expect(css.contains("--nnw-link: #0000ff !important;"))
		#expect(css.hasPrefix(":root {"))
	}

	@Test func sansFontEmitsChromeVariableAndKeepsLegacyAllowlist() {
		let css = ArticleThemeOverrides(sansFontFamilyName: "Helvetica").cssOverrideBlock(themeCSS: nil)
		#expect(css.contains("--nnw-font-chrome: \"Helvetica\" !important;"))
		#expect(css.contains(".letter-header"))
		#expect(css.contains(".feedlink"))
	}

	@Test func themeWithoutInsetVariableGetsBodyPadding() {
		let overrides = ArticleThemeOverrides(marginHorizontal: 24)
		for themeCSS in [Self.legacyThemeCSS, nil] {
			let css = overrides.cssOverrideBlock(themeCSS: themeCSS)
			#expect(!css.contains("--gx"))
			#expect(css.contains("body {\n\tpadding-left: 24.0px !important; padding-right: 24.0px !important;\n}"))
		}
	}

	@Test func themeWithInsetVariableGetsGxAndNoBodyPadding() {
		let css = ArticleThemeOverrides(marginHorizontal: 24).cssOverrideBlock(themeCSS: Self.tokenizedThemeCSS)
		#expect(css.contains("--gx: 24.0px !important;"))
		#expect(!css.contains("padding-left"))
		#expect(!css.contains("body {"))
	}

	@Test func insetDetectionIgnoresGxUsedOnlyAsAValue() {
		let css = ArticleThemeOverrides(marginHorizontal: 24).cssOverrideBlock(themeCSS: ".t { padding: 0 var(--gx); }")
		#expect(!css.contains("--gx: 24.0px"))
		#expect(css.contains("padding-left"))
	}

	@Test func topMarginIsUnchangedAndIndependentOfInsetVariable() {
		let overrides = ArticleThemeOverrides(marginTop: 12)
		for themeCSS in [Self.legacyThemeCSS, Self.tokenizedThemeCSS] {
			#expect(overrides.cssOverrideBlock(themeCSS: themeCSS).contains("#bodyContainer {\n\tpadding-top: 12.0px !important;\n}"))
		}
	}

	@Test func linkRulesHaveExclusionsAndStrippingDeclarations() {
		let css = ArticleThemeOverrides(linkColorHex: "#0000ff").cssOverrideBlock(themeCSS: nil)
		// The exclusions are chained onto each anchor selector, in this order.
		let exclusions = [":not(#ao3Preface a)", ":not(#ao3SyntheticPreface a)", ":not(#ao3SeriesFooter a)"].joined()
		#expect(css.contains(".articleBody a\(exclusions)"))
		#expect(css.contains(".articleBody a:link\(exclusions)"))
		#expect(css.contains(".articleBody a:visited\(exclusions)"))
		for declaration in ["color: #0000ff !important;", "background: none !important;", "border: 0 !important;",
							"box-shadow: none !important;", "text-shadow: none !important;", "text-decoration: underline !important;"] {
			#expect(css.contains(declaration), "missing \(declaration)")
		}
	}

	@Test func noSelectorIsABareAnchor() {
		var overrides = ArticleThemeOverrides(linkColorHex: "#0000ff", linkColorDarkHex: "#8888ff")
		overrides.textColorHex = "#111111"
		let css = overrides.cssOverrideBlock(themeCSS: Self.tokenizedThemeCSS)
		for list in Self.selectorLists(in: css) {
			for selector in list.components(separatedBy: ",") {
				let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
				#expect(trimmed != "a" && trimmed != "a:link" && trimmed != "a:visited", "bare anchor selector: \(trimmed)")
			}
		}
	}

	@Test func darkLinkRuleOnlySetsColor() throws {
		let css = ArticleThemeOverrides(linkColorHex: "#0000ff", linkColorDarkHex: "#8888ff").cssOverrideBlock(themeCSS: nil)
		let darkStart = try #require(css.range(of: "@media (prefers-color-scheme: dark)"))
		let dark = String(css[darkStart.lowerBound...])
		#expect(dark.contains("color: #8888ff !important;"))
		#expect(!dark.contains("background: none"))
		#expect(!dark.contains("text-decoration"))
		#expect(dark.contains("--nnw-link: #8888ff !important;"))
	}

	@Test func darkBlockEmitsRootBeforeBodyRule() throws {
		let overrides = ArticleThemeOverrides(textColorHex: "#111111", textColorDarkHex: "#eeeeee", backgroundColorHex: "#ffffff")
		let css = overrides.cssOverrideBlock(themeCSS: nil)
		let mediaStart = try #require(css.range(of: "@media (prefers-color-scheme: dark) {"))
		let dark = String(css[mediaStart.upperBound...])
		let rootIndex = try #require(dark.range(of: ":root {"))
		let bodyIndex = try #require(dark.range(of: "body, .articleBody {"))
		#expect(rootIndex.lowerBound < bodyIndex.lowerBound)
		#expect(dark.contains("--nnw-ink: #eeeeee !important;"))
		// Background has no dark variant, so the light value is used.
		#expect(dark.contains("--nnw-bg: #ffffff !important;"))
	}

	@Test func variableBlockPrecedesEveryOtherRule() throws {
		let css = ArticleThemeOverrides(fontSize: 20, lineHeight: 1.5, textColorHex: "#111111").cssOverrideBlock(themeCSS: nil)
		let rootIndex = try #require(css.range(of: ":root {"))
		let bodyIndex = try #require(css.range(of: "body, .articleBody {"))
		#expect(rootIndex.lowerBound < bodyIndex.lowerBound)
	}
}
