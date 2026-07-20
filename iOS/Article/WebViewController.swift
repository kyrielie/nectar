//
//  WebViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 12/28/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
@preconcurrency import WebKit
import RSCore
import RSWeb
import Account
import Articles
import SafariServices
import MessageUI
import Images
import os

final class WebViewController: UIViewController {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "WebViewController")

	private struct MessageName {
		static let imageWasClicked = "imageWasClicked"
		static let imageWasShown = "imageWasShown"
		static let showFeedInspector = "showFeedInspector"
		static let debugLog = "debugLog"
		static let scrollRestoreComplete = "scrollRestoreComplete"
	}

	private var topShowBarsView: UIView!
	private var bottomShowBarsView: UIView!
	private var topShowBarsViewConstraint: NSLayoutConstraint!
	private var bottomShowBarsViewConstraint: NSLayoutConstraint!

	// The only authoritative reference to "the" current webview. Previously this was
	// a computed property returning view.subviews[0], which silently returned whichever
	// PreloadedWebView happened to be backmost if more than one was ever inserted --
	// see loadWebViewGeneration below for why that could happen, and why subviews[0]
	// is not a safe way to identify it.
	private var webView: PreloadedWebView?

	// Bumped at the top of every loadWebView() call. Captured by value into each
	// dequeueWebView/ready completion so that a completion arriving after a newer
	// loadWebView() call has started can recognize it's stale and bail out instead
	// of inserting a second, competing PreloadedWebView into the view hierarchy.
	// This closes the race where viewDidLoad's unconditional loadWebView(reason:
	// "viewDidLoad") (windowScrollY still 0, since setArticle's async scroll-position
	// fetch hasn't resolved yet) and setArticle's own loadWebView(reason: "setArticle
	// ... after scroll fetch") (windowScrollY now the restored value) each see
	// webView == nil and each independently dequeue+insert their own webview --
	// whichever of the two ends up on top of the view stack is timing-dependent,
	// and it is not necessarily the one that captured the correct scroll position.
	private var loadWebViewGeneration = 0

	private lazy var contextMenuInteraction = UIContextMenuInteraction(delegate: self)
	private var isFullScreenAvailable: Bool {
		return AppDefaults.shared.articleFullscreenAvailable && traitCollection.userInterfaceIdiom == .phone
	}
	private lazy var articleIconSchemeHandler = ArticleIconSchemeHandler(coordinator: coordinator)
	private lazy var transition = ImageTransition(controller: self)
	private var clickedImageCompletion: (() -> Void)?

	weak var coordinator: SceneCoordinator!

	private(set) var article: Article?

	let scrollPositionQueue = CoalescingQueue(name: "Article Scroll Position", interval: 0.3, maxInterval: 0.3)

	// Mirrors of the last scroll position / reading progress actually confirmed via the
	// JS bridge in scrollPositionDidChange(). Kept as plain properties (not re-derived
	// via a fresh evaluateJavaScript call) so viewWillDisappear can flush a final save
	// synchronously without an async JS round trip racing the view's teardown -- see
	// viewWillDisappear for why that race was a real, reproducible bug.
	private var lastKnownReadingProgress: Double?
	// Diagnostic only, for tracing the duplicate-renderPage-call reports -- not
	// used for any behavior decision. (loadWebViewGeneration, below webView, is
	// the counter that actually gates behavior.)
	private var loadWebViewCallCount = 0
	// True from the start of a renderPage() call until page.html's JS confirms
	// (via the scrollRestoreComplete message) that its own multi-point scroll
	// restore (DOMContentLoaded / load / fonts.ready / ResizeObserver-driven
	// reflows) has settled. While true, scrollPositionDidChange's samples are
	// noise -- either WKWebView's native post-loadHTMLString reset to (0,0), or
	// one of page.html's own restore attempts sampled before the document has
	// reached its final height -- and must not be written to windowScrollY or
	// persisted. See scrollRestoreComplete(generation:scrollY:scrollHeight:).
	private var isRestoringScrollPosition = false

	// Safety net: if page.html's completion message never arrives (JS error,
	// ResizeObserver unsupported and load/fonts.ready somehow never fire,
	// print preview, etc.), don't block real scroll saves forever.
	private var scrollRestoreFailsafeWorkItem: DispatchWorkItem?

	// Per-load high-water mark for document height, used as a defense-in-depth
	// guard against persisting a sample taken against a shorter-than-final
	// document even if it arrives after isRestoringScrollPosition is cleared
	// (e.g. a late-loading embed that reflows after the settle/hard-cap signal
	// already fired). Reset at the top of renderPage. See scrollPositionDidChange.
	private var maxObservedScrollHeight: Double = 0

	// Set by setArticle just before it kicks off its async scroll-position fetch,
	// and cleared right before that Task calls loadWebView (both on the success
	// path and the "article changed, discard" early-return path). While true,
	// viewDidLoad's unconditional loadWebView(reason: "viewDidLoad") is skipped
	// so the first render to actually happen is the one with the correct
	// windowScrollY, instead of a render-at-0 followed by a second corrective
	// render whose reset-suppression could race and let 0 get saved over the
	// real position.
	private var isAwaitingInitialScrollFetch = false

	var windowScrollY = 0 {
		didSet {
			if windowScrollY != AppDefaults.shared.articleWindowScrollY {
				AppDefaults.shared.articleWindowScrollY = windowScrollY
			}
			// Per-article persistence (Phase 2), alongside the existing single-global
			// AppDefaults write above, which still backs relaunch state restoration
			// (SceneCoordinator's stateInfo.articleWindowScrollY path) and is left as-is.
			if let article = article, let account = article.account {
				let articleID = article.articleID
				let scrollY = windowScrollY
				Task {
					await account.saveScrollPosition(Double(scrollY), forArticleID: articleID)
				}
			}
		}
	}
	override func viewDidLoad() {
		super.viewDidLoad()

		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(avatarDidBecomeAvailable(_:)), name: .AvatarDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(faviconDidBecomeAvailable(_:)), name: .FaviconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(currentArticleThemeDidChangeNotification(_:)), name: .CurrentArticleThemeDidChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(articleThemeOverridesDidChangeNotification(_:)), name: .articleThemeOverridesDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(handleSceneDidEnterBackground(_:)), name: UIScene.didEnterBackgroundNotification, object: nil)

		// Configure the tap zones
		configureTopShowBarsView()
		configureBottomShowBarsView()

		if !isAwaitingInitialScrollFetch {
			loadWebView(reason: "viewDidLoad")
		}
		super.viewSafeAreaInsetsDidChange()
		if isFullScreenAvailable && AppDefaults.shared.logicalArticleFullscreenEnabled {
			updateBottomSafeAreaForFullScreen()
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		// Flush the final scroll position/reading progress before the view (and its
		// webView) goes away.
		//
		// This used to call scrollPositionQueue.performCallsImmediately() to force any
		// coalesced-but-not-yet-fired update to run early. That only fires the *timer*
		// early -- the selector it invokes, scrollPositionDidChange(), still does an
		// async evaluateJavaScript round trip to the WebContent process before it reads
		// window.scrollY and saves anything. viewWillDisappear returned immediately
		// after kicking that off, so if the article was popped quickly (or `webView`,
		// a pooled PreloadedWebView, got dequeued for the next article before the
		// completion handler ran), the save could be dropped or land on the wrong
		// article -- reproducing "exit fast, come back, not at your last position."
		//
		// Fix: don't re-enter the JS bridge here at all. windowScrollY and
		// lastKnownReadingProgress already hold the last values confirmed by the JS
		// bridge in scrollPositionDidChange(), so save those synchronously (no JS call,
		// nothing to race) and drop whatever's still pending in the coalescing queue.
		scrollPositionQueue.cancelPendingCalls()
		flushLastKnownScrollState()
		// Pause in-flight media before the view goes away. Leaving a video playing during
		// dismissal lets WebKit's full-screen entry continuation fire on a stale view
		// hierarchy and trip a RELEASE_ASSERT in WebFullScreenManagerProxy on iOS 26.
		stopWebViewActivity()
	}

	// MARK: Notifications

	@objc func handleSceneDidEnterBackground(_ notification: Notification) {
		// The share sheet is a popover on iPad. Opening the article in another browser
		// from it backgrounds NetNewsWire mid-presentation, orphaning the popover so it
		// can't be dismissed by tapping outside on return. Dismiss it on backgrounding. (#4269)
		if presentedViewController is UIActivityViewController {
			dismiss(animated: false)
		}
	}

	@objc func feedIconDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	@objc func avatarDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	@objc func faviconDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	@objc func currentArticleThemeDidChangeNotification(_ note: Notification) {
		loadWebView(reason: "themeChanged")
	}

	@objc func articleThemeOverridesDidChangeNotification(_ note: Notification) {
		loadWebView(reason: "themeOverridesChanged")
	}

	// MARK: Actions

	@objc func showBars(_ sender: Any) {
		showBars()
	}

	// MARK: API

	func setArticle(_ article: Article?, updateView: Bool = true) {
		if article != self.article {
			self.article = article
			if updateView {
				guard let article = article, let account = article.account else {
					windowScrollY = 0
					loadWebView(reason: "setArticle(nil)")
					return
				}
				// Real per-article scroll position (Phase 2), replacing the old
				// unconditional reset to 0 on every article switch.
				let articleID = article.articleID
				// Tell viewDidLoad not to render at windowScrollY == 0 while this
				// fetch is in flight -- see isAwaitingInitialScrollFetch.
				isAwaitingInitialScrollFetch = true
				Task {
					let scrollPosition = await account.fetchScrollPosition(forArticleID: articleID)
					Self.logger.debug("setArticle: fetched scrollPosition=\(scrollPosition, privacy: .public) for articleID=\(articleID, privacy: .public)")
					// The user may have already navigated elsewhere by the time this
					// resolves; only apply it if we're still showing the same article.
					guard self.article?.articleID == articleID else {
						Self.logger.debug("setArticle: article changed before scrollPosition fetch resolved, discarding for articleID=\(articleID, privacy: .public)")
						self.isAwaitingInitialScrollFetch = false
						return
					}
					self.windowScrollY = Int(scrollPosition)
					self.isAwaitingInitialScrollFetch = false
					self.loadWebView(reason: "setArticle(\(articleID)) after scroll fetch")
				}
			}
		}
	}

	func setScrollPosition(articleWindowScrollY: Int) {
		windowScrollY = articleWindowScrollY
		loadWebView(reason: "setScrollPosition")
	}

	func focus() {
		webView?.becomeFirstResponder()
	}

	func canScrollDown() -> Bool {
		guard let webView = webView else { return false }
		return webView.scrollView.contentOffset.y < finalScrollPosition(scrollingUp: false)
	}

	func canScrollUp() -> Bool {
		guard let webView = webView else { return false }
		return webView.scrollView.contentOffset.y > finalScrollPosition(scrollingUp: true)
	}

	private func scrollPage(up scrollingUp: Bool) {
		guard let webView, let windowScene = webView.window?.windowScene else {
			return
		}

		let overlap = 2 * UIFont.systemFont(ofSize: UIFont.systemFontSize).lineHeight * windowScene.screen.scale
		let scrollToY: CGFloat = {
			let scrollDistance = webView.scrollView.layoutMarginsGuide.layoutFrame.height - overlap
			let fullScroll = webView.scrollView.contentOffset.y + (scrollingUp ? -scrollDistance : scrollDistance)
			let final = finalScrollPosition(scrollingUp: scrollingUp)
			return (scrollingUp ? fullScroll > final : fullScroll < final) ? fullScroll : final
		}()

		let convertedPoint = self.view.convert(CGPoint(x: 0, y: 0), to: webView.scrollView)
		let scrollToPoint = CGPoint(x: convertedPoint.x, y: scrollToY)
		webView.scrollView.setContentOffset(scrollToPoint, animated: true)
	}

	func scrollPageDown() {
		scrollPage(up: false)
	}

	func scrollPageUp() {
		scrollPage(up: true)
	}

	func hideClickedImage() {
		webView?.evaluateJavaScript("hideClickedImage();")
	}

	func showClickedImage(completion: @escaping () -> Void) {
		clickedImageCompletion = completion
		webView?.evaluateJavaScript("showClickedImage();")
	}

	func fullReload() {
		loadWebView(reason: "fullReload", replaceExistingWebView: true)
	}

	func showBars(animated: Bool = true) {
		Self.logger.debug("showBars: called, animated=\(animated, privacy: .public)")
		AppDefaults.shared.articleFullscreenEnabled = false
		coordinator.showStatusBar()
		topShowBarsViewConstraint?.constant = 0
		bottomShowBarsViewConstraint?.constant = 0
		navigationController?.setNavigationBarHidden(false, animated: animated)
		navigationController?.setToolbarHidden(false, animated: animated)
		additionalSafeAreaInsets.bottom = 0
		setBottomScrollEdgeEffectHidden(false)
		configureContextMenuInteraction()
		// setNavigationBarHidden/setToolbarHidden reset interactivePopGestureRecognizer's
		// (and interactiveContentPopGestureRecognizer's) isEnabled back to true as a
		// side effect, which silently overrides articleBackSwipeEnabled = false. Re-apply
		// the gate immediately after so showing the bars doesn't re-enable back-swipe.
		coordinator.applyArticleBackSwipeGating()
		Self.logger.debug("showBars: returned from applyArticleBackSwipeGating")
	}

	func hideBars() {
		if isFullScreenAvailable {
			Self.logger.debug("hideBars: called")
			AppDefaults.shared.articleFullscreenEnabled = true
			coordinator.hideStatusBar()
			topShowBarsViewConstraint?.constant = -44.0
			bottomShowBarsViewConstraint?.constant = 44.0
			navigationController?.setNavigationBarHidden(true, animated: true)
			navigationController?.setToolbarHidden(true, animated: true)
			setBottomScrollEdgeEffectHidden(true)
			configureContextMenuInteraction()
			coordinator.applyArticleBackSwipeGating()
			Self.logger.debug("hideBars: returned from applyArticleBackSwipeGating")
		}
	}

	func stopWebViewActivity() {
		if let webView = webView {
			stopMediaPlayback(webView)
			cancelImageLoad(webView)
		}
	}

	func showActivityDialog(popOverBarButtonItem: UIBarButtonItem? = nil) {
		guard let url = article?.preferredURL else { return }
		let activityViewController = UIActivityViewController(url: url, title: article?.title, applicationActivities: [FindInArticleActivity(), OpenInBrowserActivity(), ShareAO3SeriesLinkActivity(seriesURL: article?.ao3SeriesURL)])
		activityViewController.popoverPresentationController?.barButtonItem = popOverBarButtonItem
		present(activityViewController, animated: true)
	}

	func openInAppBrowser() {
		guard let url = article?.preferredURL else { return }
		if AppDefaults.shared.useSystemBrowser {
			UIApplication.shared.open(url, options: [:])
		} else {
			openURLInSafariViewController(url)
		}
	}
}

// MARK: UIContextMenuInteractionDelegate

extension WebViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {

		return UIContextMenuConfiguration(identifier: nil, previewProvider: contextMenuPreviewProvider) { [weak self] _ in
			guard let self = self else { return nil }

			var menus = [UIMenu]()

			var navActions = [UIAction]()
			if let action = self.prevArticleAction() {
				navActions.append(action)
			}
			if let action = self.nextArticleAction() {
				navActions.append(action)
			}
			if !navActions.isEmpty {
				menus.append(UIMenu(title: "", options: .displayInline, children: navActions))
			}

			var toggleActions = [UIAction]()
			if let action = self.toggleReadAction() {
				toggleActions.append(action)
			}
			toggleActions.append(self.toggleStarredAction())
			toggleActions.append(self.toggleLovedAction())
			menus.append(UIMenu(title: "", options: .displayInline, children: toggleActions))

			if let action = self.nextUnreadArticleAction() {
				menus.append(UIMenu(title: "", options: .displayInline, children: [action]))
			}

			menus.append(UIMenu(title: "", options: .displayInline, children: [self.shareAction()]))

			return UIMenu(title: "", children: menus)
        }
    }

	func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
		coordinator.showBrowserForCurrentArticle()
	}

}

// MARK: WKNavigationDelegate

extension WebViewController: WKNavigationDelegate {

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		Self.logger.debug("webView didFinish navigation for articleID=\(self.article?.articleID ?? "nil", privacy: .public)")
		for (index, view) in view.subviews.enumerated() {
			if index != 0, let oldWebView = view as? PreloadedWebView {
				oldWebView.removeFromSuperview()
			}
		}
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		Self.logger.debug("webView didFail navigation for articleID=\(self.article?.articleID ?? "nil", privacy: .public) error=\(error.localizedDescription, privacy: .public)")
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		Self.logger.debug("webView didFailProvisionalNavigation for articleID=\(self.article?.articleID ?? "nil", privacy: .public) error=\(error.localizedDescription, privacy: .public)")
	}

	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {

		if navigationAction.navigationType == .linkActivated {
			guard let url = navigationAction.request.url else {
				decisionHandler(.allow)
				return
			}

			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
			if components?.scheme == "http" || components?.scheme == "https" {
				decisionHandler(.cancel)
				if AppDefaults.shared.useSystemBrowser {
					UIApplication.shared.open(url, options: [:])
				} else {
					UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { didOpen in
						guard didOpen == false else {
							return
						}
						self.openURLInSafariViewController(url)
					}
				}

			} else if components?.scheme == "mailto" {
				decisionHandler(.cancel)

				guard let emailAddress = url.percentEncodedEmailAddress else {
					return
				}

				if UIApplication.shared.canOpenURL(emailAddress) {
					UIApplication.shared.open(emailAddress, options: [.universalLinksOnly: false], completionHandler: nil)
				} else {
					let alert = UIAlertController(title: NSLocalizedString("Error", comment: "Error"), message: NSLocalizedString("This device cannot send emails.", comment: "This device cannot send emails."), preferredStyle: .alert)
					alert.addAction(.init(title: NSLocalizedString("Dismiss", comment: "Dismiss"), style: .cancel, handler: nil))
					self.present(alert, animated: true, completion: nil)
				}
			} else if components?.scheme == "tel" {
				decisionHandler(.cancel)

				if UIApplication.shared.canOpenURL(url) {
					UIApplication.shared.open(url, options: [.universalLinksOnly: false], completionHandler: nil)
				}

			} else {
				decisionHandler(.allow)
			}
		} else {
			decisionHandler(.allow)
		}
	}

	func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		fullReload()
	}

}

// MARK: WKUIDelegate

extension WebViewController: WKUIDelegate {

	func webView(_ webView: WKWebView, contextMenuForElement elementInfo: WKContextMenuElementInfo, willCommitWithAnimator animator: UIContextMenuInteractionCommitAnimating) {
		// We need to have at least an unimplemented WKUIDelegate assigned to the WKWebView.  This makes the
		// link preview launch Safari when the link preview is tapped.  In theory, you should be able to get
		// the link from the elementInfo above and transition to SFSafariViewController instead of launching
		// Safari.  As the time of this writing, the link in elementInfo is always nil.  ¯\_(ツ)_/¯
	}

	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		guard let url = navigationAction.request.url else {
			return nil
		}

		openURL(url)
		return nil
	}

}

// MARK: WKScriptMessageHandler

extension WebViewController: WKScriptMessageHandler {

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		switch message.name {
		case MessageName.imageWasShown:
			clickedImageCompletion?()
		case MessageName.imageWasClicked:
			imageWasClicked(body: message.body as? String)
		case MessageName.showFeedInspector:
			if let feed = article?.feed {
				coordinator.showFeedInspector(for: feed)
			}
		case MessageName.debugLog:
			// Bridges page.html's scroll-restoration console output to the same
			// os.Logger stream as the rest of the app's debug logging, since raw
			// console.log in WKWebView doesn't show up there on its own.
			Self.logger.debug("page.html: \(message.body as? String ?? "", privacy: .public)")
		case MessageName.scrollRestoreComplete:
			guard let body = message.body as? [String: Any],
				  let generation = body["generation"] as? Int,
				  let reportedScrollY = body["scrollY"] as? Int else {
				return
			}
			guard generation == loadWebViewGeneration else {
				Self.logger.debug("scrollRestoreComplete: discarding stale message, generation=\(generation, privacy: .public) currentGeneration=\(self.loadWebViewGeneration, privacy: .public)")
				return
			}
			scrollRestoreFailsafeWorkItem?.cancel()
			isRestoringScrollPosition = false
			Self.logger.debug("scrollRestoreComplete: settled scrollY=\(reportedScrollY, privacy: .public) articleID=\(self.article?.articleID ?? "nil", privacy: .public)")
			// Reconcile in-memory/DB state with what the page actually settled at,
			// in case it differs from the value we asked it to restore to (e.g. the
			// article got shorter than the saved position, so the browser clamped
			// to max scroll).
			windowScrollY = reportedScrollY
		default:
			return
		}
	}

}

// MARK: UIViewControllerTransitioningDelegate

extension WebViewController: UIViewControllerTransitioningDelegate {

	func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
		transition.presenting = true
		return transition
	}

	func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
		transition.presenting = false
		return transition
	}
}

// MARK:

extension WebViewController: UIScrollViewDelegate {

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		scrollPositionQueue.add(self, #selector(scrollPositionDidChange))
	}

	@objc func scrollPositionDidChange() {
		webView?.evaluateJavaScript("({ scrollY: window.scrollY, scrollHeight: document.body.scrollHeight, innerHeight: window.innerHeight })") { (result, error) in
			guard error == nil, let result = result as? [String: Any] else {
				Self.logger.debug("scrollPositionDidChange: evaluateJavaScript failed, error=\(String(describing: error), privacy: .public)")
				return
			}
			let javascriptScrollY = result["scrollY"] as? Int ?? 0
			// I don't know why this value gets returned sometimes, but it is in error
			guard javascriptScrollY != 33554432 else {
				Self.logger.debug("scrollPositionDidChange: discarding known-bad sentinel scrollY value")
				return
			}
			guard !self.isRestoringScrollPosition else {
				Self.logger.debug("scrollPositionDidChange: discarding sample during restore settling (scrollY=\(javascriptScrollY, privacy: .public)) -- not yet confirmed via scrollRestoreComplete")
				return
			}
			if let scrollHeight = result["scrollHeight"] as? Double, scrollHeight > 0 {
				if scrollHeight < self.maxObservedScrollHeight - 1 {
					Self.logger.debug("scrollPositionDidChange: discarding sample, scrollHeight shrank (observed=\(scrollHeight, privacy: .public) max=\(self.maxObservedScrollHeight, privacy: .public)) -- unsettled reflow")
					return
				}
				self.maxObservedScrollHeight = max(self.maxObservedScrollHeight, scrollHeight)
			}
			self.windowScrollY = javascriptScrollY
			Self.logger.debug("scrollPositionDidChange: articleID=\(self.article?.articleID ?? "nil", privacy: .public) scrollY=\(javascriptScrollY, privacy: .public)")

			// Scroll-percentage-gated read marking (Phase 2). scrollHeight includes the
			// full document; innerHeight is the viewport. Once the bottom of the viewport
			// has reached 99% of the document height, treat the article as read.
			if let scrollHeight = result["scrollHeight"] as? Double, scrollHeight > 0,
			   let innerHeight = result["innerHeight"] as? Double {
				let percentScrolled = (Double(javascriptScrollY) + innerHeight) / scrollHeight
				if percentScrolled >= 0.99 {
					self.coordinator.markCurrentArticleAsReadFromScrollCompletion()
				}

				// Visible reading progress (Phase A1). Reuses this same JS bridge payload
				// rather than adding a second round trip -- percentScrolled is already the
				// 0...1 fraction the card wants, just clamped to a valid range.
				if let article = self.article, let account = article.account {
					let articleID = article.articleID
					let readingProgress = min(max(percentScrolled, 0), 1)
					self.lastKnownReadingProgress = readingProgress
					Task {
						await account.saveReadingProgress(readingProgress, forArticleID: articleID)
					}
				}
			}
		}
	}
}

// MARK: JSON

private struct ImageClickMessage: Codable {
	let x: Float
	let y: Float
	let width: Float
	let height: Float
	let imageTitle: String?
	let imageURL: String
}

// MARK: Private

private extension WebViewController {

	/// Synchronously persists the last scroll position / reading progress values this
	/// controller already has in hand -- no JS evaluation, so nothing to race against
	/// the view tearing down. See viewWillDisappear.
	func flushLastKnownScrollState() {
		guard let article, let account = article.account else { return }
		let articleID = article.articleID
		let scrollY = windowScrollY
		let readingProgress = lastKnownReadingProgress
		Task {
			await account.saveScrollPosition(Double(scrollY), forArticleID: articleID)
			if let readingProgress {
				await account.saveReadingProgress(readingProgress, forArticleID: articleID)
			}
		}
	}

	func loadWebView(reason: String, replaceExistingWebView: Bool = false) {
		guard isViewLoaded else {
			Self.logger.debug("loadWebView: skipped, view not loaded yet (reason=\(reason, privacy: .public))")
			return
		}

		loadWebViewCallCount += 1
		loadWebViewGeneration += 1
		let generation = loadWebViewGeneration
		Self.logger.debug("loadWebView: call #\(self.loadWebViewCallCount, privacy: .public) generation=\(generation, privacy: .public) reason=\(reason, privacy: .public) articleID=\(self.article?.articleID ?? "nil", privacy: .public) windowScrollY=\(self.windowScrollY, privacy: .public) reusingExistingWebView=\(!replaceExistingWebView && self.webView != nil, privacy: .public)")

		if !replaceExistingWebView, let webView = webView {
			self.renderPage(webView)
			return
		}

		coordinator.webViewProvider.dequeueWebView { webView in

			webView.ready {

				// A newer loadWebView() call has started since this one was issued --
				// most commonly viewDidLoad's initial call losing the race against
				// setArticle's post-scroll-fetch call, or vice versa. Discard this
				// webview rather than inserting a second one into the view hierarchy;
				// the winning generation's own completion will render the page.
				guard generation == self.loadWebViewGeneration else {
					Self.logger.debug("loadWebView: discarding stale completion, generation=\(generation, privacy: .public) currentGeneration=\(self.loadWebViewGeneration, privacy: .public) reason=\(reason, privacy: .public)")
					return
				}

				// If an older webview is still around (e.g. this is a replaceExistingWebView
				// reload), remove it now so we never have more than one PreloadedWebView
				// in the view hierarchy at a time.
				if let previousWebView = self.webView, previousWebView !== webView {
					previousWebView.removeFromSuperview()
				}

				// Add the webview
				webView.translatesAutoresizingMaskIntoConstraints = false
				self.webView = webView
				self.view.insertSubview(webView, at: 0)
				NSLayoutConstraint.activate([
					self.view.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
					self.view.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
					self.view.topAnchor.constraint(equalTo: webView.topAnchor),
					self.view.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
				])

				// UISplitViewController reports the wrong size to WKWebView which can cause horizontal
				// rubberbanding on the iPad.  This interferes with our UIPageViewController preventing
				// us from easily swiping between WKWebViews.  This hack fixes that.
				webView.scrollView.contentInset = UIEdgeInsets(top: 0, left: -1, bottom: 0, right: 0)

				webView.scrollView.setZoomScale(1.0, animated: false)

				self.view.setNeedsLayout()
				self.view.layoutIfNeeded()

				// Configure the webview
				webView.navigationDelegate = self
				webView.uiDelegate = self
				webView.scrollView.delegate = self
				self.configureContextMenuInteraction()

				// Remove possible existing message handlers
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.imageWasClicked)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.imageWasShown)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.showFeedInspector)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.debugLog)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.scrollRestoreComplete)

				// Add handlers
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.imageWasClicked)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.imageWasShown)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.showFeedInspector)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.debugLog)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.scrollRestoreComplete)

				self.renderPage(webView)
			}
		}
	}

	func renderPage(_ webView: PreloadedWebView?) {
		guard let webView = webView else { return }

		let theme = ArticleThemesManager.shared.currentTheme
		let rendering: ArticleRenderer.Rendering

		if let article = article {
			rendering = ArticleRenderer.articleHTML(article: article, theme: theme, timelineFeed: coordinator?.timelineFeed)
		} else {
			rendering = ArticleRenderer.noSelectionHTML(theme: theme)
		}

		let substitutions = [
			"title": rendering.title,
			"baseURL": rendering.baseURL,
			"style": rendering.style,
			"body": rendering.html
		]
		Self.logger.debug("renderPage: articleID=\(self.article?.articleID ?? "nil", privacy: .public) windowScrollY=\(self.windowScrollY, privacy: .public) bodyLength=\(rendering.html.count, privacy: .public)")
		// WKWebView fires a scrollViewDidScroll with contentOffset reset to (0,0)
		// as part of committing a fresh loadHTMLString, before the injected
		// scroll-restore script (see WebViewConfiguration.installArticleScripts)
		// has had a chance to run or settle. Without this guard, that native
		// reset (or one of the restore script's own attempts sampled before the
		// document has reached its final height) gets picked up by
		// scrollPositionDidChange as if it were a real scroll and immediately
		// overwrites the just-restored position -- confirmed in device logs as
		// the actual mechanism behind "reopening resets to the top." Discard all
		// scrollPositionDidChange samples until the scrollRestoreComplete
		// message confirms the restore script's own multi-point restore
		// (DOMContentLoaded / load / fonts.ready / ResizeObserver-driven
		// reflows) has settled; a failsafe timer below clears this if that
		// message never arrives.
		isRestoringScrollPosition = true
		maxObservedScrollHeight = 0
		scrollRestoreFailsafeWorkItem?.cancel()
		let failsafe = DispatchWorkItem { [weak self] in
			guard let self else { return }
			Self.logger.debug("scrollRestoreComplete: failsafe fired, message never arrived, clearing isRestoringScrollPosition")
			self.isRestoringScrollPosition = false
		}
		scrollRestoreFailsafeWorkItem = failsafe
		DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: failsafe)

		var html = try! MacroProcessor.renderedText(withTemplate: ArticleRenderer.page.html, substitutions: substitutions)
		html = ArticleRenderingSpecialCases.filterHTMLIfNeeded(baseURL: rendering.baseURL, html: html)

		// Uncomment when you want to debug HTML and CSS for an article.
		// If you’re running in the simulator, this will write the file to a location on your Mac.
//		let debugFolderURL = AppConfig.dataSubfolder(named: "debug")
//		let fileURL = debugFolderURL.appendingPathComponent("article.html")
//		try? html.write(to: fileURL, atomically: true, encoding: .utf8)
//		print("article.html written to \(fileURL.path)")

		WebViewConfiguration.addContentBlockingRules(to: webView)
		WebViewConfiguration.installArticleScripts(in: webView, windowScrollY: windowScrollY, generation: loadWebViewGeneration)
		webView.loadHTMLString(html, baseURL: URL(string: rendering.baseURL))
	}

	func finalScrollPosition(scrollingUp: Bool) -> CGFloat {
		guard let webView = webView else { return 0 }

		if scrollingUp {
			return -webView.scrollView.safeAreaInsets.top
		} else {
			return webView.scrollView.contentSize.height - webView.scrollView.bounds.height + webView.scrollView.safeAreaInsets.bottom
		}
	}

	func reloadArticleImage() {
		guard let article = article else { return }

		var components = URLComponents()
		components.scheme = ArticleRenderer.imageIconScheme
		components.path = article.articleID

		if let imageSrc = components.string {
			webView?.evaluateJavaScript("reloadArticleImage(\"\(imageSrc)\")")
		}
	}

	func imageWasClicked(body: String?) {
		guard let webView, let body else { return }

		let data = Data(body.utf8)
		guard let clickMessage = try? JSONDecoder().decode(ImageClickMessage.self, from: data) else {
			return
		}

		guard let imageURL = URL(string: clickMessage.imageURL) else { return }

		Downloader.shared.download(imageURL) { [weak self] downloadResponse, error in
			guard let self, let data = downloadResponse.data, error == nil, !data.isEmpty,
				  let image = UIImage(data: data) else {
				return
			}
			self.showFullScreenImage(image: image, clickMessage: clickMessage, webView: webView)
		}
	}

	private func showFullScreenImage(image: UIImage, clickMessage: ImageClickMessage, webView: WKWebView) {

		let y = CGFloat(clickMessage.y) + webView.safeAreaInsets.top
		let rect = CGRect(x: CGFloat(clickMessage.x), y: y, width: CGFloat(clickMessage.width), height: CGFloat(clickMessage.height))
		transition.originFrame = webView.convert(rect, to: nil)

		if navigationController?.navigationBar.isHidden ?? false {
			transition.maskFrame = webView.convert(webView.frame, to: nil)
		} else {
			transition.maskFrame = webView.convert(webView.safeAreaLayoutGuide.layoutFrame, to: nil)
		}

		transition.originImage = image

		coordinator.showFullScreenImage(image: image, imageTitle: clickMessage.imageTitle, transitioningDelegate: self)
	}

	func stopMediaPlayback(_ webView: WKWebView) {
		webView.evaluateJavaScript("stopMediaPlayback();")
	}

	func cancelImageLoad(_ webView: WKWebView) {
		webView.evaluateJavaScript("cancelImageLoad();")
	}

	func configureTopShowBarsView() {
		topShowBarsView = UIView()
		topShowBarsView.backgroundColor = .clear
		topShowBarsView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(topShowBarsView)

		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			topShowBarsViewConstraint = view.topAnchor.constraint(equalTo: topShowBarsView.bottomAnchor, constant: -44.0)
		} else {
			topShowBarsViewConstraint = view.topAnchor.constraint(equalTo: topShowBarsView.bottomAnchor, constant: 0.0)
		}

		NSLayoutConstraint.activate([
			topShowBarsViewConstraint,
			view.leadingAnchor.constraint(equalTo: topShowBarsView.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: topShowBarsView.trailingAnchor),
			topShowBarsView.heightAnchor.constraint(equalToConstant: 44.0)
		])
		topShowBarsView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showBars(_:))))
	}

	func configureBottomShowBarsView() {
		bottomShowBarsView = UIView()
		bottomShowBarsView.backgroundColor = .clear
		bottomShowBarsView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(bottomShowBarsView)
		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			bottomShowBarsViewConstraint = view.bottomAnchor.constraint(equalTo: bottomShowBarsView.topAnchor, constant: 44.0)
		} else {
			bottomShowBarsViewConstraint = view.bottomAnchor.constraint(equalTo: bottomShowBarsView.topAnchor, constant: 0.0)
		}
		NSLayoutConstraint.activate([
			bottomShowBarsViewConstraint,
			view.leadingAnchor.constraint(equalTo: bottomShowBarsView.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: bottomShowBarsView.trailingAnchor),
			bottomShowBarsView.heightAnchor.constraint(equalToConstant: 44.0)
		])
		bottomShowBarsView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showBars(_:))))
	}

	func updateBottomSafeAreaForFullScreen() {
		let rawBottom = view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom
		additionalSafeAreaInsets.bottom = -rawBottom
	}

	/// Hide or show the toolbar scroll edge effect at the bottom of the web view.
	///
	/// Hidden when entering fullscreen so a residual effect doesn't obscure the
	/// bottom of the article.
	///
	/// <https://github.com/Ranchero-Software/NetNewsWire/issues/5298>
	func setBottomScrollEdgeEffectHidden(_ hidden: Bool) {
		guard #available(iOS 26, *) else {
			return
		}
		guard let scrollView = webView?.scrollView else {
			return
		}
		scrollView.bottomEdgeEffect.isHidden = hidden
	}

	func configureContextMenuInteraction() {
		if isFullScreenAvailable {
			if navigationController?.isNavigationBarHidden ?? false {
				webView?.addInteraction(contextMenuInteraction)
			} else {
				webView?.removeInteraction(contextMenuInteraction)
			}
		}
	}

	func contextMenuPreviewProvider() -> UIViewController {
		let previewProvider = UIStoryboard.main.instantiateController(ofType: ContextMenuPreviewViewController.self)
		previewProvider.article = article
		return previewProvider
	}

	func prevArticleAction() -> UIAction? {
		guard coordinator.isPrevArticleAvailable else { return nil }
		let title = NSLocalizedString("Previous Article", comment: "Previous Article")
		return UIAction(title: title, image: Assets.Images.prevArticle) { [weak self] _ in
			self?.coordinator.selectPrevArticle()
		}
	}

	func nextArticleAction() -> UIAction? {
		guard coordinator.isNextArticleAvailable else { return nil }
		let title = NSLocalizedString("Next Article", comment: "Next Article")
		return UIAction(title: title, image: Assets.Images.nextArticle) { [weak self] _ in
			self?.coordinator.selectNextArticle()
		}
	}

	func toggleReadAction() -> UIAction? {
		guard let article = article, !article.status.read || article.isAvailableToMarkUnread else { return nil }

		let title = article.status.read ? NSLocalizedString("Mark as Unread", comment: "Command") : NSLocalizedString("Mark as Read", comment: "Command")
		let readImage = article.status.read ? Assets.Images.circleClosed : Assets.Images.circleOpen
		return UIAction(title: title, image: readImage) { [weak self] _ in
			self?.coordinator.toggleReadForCurrentArticle()
		}
	}

	func toggleStarredAction() -> UIAction {
		let starred = article?.status.starred ?? false
		let title = starred ? NSLocalizedString("Remove from Read Later", comment: "Command") : NSLocalizedString("Add to Read Later", comment: "Command")
		let starredImage = starred ? Assets.Images.starOpen : Assets.Images.starClosed
		return UIAction(title: title, image: starredImage) { [weak self] _ in
			self?.coordinator.toggleStarredForCurrentArticle()
		}
	}

	func toggleLovedAction() -> UIAction {
		let loved = article?.status.loved ?? false
		let title = loved ? NSLocalizedString("Remove from Loved", comment: "Command") : NSLocalizedString("Add to Loved", comment: "Command")
		let lovedImage = loved ? Assets.Images.heartOpen : Assets.Images.heartClosed
		return UIAction(title: title, image: lovedImage) { [weak self] _ in
			self?.coordinator.toggleLovedForCurrentArticle()
		}
	}

	func nextUnreadArticleAction() -> UIAction? {
		guard coordinator.isNextUnreadAvailable else { return nil }
		let title = NSLocalizedString("Next Unread Article", comment: "Next Unread Article")
		return UIAction(title: title, image: Assets.Images.nextUnread) { [weak self] _ in
			self?.coordinator.selectNextUnread()
		}
	}

	func shareAction() -> UIAction {
		let title = NSLocalizedString("Share", comment: "Share button")
		return UIAction(title: title, image: Assets.Images.share) { [weak self] _ in
			self?.showActivityDialog()
		}
	}

	// If the resource cannot be opened with an installed app, present the web view.
	func openURL(_ url: URL) {
		UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { didOpen in
			assert(Thread.isMainThread)
			guard didOpen == false else {
				return
			}
			self.openURLInSafariViewController(url)
		}
	}

	func openURLInSafariViewController(_ url: URL) {
		guard let viewController = SFSafariViewController.safeSafariViewController(url) else {
			return
		}
		present(viewController, animated: true)
	}
}

// MARK: Find in Article

private struct FindInArticleOptions: Codable {
	var text: String
	var caseSensitive = false
	var regex = false
}

internal struct FindInArticleState: Codable {
	struct WebViewClientRect: Codable {
		let x: Double
		let y: Double
		let width: Double
		let height: Double
	}

	struct FindInArticleResult: Codable {
		let rects: [WebViewClientRect]
		let bounds: WebViewClientRect
		let index: UInt
		let matchGroups: [String]
	}

	let index: UInt?
	let results: [FindInArticleResult]
	let count: UInt
}

extension WebViewController {

	func searchText(_ searchText: String, completionHandler: @escaping (FindInArticleState) -> Void) {
		guard let json = try? JSONEncoder().encode(FindInArticleOptions(text: searchText)) else {
			return
		}
		let encoded = json.base64EncodedString()

		webView?.evaluateJavaScript("updateFind(\"\(encoded)\")") { (result, error) in
			guard error == nil,
				let b64 = result as? String,
				let rawData = Data(base64Encoded: b64),
				let findState = try? JSONDecoder().decode(FindInArticleState.self, from: rawData) else {
					return
			}

			completionHandler(findState)
		}
	}

	func endSearch() {
		webView?.evaluateJavaScript("endFind()")
	}

	func selectNextSearchResult() {
		webView?.evaluateJavaScript("selectNextResult()")
	}

	func selectPreviousSearchResult() {
		webView?.evaluateJavaScript("selectPreviousResult()")
	}

}
