//
//  ArticleThemePreviewWebView.swift
//  NetNewsWire-iOS
//
//  Created for Settings → Theme → Font & Color Overrides.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import SwiftUI
import WebKit

/// Renders a small, non-interactive sample article styled with real theme CSS, so the
/// override screen's preview reflects the actual current theme (default or an imported
/// .nnwtheme) as a baseline, with the in-progress override CSS layered on top -- the
/// same layering ArticleRenderer.styleString() does for real articles. A SwiftUI-only
/// preview (as used before this theme was wired up) can't do this: it has no way to
/// know an arbitrary theme's colors or fonts, since those live in that theme's own
/// stylesheet.css, not in anything Swift can introspect.
struct ArticleThemePreviewWebView: UIViewRepresentable {

	let importCSS: String?
	let css: String

	/// Mirrors the real template.html structure closely enough that every selector
	/// any theme or override actually targets has something to hit -- the previous
	/// bare <h1>/<p>/<a> matched nothing real (no .headerContainer, no
	/// #bodyContainer/.articleBody, no #ao3SyntheticPreface), so paragraph
	/// spacing/indent and any override targeting chrome or the AO3 preface showed no
	/// visible change here even when correctly applied to a real article. Doesn't add
	/// a distinct visual treatment for AO3 Notes/End Notes, because none exists in
	/// core.css today (only the preface has one -- confirmed, no
	/// .notes/#chapter_endnotes-equivalent rule anywhere in core.css or the AO3
	/// extractor); the sample includes a plain, unstyled note paragraph so the
	/// preview doesn't misrepresent notes as having special styling they don't have.
	internal static let sampleBodyForTesting = """
	<header class="headerContainer">
	    <table class="headerTable"><tr>
	        <td class="header leftAlign"><a class="feedlink" href="#">Sample Fandom Feed</a><br>by <a href="#">Author Name</a></td>
	        <td class="header rightAlign avatar"></td>
	    </tr></table>
	</header>
	<article>
	    <div class="articleTitle"><h1><a href="#">Sample Work Title</a></h1></div>
	    <div class="articleDatelineTitle"><a href="#">June 2026</a></div>
	    <div id="bodyContainer" class="articleBody">
	        <div id="ao3SyntheticPreface">
	            <dl class="tags">
	                <dt>Rating:</dt><dd>Teen And Up Audiences</dd>
	                <dt>Fandom:</dt><dd class="wide">Sample Fandom</dd>
	                <dt>Chapters:</dt><dd>1/1</dd>
	            </dl>
	        </div>
	        <p><em>Author's Note: sample note text, before the chapter proper.</em></p>
	        <p>Preview text in your chosen font, size, and line height. The quick brown fox jumps over the lazy dog.</p>
	        <p><a href="#">A link looks like this.</a></p>
	    </div>
	</article>
	"""

	private static var sampleBody: String { sampleBodyForTesting }

	func makeUIView(context: Context) -> WKWebView {
		let configuration = WKWebViewConfiguration()
		configuration.userContentController = WKUserContentController()
		let webView = WKWebView(frame: .zero, configuration: configuration)
		webView.isOpaque = false
		webView.backgroundColor = .clear
		webView.scrollView.isScrollEnabled = false
		webView.scrollView.bounces = false
		webView.isUserInteractionEnabled = false
		return webView
	}

	func updateUIView(_ webView: WKWebView, context: Context) {
		let html = """
		<html>
		<head>
		<meta name="viewport" content="width=device-width, initial-scale=1">
		\(importStyle)
		<style>
		body { margin: 0; padding: 16px 0; -webkit-text-size-adjust: none; box-sizing: border-box; }
		\(css)
		</style>
		</head>
		<body>
		\(Self.sampleBody)
		</body>
		</html>
		"""
		webView.loadHTMLString(html, baseURL: nil)
	}

	private var importStyle: String {
		guard let importCSS, !importCSS.isEmpty else {
			return ""
		}

		return """
		<style>
		\(importCSS)
		</style>
		"""
	}
}
