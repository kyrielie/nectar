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

	let css: String

	private static let sampleBody = """
	<h1>The Sample Chapter Title</h1>
	<p>This is a preview of how article text will look with your chosen font, size, line height, and colors. The quick brown fox jumps over the lazy dog.</p>
	<p><a href="#">A link looks like this.</a></p>
	"""

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
}
