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

	private var topShowBarsView: UIView!
	private var bottomShowBarsView: UIView!
	private var topShowBarsViewConstraint: NSLayoutConstraint!
	private var bottomShowBarsViewConstraint: NSLayoutConstraint!

	// Notch mask and page counter for fullscreen reading (see
	// updateNotchAndPageCounterVisibility for the visibility rules). Unlike
	// topShowBarsView, an invisible tap target moved off-screen in fullscreen,
	// the cover is a persistent mask over the notch itself.
	private var notchCoverView: UIView!
	private var notchCoverViewHeightConstraint: NSLayoutConstraint!
	private var pageCounterLabel: UILabel!
	private var readingTimePieIndicatorView: ReadingTimePieIndicatorView!

	// The single authoritative reference to the current webview. Not derived from
	// view.subviews[0], which could return the wrong view if two were ever
	// inserted (see loadWebViewGeneration).
	private var webView: PreloadedWebView?

	/// Non-nil (view coordinates) only in .nativeMenu mode while a live, non-empty
	/// selection exists. Set/cleared in textWasSelected(body:); backs
	/// isSelectionHighlightable, which buildMenu(with:) uses to decide whether to
	/// offer "Highlight". Stays nil in .popup/.off.
	private var currentSelectionRect: CGRect?

	/// Backing storage for awaitNextPageLoad(), resumed from webView(_:didFinish:).
	/// An array so concurrent awaiters are all resumed rather than one dropped.
	private var nextPageLoadContinuations: [CheckedContinuation<Void, Never>] = []

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
	private var loadWebViewGeneration = 0

	private lazy var contextMenuInteraction = UIContextMenuInteraction(delegate: self)
	private var isFullScreenAvailable: Bool {
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
	private var lastKnownReadingProgress: Double?
	// Diagnostic only (traces duplicate renderPage reports); loadWebViewGeneration gates behavior.
	private var loadWebViewCallCount = 0
	// True from the start of renderPage() until page.html reports
	// (scrollRestoreComplete) that its multi-point scroll restore has settled.
	// While true, scroll samples are noise (WKWebView's native reset to (0,0), or
	// restore attempts before the document reaches final height) and must not be
	// written to windowScrollY or persisted.
	private var isRestoringScrollPosition = false

	// True while the rendered content is a not-yet-fetched AO3 stub (see
	// isProvisionalAO3Stub) or a fetched chapter is being swapped in. Scroll
	// samples then don't reflect the real document and must not be recorded as
	// progress or Reading Stats credit; see scrollPositionDidChange.
	private var isContentProvisional = false

	// Safety net so scroll saves aren't blocked forever if page.html's completion
	// message never arrives (JS error, print preview, etc.).
	private var scrollRestoreFailsafeWorkItem: DispatchWorkItem?

	// Per-load high-water mark of document height. Defense in depth against
	// persisting a sample taken against a shorter-than-final document after
	// isRestoringScrollPosition clears (e.g. a late embed reflow). Reset in renderPage.
	private var maxObservedScrollHeight: Double = 0

	// Set by setArticle before its async scroll-position fetch and cleared just
	// before that Task calls loadWebView. While true, viewDidLoad skips its own
	// loadWebView so the first render uses the restored windowScrollY, instead of
	// rendering at 0 and then re-rendering (where reset suppression could race and
	// save 0 over the real position).
	private var isAwaitingInitialScrollFetch = false

	/// Session-only stack of pre-jump windowScrollY values, pushed before each
	/// programmatic jump (scrollToHeading, scrollToAnnotation); see scrollBack().
	/// Large manual scroll deltas are not detected as jumps (docs/reading-progress.md).
	private var scrollJumpHistory: [Double] = []

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

	// notchCoverView's height is the raw physical top inset. It can't be pinned to
	// safeAreaLayoutGuide: hideBars() zeroes that guide via additionalSafeAreaInsets.top
	// (so content flows under the notch), which would collapse the cover to 0pt for
	// good. Subtracting additionalSafeAreaInsets.top recovers the raw inset, the same
	// formula updateTopSafeAreaForFullScreen() uses. UIKit also calls this on the
	// first safe-area establishment, so viewDidLoad needs no separate call.
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

	// MARK: Actions

	@objc func showBars(_ sender: Any) {
		showBars()
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

	func showBars(animated: Bool = true) {
		AppDefaults.shared.articleFullscreenEnabled = false
		coordinator.showStatusBar()
		topShowBarsViewConstraint?.constant = 0
		bottomShowBarsViewConstraint?.constant = 0
		navigationController?.setNavigationBarHidden(false, animated: animated)
		navigationController?.setToolbarHidden(false, animated: animated)
		additionalSafeAreaInsets.bottom = 0
		additionalSafeAreaInsets.top = 0
		setBottomScrollEdgeEffectHidden(false)
		configureContextMenuInteraction()
		updateNotchAndPageCounterVisibility()
		updateScrollbarVisibility()
		// setNavigationBarHidden/setToolbarHidden reset the pop gesture recognizers'
		// isEnabled to true, overriding articleBackSwipeEnabled = false; re-apply the gate.
		coordinator.applyArticleBackSwipeGating()
	}

	func hideBars() {
		if isFullScreenAvailable {
			AppDefaults.shared.articleFullscreenEnabled = true
			coordinator.hideStatusBar()
			topShowBarsViewConstraint?.constant = -44.0
			bottomShowBarsViewConstraint?.constant = 44.0
			navigationController?.setNavigationBarHidden(true, animated: true)
			navigationController?.setToolbarHidden(true, animated: true)
			// Mirror showBars()'s synchronous inset reset instead of relying on the reactive
			// viewSafeAreaInsetsDidChange path; otherwise adjustedContentInset.bottom can stay
			// stale for a beat and shift the visible scroll position.
			updateBottomSafeAreaForFullScreen()
			// Same, top side: a stale webView.safeAreaInsets.top (read in textWasSelected)
			// shifts HighlightColorPopover's sourceRect away from the selection; see also the
			// clamp in presentHighlightColorPopover.
			updateTopSafeAreaForFullScreen()
			setBottomScrollEdgeEffectHidden(true)
			configureContextMenuInteraction()
			updateNotchAndPageCounterVisibility()
			updateScrollbarVisibility()
			coordinator.applyArticleBackSwipeGating()
		}
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

// MARK: UIContextMenuInteractionDelegate

extension WebViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {

		return UIContextMenuConfiguration(identifier: nil, previewProvider: contextMenuPreviewProvider) { [weak self] _ in
			self?.buildContextMenu()
        }
    }

	func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
		coordinator.showBrowserForCurrentArticle()
	}

	/// Builds the full press-and-hold context menu. Shared by the elements provider
	/// and refreshVisibleContextMenu so both build the same menu.
	private func buildContextMenu() -> UIMenu {
		var menus = [UIMenu]()

		var navActions = [UIAction]()
		if let action = prevArticleAction() {
			navActions.append(action)
		}
		if let action = nextArticleAction() {
			navActions.append(action)
		}
		if !navActions.isEmpty {
			menus.append(UIMenu(title: "", options: .displayInline, children: navActions))
		}

		var toggleActions = [UIAction]()
		if let action = toggleReadAction() {
			toggleActions.append(action)
		}
		toggleActions.append(toggleStarredAction())
		toggleActions.append(toggleLovedAction())
		menus.append(UIMenu(title: "", options: .displayInline, children: toggleActions))

		if let action = nextUnreadArticleAction() {
			menus.append(UIMenu(title: "", options: .displayInline, children: [action]))
		}

		if let action = checkForUpdatesAction() {
			menus.append(UIMenu(title: "", options: .displayInline, children: [action]))
		}

		let ignoreMenuActions = ignoreActions()
		if !ignoreMenuActions.isEmpty {
			menus.append(UIMenu(title: "", options: .displayInline, children: ignoreMenuActions))
		}

		menus.append(UIMenu(title: "", options: .displayInline, children: [shareAction()]))

		return UIMenu(title: "", children: menus)
	}

	/// Rebuilds the presented menu in place after a toggle tap. The toggles set
	/// `keepsMenuPresented`, but UIKit doesn't re-run the elements provider on its
	/// own; `updateVisibleMenu` swaps the contents so icons/titles show the new state.
	private func refreshVisibleContextMenu() {
		contextMenuInteraction.updateVisibleMenu { [weak self] _ in
			self?.buildContextMenu() ?? UIMenu(title: "")
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

// MARK: Annotations (highlights + notes)

extension WebViewController {

	/// Wires annotations.js's `selectionchange`/tap listeners for the loaded document,
	/// so selections post `textWasSelected` and taps on a `<mark>` post
	/// `annotationWasTapped`. Runs on every navigation, not only when annotations
	/// exist, since a chapter with none still needs to support creating its first.
	///
	/// Reads annotationCreationMethod fresh each call (not cached), like the other
	/// per-dequeue settings, so a change applies on the next article load but not
	/// retroactively to what's on screen.
	func initAnnotations() {
		let mode = AppDefaults.shared.annotationCreationMethod
		guard let argsJSON = try? JSONSerialization.data(withJSONObject: ["mode": mode.rawValue]) else { return }
		let encodedArgs = argsJSON.base64EncodedString()

		webView?.evaluateJavaScript("Annotations.initAnnotations(\"\(encodedArgs)\")") { _, error in
			if let error {
				Self.logger.error("initAnnotations: Annotations.initAnnotations() JS call failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	/// Sets the ten --nnw-highlight-* CSS custom properties (light + dark per
	/// Annotation.Color) on the document root from AppDefaults.shared.highlightPalette,
	/// so core.css's mark.nnw-highlight rules resolve against the selected palette
	/// instead of their hardcoded fallback hex. See docs/annotations.md, "Color palette".
	///
	/// Both light and dark values are always set; core.css's own
	/// `@media (prefers-color-scheme: dark)` block switches between them live, so no
	/// registerForTraitChanges hook is needed. Called from webView(_:didFinish:) on
	/// every render and from highlightPaletteDidChange(_:), where existing <mark>s
	/// repaint for free because they read the custom property.
	func applyHighlightPaletteColors() {
		let palette = AppDefaults.shared.highlightPalette
		let light = palette.lightHexSet
		let dark = palette.darkHexSet

		var declarations = ""
		for color in Annotation.Color.allCases {
			declarations += "document.documentElement.style.setProperty('--nnw-highlight-\(color.rawValue)', '\(light[color])');"
			declarations += "document.documentElement.style.setProperty('--nnw-highlight-\(color.rawValue)-dark', '\(dark[color])');"
		}

		webView?.evaluateJavaScript(declarations) { _, error in
			if let error {
				Self.logger.error("applyHighlightPaletteColors: JS injection failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	@objc func highlightPaletteDidChange(_ note: Notification) {
		applyHighlightPaletteColors()
	}

	/// First-run rule-driven text replacement (categories 1 and 3; see
	/// docs/annotations.md, "Storage shape"). Applies the typo table, reader-insert
	/// table and custom rules to the article's canonical text, writing one edit row
	/// (`hasHighlight = false`) per match through the same pipeline saveTextEdit uses.
	///
	/// "First time" is detected by absence: if any edit row with `hasHighlight == false`
	/// and a non-nil `originalText` exists, this already ran (or a person reverted a row
	/// that is still reviewable in Edit History). Re-running would duplicate matches or
	/// resurrect a reverted one, so it only runs when that set is empty. Called before
	/// loadAndRenderAnnotations() on every load so new matches render the same load.
	@MainActor
	func applyTextReplacementRulesIfNeeded() async {
		guard AppDefaults.shared.textReplacementApplyAutomatically else { return }
		guard let article, let account = article.account else { return }
		let articleID = article.articleID

		let existing = await account.fetchAnnotations(forArticleID: articleID)
		let alreadyRan = existing.contains { !$0.hasHighlight && $0.originalText != nil }
		guard !alreadyRan else { return }

		var table = TextReplacementRuleTable()
		if AppDefaults.shared.textReplacementTypoFixesEnabled {
			table.rules.append(contentsOf: AppDefaults.shared.textReplacementTypoTable.rules)
		}
		// A per-work override takes precedence over the global reader-insert table:
		// prepending its rules suffices because TextReplacementRuleEngine lets the earlier
		// rule win an overlap (see TextReplacementPerWorkOverride.mergedReaderInsertTable).
		// A nil bookKey falls through to the global table.
		let mergedReaderInsertTable = AppDefaults.shared.textReplacementPerWorkOverride.mergedReaderInsertTable(
			forBookKey: article.bookKey,
			global: AppDefaults.shared.textReplacementReaderInsertTable
		)
		table.rules.append(contentsOf: mergedReaderInsertTable.rules)
		table.rules.append(contentsOf: AppDefaults.shared.textReplacementCustomTable.rules)
		let quoteConversionEnabled = AppDefaults.shared.textReplacementQuoteConversionEnabled
		guard !table.rules.isEmpty || quoteConversionEnabled else { return }

		guard let textResult = try? await self.webView?.evaluateJavaScript("Annotations.getArticleText(\".articleBody\")"),
			  let text = textResult as? String, !text.isEmpty else {
			return
		}

		// Rule-table matches (categories 1/3) and quote conversion (category 2) are found
		// independently. On an overlapping span the rule-table match wins and the quote
		// candidate is dropped: a rule is an explicit correction, quote conversion a
		// blanket style pass.
		var matches = TextReplacementRuleEngine.findMatches(applying: table, to: text)
		if quoteConversionEnabled {
			let ruleRanges = matches.map { NSRange(location: $0.startOffset, length: $0.endOffset - $0.startOffset) }
			let quoteMatches = TextReplacementQuoteConversion.findMatches(in: text).filter { quoteMatch in
				let quoteRange = NSRange(location: quoteMatch.startOffset, length: quoteMatch.endOffset - quoteMatch.startOffset)
				return !ruleRanges.contains { NSIntersectionRange($0, quoteRange).length > 0 }
			}
			matches.append(contentsOf: quoteMatches)
		}
		guard !matches.isEmpty else { return }

		// Capture prefix/suffix as selectorForRange does in JS (CONTEXT_CHARS = 200). Empty
		// values would starve resolveAnnotation's disambiguation (scoreCandidate) if this
		// quote later needs multi-match resolution.
		let nsText = text as NSString
		let contextChars = 200

		// Apply in descending offset order (as for manual edits) so an earlier match's
		// offset is never invalidated by a later match's length delta.
		let descending = matches.sorted { $0.startOffset > $1.startOffset }
		var appliedCount = 0
		for match in descending {
			let prefixStart = max(0, match.startOffset - contextChars)
			let quotePrefix = nsText.substring(with: NSRange(location: prefixStart, length: match.startOffset - prefixStart))
			let suffixEnd = min(nsText.length, match.endOffset + contextChars)
			let quoteSuffix = nsText.substring(with: NSRange(location: match.endOffset, length: suffixEnd - match.endOffset))

			let annotationID = UUID().uuidString
			let now = Date()
			let annotation = Annotation(
				annotationID: annotationID,
				articleID: articleID,
				bookKey: nil,
				quoteExact: match.originalText,
				quotePrefix: quotePrefix,
				quoteSuffix: quoteSuffix,
				startOffset: match.startOffset,
				endOffset: match.endOffset,
				color: .yellow,
				note: nil,
				hasHighlight: false,
				originalText: match.originalText,
				replacementText: match.replacementText,
				createdAt: now,
				updatedAt: now
			)
			await account.saveAnnotation(annotation)
			appliedCount += 1
		}

		if appliedCount > 0 {
			Self.logger.debug("applyTextReplacementRulesIfNeeded: applied \(appliedCount, privacy: .public) rule-driven replacements for articleID=\(articleID, privacy: .public)")
			// Surface a one-time summary banner via ArticleViewController. The debug log above
			// is kept for diagnosing reports of unexpected replacements. A nil closure just
			// means no visible banner; the pass has already completed and persisted.
			onTextReplacementReplacementsApplied?(appliedCount)
		}
	}

	/// Fetches saved annotations and hands them to annotations.js's
	/// renderAnnotationsEncoded, which resolves each against the fresh DOM and draws it.
	/// "Moved" annotations get their stored anchor updated so the next render hits the
	/// stored-offset fast path; "orphaned" ones are marked (Annotation.orphanedAt),
	/// never deleted, so a note is not silently lost.
	func loadAndRenderAnnotations() {
		guard let article, let account = article.account else { return }
		let articleID = article.articleID

		Task {
			let annotations = await account.fetchAnnotations(forArticleID: articleID)
			guard !annotations.isEmpty else { return }

			// Discard if the person navigated to a different article during the fetch.
			guard self.article?.articleID == articleID else {
				Self.logger.debug("loadAndRenderAnnotations: articleID changed before annotation fetch resolved, discarding for articleID=\(articleID, privacy: .public)")
				return
			}

			guard let json = try? JSONEncoder().encode(annotations) else { return }
			let encoded = json.base64EncodedString()

			do {
				let result = try await self.webView?.evaluateJavaScript("Annotations.renderAnnotationsEncoded(\"\(encoded)\")")
				guard let b64 = result as? String, let data = Data(base64Encoded: b64) else {
					Self.logger.error("loadAndRenderAnnotations: renderAnnotationsEncoded() returned an unexpected result type or invalid base64")
					return
				}
				guard let report = try? JSONDecoder().decode(ReanchorReport.self, from: data) else {
					Self.logger.error("loadAndRenderAnnotations: failed to decode ReanchorReport from renderAnnotationsEncoded() result")
					return
				}
				self.reconcile(report, account: account)
			} catch {
				Self.logger.error("loadAndRenderAnnotations: renderAnnotationsEncoded() JS call failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	private func reconcile(_ report: ReanchorReport, account: Account) {
		Task {
			for moved in report.moved {
				await account.reanchorAnnotation(
					annotationID: moved.annotationID,
					startOffset: moved.startOffset,
					endOffset: moved.endOffset,
					quoteExact: moved.quoteExact,
					quotePrefix: moved.quotePrefix,
					quoteSuffix: moved.quoteSuffix,
					chapterTitle: moved.chapterTitle
				)
			}
			for orphanedID in report.orphanedIDs {
				await account.markAnnotationOrphaned(annotationID: orphanedID, at: Date())
			}
		}
	}

	/// Scrolls to and briefly flashes the annotation's highlight via annotations.js.
	/// That file is cross-platform and exposes plain-argument functions on the global
	/// `Annotations` object, so no base64 encoding is needed for a single ID (unlike
	/// main_ios.js's scrollToHeading). Fire-and-forget; no-op if the mark isn't in the DOM.
	func scrollToAnnotation(annotationID: String) {
		scrollJumpHistory.append(Double(windowScrollY))
		let escaped = annotationID.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
		webView?.evaluateJavaScript("Annotations.scrollToAnnotation(\"\(escaped)\")") { _, error in
			if let error {
				Self.logger.error("scrollToAnnotation: Annotations.scrollToAnnotation() JS call failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	/// Resolves when this controller's page finishes loading. Used by
	/// ArticleViewController.navigateToAnnotation: article selection resolves well
	/// before the new controller's didFinish, and the mark to scroll to doesn't exist
	/// until then. If the page already loaded, this waits for the next load rather
	/// than hanging, since callers want the result of a navigation.
	func awaitNextPageLoad() async {
		await withCheckedContinuation { continuation in
			nextPageLoadContinuations.append(continuation)
		}
	}

	/// Resumes every pending awaitNextPageLoad() caller; called from webView(_:didFinish:).
	/// Storage is a stored property on the class, since extensions can't add them.
	fileprivate func resumeAwaitingPageLoads() {
		let continuations = nextPageLoadContinuations
		nextPageLoadContinuations = []
		for continuation in continuations {
			continuation.resume()
		}
	}

	/// annotations.js reports new selections (with a rect) and selection-cleared events
	/// (`{cleared: true}`) through this handler. Behavior depends on
	/// annotationCreationMethod, read fresh (see initAnnotations()):
	///  - .popup: a non-empty selection presents HighlightColorPopover; `cleared` is ignored.
	///  - .nativeMenu: never presents the popover. Tracks whether a highlightable
	///    selection exists (currentSelectionRect), exposed via isSelectionHighlightable
	///    so buildMenu(with:) knows whether to offer "Highlight". `cleared` resets it to nil.
	///  - .off: shouldn't fire (annotations.js doesn't wire selectionchange), but a stale
	///    message after a mid-session mode change is ignored.
	func textWasSelected(body: [String: Any]?) {
		guard let body else { return }

		if body["cleared"] as? Bool == true {
			currentSelectionRect = nil
			return
		}

		guard let webView,
			  let x = body["x"] as? Double,
			  let y = body["y"] as? Double,
			  let width = body["width"] as? Double,
			  let height = body["height"] as? Double else {
			return
		}

		// Same safe-area offset and conversion as showFullScreenImage: the JS rect is in
		// web content coordinates, not this controller's.
		let adjustedY = CGFloat(y) + webView.safeAreaInsets.top
		let rect = CGRect(x: CGFloat(x), y: adjustedY, width: CGFloat(width), height: CGFloat(height))
		let convertedRect = webView.convert(rect, to: view)

		switch AppDefaults.shared.annotationCreationMethod {
		case .popup:
			presentHighlightColorPopover(sourceRect: convertedRect)
		case .nativeMenu:
			// No popover; just record that a highlightable selection exists. buildMenu(with:)
			// reads isSelectionHighlightable when the system next rebuilds its menu.
			currentSelectionRect = convertedRect
		case .off:
			break
		}
	}

	private func presentHighlightColorPopover(sourceRect: CGRect) {
		let popover = HighlightColorPopover(
			onSelectColor: { [weak self] color in
				self?.dismiss(animated: true)
				self?.saveHighlightFromSelection(color: color)
			}
		)

		let hostingController = UIHostingController(rootView: popover)
		hostingController.modalPresentationStyle = .popover
		// Sized for 3 swatches (3*28 + 2*14 + 2*16 = 144); fewer just leave it slightly
		// wider than its content, since SwiftUI centers the HStack.
		hostingController.preferredContentSize = CGSize(width: 144, height: 56)
		if let presentationController = hostingController.popoverPresentationController {
			presentationController.sourceView = view
			// Defensive clamp: if sourceRect falls outside view.bounds (a short selection's
			// small rect triggered this), UIPopoverPresentationController silently never
			// presents. Clamping anchors at the nearest valid edge instead. Independent of
			// updateTopSafeAreaForFullScreen().
			presentationController.sourceRect = sourceRect.intersects(view.bounds)
				? sourceRect
				: sourceRect.clamped(toBounds: view.bounds)
			presentationController.permittedArrowDirections = [.up, .down]
			presentationController.delegate = self
		}
		present(hostingController, animated: true)
	}

	/// Calls annotations.js's addHighlightFromSelection to resolve the live selection
	/// into a selector and draw the highlight, then persists it. Does nothing if the
	/// selection didn't survive (popover dismissed, scrolled, etc.); there is no stale
	/// selector to fall back on, since the live selection is the only authority.
	///
	/// Save-only for both callers (popup swatch tap, native menu "Highlight"). A note
	/// is added later by tapping the mark, which routes to annotationWasTapped.
	private func saveHighlightFromSelection(color: Annotation.Color) {
		guard let article, let account = article.account else { return }

		let annotationID = UUID().uuidString
		let args: [String: String] = ["annotationID": annotationID, "color": color.rawValue]
		guard let argsJSON = try? JSONSerialization.data(withJSONObject: args) else { return }
		let encodedArgs = argsJSON.base64EncodedString()

		webView?.evaluateJavaScript("Annotations.addHighlightFromSelection(\"\(encodedArgs)\")") { [weak self] result, error in
			guard self != nil else { return }
			if let error {
				Self.logger.error("saveHighlightFromSelection: addHighlightFromSelection() JS call failed: \(error.localizedDescription, privacy: .public)")
				return
			}
			guard let b64 = result as? String, let data = Data(base64Encoded: b64) else {
				Self.logger.error("saveHighlightFromSelection: addHighlightFromSelection() returned an unexpected result type or invalid base64")
				return
			}
			guard let selector = try? JSONDecoder().decode(AnnotationSelector.self, from: data) else {
				// Not necessarily an error -- addHighlightFromSelection legitimately
				// returns base64("null") when the selection didn't survive.
				return
			}

			let now = Date()
			let annotation = Annotation(
				annotationID: selector.annotationID,
				articleID: article.articleID,
				bookKey: nil, // resolved from articleID at save time -- see ArticlesTable.saveAnnotationAsync
				quoteExact: selector.quoteExact,
				quotePrefix: selector.quotePrefix,
				quoteSuffix: selector.quoteSuffix,
				rootSelector: selector.rootSelector,
				startOffset: selector.startOffset,
				endOffset: selector.endOffset,
				color: color,
				note: nil,
				chapterTitle: selector.chapterTitle,
				createdAt: now,
				updatedAt: now
			)

			Task {
				await account.saveAnnotation(annotation)
			}
		}
	}

	/// The person tapped an existing highlight: open its note editor
	/// (creating one if this highlight has no note yet).
	func annotationWasTapped(body: [String: Any]?) {
		guard let article, let account = article.account,
			  let body, let annotationID = body["annotationID"] as? String else {
			return
		}

		Task {
			let annotations = await account.fetchAnnotations(forArticleID: article.articleID)
			guard let annotation = annotations.first(where: { $0.annotationID == annotationID }) else { return }
			self.openNoteEditor(for: annotation)
		}
	}

	/// "Highlight" chosen from the native selection menu (.nativeMenu mode). Reuses
	/// the popup's save path against the still-live selection (the system menu doesn't
	/// clear it), with the default color since there is no picker in this mode. See
	/// PreloadedWebView.buildMenu.
	func nativeMenuHighlightWasTapped() {
		saveHighlightFromSelection(color: AppDefaults.shared.defaultAnnotationColor)
	}

	/// Presents the note-editor half-sheet; a fresh highlight's mark tap and an
	/// existing <mark> tap both converge here.
	private func openNoteEditor(for annotation: Annotation) {
		guard let article, let account = article.account else { return }

		let editorView = AnnotationEditorView(
			annotation: annotation,
			onSave: { [weak self] note, color, editedText, keepHighlight in
				self?.saveNoteEdit(annotation: annotation, note: note, color: color, account: account)
				if let editedText {
					self?.saveTextEdit(annotation: annotation, replacementText: editedText, keepHighlight: keepHighlight, account: account)
				} else if keepHighlight != annotation.hasHighlight, annotation.originalText != nil {
					// Text unchanged but "keep highlight" moved on a row that already has an edit.
					// No offset shift or overlap is possible, so skip saveTextEdit's pipeline and
					// persist hasHighlight directly. The `originalText != nil` guard matters:
					// unchecking on a never-edited row would write hasHighlight == false with
					// originalText == nil, violating the Validity rule (docs/annotations.md, "Storage
					// shape"). That case is a no-op here rather than a silent delete or invalid row.
					self?.saveHasHighlightChange(annotation: annotation, hasHighlight: keepHighlight, account: account)
				}
			},
			onDelete: { [weak self] in
				self?.deleteAnnotation(annotation, account: account)
			}
		)

		let hostingController = UIHostingController(rootView: editorView)
		if let sheet = hostingController.sheetPresentationController {
			sheet.detents = [.medium(), .large()]
			sheet.prefersGrabberVisible = true
		}
		present(hostingController, animated: true)
	}

	private func saveNoteEdit(annotation: Annotation, note: String?, color: Annotation.Color, account: Account) {
		let colorChanged = color != annotation.color
		let noteChanged = note != annotation.note

		if colorChanged {
			webView?.evaluateJavaScript("Annotations.updateAnnotationColor(\"\(annotation.annotationID)\", \"\(color.rawValue)\")") { _, error in
				if let error {
					Self.logger.error("saveNoteEdit: Annotations.updateAnnotationColor() JS call failed: \(error.localizedDescription, privacy: .public)")
				}
			}
		}

		Task {
			if colorChanged {
				await account.updateAnnotationColor(annotationID: annotation.annotationID, color: color)
			}
			if noteChanged {
				await account.updateAnnotationNote(annotationID: annotation.annotationID, note: note)
			}
		}
	}

	/// Handles the "Edit text" field and "Keep highlight" checkbox from
	/// AnnotationEditorView (docs/annotations.md, "Manual edit UI"). Called only when
	/// the text actually changed.
	///
	/// Pipeline (docs/annotations.md, "Applying edits"): fetch the other annotations,
	/// ask annotations.js (computeTextEditPlan, non-mutating, against the live DOM) to
	/// check for overlap and compute shifted anchors, then persist this row's edit
	/// fields and each shifted row's new anchor via account.reanchorAnnotation in
	/// descending-offset order (write order matters for the same reason as
	/// TextReplacementOffsetShift). Finally loadAndRenderAnnotations() re-renders; the
	/// DOM mutation (applyTextEdit) happens there, not here.
	///
	/// An overlap shows a blocking alert and writes nothing.
	private func saveTextEdit(annotation: Annotation, replacementText: String, keepHighlight: Bool, account: Account) {
		guard let article else { return }
		let articleID = article.articleID
		let originalText = annotation.replacementText ?? annotation.quoteExact
		let replacementLength = replacementText.count

		// Validity rule (docs/annotations.md, "Storage shape"): hasHighlight == true OR
		// originalText != nil. AnnotationEditorView only calls this for a real text
		// change, so no extra guard is needed here.

		Task {
			let allAnnotations = await account.fetchAnnotations(forArticleID: articleID)
			let others = allAnnotations.filter { $0.annotationID != annotation.annotationID }

			let otherPayload = others.map { [
				"annotationID": $0.annotationID,
				"startOffset": $0.startOffset,
				"endOffset": $0.endOffset
			] as [String: Any] }

			let args: [String: Any] = [
				"annotationToEditID": annotation.annotationID,
				"startOffset": annotation.startOffset,
				"endOffset": annotation.endOffset,
				"replacementLength": replacementLength,
				"otherAnnotations": otherPayload,
				"rootSelector": annotation.rootSelector
			]
			guard let argsJSON = try? JSONSerialization.data(withJSONObject: args) else {
				Self.logger.error("saveTextEdit: failed to serialize computeTextEditPlan args")
				return
			}
			let encodedArgs = argsJSON.base64EncodedString()

			let plan: TextEditPlan
			do {
				let result = try await self.webView?.evaluateJavaScript("Annotations.computeTextEditPlanEncoded(\"\(encodedArgs)\")")
				guard let b64 = result as? String, let data = Data(base64Encoded: b64) else {
					Self.logger.error("saveTextEdit: computeTextEditPlanEncoded() returned an unexpected result type or invalid base64")
					return
				}
				guard let decoded = try? JSONDecoder().decode(TextEditPlan.self, from: data) else {
					Self.logger.error("saveTextEdit: failed to decode TextEditPlan from computeTextEditPlanEncoded() result")
					return
				}
				plan = decoded
			} catch {
				Self.logger.error("saveTextEdit: computeTextEditPlanEncoded() JS call failed: \(error.localizedDescription, privacy: .public)")
				return
			}

			if plan.status == "overlap" {
				self.presentTextEditOverlapAlert()
				return
			}

			// Write this row's edit fields first; its offsets don't change.
			await account.setAnnotationEditFields(
				annotationID: annotation.annotationID,
				hasHighlight: keepHighlight,
				originalText: originalText,
				replacementText: replacementText
			)

			// Persist shifted rows in descending offset order (see TextReplacementOffsetShift).
			let shiftedDescending = plan.shifted.sorted { $0.startOffset > $1.startOffset }
			for shifted in shiftedDescending {
				await account.reanchorAnnotation(
					annotationID: shifted.annotationID,
					startOffset: shifted.startOffset,
					endOffset: shifted.endOffset,
					quoteExact: shifted.quoteExact,
					quotePrefix: shifted.quotePrefix,
					quoteSuffix: shifted.quoteSuffix,
					chapterTitle: shifted.chapterTitle
				)
			}

			self.loadAndRenderAnnotations()
		}
	}

	/// Persists a `hasHighlight`-only change (checkbox flipped, text untouched).
	/// Bypasses saveTextEdit's plan pipeline: this row's anchor doesn't move, so there
	/// is no overlap to check and nothing to reanchor. originalText/replacementText
	/// carry through. The re-render wraps/unwraps the <mark> since renderAnnotations
	/// re-evaluates hasHighlight per row (docs/annotations.md, "Storage shape").
	private func saveHasHighlightChange(annotation: Annotation, hasHighlight: Bool, account: Account) {
		Task {
			await account.setAnnotationEditFields(
				annotationID: annotation.annotationID,
				hasHighlight: hasHighlight,
				originalText: annotation.originalText,
				replacementText: annotation.replacementText
			)
			self.loadAndRenderAnnotations()
		}
	}

	/// Blocking alert for the overlap case (docs/annotations.md, "Applying edits").
	private func presentTextEditOverlapAlert() {
		let alert = UIAlertController(
			title: NSLocalizedString("Can’t Edit This Text", comment: "Text-edit overlap alert title"),
			message: NSLocalizedString("This text is part of an existing highlight or edit. Remove or resize it first.", comment: "Text-edit overlap alert message"),
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK button"), style: .default))
		present(alert, animated: true)
	}

	private func deleteAnnotation(_ annotation: Annotation, account: Account) {
		revertOrUnwrapAnnotationDOM(annotation)

		Task {
			await account.deleteAnnotation(annotationID: annotation.annotationID)
		}
	}

	/// Reverts the live DOM only when the row belongs to this web view's
	/// currently displayed article. Persistence remains owned by the caller.
	func revertOrUnwrapAnnotationDOM(_ annotation: Annotation) {
		if let originalText = annotation.originalText {
			// A text-edit row: applyTextEdit already mutated the DOM at render time, so
			// unwrapping alone would leave the replacement text. revertTextEdit restores
			// originalText first, then unwraps (see annotations.js).
			let args: [String: String] = ["annotationID": annotation.annotationID, "originalText": originalText]
			guard let argsJSON = try? JSONSerialization.data(withJSONObject: args) else { return }
			let encodedArgs = argsJSON.base64EncodedString()

			webView?.evaluateJavaScript("Annotations.revertTextEdit(\"\(encodedArgs)\")") { _, error in
				if let error {
					Self.logger.error("deleteAnnotation: Annotations.revertTextEdit() JS call failed: \(error.localizedDescription, privacy: .public)")
				}
			}
		} else {
			// Highlight-only row: the text was never touched, so unwrap the <mark> and
			// normalize the text nodes (see annotations.js).
			webView?.evaluateJavaScript("Annotations.removeAnnotationHighlight(\"\(annotation.annotationID)\")") { _, error in
				if let error {
					Self.logger.error("deleteAnnotation: Annotations.removeAnnotationHighlight() JS call failed: \(error.localizedDescription, privacy: .public)")
				}
			}
		}

	}

}

extension WebViewController: UIPopoverPresentationControllerDelegate {

	func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
		// Force a true popover on compact width, where UIKit would adapt to a sheet.
		.none
	}

}

// MARK: PreloadedWebViewAnnotationDelegate

extension WebViewController: PreloadedWebViewAnnotationDelegate {

	/// Backed by currentSelectionRect, which is only set in .nativeMenu mode, so this
	/// is false by construction in .popup/.off.
	var isSelectionHighlightable: Bool {
		currentSelectionRect != nil
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
			// Stub or still-settling provisional content: don't write position, credit
			// Reading Stats, mark read, or persist.
			guard !self.isContentProvisional else {
				Self.logger.debug("scrollPositionDidChange: discarding sample, content is provisional (scrollY=\(javascriptScrollY, privacy: .public))")
				return
			}
			self.windowScrollY = javascriptScrollY

			// Mark read once the viewport bottom reaches ReadingProgressEvaluator.completionThreshold
			// (shared with ReadingStatsTracker). The math lives there so it is testable without a WKWebView.
			if let scrollHeight = result["scrollHeight"] as? Double,
			   let innerHeight = result["innerHeight"] as? Double,
			   let sample = ReadingProgressEvaluator.sample(scrollY: Double(javascriptScrollY), scrollHeight: scrollHeight, viewportHeight: innerHeight) {
				ReadingStatsTracker.shared.recordProgress(sample.rawFraction)
				if sample.isComplete {
					self.coordinator.markCurrentArticleAsReadFromScrollCompletion()
				}

				// Page counter; reuses this JS payload rather than a second round trip.
				switch AppDefaults.shared.pageCounterDisplayMode {
				case .off:
					break
				case .percentage:
					self.pageCounterLabel.text = "\(sample.percentRounded)%"
				case .pageCount:
					// nil when the viewport reports zero height; leave the label as-is
					// rather than converting an infinite ratio to Int.
					if let page = ReadingProgressEvaluator.pageCounter(for: sample) {
						self.pageCounterLabel.text = "\(page.current)/\(page.total)"
					}
				}

				// Visible reading progress; reuses the same payload (sample.fraction is the 0...1 value).
				if let article = self.article, let account = article.account {
					let articleID = article.articleID
					let readingProgress = sample.fraction
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

/// Shapes returned by annotations.js (renderAnnotationsEncoded/addHighlightFromSelection)
/// over the base64-JSON bridge: `AnnotationSelector` is a live selection resolved to a
/// selector; `ReanchorReport` is a render's {moved, orphanedIDs} report.
private struct AnnotationSelector: Codable {
	let annotationID: String
	let color: String
	let quoteExact: String
	let quotePrefix: String
	let quoteSuffix: String
	let rootSelector: String
	let startOffset: Int
	let endOffset: Int
	/// See Annotation.chapterTitle; computed by annotations.js's nearestChapterTitle.
	let chapterTitle: String?
}

private struct ReanchorReport: Codable {
	struct Moved: Codable {
		let annotationID: String
		let startOffset: Int
		let endOffset: Int
		let quoteExact: String
		let quotePrefix: String
		let quoteSuffix: String
		let chapterTitle: String?
	}
	let moved: [Moved]
	let orphanedIDs: [String]
}

/// Shape returned by annotations.js's computeTextEditPlanEncoded: an overlap
/// conflict, or the other rows an edit's length delta shifts, with
/// quote/prefix/suffix/chapterTitle already recomputed against the simulated
/// post-edit text. See docs/annotations.md, "Applying edits".
private struct TextEditPlan: Codable {
	struct Shifted: Codable {
		let annotationID: String
		let startOffset: Int
		let endOffset: Int
		let quoteExact: String
		let quotePrefix: String
		let quoteSuffix: String
		let chapterTitle: String?
	}
	let status: String
	let delta: Int?
	let shifted: [Shifted]
	let conflictingAnnotationID: String?

	private enum CodingKeys: String, CodingKey {
		case status, delta, shifted, conflictingAnnotationID
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		status = try container.decode(String.self, forKey: .status)
		delta = try container.decodeIfPresent(Int.self, forKey: .delta)
		shifted = try container.decodeIfPresent([Shifted].self, forKey: .shifted) ?? []
		conflictingAnnotationID = try container.decodeIfPresent(String.self, forKey: .conflictingAnnotationID)
	}
}

// MARK: Private

private extension WebViewController {

	/// Synchronously persists the last known scroll position/progress (no JS evaluation,
	/// so nothing races view teardown). See viewWillDisappear.
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
			"lang": Locale.current.language.languageCode?.identifier ?? "en"
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

		webView.loadHTMLString(html, baseURL: URL(string: rendering.baseURL))
	}

	// Resolve the theme's background before loadHTMLString commits, so there is no
	// flash of the default .systemBackground (near-black in dark mode; see
	// PreloadedWebView.init). Precedence: override background, then theme background,
	// then ArticleThemeColorExtractor's black/white fallback.
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

	/// Applies articleScrollbarVisibility to the live webview. Called from
	/// applyResolvedBackgroundColors() (fresh load/dequeue) and showBars()/hideBars()
	/// (so .whenNotFullScreen re-evaluates live).
	func updateScrollbarVisibility() {
		guard let webView else { return }
		switch AppDefaults.shared.articleScrollbarVisibility {
		case .off:
			webView.scrollView.showsVerticalScrollIndicator = false
		case .always:
			webView.scrollView.showsVerticalScrollIndicator = true
		case .whenNotFullScreen:
			webView.scrollView.showsVerticalScrollIndicator = !AppDefaults.shared.articleFullscreenEnabled
		}
	}

	/// Precedence: override background, then theme background, then
	/// ArticleThemeColorExtractor's black/white fallback. Shared by
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

	// notchCoverView spans the top safe-area inset (the notch/Dynamic Island footprint).
	// pageCounterLabel sits on it, leading-aligned (one label, not mirrored).
	func configureNotchCoverView() {
		notchCoverView = UIView()
		notchCoverView.isHidden = true
		notchCoverView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(notchCoverView)

		// Deliberately not safeAreaLayoutGuide.topAnchor: hideBars() zeroes that guide via
		// additionalSafeAreaInsets.top, which collapsed the cover to 0pt permanently once
		// fullscreen engaged. A fixed height kept in sync with the raw inset in
		// viewSafeAreaInsetsDidChange is immune.
		notchCoverViewHeightConstraint = notchCoverView.heightAnchor.constraint(equalToConstant: view.safeAreaInsets.top)
		NSLayoutConstraint.activate([
			notchCoverView.topAnchor.constraint(equalTo: view.topAnchor),
			notchCoverViewHeightConstraint,
			notchCoverView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			notchCoverView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
		])

		// The cover sits above topShowBarsView's tap zone and would swallow the tap that
		// brings the bars back, so give it the same reveal gesture.
		notchCoverView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showBars(_:))))

		pageCounterLabel = UILabel()
		pageCounterLabel.font = .preferredFont(forTextStyle: .caption2)
		pageCounterLabel.textColor = .label
		pageCounterLabel.isHidden = true
		pageCounterLabel.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(pageCounterLabel)

		NSLayoutConstraint.activate([
			pageCounterLabel.centerYAnchor.constraint(equalTo: notchCoverView.centerYAnchor),
			// NOTE: the old 20pt inset was still clipped by corner curvature on iPhone 17 in the
			// simulator; pageCounterLeadingInset (44pt, topShowBarsView's tap-zone height) is a
			// starting point. Re-check on an iPhone 17 simulator/device; don't adjust blind.
			pageCounterLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Self.pageCounterLeadingInset)
		])

		// Trailing counterpart to pageCounterLabel: same vertical placement, mirrored
		// inset, sized to roughly match the label's cap height.
		readingTimePieIndicatorView = ReadingTimePieIndicatorView()
		readingTimePieIndicatorView.tintColor = pageCounterLabel.textColor
		readingTimePieIndicatorView.isHidden = true
		readingTimePieIndicatorView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(readingTimePieIndicatorView)

		NSLayoutConstraint.activate([
			readingTimePieIndicatorView.centerYAnchor.constraint(equalTo: notchCoverView.centerYAnchor),
			readingTimePieIndicatorView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Self.pageCounterLeadingInset),
			readingTimePieIndicatorView.widthAnchor.constraint(equalToConstant: 16),
			readingTimePieIndicatorView.heightAnchor.constraint(equalToConstant: 16)
		])
	}

	private static let pageCounterLeadingInset: CGFloat = 44

	/// Called from showBars()/hideBars() (no args: reuses the last resolved color) and
	/// from renderPage() (explicit args, so the cover/label track the theme on every render).
	///
	/// notchCoverView is gated on isFullScreenAvailable (device + "Enable Full Screen
	/// Articles"), not the momentary articleFullscreenEnabled flag: the cover sits above a
	/// revealed nav bar, so keeping it up while peeking causes no conflict, and tying it
	/// to the peek state made it flicker. pageCounterLabel is fullscreen-reading chrome,
	/// so it is additionally gated on articleFullscreenEnabled.
	func updateNotchAndPageCounterVisibility(resolvedBackground: UIColor? = nil, resolvedText: UIColor? = nil) {
		let pageCounterOn = AppDefaults.shared.pageCounterDisplayMode != .off
		// A visible page counter implies hiding the notch, without needing hideNotchInFullScreen.
		let shouldHideNotch = AppDefaults.shared.hideNotchInFullScreen || pageCounterOn

		// Prefer the just-resolved theme color; else reuse webView.backgroundColor (kept
		// theme-accurate between renders) rather than the stale .systemBackground default.
		if let resolvedBackground {
			notchCoverView.backgroundColor = resolvedBackground
		} else if let webViewBackground = webView?.backgroundColor {
			notchCoverView.backgroundColor = webViewBackground
		}
		if let resolvedText {
			pageCounterLabel.textColor = resolvedText
		}
		notchCoverView.isHidden = !(shouldHideNotch && isFullScreenAvailable)
		// Page counter is fullscreen-reading chrome: also gate on the bars actually being hidden.
		pageCounterLabel.isHidden = !(pageCounterOn && isFullScreenAvailable && AppDefaults.shared.articleFullscreenEnabled)
		updateReadingTimePieIndicatorView(resolvedText: resolvedText)
	}

	/// Shares pageCounterLabel's fullscreen-chrome visibility rule so the two can't drift;
	/// additionally hidden when there is no active daily limit to show progress against.
	private func updateReadingTimePieIndicatorView(resolvedText: UIColor? = nil) {
		if let resolvedText {
			readingTimePieIndicatorView.tintColor = resolvedText
		}
		guard AppDefaults.shared.readingTimeEnabled, AppDefaults.shared.readingTimeDailyLimitEnabled else {
			readingTimePieIndicatorView.isHidden = true
			return
		}
		let weekday = Calendar.current.component(.weekday, from: Date())
		let limitSeconds = AppDefaults.shared.readingTimeDailyLimitMinutes(for: weekday) * 60
		let usedSeconds = AppDefaults.shared.readingTimeMinutesUsedTodaySeconds
		readingTimePieIndicatorView.fraction = limitSeconds > 0 ? CGFloat(usedSeconds) / CGFloat(limitSeconds) : 0
		// Own display-mode toggle, gated like pageCounterLabel above.
		let indicatorModeOn = AppDefaults.shared.readingTimeIndicatorDisplayMode != .off
		readingTimePieIndicatorView.isHidden = !(indicatorModeOn && isFullScreenAvailable && AppDefaults.shared.articleFullscreenEnabled)
	}

	@objc private func readingTimeUsageDidChange(_ note: Notification) {
		updateReadingTimePieIndicatorView()
	}

	func updateBottomSafeAreaForFullScreen() {
		let rawBottom = view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom
		additionalSafeAreaInsets.bottom = -rawBottom
	}

	/// Top-side counterpart of updateBottomSafeAreaForFullScreen(), called from hideBars().
	/// Relying on the reactive viewSafeAreaInsetsDidChange path left webView.safeAreaInsets.top
	/// stale for a beat, which textWasSelected(body:) reads to position the popover's
	/// sourceRect. showBars() resets the top inset synchronously, as it does the bottom.
	func updateTopSafeAreaForFullScreen() {
		let rawTop = view.safeAreaInsets.top - additionalSafeAreaInsets.top
		additionalSafeAreaInsets.top = -rawTop
	}

	/// Hides or shows the toolbar scroll edge effect at the bottom of the web view;
	/// hidden in fullscreen so a residual effect doesn't obscure the article.
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
		guard AppDefaults.shared.articleFullscreenContextMenuEnabled else {
			webView?.removeInteraction(contextMenuInteraction)
			return
		}
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
		let title = NSLocalizedString("Previous Work", comment: "Previous Article")
		return UIAction(title: title, image: Assets.Images.prevArticle) { [weak self] _ in
			self?.coordinator.selectPrevArticle()
		}
	}

	func nextArticleAction() -> UIAction? {
		guard coordinator.isNextArticleAvailable else { return nil }
		let title = NSLocalizedString("Next Work", comment: "Next Article")
		return UIAction(title: title, image: Assets.Images.nextArticle) { [weak self] _ in
			self?.coordinator.selectNextArticle()
		}
	}

	func toggleReadAction() -> UIAction? {
		guard let article = article, !article.status.read || article.isAvailableToMarkUnread else { return nil }

		let title = article.status.read ? NSLocalizedString("Mark as Unread", comment: "Command") : NSLocalizedString("Mark as Read", comment: "Command")
		// Icons match ArticleViewController's toolbar convention (read: circleOpen).
		let readImage = article.status.read ? Assets.Images.circleOpen : Assets.Images.circleClosed
		let action = UIAction(title: title, image: readImage, attributes: .keepsMenuPresented) { [weak self] _ in
			// Menu rebuild happens from statusesDidChange(_:) once the toggle's
			// async write actually lands -- see that method's doc comment.
			self?.coordinator.toggleReadForCurrentArticle()
		}
		return action
	}

	func toggleStarredAction() -> UIAction {
		let starred = article?.status.starred ?? false
		let title = starred ? NSLocalizedString("Remove from Read Later", comment: "Command") : NSLocalizedString("Add to Read Later", comment: "Command")
		// Icons match ArticleViewController's toolbar convention (starred: starClosed).
		let starredImage = starred ? Assets.Images.starClosed : Assets.Images.starOpen
		let action = UIAction(title: title, image: starredImage, attributes: .keepsMenuPresented) { [weak self] _ in
			// Menu rebuild happens from statusesDidChange(_:) once the toggle's
			// async write actually lands -- see that method's doc comment.
			self?.coordinator.toggleStarredForCurrentArticle()
		}
		return action
	}

	func toggleLovedAction() -> UIAction {
		let loved = article?.status.loved ?? false
		let title = loved ? NSLocalizedString("Remove from Loved", comment: "Command") : NSLocalizedString("Add to Loved", comment: "Command")
		// Icons match ArticleViewController's toolbar convention (loved: heartClosed).
		let lovedImage = loved ? Assets.Images.heartClosed : Assets.Images.heartOpen
		let action = UIAction(title: title, image: lovedImage, attributes: .keepsMenuPresented) { [weak self] _ in
			// Menu rebuild happens from statusesDidChange(_:) once the toggle's
			// async write actually lands -- see that method's doc comment.
			self?.coordinator.toggleLovedForCurrentArticle()
		}
		return action
	}

	func nextUnreadArticleAction() -> UIAction? {
		guard coordinator.isNextUnreadAvailable else { return nil }
		let title = NSLocalizedString("Next Unread Work", comment: "Next Unread Article")
		return UIAction(title: title, image: Assets.Images.nextUnread) { [weak self] _ in
			self?.coordinator.selectNextUnread()
		}
	}

	/// Explicit per-article "Check for updates" for a single AO3 work (not an anthology
	/// or combined-series bookKey) with no unresolved pending update. Deliberately no
	/// bulk equivalent.
	///
	/// For an Ambrosia article with `AmbrosiaAO3NetworkPreference.updatesEnabled` off,
	/// the action is returned disabled with an explanatory label rather than nil, so the
	/// row explains why it's inert instead of vanishing.
	func checkForUpdatesAction() -> UIAction? {
		// A pending update blocks re-checking, which would leave the menu empty for the
		// state that most needs action; offer the review alert instead.
		if let article, article.pendingUpdateContentHTML != nil, article.account != nil {
			let title = NSLocalizedString("Review Pending Update", comment: "Command: a fetched AO3 update is waiting for the person to accept or keep")
			return UIAction(title: title, image: Assets.Images.checkForUpdates) { [weak self] _ in
				self?.presentPendingContentUpdateAlertIfNeeded()
			}
		}
		guard let article, AO3FetchPolicy.canCheckForUpdates(for: article) else { return nil }
		guard AO3FetchPolicy.isNetworkRequestAllowed(for: article) else {
			let title = NSLocalizedString("Check for Updates (Enable AO3 Updates in Settings)", comment: "Command, disabled: Ambrosia article with the AO3 network toggle off")
			return UIAction(title: title, image: Assets.Images.checkForUpdates, attributes: .disabled) { _ in }
		}
		let title = NSLocalizedString("Check for Updates", comment: "Command")
		return UIAction(title: title, image: Assets.Images.checkForUpdates) { [weak self] _ in
			guard let article = self?.article else { return }
			AO3ChapterFetcher.shared.checkForUpdates(for: article)
		}
	}

	/// "Ignore This Work" and "Ignore Author" for an AO3 work; empty for anything else.
	/// Ignoring hides future feed items only (see `AO3IgnoreList`), so each action
	/// confirms. An author is offered only with an AO3 URL, since rules match by exact
	/// URL. With several authors, each gets a row named after them.
	func ignoreActions() -> [UIAction] {
		guard let article, let workID = AO3FetchPolicy.workID(fromBookKey: article.bookKey) else {
			return []
		}

		var actions = [UIAction]()
		let workTitle = article.title
		actions.append(UIAction(title: NSLocalizedString("Ignore This Work", comment: "Command: hide future feed items for this AO3 work"), image: UIImage(systemName: "eye.slash")) { [weak self] _ in
			self?.confirmIgnoreWork(id: workID, title: workTitle)
		})

		let authorsWithURLs = (article.authors ?? [])
			.compactMap { author -> (url: String, name: String?)? in
				guard let urlString = author.url, let url = URL(string: urlString), AO3Link.isAO3Host(url) else {
					return nil
				}
				return (urlString, author.name)
			}
			.sorted { ($0.name ?? $0.url) < ($1.name ?? $1.url) }

		for author in authorsWithURLs {
			let title: String
			if authorsWithURLs.count > 1, let name = author.name, !name.isEmpty {
				title = String(format: NSLocalizedString("Ignore Author: %@", comment: "Command: hide future feed items by this AO3 author; %@ is the author's name"), name)
			} else {
				title = NSLocalizedString("Ignore Author", comment: "Command: hide future feed items by this AO3 author")
			}
			actions.append(UIAction(title: title, image: UIImage(systemName: "person.crop.circle.badge.xmark")) { [weak self] _ in
				self?.confirmIgnoreAuthor(url: author.url, name: author.name)
			})
		}
		return actions
	}

	private func confirmIgnoreWork(id: String, title: String?) {
		let message = NSLocalizedString("New feed items for this work will be hidden. It stays in your library, and you can undo this in AO3 settings under Ignored Works and Authors.", comment: "Ignore work confirmation message")
		let alert = UIAlertController(title: NSLocalizedString("Ignore This Work?", comment: "Ignore work confirmation title"), message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: NSLocalizedString("Ignore Work", comment: "Command"), style: .destructive) { _ in
			AO3IgnoreList.ignoreWork(id: id, label: title)
		})
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
		present(alert, animated: true)
	}

	private func confirmIgnoreAuthor(url: String, name: String?) {
		let message = NSLocalizedString("New feed items by this author will be hidden. Their works already in your library stay, and you can undo this in AO3 settings under Ignored Works and Authors.", comment: "Ignore author confirmation message")
		let alert = UIAlertController(title: NSLocalizedString("Ignore This Author?", comment: "Ignore author confirmation title"), message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: NSLocalizedString("Ignore Author", comment: "Command"), style: .destructive) { _ in
			AO3IgnoreList.ignoreAuthor(url: url, label: name)
		})
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
		present(alert, animated: true)
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

	func scrollToHeading(tocIndex: Int) {
		scrollJumpHistory.append(Double(windowScrollY))
		guard let json = try? JSONEncoder().encode(["tocIndex": tocIndex]) else { return }
		let encoded = json.base64EncodedString()
		webView?.evaluateJavaScript("scrollToHeading(\"\(encoded)\")")
	}

	/// Pops the most recent pre-jump position (pushed by scrollToHeading/scrollToAnnotation)
	/// and scrolls back to it; no-op if none. Callers wiring this to a toolbar item should
	/// hide or disable it based on scrollJumpHistory.isEmpty.
	func scrollBack() {
		guard let previousY = scrollJumpHistory.popLast() else { return }
		let payload = ["y": previousY]
		guard let json = try? JSONEncoder().encode(payload) else { return }
		let encoded = json.base64EncodedString()
		webView?.evaluateJavaScript("scrollToWindowY(\"\(encoded)\")")
	}

	var isScrollBackAvailable: Bool {
		!scrollJumpHistory.isEmpty
	}

	func scrollToTop() {
		webView?.evaluateJavaScript("window.scrollTo({ top: 0, behavior: 'instant' });")
	}

	func scrollToBottom() {
		webView?.evaluateJavaScript("window.scrollTo({ top: document.body.scrollHeight, behavior: 'instant' });")
	}

}
