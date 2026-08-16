//
//  WebViewConfiguration.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 1/15/25.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import Foundation
import os
import WebKit

@MainActor final class WebViewConfiguration {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "WebViewConfiguration")

	private static var contentBlockingRuleList: WKContentRuleList?
	private static var configuredContentControllers = NSHashTable<WKUserContentController>.weakObjects()

	static func configuration(with urlSchemeHandler: WKURLSchemeHandler) -> WKWebViewConfiguration {
		assert(Thread.isMainThread)

		let configuration = WKWebViewConfiguration()

		configuration.preferences = preferences
		configuration.defaultWebpagePreferences = webpagePreferences
		configuration.mediaTypesRequiringUserActionForPlayback = .all
		configuration.setURLSchemeHandler(urlSchemeHandler, forURLScheme: ArticleRenderer.imageIconScheme)
		configuration.userContentController = userContentController

		// Present article content as NetNewsWire on top of WebKit's default browser UA, rather than a non-browser string.
		// <https://github.com/Ranchero-Software/NetNewsWire/issues/4453>
		configuration.applicationNameForUserAgent = "NetNewsWire"

#if os(iOS)
		configuration.allowsInlineMediaPlayback = true
#endif

		return configuration
	}

	/// Add content blocking rules to a web view. Call before loading article content.
	static func addContentBlockingRules(to webView: WKWebView) {
		guard let contentBlockingRuleList else {
			return
		}
		let contentController = webView.configuration.userContentController
		if !configuredContentControllers.contains(contentController) {
			contentController.add(contentBlockingRuleList)
			configuredContentControllers.add(contentController)
		}
	}

	/// Reinstalls the article WKUserScripts on a web view immediately before each load,
	/// replacing the previous navigation's scroll-restore script with one carrying this
	/// navigation's target scrollY and generation.
	///
	/// WKUserScripts persist on the WKUserContentController across loadHTMLString calls on
	/// the same WKWebView and re-run on every subsequent navigation. Just adding a new
	/// scroll-restore script on each call without removing the previous one would leave every
	/// prior navigation's script (with its now-stale target scrollY) still attached and
	/// re-firing on every future load. removeAllUserScripts() + a full reinstall keeps exactly
	/// one scroll-restore script active, matching the navigation it was written for. Call
	/// this before webView.loadHTMLString, since .atDocumentStart scripts must already be
	/// registered when a navigation begins.
	@MainActor
	static func installArticleScripts(in webView: WKWebView, windowScrollY: Int, generation: Int) {
		let contentController = webView.configuration.userContentController
		contentController.removeAllUserScripts()
		for script in articleScripts {
			contentController.addUserScript(script)
		}
		contentController.addUserScript(scrollRestoreUserScript(windowScrollY: windowScrollY, generation: generation))
	}

	/// Compile content blocking rules. Call early at app startup.
	static func compileContentBlockingRules() async {

		guard let url = Bundle.main.url(forResource: "ContentRules", withExtension: "json") else {
			logger.warning("WebViewConfiguration: ContentRules.json not found in bundle")
			return
		}

		let rulesJSON: String
		do {
			rulesJSON = try String(contentsOf: url, encoding: .utf8)
		} catch {
			logger.error("WebViewConfiguration: Failed to read ContentRules.json: \(error.localizedDescription)")
			return
		}

		let startTime = CFAbsoluteTimeGetCurrent()

		do {
			let ruleList = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "ContentBlockingRules", encodedContentRuleList: rulesJSON)
			let elapsed = CFAbsoluteTimeGetCurrent() - startTime
			if let ruleList {
				contentBlockingRuleList = ruleList
				logger.info("WebViewConfiguration: Compiled content blocking rules in \(elapsed, format: .fixed(precision: 4))s")
			}
		} catch {
			let elapsed = CFAbsoluteTimeGetCurrent() - startTime
			logger.error("WebViewConfiguration: Failed to compile content blocking rules in \(elapsed, format: .fixed(precision: 4))s: \(error.localizedDescription)")
		}
	}
}

private extension WebViewConfiguration {

	static var preferences: WKPreferences {
		let preferences = WKPreferences()
		preferences.javaScriptCanOpenWindowsAutomatically = false
		preferences.minimumFontSize = 12
		preferences.isElementFullscreenEnabled = true

		return preferences
	}

	static var webpagePreferences: WKWebpagePreferences {
		assert(Thread.isMainThread)

		let preferences = WKWebpagePreferences()
		preferences.allowsContentJavaScript = false
		return preferences
	}

	static var userContentController: WKUserContentController {
		let userContentController = WKUserContentController()
		for script in articleScripts {
			userContentController.addUserScript(script)
		}
		if let contentBlockingRuleList {
			userContentController.add(contentBlockingRuleList)
		}
		return userContentController
	}

	static let articleScripts: [WKUserScript] = {
#if os(iOS)
		let filenames = ["main", "main_ios", "newsfoot", "annotations"]
#else
		let filenames = ["main", "main_mac", "newsfoot", "annotations"]
#endif

		let scripts = filenames.map { filename in
			let scriptURL = Bundle.main.url(forResource: filename, withExtension: ".js")!
			let scriptSource = try! String(contentsOf: scriptURL, encoding: .utf8)
			return WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
		}
		return scripts
	}()

	/// Content JavaScript is disabled above (`webpagePreferences.allowsContentJavaScript =
	/// false`), so any inline `<script>` inside page.html's own HTML never runs -- it's "web
	/// content" JS, which that preference blocks outright, silently. WKUserScripts are
	/// explicitly exempt from that restriction (as already relied on by main.js/main_ios.js/
	/// newsfoot.js for their event listeners and window.webkit.messageHandlers bridges), so
	/// the scroll-restore logic has to be injected this way instead of living in page.html.
	///
	/// Reapplies the target scroll position whenever document layout changes (via a
	/// ResizeObserver on document.body) rather than only at fixed lifecycle points, and
	/// reports completion -- via the scrollRestoreComplete message, tagged with `generation`
	/// so WebViewController can discard reports from a superseded navigation -- once layout
	/// has gone quiet for 250ms or a 3s hard cap (anchored to DOMContentLoaded, which fires
	/// reliably regardless of how long images/fonts take) elapses.
	static func scrollRestoreUserScript(windowScrollY: Int, generation: Int) -> WKUserScript {
		// The per-lifecycle-event debugLog() calls that used to sit at every
		// step below (script-parsed, before/after each restore point, reveal)
		// were development-time scaffolding for building this feature -- 8-10
		// unconditional console lines per single page load, which in practice
		// buried everything else in the Xcode console. The feature is settled
		// now; the one signal worth keeping is the terminal "did restore land
		// correctly" state, which still reaches the native side via the
		// scrollRestoreComplete message (see WebViewController's handler) --
		// that's a structured, single-shot message per navigation, not a raw
		// debug print, so it's kept. If step-by-step tracing is needed again
		// for a specific scroll-restore bug, reintroduce debugLog() calls
		// locally rather than leaving them on by default.
		let source = """
		(function() {
			function scrollState(label) {
				return label + ": target=\(windowScrollY) actualScrollY=" + window.scrollY +
					" scrollHeight=" + (document.body ? document.body.scrollHeight : -1) +
					" innerHeight=" + window.innerHeight +
					" readyState=" + document.readyState;
			}

			// §1b. Runs at .atDocumentStart, before first paint: hide the document
			// immediately so WKWebView never paints it at its natural (0,0) scroll
			// position before applyRestore() gets a chance to run from
			// DOMContentLoaded. Revealed as soon as that first restore lands, with a
			// short hard-cap fallback below in case DOMContentLoaded is ever delayed
			// or skipped, so the page is never left invisible.
			document.documentElement.style.visibility = 'hidden';
			var revealed = false;
			function reveal(reason) {
				if (revealed) { return; }
				revealed = true;
				document.documentElement.style.visibility = 'visible';
			}
			setTimeout(function() { reveal("reveal-hard-cap"); }, 500);

			var settleTimer = null;
			var hardCapTimer = null;
			var complete = false;

			function applyRestore() {
				window.scrollTo(0, \(windowScrollY));
			}

			function finalize(reason) {
				if (complete) { return; }
				complete = true;
				applyRestore();
				clearTimeout(hardCapTimer);
				try {
					window.webkit.messageHandlers.scrollRestoreComplete.postMessage({
						generation: \(generation),
						scrollY: window.scrollY,
						scrollHeight: document.body.scrollHeight
					});
				} catch (e) {
					// messageHandler not installed (e.g. print preview) -- ignore.
				}
			}

			function scheduleSettleCheck() {
				clearTimeout(settleTimer);
				settleTimer = setTimeout(function() {
					finalize("quiet-period");
				}, 250);
			}

			document.addEventListener("DOMContentLoaded", function() {
				applyRestore();
				reveal("DOMContentLoaded");

				if (window.ResizeObserver) {
					var ro = new ResizeObserver(function() {
						applyRestore();
						scheduleSettleCheck();
					});
					ro.observe(document.body);
				}
				scheduleSettleCheck();

				hardCapTimer = setTimeout(function() {
					finalize("hard-cap");
				}, 3000);
			});

			window.addEventListener("load", function() {
				applyRestore();
				scheduleSettleCheck();
			});

			if (document.fonts && document.fonts.ready) {
				document.fonts.ready.then(function() {
					applyRestore();
					scheduleSettleCheck();
				});
			}
		})();
		"""
		return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
	}
}
