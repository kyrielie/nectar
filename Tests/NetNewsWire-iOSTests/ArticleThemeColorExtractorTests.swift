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
@testable import Nectar

@Suite struct ArticleThemeColorExtractorTests {

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
}
