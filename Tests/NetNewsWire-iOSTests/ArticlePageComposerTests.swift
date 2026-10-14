//
//  ArticlePageComposerTests.swift
//  NetNewsWire-iOSTests
//
//  Guards the shared page composer against drifting from the reader: the
//  reader's own render path (`ArticleRenderer` + `MacroProcessor` with the six
//  `page.html` keys, as in `WebViewController.renderPage`) must produce the
//  same HTML as `ArticlePageComposer`, so the preview and the theme color probe
//  see the same page the reader does.
//

import Testing
import Foundation
import RSCore
@testable import Nectar
@testable import ArticleTheming

@MainActor @Suite struct ArticlePageComposerTests {

	@Test func composerMatchesReaderPathForDefaultTheme() throws {
		try assertMatchesReader(theme: ArticleTheme.defaultTheme)
	}

	@Test func composerMatchesReaderPathForThemeWithImports() throws {
		// A gallery theme begins with a leading Google Fonts @import, so this
		// exercises the importStyle block as well.
		let theme = try ArticleTheme(url: try Self.firstGalleryTheme(), isAppTheme: false)
		try assertMatchesReader(theme: theme)
	}

	@Test func composerStylePassMatchesRendererStylePass() throws {
		let theme = ArticleTheme.defaultTheme
		let rendering = ArticleRenderer.noSelectionHTML(theme: theme)
		let css = theme.css ?? ArticleRenderer.defaultStyleSheet
		let expected = try MacroProcessor.renderedText(withTemplate: css, substitutions: ArticleRenderer.styleSubstitutions())
		// Overrides, if any are saved in this test host, are appended after the theme CSS.
		#expect(rendering.style.hasPrefix(expected))
	}

	@Test func importStyleIsEmptyWithoutImports() {
		#expect(ArticlePageComposer.importStyle(importCSS: nil) == "")
		#expect(ArticlePageComposer.importStyle(importCSS: "") == "")
		#expect(ArticlePageComposer.importStyle(importCSS: "@import url(x);").contains("@import url(x);"))
	}

	@Test func composerFillsExactlyTheSixPageKeys() throws {
		let html = try ArticlePageComposer.compose(
			pageHTML: ArticleRenderer.page.html,
			title: "T",
			importStyle: "<!--import-->",
			style: "/*style*/",
			baseURL: "https://example.invalid/",
			body: "<p>BODY</p>",
			lang: "fr"
		)
		for needle in ["<title>T</title>", "<!--import-->", "/*style*/", "href=\"https://example.invalid/\"", "<p>BODY</p>", "lang=\"fr\""] {
			#expect(html.contains(needle), "Missing \(needle)")
		}
		#expect(!html.contains("[["))
	}

	// MARK: - Helpers

	private func assertMatchesReader(theme: ArticleTheme) throws {
		let rendering = ArticleRenderer.noSelectionHTML(theme: theme)
		let lang = Locale.current.language.languageCode?.identifier ?? "en"

		// The reader's path (WebViewController.renderPage).
		let readerHTML = try MacroProcessor.renderedText(withTemplate: ArticleRenderer.page.html, substitutions: [
			"title": rendering.title,
			"baseURL": rendering.baseURL,
			"importStyle": rendering.importStyle,
			"style": rendering.style,
			"body": rendering.html,
			"lang": lang
		])

		let composed = try ArticlePageComposer.compose(
			pageHTML: ArticleRenderer.page.html,
			title: rendering.title,
			importStyle: ArticlePageComposer.importStyle(importCSS: theme.importCSS),
			style: rendering.style,
			baseURL: rendering.baseURL,
			body: rendering.html,
			lang: ArticlePageComposer.defaultLang
		)
		#expect(composed == readerHTML)
		#expect(ArticlePageComposer.importStyle(importCSS: theme.importCSS) == rendering.importStyle)
	}

	private static func repoURL(_ relativePath: String) throws -> URL {
		var url = URL(fileURLWithPath: #filePath)
		while url.pathComponents.count > 1 {
			url.deleteLastPathComponent()
			let candidate = url.appendingPathComponent(relativePath)
			if FileManager.default.fileExists(atPath: candidate.path) {
				return candidate
			}
		}
		throw CocoaError(.fileNoSuchFile)
	}

	private static func firstGalleryTheme() throws -> URL {
		let directory = try repoURL("gallery-themes")
		let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".nnwtheme") }.sorted()
		guard let first = names.first else {
			throw CocoaError(.fileNoSuchFile)
		}
		return directory.appendingPathComponent(first)
	}
}
