//
//  PreloadedWebView.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 2/25/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import Foundation
import WebKit

final class PreloadedWebView: WKWebView {

	private var isReady: Bool = false
	private var readyCompletion: (() -> Void)?

	init(articleIconSchemeHandler: ArticleIconSchemeHandler) {
		let configuration = WebViewConfiguration.configuration(with: articleIconSchemeHandler)
		super.init(frame: .zero, configuration: configuration)

		// WKWebView defaults to an opaque white background, which shows
		// through between insertion/navigation and the moment the article
		// theme's CSS actually paints -- most visible as a stark white flash
		// on every article open (and on relaunch, restoring the last-viewed
		// article) when in dark mode. Follow the system appearance instead so
		// the gap, if any, isn't jarring. This is a reasonable default rather
		// than a per-theme-accurate one (a light-styled theme like Sepia used
		// while the system is in dark mode will still briefly show a dark
		// backdrop); getting that exactly right would need each theme to
		// expose its own background color.
		isOpaque = false
		backgroundColor = .systemBackground
		underPageBackgroundColor = .systemBackground
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)

	}

	func preload() {
		navigationDelegate = self
		loadFileURL(ArticleRenderer.blank.url, allowingReadAccessTo: ArticleRenderer.blank.baseURL)
	}

	func ready(completion: @escaping () -> Void) {
		if isReady {
			completeRequest(completion: completion)
		} else {
			readyCompletion = completion
		}
	}
}

// MARK: WKScriptMessageHandler

extension PreloadedWebView: WKNavigationDelegate {

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		isReady = true
		if let completion = readyCompletion {
			completeRequest(completion: completion)
			readyCompletion = nil
		}
	}
}

// MARK: Private

private extension PreloadedWebView {

	func completeRequest(completion: @escaping () -> Void) {
		isReady = false
		navigationDelegate = nil
		completion()
	}
}
