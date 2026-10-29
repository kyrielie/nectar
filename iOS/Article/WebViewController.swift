import AO3Kit
//
//  WebViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 12/28/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import SwiftUI
@preconcurrency import WebKit
import RSCore
import RSWeb
import Account
import Articles
import AnnotationsKit
import SafariServices
import MessageUI
import Images
import os
import ArticleTheming

final class WebViewController: UIViewController {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "WebViewController")

	private struct MessageName {
		static let imageWasClicked = "imageWasClicked"
		static let imageWasShown = "imageWasShown"
		static let showFeedInspector = "showFeedInspector"
		static let debugLog = "debugLog"
		static let scrollRestoreComplete = "scrollRestoreComplete"
		static let textWasSelected = "textWasSelected"
		static let annotationWasTapped = "annotationWasTapped"
	}

	// Private scheme for AO3PrefaceRenderer's inline series nav links
	// (`nectar-series:<direction>?ao3id=...&workurl=...`), handled in
	// decidePolicyFor navigationAction. See docs/ao3-feeds.md.
	private static let nectarSeriesScheme = "nectar-series"

	var topShowBarsView: UIView!
	var bottomShowBarsView: UIView!
	var topShowBarsViewConstraint: NSLayoutConstraint!
	var bottomShowBarsViewConstraint: NSLayoutConstraint!

	// Notch mask and page counter for fullscreen reading (see
	// updateNotchAndPageCounterVisibility for the visibility rules). Unlike
	// topShowBarsView, an invisible tap target moved off-screen in fullscreen,
	// the cover is a persistent mask over the notch itself.
	var notchCoverView: UIView!
	var notchCoverViewHeightConstraint: NSLayoutConstraint!
	var pageCounterLabel: UILabel!
	var readingTimePieIndicatorView: ReadingTimePieIndicatorView!

	// The single authoritative reference to the current webview. Not derived from
	// view.subviews[0], which could return the wrong view if two were ever
	// inserted (see loadWebViewGeneration).
	var webView: PreloadedWebView?

	/// Non-nil (view coordinates) only in .nativeMenu mode while a live, non-empty
	/// selection exists. Set/cleared in textWasSelected(body:); backs
	/// isSelectionHighlightable, which buildMenu(with:) uses to decide whether to
	/// offer "Highlight". Stays nil in .popup/.off.
	var currentSelectionRect: CGRect?

	/// Backing storage for awaitNextPageLoad(), resumed from webView(_:didFinish:).
	/// An array so concurrent awaiters are all resumed rather than one dropped.
	var nextPageLoadContinuations: [CheckedContinuation<Void, Never>] = []

	// Per-(series, direction) in-flight/failure state for the inline series nav
	// links. Keyed on SeriesNavKey so different series' links (or one series'
	// Previous and Next) can be in flight or failed independently. Reset when
	// `article` changes. See docs/ao3-feeds.md and handleNectarSeriesLink.
	private struct SeriesNavKey: Hashable {
		let ao3SeriesID: String
		let direction: AO3SeriesNavigator.Direction
	}
	private enum SeriesNavState {
		case inFlight
		case failed(String)
	}
	private var seriesNavState: [SeriesNavKey: SeriesNavState] = [:]

	// Bumped on every loadWebView() call and captured by each dequeue/ready
	// completion, so a completion arriving after a newer call can detect it is
	// stale and bail out. Closes a race where viewDidLoad's loadWebView
	// (windowScrollY still 0) and setArticle's post-scroll-fetch loadWebView each
	// saw webView == nil and each inserted a webview; which one ended up on top
	// was timing-dependent.
	var loadWebViewGeneration = 0

	lazy var contextMenuInteraction = UIContextMenuInteraction(delegate: self)
	var isFullScreenAvailable: Bool {
		return AppDefaults.shared.articleFullscreenAvailable && traitCollection.userInterfaceIdiom == .phone
	}
	private lazy var articleIconSchemeHandler = ArticleIconSchemeHandler(coordinator: coordinator)
	private lazy var transition = ImageTransition(controller: self)
	private var clickedImageCompletion: (() -> Void)?

	weak var coordinator: SceneCoordinator!

	/// Fired once per successful auto-apply pass (see applyTextReplacementRulesIfNeeded)
	/// with the number of rows written, so ArticleViewController can show the summary
	/// banner. A plain closure, matching the other WebViewController callbacks in
	/// this feature. nil means no banner host, so the pass has no visible summary.
	var onTextReplacementReplacementsApplied: ((Int) -> Void)?

	private(set) var article: Article? {
		didSet {
			// A different work has its own separate prev/next/first state --
			// don't carry over another article's in-flight/error state.
			if article?.articleID != oldValue?.articleID {
				seriesNavState.removeAll()
			}
		}
	}

	let scrollPositionQueue = CoalescingQueue(name: "Article Scroll Position", interval: 0.3, maxInterval: 0.3)

	// Last scroll position / reading progress confirmed via the JS bridge in
	// scrollPositionDidChange(). Plain properties so viewWillDisappear can flush a
	// final save synchronously, without an async JS round trip racing teardown.
	var lastKnownReadingProgress: Double?
	// Diagnostic only (traces duplicate renderPage reports); loadWebViewGeneration gates behavior.
	private var loadWebViewCallCount = 0
	// True from the start of renderPage() until page.html reports
	// (scrollRestoreComplete) that its multi-point scroll restore has settled.
	// While true, scroll samples are noise (WKWebView's native reset to (0,0), or
	// restore attempts before the document reaches final height) and must not be
	// written to windowScrollY or persisted.
	var isRestoringScrollPosition = false

	// True while the rendered content is a not-yet-fetched AO3 stub (see
	// isProvisionalAO3Stub) or a fetched chapter is being swapped in. Scroll
	// samples then don't reflect the real document and must not be recorded as
	// progress or Reading Stats credit; see scrollPositionDidChange.
	var isContentProvisional = false

	// Safety net so scroll saves aren't blocked forever if page.html's completion
	// message never arrives (JS error, print preview, etc.).
	var scrollRestoreFailsafeWorkItem: DispatchWorkItem?

	// Per-load high-water mark of document height. Defense in depth against
	// persisting a sample taken against a shorter-than-final document after
	// isRestoringScrollPosition clears (e.g. a late embed reflow). Reset in renderPage.
	var maxObservedScrollHeight: Double = 0

	// Set by setArticle before its async scroll-position fetch and cleared just
	// before that Task calls loadWebView. While true, viewDidLoad skips its own
	// loadWebView so the first render uses the restored windowScrollY, instead of
	// rendering at 0 and then re-rendering (where reset suppression could race and
	// save 0 over the real position).
	private var isAwaitingInitialScrollFetch = false

	/// Session-only stack of pre-jump windowScrollY values, pushed before each
	/// programmatic jump (scrollToHeading, scrollToAnnotation); see scrollBack().
	/// Large manual scroll deltas are not detected as jumps (docs/reading-progress.md).
	var scrollJumpHistory: [Double] = []

	/// URL the current page was loaded with (set in renderPage). nil when the article has no
	/// usable base URL. Used to recognise links that only change the fragment (same-document).
	private var renderedDocumentURL: URL?

	var windowScrollY = 0 {
		didSet {
			// Persists per article (relaunch and Handoff restore read this per-book value).
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
		NotificationCenter.default.addObserver(self, selector: #selector(ao3ChapterFetchDidComplete(_:)), name: .ao3ChapterFetchDidComplete, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(ao3ChapterFetchDidFail(_:)), name: .ao3ChapterFetchDidFail, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(statusesDidChange(_:)), name: .StatusesDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(accountDidDownloadArticles(_:)), name: .AccountDidDownloadArticles, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(highlightPaletteDidChange(_:)), name: .highlightPaletteDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(readingTimeUsageDidChange(_:)), name: .readingTimeUsageDidChange, object: nil)

		// Re-resolve the native colors (webView background, notchCoverView,
		// pageCounterLabel) on an Appearance change while an article is open. The
		// article CSS repaints itself via prefers-color-scheme, but these colors
		// otherwise only re-resolved on the next renderPage.
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: WebViewController, previousTraitCollection: UITraitCollection) in
			guard self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle else {
				return
			}
			self.applyResolvedBackgroundColors()
		}

		// Configure the tap zones
		configureTopShowBarsView()
		configureBottomShowBarsView()
		configureNotchCoverView()
		// Without this, notchCoverView stays hidden (its default) until the first
		// showBars()/hideBars(), which for a freshly paged-in article can land a frame
		// or more after the view is on screen, flashing the bare notch on every page turn.
		//
		// Pass the resolved colors explicitly: renderPage() hasn't run and webView is
		// still nil, so updateNotchAndPageCounterVisibility has nothing to reuse and
		// the cover would show the surrounding chrome instead of the theme background.
		// Reading self.traitCollection is safe here since the view is loaded (see
		// article-color-pipeline.md).
		let initialColors = Self.resolvedArticleColors(isDark: traitCollection.userInterfaceStyle == .dark)
		updateNotchAndPageCounterVisibility(resolvedBackground: initialColors.background, resolvedText: initialColors.text)

		if !isAwaitingInitialScrollFetch {
			loadWebView(reason: "viewDidLoad")
		}
		if isFullScreenAvailable && AppDefaults.shared.logicalArticleFullscreenEnabled {
			updateBottomSafeAreaForFullScreen()
		}
	}

	// Self-heals a cold-launch background inversion. viewDidLoad's initialColors
	// read and applyResolvedBackgroundColors() (from renderPage) both resolve
	// against self's traitCollection, which during state restoration may not have
	// settled: the restored article is pushed from
	// SceneDelegate.scene(_:willConnectTo:options:) before the window is key. A wrong
	// read disagrees with WKWebView's own prefers-color-scheme and nothing corrects
	// it, since registerForTraitChanges only fires on a change. Most visible on
	// themes with no explicit body background (e.g. Broadsheet), whose light and
	// dark fallbacks are opposites; see article-color-pipeline.md.
	//
	// viewDidAppear is the first point guaranteed to run with the view on screen in
	// a key window. Re-resolving here is a no-op when the earlier read was right.
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		applyResolvedBackgroundColors()
	}

	// notchCoverView's height is the top safe-area inset. The top inset is no longer
	// cancelled in full-screen reading (matching upstream NetNewsWire), so the page
	// starts directly below the cover at scroll position 0 and themes need no
	// clearance padding. additionalSafeAreaInsets.top is always 0 now; the subtraction
	// is kept as a harmless guard. UIKit also calls this on the first safe-area
	// establishment, so viewDidLoad needs no separate call.
	override func viewSafeAreaInsetsDidChange() {
		super.viewSafeAreaInsetsDidChange()
		let rawTop = view.safeAreaInsets.top - additionalSafeAreaInsets.top
		notchCoverViewHeightConstraint?.constant = rawTop
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		// Flush the final scroll position/reading progress before the view goes away.
		// Don't re-enter the JS bridge: performCallsImmediately() only fires the timer
		// early, and scrollPositionDidChange() still does an async evaluateJavaScript,
		// so a fast pop (or the pooled webView being dequeued for the next article)
		// could drop the save or land it on the wrong article. windowScrollY and
		// lastKnownReadingProgress already hold the last confirmed values, so save
		// those synchronously and drop whatever is pending in the queue.
		scrollPositionQueue.cancelPendingCalls()
		flushLastKnownScrollState()
		// Pause media before dismissal: a playing video can trigger a RELEASE_ASSERT in
		// WebFullScreenManagerProxy on iOS 26 when full-screen entry fires on a stale hierarchy.
		stopWebViewActivity()
		// Stop Reading Stats accruing against this book while the person is elsewhere in the app.
		ReadingStatsTracker.shared.setArticle(nil)
	}

	// MARK: Notifications

	@objc func handleSceneDidEnterBackground(_ notification: Notification) {
		// A share sheet popover on iPad is orphaned if opening another browser
		// backgrounds the app mid-presentation; dismiss it on backgrounding. (#4269)
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

	@objc func ao3ChapterFetchDidComplete(_ note: Notification) {
		guard let fetchedArticleID = note.userInfo?[AO3ChapterFetchUserInfoKey.articleID] as? String,
		      let article, article.articleID == fetchedArticleID, let account = article.account else {
			return
		}
		Task {
			// Re-fetch rather than mutate: Article's stored properties are immutable.
			let refetchedArticles = await account.fetchArticlesAsync(.articleIDs([fetchedArticleID]))
			guard let refetchedArticle = refetchedArticles.first, self.article?.articleID == fetchedArticleID else {
				return
			}
			self.article = refetchedArticle
			// Provisional until scrollRestoreComplete confirms the new content settled.
			self.isContentProvisional = true
			self.loadWebView(reason: "ao3ChapterFetchDidComplete(\(fetchedArticleID))")
			// Also fires when the result was a regression stashed as a pending update;
			// offer the review prompt in that case.
			self.presentPendingContentUpdateAlertIfNeeded()
		}
	}

	/// Re-anchoring's second hook point (the first is ao3ChapterFetchDidComplete).
	/// Any ordinary content update (feed refresh, Ambrosia re-export, a chapter fetch
	/// that didn't trip the regression guard) skips the pending-confirmation UI and
	/// carries no notification of its own. All of them fire AccountDidDownloadArticles,
	/// so this catches them generically.
	///
	/// Re-anchoring itself runs in loadAndRenderAnnotations once loadWebView
	/// re-renders. This only notices that the displayed article's contentHTML changed
	/// and reloads it. Articles not currently open re-anchor the next time they open.
	@objc func accountDidDownloadArticles(_ note: Notification) {
		guard let article, let updatedArticles = note.userInfo?[Account.UserInfoKey.updatedArticles] as? Set<Article>,
		      let updatedArticle = updatedArticles.first(where: { $0.articleID == article.articleID }) else {
			return
		}
		// The incoming article can carry nil contentHTML for an update that didn't touch
		// it (changesFrom only writes non-nil). Reload only on a real difference, not on
		// unrelated changes (kudos/comment/bookmark counts) this notification also covers.
		guard let newContentHTML = updatedArticle.contentHTML, newContentHTML != article.contentHTML else {
			return
		}
		let articleID = article.articleID
		guard let account = article.account else { return }
		Task {
			let refetchedArticles = await account.fetchArticlesAsync(.articleIDs([articleID]))
			guard let refetchedArticle = refetchedArticles.first, self.article?.articleID == articleID else {
				return
			}
			self.article = refetchedArticle
			self.loadWebView(reason: "accountDidDownloadArticles(\(articleID))")
		}
	}

	/// The full-screen context menu's toggle actions persist asynchronously, so
	/// rebuilding the menu right after firing them would read `self.article` before
	/// the write lands and show the pre-toggle state. Rebuild from .StatusesDidChange,
	/// which fires once the write is done (as ArticleViewController's toolbar does).
	@objc func statusesDidChange(_ note: Notification) {
		guard let articleIDs = note.userInfo?[Account.UserInfoKey.articleIDs] as? Set<String> else {
			return
		}
		guard let article else {
			return
		}
		if articleIDs.contains(article.articleID) {
			refreshVisibleContextMenu()
			// Push star/love to the page's #nectarState marker; a re-render would lose
			// scroll position and annotation overlays. `restricted` has no live path:
			// it only changes via a chapter fetch, which re-renders.
			webView?.evaluateJavaScript("setNectarState({starred: \(article.status.starred), loved: \(article.status.loved)})")
		}
	}

	@objc func ao3ChapterFetchDidFail(_ note: Notification) {
		// The Article itself hasn't changed (contentHTML is left alone on failure), so
		// just re-render; ArticleRenderer reads the failure message from AO3ChapterFetcher.
		guard let fetchedArticleID = note.userInfo?[AO3ChapterFetchUserInfoKey.articleID] as? String,
		      let article, article.articleID == fetchedArticleID else {
			return
		}
		loadWebView(reason: "ao3ChapterFetchDidFail(\(fetchedArticleID))")
	}

	// MARK: API

	/// True for an AO3-sourced article still on an RSS/Atom stub (`contentHTML`
	/// nil/empty). Scroll/progress samples are withheld until the real content swaps
	/// in (see ao3ChapterFetchDidComplete). Internal for direct testing; see
	/// WebViewControllerAppearanceToggleTests.swift.
	static func isProvisionalAO3Stub(_ article: Article?) -> Bool {
		guard let article, AO3Link.workID(fromBookKey: article.bookKey) != nil else { return false }
		return (article.contentHTML?.isEmpty ?? true)
	}

	func setArticle(_ article: Article?, updateView: Bool = true) {
		if article != self.article {
			self.article = article
			ReadingStatsTracker.shared.setArticle(article)
			isContentProvisional = Self.isProvisionalAO3Stub(article)
			if updateView {
				guard let article = article, let account = article.account else {
					windowScrollY = 0
					loadWebView(reason: "setArticle(nil)")
					return
				}
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
					// Fire-and-forget; no-op unless this is an AO3 article with stale content.
					AO3ChapterFetcher.shared.fetchIfNeeded(for: article)
					// Also offer the pending-update prompt on open, not just after a fresh fetch.
					self.presentPendingContentUpdateAlertIfNeeded()
				}
			}
		}
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

	func stopWebViewActivity() {
		if let webView = webView {
			stopMediaPlayback(webView)
			cancelImageLoad(webView)
		}
	}

	/// Prompt shown when the article has an unresolved pendingUpdateContentHTML (a newer
	/// version that looks smaller). Accepting promotes it to contentHTML, keeping discards
	/// it, both via Account.resolvePendingContentUpdateAsync, which also re-enables the
	/// AO3FetchPolicy.isStale auto-fetch gate.
	func presentPendingContentUpdateAlertIfNeeded() {
		guard let article, article.pendingUpdateContentHTML != nil, let account = article.account else {
			return
		}
		let articleID = article.articleID
		let alert = UIAlertController(
			title: NSLocalizedString("Possible Content Change", comment: "Title"),
			message: NSLocalizedString("A newer version of this work was fetched, but it looks smaller than what's archived -- this can happen on a real edit, or on a deleted/shrunk chapter. Use the new version, or keep what's archived?", comment: "Message"),
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("Use New Version", comment: "Command"), style: .default) { [weak self] _ in
			self?.resolvePendingContentUpdate(accept: true, account: account, articleID: articleID)
		})
		alert.addAction(UIAlertAction(title: NSLocalizedString("Keep Archived Version", comment: "Command"), style: .default) { [weak self] _ in
			self?.resolvePendingContentUpdate(accept: false, account: account, articleID: articleID)
		})
		alert.addAction(UIAlertAction(title: NSLocalizedString("Later", comment: "Command"), style: .cancel))
		present(alert, animated: true)
	}

	private func resolvePendingContentUpdate(accept: Bool, account: Account, articleID: String) {
		Task {
			await account.resolvePendingContentUpdateAsync(forArticleID: articleID, accept: accept)
			let refetchedArticles = await account.fetchArticlesAsync(.articleIDs([articleID]))
			guard let refetchedArticle = refetchedArticles.first, self.article?.articleID == articleID else {
				return
			}
			self.article = refetchedArticle
			self.loadWebView(reason: "resolvePendingContentUpdate(\(articleID))")
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
			openURLInAppBrowser(url)
		}
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
		initAnnotations()
		applyHighlightPaletteColors()
		Task {
			await self.applyTextReplacementRulesIfNeeded()
			self.loadAndRenderAnnotations()
		}
		resumeAwaitingPageLoads()
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		Self.logger.debug("webView didFail navigation for articleID=\(self.article?.articleID ?? "nil", privacy: .public) error=\(error.localizedDescription, privacy: .public)")
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		Self.logger.debug("webView didFailProvisionalNavigation for articleID=\(self.article?.articleID ?? "nil", privacy: .public) error=\(error.localizedDescription, privacy: .public)")
	}

	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {

		if navigationAction.navigationType == .linkActivated {
			let url = navigationAction.request.url

			// nectar-series: links are app-internal navigation, not what disableArticleLinks
			// guards, so handle them before that early return.
			if url?.scheme == Self.nectarSeriesScheme {
				decisionHandler(.cancel)
				if let url {
					handleNectarSeriesLink(url)
				}
				return
			}

			// Links that only change the fragment (AO3's "more notes" pointer, footnote-style
			// anchors) are navigation inside the article, not what disableArticleLinks guards.
			// WebKit hands them over as absolute URLs equal to the base URL plus a fragment, so
			// without this they would match the http(s) branch below and open the browser.
			if let url, Self.isSameDocumentFragmentNavigation(url: url, documentURL: renderedDocumentURL) {
				decisionHandler(.cancel)
				handleSameDocumentAnchor(url)
				return
			}

			if AppDefaults.shared.disableArticleLinks {
				decisionHandler(.cancel)
				return
			}

			guard let url else {
				decisionHandler(.allow)
				return
			}

			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
			if components?.scheme == "http" || components?.scheme == "https" {
				decisionHandler(.cancel)
				openExternalLink(url)

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
		// An unimplemented WKUIDelegate must be assigned so tapping a link preview
		// launches Safari. elementInfo's link is always nil, so SFSafariViewController
		// isn't an option.
	}

	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		// nectar-series: links are never target="_blank", so this shouldn't be reachable;
		// block anyway. Taps are handled only in decidePolicyFor navigationAction.
		if navigationAction.request.url?.scheme == Self.nectarSeriesScheme {
			return nil
		}

		if AppDefaults.shared.disableArticleLinks {
			return nil
		}

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
			// Bridges page.html's console output to os.Logger, which console.log doesn't reach.
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
			// Reconcile with where the page settled (e.g. clamped to max scroll if the
			// article got shorter than the saved position).
			windowScrollY = reportedScrollY
			// Content settled: clear the provisional guard and refresh Reading Stats' snapshot
			// so an AO3 stub-to-chapter swap uses the real word count/tags and restarts the
			// session from the restored position.
			isContentProvisional = false
			if let article {
				ReadingStatsTracker.shared.setArticle(article)
			}
		case MessageName.textWasSelected:
			textWasSelected(body: message.body as? [String: Any])
		case MessageName.annotationWasTapped:
			annotationWasTapped(body: message.body as? [String: Any])
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

				// A newer loadWebView() has started (typically viewDidLoad's call losing the race
				// with setArticle's post-scroll-fetch call): discard this webview rather than
				// insert a second one. The winning generation's completion renders the page.
				guard generation == self.loadWebViewGeneration else {
					Self.logger.debug("loadWebView: discarding stale completion, generation=\(generation, privacy: .public) currentGeneration=\(self.loadWebViewGeneration, privacy: .public) reason=\(reason, privacy: .public)")
					return
				}

				// Remove any older webview (e.g. replaceExistingWebView) so only one is ever in the hierarchy.
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

				// UISplitViewController reports the wrong size to WKWebView, causing horizontal
				// rubberbanding on iPad that interferes with the UIPageViewController swipe.
				webView.scrollView.contentInset = UIEdgeInsets(top: 0, left: -1, bottom: 0, right: 0)

				webView.scrollView.setZoomScale(1.0, animated: false)

				// Tapping the status bar would scrollsToTop and discard the reader's place. The
				// webview is pooled, so this is reasserted on every dequeue, as are the settings below.
				webView.scrollView.scrollsToTop = false

				// updateScrollbarVisibility() reads articleScrollbarVisibility fresh, so a Settings
				// change applies on the next open, and .whenNotFullScreen re-evaluates live in
				// showBars()/hideBars().
				self.updateScrollbarVisibility()

				// Belt-and-suspenders alongside page.html's viewport-meta zoom restriction, which
				// is inconsistent across WKWebView versions/content types.
				webView.scrollView.pinchGestureRecognizer?.isEnabled = false

				self.view.setNeedsLayout()
				self.view.layoutIfNeeded()

				// Configure the webview
				webView.navigationDelegate = self
				webView.uiDelegate = self
				webView.scrollView.delegate = self
				// Reasserted per dequeue (the webview is shared across controllers). Backs
				// buildMenu(with:)'s native-menu "Highlight" action; see PreloadedWebView.swift.
				webView.annotationMenuDelegate = self
				self.configureContextMenuInteraction()

				// Remove possible existing message handlers
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.imageWasClicked)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.imageWasShown)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.showFeedInspector)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.debugLog)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.scrollRestoreComplete)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.textWasSelected)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.annotationWasTapped)

				// Add handlers
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.imageWasClicked)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.imageWasShown)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.showFeedInspector)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.debugLog)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.scrollRestoreComplete)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.textWasSelected)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.annotationWasTapped)

				self.renderPage(webView)
			}
		}
	}

	func renderPage(_ webView: PreloadedWebView?) {
		guard let webView = webView else { return }

		// New HTML means no selection: clear any tracked rect so a stale one doesn't make
		// isSelectionHighlightable offer "Highlight" with nothing live to resolve against.
		currentSelectionRect = nil

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
			"importStyle": rendering.importStyle,
			"style": rendering.style,
			"body": rendering.html,
			// Device-locale fallback (no per-feed/article language is parsed). Needed so
			// `hyphens: auto` picks the right WebKit hyphenation dictionary; page.html had no
			// lang attribute before.
			"lang": ArticlePageComposer.defaultLang
		]
		Self.logger.debug("renderPage: articleID=\(self.article?.articleID ?? "nil", privacy: .public) windowScrollY=\(self.windowScrollY, privacy: .public) bodyLength=\(rendering.html.count, privacy: .public)")
		// WKWebView fires scrollViewDidScroll with contentOffset reset to (0,0) while
		// committing loadHTMLString, before the scroll-restore script
		// (WebViewConfiguration.installArticleScripts) settles. Without this guard that
		// reset, or a restore attempt sampled before the document reaches final height,
		// overwrites the restored position (the cause of "reopening resets to the top").
		// Discard samples until scrollRestoreComplete arrives; the failsafe below clears
		// it if that message never does.
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

		// To debug article HTML/CSS, write `html` to a file (e.g. under AppConfig.dataSubfolder(named: "debug")).

		WebViewConfiguration.addContentBlockingRules(to: webView)
		WebViewConfiguration.installArticleScripts(in: webView, windowScrollY: windowScrollY, generation: loadWebViewGeneration)

		applyResolvedBackgroundColors()

		renderedDocumentURL = rendering.baseURL.isEmpty ? nil : URL(string: rendering.baseURL)
		webView.loadHTMLString(html, baseURL: URL(string: rendering.baseURL))
	}

	// Resolve the theme's background before loadHTMLString commits, so there is no
	// flash of the default .systemBackground (near-black in dark mode; see
	// PreloadedWebView.init). Precedence: override background, then the theme's
	// background from ArticleThemeColorStore (measured value if cached, else the
	// legacy scanner, whose black/white fallback applies last).
	//
	// Also re-run on its own (no reload) from the registerForTraitChanges handler in
	// viewDidLoad, since these native colors otherwise go stale until the next
	// renderPage. See article-color-pipeline.md.
	private func applyResolvedBackgroundColors() {
		guard let webView else { return }

		// Read isDark from self, not webView: the pooled PreloadedWebView is reused and
		// reattached outside the normal lifecycle, so its traitCollection can lag one
		// trait-change cycle behind. The registerForTraitChanges handler has already
		// confirmed self's is fresh. A stale read applies exactly one toggle behind (dark
		// to light shows the dark override, then back shows the light one) until a third
		// toggle resyncs.
		let isDark = Self.isDarkForColorResolution(selfTraitCollection: traitCollection, webViewTraitCollection: webView.traitCollection)
		// Pin the web view's own interface style to the same value, so its prefers-color-scheme
		// CSS and the native colors below come from one source instead of the pooled web view's
		// inherited trait (docs/article-color-pipeline.md). Re-applied on every call, so a reused
		// pooled web view is re-pinned.
		webView.overrideUserInterfaceStyle = isDark ? .dark : .light
		let colors = Self.resolvedArticleColors(isDark: isDark)
		webView.backgroundColor = colors.background
		webView.underPageBackgroundColor = colors.background
		webView.scrollView.backgroundColor = colors.background

		// Derive indicatorStyle from the resolved background's luminance. Left at its
		// default it tracks the system trait, so a dark theme in Light Mode (or a light
		// theme in Dark Mode via a per-theme override) got an indicator invisible
		// against its own track.
		webView.scrollView.indicatorStyle = Self.isPerceptuallyDark(colors.background) ? .white : .black

		updateScrollbarVisibility()

		// Keep the notch cover/page counter in sync on every render, not just the next bars toggle.
		updateNotchAndPageCounterVisibility(resolvedBackground: colors.background, resolvedText: colors.text)
	}

	/// Same 0.299/0.587/0.114 luminance weighting as BadgeColorTable.textColor(against:).
	private static func isPerceptuallyDark(_ color: UIColor) -> Bool {
		var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
		color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
		return luminance <= 0.6
	}

	/// Precedence: override background, then the theme's background from
	/// ArticleThemeColorStore (measured if cached, else the legacy scanner, whose
	/// black/white fallback applies last). Shared by
	/// applyResolvedBackgroundColors() and viewDidLoad's initial notch-cover resolution
	/// (before webView exists) so both agree. Static; the caller supplies isDark from
	/// whichever trait collection is valid at its call site.
	private static func resolvedArticleColors(isDark: Bool) -> (background: UIColor, text: UIColor) {
		return ArticleResolvedColors.current(isDark: isDark)
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

	/// Handles a tap on a `nectar-series:` link that `AO3PrefaceRenderer` builds into the
	/// preface Series row and footer: `first?ao3id=<id>` or
	/// `previous|next?ao3id=<id>&workurl=<permalink>`. For a non-hierarchical URI (no
	/// `//`), `URLComponents` puts the direction in `path`, not `host`.
	///
	/// Flow: bounded two-page series-listing walk via `AO3SeriesNavigator.openSeriesWork`,
	/// direct selection via `SceneCoordinator.selectArticleDirectly` (stays in the
	/// reader), and a JS repaint of the tapped link's text/disabled state
	/// (`updateNectarSeriesLink`) while the fetch is in flight.
	private func handleNectarSeriesLink(_ url: URL) {
		guard let article, let account = article.account else { return }
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

		let directionString = components.path
		let queryItems = components.queryItems ?? []
		let ao3ID = queryItems.first(where: { $0.name == "ao3id" })?.value
		let workURL = queryItems.first(where: { $0.name == "workurl" })?.value

		Self.logger.debug("handleNectarSeriesLink: tapped direction=\(directionString, privacy: .public) ao3ID=\(ao3ID ?? "nil", privacy: .public) workURL=\(workURL ?? "nil", privacy: .public)")

		let direction: AO3SeriesNavigator.Direction
		switch directionString {
		case "first":
			direction = .first
		case "previous":
			direction = .previous
		case "next":
			direction = .next
		default:
			Self.logger.debug("handleNectarSeriesLink: unrecognized direction '\(directionString, privacy: .public)' in \(url.absoluteString, privacy: .public)")
			return
		}

		guard let ao3ID else { return }

		// .previous/.next need the tapped link's own permalink -- it's
		// already known (Phase 2's per-span parse), no re-derivation.
		if direction != .first, workURL == nil {
			return
		}

		let key = SeriesNavKey(ao3SeriesID: ao3ID, direction: direction)

		// A fast double-tap on the same link while the first tap is
		// still in flight is a no-op, not a second fetch.
		if case .inFlight = seriesNavState[key] {
			Self.logger.debug("handleNectarSeriesLink: ignored, already in flight for ao3ID=\(ao3ID, privacy: .public) direction=\(directionString, privacy: .public)")
			return
		}

		// targetIndex only matters for .previous/.next: this article's series entry index
		// +/- 1, used to pick the listing page if openSeriesWork doesn't find it on page 1.
		// nil for .first, or if no entry matches (openSeriesWork then reports
		// .seriesListingMismatch rather than guessing a page).
		var targetIndex: Int?
		if direction != .first, let matchingEntry = article.series?.first(where: { $0.ao3ID == ao3ID }) {
			targetIndex = direction == .previous ? matchingEntry.index - 1 : matchingEntry.index + 1
		}

		seriesNavState[key] = .inFlight
		updateNectarSeriesLinkUI(key: key, disabled: true)

		Self.logger.debug("handleNectarSeriesLink: starting openSeriesWork ao3ID=\(ao3ID, privacy: .public) direction=\(directionString, privacy: .public) targetIndex=\(targetIndex.map(String.init) ?? "nil", privacy: .public)")

		Task { @MainActor in
			let result = await AO3SeriesNavigator.openSeriesWork(
				ao3SeriesID: ao3ID,
				direction: direction,
				targetWorkURL: workURL,
				targetIndex: targetIndex,
				existingArticle: article,
				account: account
			)

			// The person may have navigated away; state and repaint belong to the originating article.
			guard self.article?.articleID == article.articleID else { return }

			switch result {
			case .success(let newArticleID):
				Self.logger.debug("handleNectarSeriesLink: openSeriesWork succeeded, newArticleID=\(newArticleID, privacy: .public)")
				self.seriesNavState[key] = nil
				self.updateNectarSeriesLinkUI(key: key, disabled: false)
				await self.coordinator.selectArticleDirectly(newArticleID, account: account)
			case .failure(let error):
				self.seriesNavState[key] = .failed(error.displayMessage)
				self.updateNectarSeriesLinkUI(key: key, disabled: false)
				UIAccessibility.post(notification: .announcement, argument: error.displayMessage)
				Self.logger.debug("nectar-series link navigation failed: \(error.displayMessage, privacy: .public)")
			}
		}
	}

	/// The label AO3PrefaceRenderer rendered for this direction, restored when the
	/// fetch ends. Failure is announced via `UIAccessibility.post`, not the label.
	private func seriesNavLabel(for direction: AO3SeriesNavigator.Direction) -> String {
		switch direction {
		case .first: return NSLocalizedString("First", comment: "Inline series navigation link")
		case .previous: return NSLocalizedString("Previous", comment: "Inline series navigation link")
		case .next: return NSLocalizedString("Next", comment: "Inline series navigation link")
		}
	}

	/// Repaints every on-page occurrence of `key`'s link (it can appear in both the
	/// preface row and the footer). `seriesKey` must match the `data-nectar-series-key`
	/// format `AO3PrefaceRenderer.seriesNavKey(ao3ID:direction:)` stamps
	/// (`"<ao3ID>|<direction>"`, lowercase); kept in sync by hand.
	private struct UpdateNectarSeriesLinkOptions: Encodable {
		let seriesKey: String
		let label: String
		let disabled: Bool
	}

	private func updateNectarSeriesLinkUI(key: SeriesNavKey, disabled: Bool) {
		let directionString: String
		switch key.direction {
		case .first: directionString = "first"
		case .previous: directionString = "previous"
		case .next: directionString = "next"
		}
		let options = UpdateNectarSeriesLinkOptions(
			seriesKey: "\(key.ao3SeriesID)|\(directionString)",
			label: seriesNavLabel(for: key.direction),
			disabled: disabled
		)
		guard let json = try? JSONEncoder().encode(options) else { return }
		let encoded = json.base64EncodedString()
		webView?.evaluateJavaScript("updateNectarSeriesLink(\"\(encoded)\");")
	}

	// If the resource cannot be opened with an installed app, present the web view.
	func openURL(_ url: URL) {
		UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { didOpen in
			assert(Thread.isMainThread)
			guard didOpen == false else {
				return
			}
			self.openURLInAppBrowser(url)
		}
	}

	/// Routes an in-app link open to the AO3-authenticated browser for AO3 domains, or
	/// SFSafariViewController otherwise. Every in-app "open this URL" path in this file
	/// should call this rather than openURLInSafariViewController(_:) directly.
	///
	/// No AO3SessionStore.isSignedIn check: the browser's persistent WKWebsiteDataStore
	/// remembers a sign-in made inside it, so there is no signed-out case to fall back from.
	func openURLInAppBrowser(_ url: URL) {
		if AO3Link.isAO3Host(url) {
			let ao3ViewController = AO3AuthenticatedWebViewController(url: url)
			let navigationController = UINavigationController(rootViewController: ao3ViewController)
			present(navigationController, animated: true)
		} else {
			openURLInSafariViewController(url)
		}
	}

	func openURLInSafariViewController(_ url: URL) {
		guard let viewController = SFSafariViewController.safeSafariViewController(url) else {
			return
		}
		present(viewController, animated: true)
	}
}

extension WebViewController {

	/// True when `url` points at a fragment of the document the page was loaded from: same
	/// URL once fragments are removed, and a non-empty fragment on the target. Pure so it can
	/// be unit tested without a web view.
	nonisolated static func isSameDocumentFragmentNavigation(url: URL, documentURL: URL?) -> Bool {
		guard let documentURL,
			  var target = URLComponents(url: url, resolvingAgainstBaseURL: false),
			  var document = URLComponents(url: documentURL, resolvingAgainstBaseURL: false),
			  let fragment = target.fragment, !fragment.isEmpty else {
			return false
		}
		target.fragment = nil
		document.fragment = nil
		return target.string == document.string
	}

	/// Isolates the "which trait collection is authoritative" decision behind
	/// applyResolvedBackgroundColors() as a dependency-free function, so tests can
	/// reproduce the self-vs-webView divergence without a live view hierarchy. Ignores
	/// webViewTraitCollection on purpose; it stays a parameter so call sites show which
	/// value was considered and rejected. Lives in this internal extension, not the
	/// private one, because members of a `private extension` can't be more accessible
	/// than it. `nonisolated` because it touches no actor-isolated state; otherwise it
	/// inherits @MainActor and can't be called from a synchronous test. See
	/// article-color-pipeline.md.
	nonisolated static func isDarkForColorResolution(selfTraitCollection: UITraitCollection, webViewTraitCollection: UITraitCollection) -> Bool {
		return selfTraitCollection.userInterfaceStyle == .dark
	}

}

struct TableOfContentsEntry: Codable, Hashable {
	let tocIndex: Int
	let id: String
	let text: String
	let tagName: String
	/// True for Calibre's "Afterword" closer and a one-shot's repeated title heading. Not
	/// used for book/chapter grouping (tagName does that; see
	/// TableOfContentsViewController.chaptersByBook); currently unread elsewhere.
	let isTocHeading: Bool
}

private struct TableOfContentsResponse: Codable {
	let entries: [TableOfContentsEntry]
	let currentTocIndex: Int
}

extension WebViewController {

	/// Entries are addressed by `tocIndex` (position among all h1/h2.heading/h2.toc-heading
	/// elements in document order), not `id`: anthology content reuses ids (e.g.
	/// "calibre_toc_3") across concatenated books. See main_ios.js's tocNodes()/
	/// getTableOfContents/scrollToHeading.
	///
	/// `currentTocIndex` is the entry nearest the current scroll position (last heading
	/// scrolled past the top edge), computed in the same JS call rather than from
	/// `windowScrollY`. `nil` means above the first heading (e.g. in a preface), so
	/// nothing is highlighted.
	func fetchTableOfContents(completionHandler: @escaping ([TableOfContentsEntry], _ currentTocIndex: Int?) -> Void) {
		webView?.evaluateJavaScript("getTableOfContents(\"e30=\")") { result, error in   // "e30=" == base64("{}")
			if let error {
				Self.logger.error("fetchTableOfContents: getTableOfContents() JS call failed: \(error.localizedDescription, privacy: .public)")
				completionHandler([], nil)
				return
			}
			guard let b64 = result as? String, let data = Data(base64Encoded: b64) else {
				Self.logger.error("fetchTableOfContents: getTableOfContents() returned an unexpected result type or invalid base64")
				completionHandler([], nil)
				return
			}
			guard let response = try? JSONDecoder().decode(TableOfContentsResponse.self, from: data) else {
				Self.logger.error("fetchTableOfContents: failed to decode TableOfContentsResponse from getTableOfContents() result")
				completionHandler([], nil)
				return
			}
			completionHandler(response.entries, response.currentTocIndex == -1 ? nil : response.currentTocIndex)
		}
	}

	/// Opens an http(s) link in the system browser, a universal-link app, or the in-app
	/// browser, per the useSystemBrowser setting.
	func openExternalLink(_ url: URL) {
		if AppDefaults.shared.useSystemBrowser {
			UIApplication.shared.open(url, options: [:])
		} else {
			UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { didOpen in
				guard didOpen == false else {
					return
				}
				self.openURLInAppBrowser(url)
			}
		}
	}

}
