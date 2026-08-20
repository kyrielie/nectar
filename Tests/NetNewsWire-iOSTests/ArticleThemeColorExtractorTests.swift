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
			let css = try Self.readThemeStylesheet("Black & White")
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
			let themesDirectory = ArticleThemeColorExtractorTests.repoThemesDirectory()
			let stylesheetURL = themesDirectory
				.appendingPathComponent("\(themeName).nnwtheme")
				.appendingPathComponent("stylesheet.css")
			return try String(contentsOf: stylesheetURL, encoding: .utf8)
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
	/// test runner's bundle, not the app's, and doesn't have Themes/ copied in.
	fileprivate static func repoThemesDirectory() -> URL {
		var url = URL(fileURLWithPath: #filePath)
		while url.pathComponents.count > 1 {
			url.deleteLastPathComponent()
			let candidate = url.appendingPathComponent("Themes")
			if FileManager.default.fileExists(atPath: candidate.path) {
				return candidate
			}
		}
		fatalError("Could not locate repo Themes/ directory by walking up from \(#filePath)")
	}
}
