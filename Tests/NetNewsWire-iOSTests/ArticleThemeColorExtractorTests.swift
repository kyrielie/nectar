//
//  ArticleThemeColorExtractorTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for the @supports/@supports-not brace-block stripping in
//  ArticleThemeColorExtractor.stripBraceBlocks (see docs/article-color-pipeline.md):
//  confirms the widened regex strips both the `@supports (...)` and
//  `@supports not (...)` forms, and documents the known single-paren-depth limit
//  on compound conditions rather than silently regressing on it.
//

import Testing
import Foundation
@testable import Nectar
@testable import HexColor
@testable import ArticleTheming

@Suite struct ArticleThemeColorExtractorTests {

	/// Coverage for the "background-inversion on cold launch" bug (see
	/// docs/article-color-pipeline.md): themes with no `body`/`.articleBody`
	/// `color`/`background-color` of their own fall back to genuinely opposite
	/// colors between light and dark (`.black`-on-`.white` vs `.white`-on-`.black`),
	/// which is what makes a wrong `isDark` read at cold-launch-restore time
	/// visibly wrong instead of a no-op. Themes that declare an explicit,
	/// appearance-invariant background/color (no dark media block) don't have
	/// this exposure -- both branches resolve to the same value -- so they're
	/// not useful as a repro target for this bug even though they also don't
	/// declare per-appearance colors.
	@Suite struct BackgroundInversionExposure {

		@Test func broadsheetHasGenuinelyOppositeLightAndDarkFallbackColors() throws {
			let css = try Self.readThemeStylesheet("Broadsheet")
			let colors = ArticleThemeColorExtractor.colors(css: css)

			// Neither body nor .articleBody declares color/background-color anywhere
			// in Broadsheet's stylesheet.css, light or dark scan -- so both channels
			// fall all the way through to the generic black-on-white / white-on-black
			// fallback, and light/dark genuinely disagree.
			#expect(colors.backgroundColor == .white)
			#expect(colors.textColor == .black)
			#expect(colors.backgroundColorDark == .black)
			#expect(colors.textColorDark == .white)
		}

		@Test func blackAndWhiteResolvesIdenticallyRegardlessOfIsDark() throws {
			// Black & White's stylesheet.css leads with an `@import` line (a Google
			// Fonts request). ArticleTheme.init() always runs CSSImportExtractor
			// first and only ever hands ArticleThemeColorExtractor the remaining
			// CSS (see ComposedThemeDarkBlockCollision above) -- reading the raw
			// file here instead would leave the import glued onto `body`'s
			// selector text (`@import url(...); body`), which never matches `body`
			// and silently falls through to the light/dark fallback this test is
			// specifically checking doesn't diverge.
			let rawCSS = try Self.readThemeStylesheet("Black & White")
			let css = CSSImportExtractor.extract(from: rawCSS).remainingCSS
			let colors = ArticleThemeColorExtractor.colors(css: css)

			// Black & White declares an explicit body background-color/color, but no
			// @media (prefers-color-scheme: dark) block at all -- so per
			// colors(css:)'s "darkFound ?? lightFound ?? generic fallback" precedence,
			// the dark channel reuses the light value verbatim. A wrong isDark read
			// at cold-launch-restore time can't produce a visible mismatch here: both
			// branches compute the same color.
			#expect(colors.backgroundColor == colors.backgroundColorDark)
			#expect(colors.textColor == colors.textColorDark)
			#expect(colors.backgroundColor == UIColor(cssHex: "#FFFFFF"))
			#expect(colors.textColor == UIColor(cssHex: "#000000"))
		}

		private static func readThemeStylesheet(_ themeName: String) throws -> String {
			let stylesheetURL = try ArticleThemeColorExtractorTests.locateThemeBundle(themeName)
				.appendingPathComponent("stylesheet.css")
			return try String(contentsOf: stylesheetURL, encoding: .utf8)
		}
	}

	/// Coverage for the "notch cover stays the dark color in light mode" bug (see
	/// docs/article-color-pipeline.md): `ArticleTheme.css` is always `core.css +
	/// "\n" + <theme's own stylesheet.css>` (see `ArticleTheme.init()`), and
	/// `core.css` carries its own `@media (prefers-color-scheme: dark) { ... }`
	/// block (the `mark.nnw-highlight` dark rules) ahead of any theme's own dark
	/// block in that concatenation. `colors(for:)`'s single-theme-stylesheet
	/// tests above never reproduce this, because they read `stylesheet.css`
	/// directly off disk rather than composing it with core.css the way
	/// production actually does -- these tests build the real composed string
	/// instead, so a regression back to "only the first dark block is found"
	/// fails here even though it passes every test above.
	@Suite struct ComposedThemeDarkBlockCollision {

		@Test func duskbloomLightAndDarkBackgroundsDisagree() throws {
			let css = try Self.composedCSS(themeName: "Duskbloom")
			let colors = ArticleThemeColorExtractor.colors(css: css)

			// Duskbloom (Themes/Duskbloom.nnwtheme/stylesheet.css): light mode is
			// Moonlit Wisteria (#F5EDE8 background), dark mode is Charcoal Rose
			// (#1D1D1D background), declared via a :root custom-property
			// redefinition inside the theme's own dark media block -- exactly the
			// shape that collides with core.css's own dark block if only the
			// first dark block in the composed string is found.
			#expect(colors.backgroundColor == UIColor(cssHex: "#F5EDE8"))
			#expect(colors.backgroundColorDark == UIColor(cssHex: "#1D1D1D"))
			#expect(colors.backgroundColor != colors.backgroundColorDark)
		}

		/// core.css's `mark.nnw-highlight` dark rules must still work correctly
		/// on their own -- this fix must not, e.g., accidentally start ignoring
		/// core.css's dark block instead of merging it with the theme's.
		@Test func composedCSSStillContainsCoreCSSDarkHighlightRule() throws {
			let css = try Self.composedCSS(themeName: "Duskbloom")
			#expect(css.contains("--nnw-highlight-yellow-dark"))
		}

		private static func composedCSS(themeName: String) throws -> String {
			let coreCSS = try String(contentsOf: ArticleThemeColorExtractorTests.repoCoreCSSFile(), encoding: .utf8)
			let stylesheetURL = try ArticleThemeColorExtractorTests.locateThemeBundle(themeName)
				.appendingPathComponent("stylesheet.css")
			let stylesheetCSS = try String(contentsOf: stylesheetURL, encoding: .utf8)
			// Mirrors ArticleTheme.init(url:isAppTheme:): core.css + "\n" + the
			// theme's own stylesheet (no @import lines in Duskbloom's, so skipping
			// CSSImportExtractor here doesn't change what's under test).
			return coreCSS + "\n" + stylesheetCSS
		}
	}

	@Test func stripsPlainSupportsBlock() {
		let css = """
		body { background-color: blue; }
		@supports (-webkit-touch-callout: none) {
			body { background-color: red; }
		}
		"""
		let stripped = ArticleThemeColorExtractor.stripBraceBlocks(css)
		#expect(stripped.contains("background-color: blue;"))
		#expect(!stripped.contains("background-color: red;"))
	}

	@Test func stripsSupportsNotBlock() {
		let css = """
		body { background-color: blue; }
		@supports not (-webkit-touch-callout: none) {
			body { background-color: red; }
		}
		"""
		let stripped = ArticleThemeColorExtractor.stripBraceBlocks(css)
		#expect(stripped.contains("background-color: blue;"))
		#expect(!stripped.contains("background-color: red;"))
	}

	@Test func stripsBothFormsTogether() {
		let css = """
		body { background-color: blue; }
		@supports (-webkit-touch-callout: none) {
			body { background-color: green; }
		}
		@supports not (-webkit-touch-callout: none) {
			body { background-color: red; }
		}
		"""
		let stripped = ArticleThemeColorExtractor.stripBraceBlocks(css)
		#expect(stripped.contains("background-color: blue;"))
		#expect(!stripped.contains("background-color: green;"))
		#expect(!stripped.contains("background-color: red;"))
	}

	@Test func doesNotMatchSupportsNotWithoutSpace() {
		let css = "@supportsnot(color: red) { body { color: red; } }"
		let stripped = ArticleThemeColorExtractor.stripBraceBlocks(css)
		#expect(stripped == css)
	}

	/// Documents a known limit, not a target for this fix: `[^)]*` only matches a
	/// single paren-depth, so a compound `and`/`or` condition whose second clause
	/// re-opens a paren (`(not (color: green))`) never finds a closing `)` that
	/// completes the opener pattern's `\([^)]*\)` before hitting the first `)`
	/// inside the nested clause -- the whole opener regex fails to match, so
	/// nothing is stripped at all here, not a partial strip. This behavior
	/// predates this fix (the old `@supports\s*\(...` pattern had the same
	/// single-depth limit) and stays this way as a documented, not silently
	/// regressed, limitation.
	@Test func compoundConditionIsNotStripped() {
		let css = "@supports (color: red) and (not (color: green)) { body { color: red; } }"
		let stripped = ArticleThemeColorExtractor.stripBraceBlocks(css)
		#expect(stripped == css)
	}

	/// Same walk-up-to-repo-root pattern as ArticleThemePlistFamilyTests/
	/// ArticleThemeOverflowSafetyTests -- Bundle.main inside a test target is the
	/// test runner's bundle, not the app's, and doesn't have either directory
	/// copied in. Returns whichever of Themes/ (app-embedded) and
	/// gallery-themes/ (gallery-only) actually exist at the repo root.
	fileprivate static func repoThemeDirectories() -> [URL] {
		var url = URL(fileURLWithPath: #filePath)
		while url.pathComponents.count > 1 {
			url.deleteLastPathComponent()
			let themes = url.appendingPathComponent("Themes")
			if FileManager.default.fileExists(atPath: themes.path) {
				let galleryThemes = url.appendingPathComponent("gallery-themes")
				return [themes, galleryThemes].filter { FileManager.default.fileExists(atPath: $0.path) }
			}
		}
		fatalError("Could not locate repo Themes/ directory by walking up from \(#filePath)")
	}

	/// Finds `<themeName>.nnwtheme`, checking Themes/ first, then gallery-themes/
	/// -- a theme's current folder is which directory ships it (e.g. Broadsheet
	/// moved to gallery-themes/), not whether the bundle exists at all.
	fileprivate static func locateThemeBundle(_ themeName: String) throws -> URL {
		for directory in repoThemeDirectories() {
			let candidate = directory.appendingPathComponent("\(themeName).nnwtheme")
			if FileManager.default.fileExists(atPath: candidate.path) {
				return candidate
			}
		}
		throw CocoaError(.fileNoSuchFile)
	}

	/// Same walk-up-to-repo-root approach as `repoThemeDirectories()`, for
	/// `core.css` -- needed by `ComposedThemeDarkBlockCollision` to build CSS the
	/// same way `ArticleTheme.init()` actually does (core.css prepended), not
	/// just a theme's own stylesheet.css in isolation.
	fileprivate static func repoCoreCSSFile() -> URL {
		var url = URL(fileURLWithPath: #filePath)
		while url.pathComponents.count > 1 {
			url.deleteLastPathComponent()
			let candidate = url.appendingPathComponent("Shared").appendingPathComponent("Article Rendering").appendingPathComponent("core.css")
			if FileManager.default.fileExists(atPath: candidate.path) {
				return candidate
			}
		}
		fatalError("Could not locate repo Shared/Article Rendering/core.css by walking up from \(#filePath)")
	}
}
