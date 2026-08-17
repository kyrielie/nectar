//
//  PreloadedWebView.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 2/25/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import Foundation
import UIKit
import WebKit

/// Lets PreloadedWebView ask its owning WebViewController (via a weak
/// delegate, set/reasserted on every dequeue the same way navigationDelegate/
/// uiDelegate/scrollView.delegate already are -- see WebViewController.
/// loadWebView) whether there's currently a highlightable selection, and
/// tells it when the person taps the injected "Highlight" action. Only
/// consulted when AnnotationCreationMethod == .nativeMenu; buildMenu(with:)
/// checks the mode itself before ever asking.
///
/// @MainActor because both the sole conformer (WebViewController, a
/// UIViewController) and the sole caller (PreloadedWebView.buildMenu(with:),
/// a UIView override called synchronously by UIKit on the main thread) are
/// themselves main-actor-isolated -- without this, the protocol's
/// requirements are nonisolated by default, and WebViewController's actual
/// (isolated) implementation of isSelectionHighlightable doesn't satisfy a
/// nonisolated requirement, which is a data-race error under Swift 6's
/// strict concurrency checking, not just a warning.
@MainActor
protocol PreloadedWebViewAnnotationDelegate: AnyObject {
	/// True only if there's a live, non-empty text selection inside the
	/// loaded article's content right now.
	var isSelectionHighlightable: Bool { get }
	func nativeMenuHighlightWasTapped()
}

final class PreloadedWebView: WKWebView {

	private var isReady: Bool = false
	private var readyCompletion: (() -> Void)?

	/// See PreloadedWebViewAnnotationDelegate. Weak, and reasserted on
	/// every dequeue by WebViewController.loadWebView -- not set once at
	/// init -- because PreloadedWebView instances are pooled and reused
	/// across different WebViewControllers (same reason navigationDelegate/
	/// uiDelegate/scrollView.delegate are reasserted there too).
	weak var annotationMenuDelegate: PreloadedWebViewAnnotationDelegate?

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

	/// Strips WebKit's own "Share…" submenu from the native text-selection
	/// callout menu -- the only place "Copy Link with Highlight" (WebKit's
	/// built-in text-fragment link generator, unrelated to this app's own
	/// highlight/annotation feature) lives. WebKit doesn't expose a
	/// narrower identifier for that one item, so removing the whole
	/// `.share` submenu is the only available lever (confirmed still
	/// working this way as of iOS 18.2:
	/// <https://developer.apple.com/forums/thread/770785>). This doesn't
	/// lose sharing capability: the app has its own "Share" entry in the
	/// custom long-press context menu (WebViewController.buildContextMenu/
	/// shareAction), which is a separate menu system from this one.
	override func buildMenu(with builder: UIMenuBuilder) {
		super.buildMenu(with: builder)
		builder.remove(menu: .share)

		// Native-menu highlight creation: only relevant when the person
		// has chosen .nativeMenu (not .popup or .off) in Annotations
		// settings, and only when there's actually something selected to
		// highlight right now. isSelectionHighlightable is tracked
		// independently of this method's own call timing -- see
		// WebViewController.textWasSelected(body:)/currentSelectionRect --
		// since buildMenu(with:) can be invoked by UIKit at moments this
		// class has no other hook into.
		guard AppDefaults.shared.annotationCreationMethod == .nativeMenu,
			  annotationMenuDelegate?.isSelectionHighlightable == true else {
			return
		}

		let highlight = UIAction(
			title: NSLocalizedString("Highlight", comment: "Native selection menu: highlight action"),
			image: UIImage(systemName: "highlighter")
		) { [weak self] _ in
			self?.annotationMenuDelegate?.nativeMenuHighlightWasTapped()
		}
		let highlightMenu = UIMenu(title: "", options: .displayInline, children: [highlight])
		builder.insertChild(highlightMenu, atStartOfMenu: .standardEdit)
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
