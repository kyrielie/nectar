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

	// Inline series navigation (nectar-inline-series-nav-implementation-
	// plan.md, Phase 3a) -- the private, non-web URL scheme
	// AO3PrefaceRenderer's First/Previous/Next links use
	// (`nectar-series:<direction>?ao3id=...&workurl=...`), recognized in
	// decidePolicyFor navigationAction below.
	private static let nectarSeriesScheme = "nectar-series"

	private var topShowBarsView: UIView!
	private var bottomShowBarsView: UIView!
	private var topShowBarsViewConstraint: NSLayoutConstraint!
	private var bottomShowBarsViewConstraint: NSLayoutConstraint!

	// §6/§7: persistent notch mask + page counter, both only ever visible
	// while fullscreen reading mode is actually active (bars hidden) -- see
	// updateNotchAndPageCounterVisibility(), called from showBars()/hideBars().
	// Distinct from topShowBarsView above: that view is an invisible tap
	// target that's pulled off-screen while fullscreen, not a persistent
	// mask over the notch itself.
	private var notchCoverView: UIView!
	private var pageCounterLabel: UILabel!

	// The only authoritative reference to "the" current webview. Previously this was
	// a computed property returning view.subviews[0], which silently returned whichever
	// PreloadedWebView happened to be backmost if more than one was ever inserted --
	// see loadWebViewGeneration below for why that could happen, and why subviews[0]
	// is not a safe way to identify it.
	private var webView: PreloadedWebView?

	// Inline series navigation (nectar-inline-series-nav-implementation-
	// plan.md, Phase 4e). Per-(series, direction) in-flight/failure state
	// for the links AO3PrefaceRenderer renders directly into the article
	// -- replaces Task 10's single-slot `seriesNavigationInFlight`/
	// `isFetchingFirstWorkInSeries`/`seriesNavigationFailureMessage`
	// (deleted along with the context-menu actions they backed, see
	// handleNectarSeriesLink below). Two different series' Previous
	// links (or the same series' Previous and Next) must be able to be
	// in-flight/failed independently, hence a dictionary keyed on
	// `SeriesNavKey` rather than one shared flag. Reset whenever
	// `article` changes -- see `article` didSet.
	private struct SeriesNavKey: Hashable {
		let ao3SeriesID: String
		let direction: AO3SeriesNavigator.Direction
	}
	private enum SeriesNavState {
		case inFlight
		case failed(String)
	}
	private var seriesNavState: [SeriesNavKey: SeriesNavState] = [:]

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
			// Per-article persistence (Phase 2). The single-global AppDefaults
			// write that used to sit here has been removed -- see the comments
			// on ArticleViewController.setScrollPosition(articleWindowScrollY:)
			// and AppDefaults.articleWindowScrollY, now also deleted: relaunch
			// and Handoff restore were already migrated to this per-book path
			// (SceneCoordinator.restoreSelectedSidebarItemAndArticle/selectArticle),
			// leaving the global write with zero readers.
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

		// Deployment target is iOS 17+ (xcconfig/NetNewsWire_project.xcconfig,
		// IPHONEOS_DEPLOYMENT_TARGET = 17.0), so use registerForTraitChanges rather
		// than the traitCollectionDidChange override it deprecated. Without this,
		// webView.backgroundColor / notchCoverView / pageCounterLabel stay resolved
		// off a stale trait snapshot when the person flips Settings -> Appearance (or
		// the system auto-switches) while an article is open -- the article body's
		// own CSS repaints live via @media prefers-color-scheme, but these native
		// colors previously only re-resolved on the next full renderPage.
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: WebViewController, previousTraitCollection: UITraitCollection) in
			guard self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle else { return }
			// TEMPORARY (nectar-theme-background-toolbar-plan.md item 2 investigation) --
			// remove once the live-switch background bug is confirmed fixed on-device.
			Self.logger.debug("registerForTraitChanges: fired previous=\(previousTraitCollection.userInterfaceStyle.rawValue, privacy: .public) new=\(self.traitCollection.userInterfaceStyle.rawValue, privacy: .public) webViewTrait=\(self.webView?.traitCollection.userInterfaceStyle.rawValue ?? -1, privacy: .public) inAppPalette=\(AppDefaults.userInterfaceColorPalette.rawValue, privacy: .public) articleID=\(self.article?.articleID ?? "nil", privacy: .public)")
			self.applyResolvedBackgroundColors()
			self.logCSSColorSchemeAgreement(context: "registerForTraitChanges")
		}

		// Configure the tap zones
		configureTopShowBarsView()
		configureBottomShowBarsView()
		configureNotchCoverView()
		// Without this, notchCoverView stays at its configureNotchCoverView() default
		// (isHidden = true) until the first showBars()/hideBars() call -- which, for a
		// freshly-paged-in article in the fullscreen pager, can land a frame or more
		// after this view is already on screen, showing a real flash of the bare notch
		// on every page turn. renderPage() below will refresh the color/text again once
		// the theme is known; this just gets visibility correct immediately.
		//
		// Resolve the theme colors ourselves here rather than calling
		// updateNotchAndPageCounterVisibility() bare: at this point renderPage()
		// hasn't run yet and webView is still nil (it's only assigned inside
		// loadWebView()'s async dequeue completion), so updateNotchAndPageCounterVisibility's
		// own "reuse webView.backgroundColor" fallback has nothing to reuse. If
		// shouldHideNotch is on, notchCoverView can go visible right here, with no
		// background color ever set on it -- it shows whatever's behind it (this
		// controller's own view, i.e. the surrounding chrome) instead of the
		// article's theme background, until the async renderPage() catches up a
		// frame or more later. Passing the resolved colors explicitly closes that
		// window. self.traitCollection is safe to read here (unlike the bare
		// Assets.Colors namespace -- see nectar-architecture.md's "Article
		// background/notch color pipeline"): the view is already loaded, so this
		// is a real view's own trait collection, not the ambient current one.
		let initialColors = Self.resolvedArticleColors(isDark: traitCollection.userInterfaceStyle == .dark)
		updateNotchAndPageCounterVisibility(resolvedBackground: initialColors.background, resolvedText: initialColors.text)

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

	@objc func ao3ChapterFetchDidComplete(_ note: Notification) {
		guard let fetchedArticleID = note.userInfo?[AO3ChapterFetchUserInfoKey.articleID] as? String,
		      let article, article.articleID == fetchedArticleID, let account = article.account else {
			return
		}
		Task {
			// Re-fetch the Article rather than mutating in place -- contentHTML
			// (and chapterCurrent) just changed underneath the copy this view
			// controller is holding, and Article's stored properties are
			// immutable (see Article.swift).
			let refetchedArticles = await account.fetchArticlesAsync(.articleIDs([fetchedArticleID]))
			guard let refetchedArticle = refetchedArticles.first, self.article?.articleID == fetchedArticleID else {
				return
			}
			self.article = refetchedArticle
			// Preface flash fix: this used to be loadWebView(reason:), a full
			// reload of the whole document. AO3ChapterFetcher finishing just
			// swaps in richer content for the same article that's already on
			// screen -- an in-place DOM update instead of a navigation avoids
			// the visible blank-and-repaint. See updateArticleBodyInPlace(reason:).
			self.updateArticleBodyInPlace(reason: "ao3ChapterFetchDidComplete(\(fetchedArticleID))")
			// Task 8: this notification also fires when the fetch's result
			// was a detected regression stashed as a pending update rather
			// than written to contentHTML -- offer the "view what changed?"
			// prompt in that case.
			self.presentPendingContentUpdateAlertIfNeeded()
		}
	}

	@objc func ao3ChapterFetchDidFail(_ note: Notification) {
		// Unlike the success path, the Article itself hasn't changed --
		// contentHTML is deliberately left alone on failure (see
		// AO3ChapterFetcher's header comment) -- so there's nothing to
		// re-fetch. Just re-render in place: ArticleRenderer reads the
		// new failure message straight from AO3ChapterFetcher's own
		// storage, keyed by articleID, the next time it builds the body.
		guard let fetchedArticleID = note.userInfo?[AO3ChapterFetchUserInfoKey.articleID] as? String,
		      let article, article.articleID == fetchedArticleID else {
			return
		}
		// Same preface-flash fix as the success path above -- a failure
		// message appearing is a smaller update than a successful chapter
		// fetch, and equally flash-prone under the old full-reload path.
		updateArticleBodyInPlace(reason: "ao3ChapterFetchDidFail(\(fetchedArticleID))")
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
					// Fire-and-forget: no-op for anything but an AO3-sourced
					// article whose stored content looks stale. See
					// AO3ChapterFetcher.fetchIfNeeded and
					// ao3ChapterFetchDidComplete(_:) above for the reload path.
					AO3ChapterFetcher.shared.fetchIfNeeded(for: article)
					// Task 8: if a prior fetch already flagged a pending
					// content update for this article, offer the "view what
					// changed?" prompt on open too, not just right after a
					// fresh fetch completes.
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
		setBottomScrollEdgeEffectHidden(false)
		configureContextMenuInteraction()
		updateNotchAndPageCounterVisibility()
		// setNavigationBarHidden/setToolbarHidden reset interactivePopGestureRecognizer's
		// (and interactiveContentPopGestureRecognizer's) isEnabled back to true as a
		// side effect, which silently overrides articleBackSwipeEnabled = false. Re-apply
		// the gate immediately after so showing the bars doesn't re-enable back-swipe.
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
			// showBars() resets additionalSafeAreaInsets.bottom synchronously; do the
			// equivalent here rather than relying solely on the reactive
			// viewSafeAreaInsetsDidChange -> updateBottomSafeAreaForFullScreen() path.
			// Leaving this asymmetric meant the webview's adjustedContentInset.bottom
			// could still reflect the pre-fullscreen inset for a beat after hideBars()
			// returns, shifting the visible scroll position relative to where it
			// settles once the deferred update finally runs.
			updateBottomSafeAreaForFullScreen()
			setBottomScrollEdgeEffectHidden(true)
			configureContextMenuInteraction()
			updateNotchAndPageCounterVisibility()
			coordinator.applyArticleBackSwipeGating()
		}
	}

	func stopWebViewActivity() {
		if let webView = webView {
			stopMediaPlayback(webView)
			cancelImageLoad(webView)
		}
	}

	/// Task 8's "a newer version exists and looks smaller -- view what
	/// changed?" prompt, shown whenever the current article has an
	/// unresolved pendingUpdateContentHTML diff. Deliberately a lightweight
	/// accept/keep/later choice rather than an inline diff view --
	/// resolving either promotes the pending copy to contentHTML or
	/// discards it, both via Account.resolvePendingContentUpdateAsync,
	/// which also unblocks AO3ChapterFetcher.isStale's auto-fetch gate for
	/// this article again.
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

	/// Builds the full press-and-hold context menu, including the
	/// loved/starred/read toggle row. Also called from those toggle
	/// actions' own handlers (via `refreshVisibleContextMenu`) to rebuild
	/// the menu in place after a tap -- extracted out of
	/// `configurationForMenuAtLocation`'s elementsProvider closure so both
	/// call sites build the exact same menu.
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

		// Previous/Next/First Work in Series used to be here as
		// context-menu actions (Task 10) -- superseded by the inline
		// "First · Previous · Next" links AO3PrefaceRenderer now
		// renders directly in the article (inline-series-navigation
		// plan, Phase 3/4). See handleNectarSeriesLink below.

		menus.append(UIMenu(title: "", options: .displayInline, children: [shareAction()]))

		return UIMenu(title: "", children: menus)
	}

	/// Rebuilds the currently-presented context menu in place after a
	/// loved/starred/read toggle tap. Those three actions set
	/// `keepsMenuPresented = true` (iOS 16+) so the tap doesn't dismiss the
	/// menu, but UIKit doesn't re-invoke `configurationForMenuAtLocation`'s
	/// elementsProvider closure on its own -- `updateVisibleMenu` is the
	/// supported way to swap the presented menu's contents in place, so the
	/// tapped row's icon/title reflect the new state immediately.
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

			// nectar-series: links (inline series navigation, plan Phase
			// 3a) are app-internal navigation, not the external-link case
			// AppDefaults.shared.disableArticleLinks exists to guard --
			// checked before that early-return so the toggle can't
			// silently break this feature (confirmed hazard, plan's
			// Revision notes).
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
		// We need to have at least an unimplemented WKUIDelegate assigned to the WKWebView.  This makes the
		// link preview launch Safari when the link preview is tapped.  In theory, you should be able to get
		// the link from the elementInfo above and transition to SFSafariViewController instead of launching
		// Safari.  As the time of this writing, the link in elementInfo is always nil.  ¯\_(ツ)_/¯
	}

	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		// nectar-series: links are never rendered with target="_blank", so
		// this path shouldn't be reachable for them -- but block rather
		// than assume, same "confirm, don't assume" caution the plan
		// calls for on this mirror check (Phase 3a). No navigation
		// side-effect here either way: decidePolicyFor navigationAction
		// above is the one and only place a tap is actually handled.
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
			// (Routine per-sample log removed -- this fires on every scroll tick and
			// was the single largest noise source in the console during normal
			// reading. The three guards above still log the anomaly cases, which is
			// where the diagnostic value actually is.)

			// Scroll-percentage-gated read marking (Phase 2). scrollHeight includes the
			// full document; innerHeight is the viewport. Once the bottom of the viewport
			// has reached 99% of the document height, treat the article as read.
			if let scrollHeight = result["scrollHeight"] as? Double, scrollHeight > 0,
			   let innerHeight = result["innerHeight"] as? Double {
				let percentScrolled = (Double(javascriptScrollY) + innerHeight) / scrollHeight
				if percentScrolled >= 0.99 {
					self.coordinator.markCurrentArticleAsReadFromScrollCompletion()
				}

				// Page counter (§7). Reuses this same JS bridge payload rather than
				// adding a second round trip -- percentScrolled/scrollHeight/innerHeight
				// are already exactly what's needed.
				switch AppDefaults.shared.pageCounterDisplayMode {
				case .off:
					break
				case .percentage:
					let clamped = min(max(percentScrolled, 0), 1)
					self.pageCounterLabel.text = "\(Int((clamped * 100).rounded()))%"
				case .pageCount:
					let totalPages = max(1, Int((scrollHeight / innerHeight).rounded(.up)))
					let currentPage = min(totalPages, Int((Double(javascriptScrollY) / innerHeight).rounded()) + 1)
					self.pageCounterLabel.text = "\(currentPage)/\(totalPages)"
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

				// Pinch-zoom is disabled unconditionally (not a Settings
				// toggle -- reading position/layout, not appearance).
				// setZoomScale above is only a one-time reset, not a lock:
				// disabling the pinch gesture recognizer is what actually
				// prevents zooming; the min/max clamp is defense-in-depth
				// for any other path that might still try to set a scale.
				// Reasserted on every dequeue, same pooling concern as
				// scrollsToTop/showsVerticalScrollIndicator below --
				// PreloadedWebView instances are reused, not recreated.
				webView.scrollView.pinchGestureRecognizer?.isEnabled = false
				webView.scrollView.minimumZoomScale = 1.0
				webView.scrollView.maximumZoomScale = 1.0

				// Tapping the status bar performs scrollsToTop on the first eligible
				// scroll view, which jumps the article back to its beginning and
				// discards the reader's place. PreloadedWebView instances are pooled
				// and reused (see loadWebViewGeneration above), so this must be set
				// on every dequeue rather than once at creation.
				webView.scrollView.scrollsToTop = false

				// Same pooling concern as scrollsToTop above: reasserted on every
				// dequeue rather than once at creation, and read fresh (not cached)
				// so a Settings change takes effect on the next article open without
				// needing a relaunch.
				webView.scrollView.showsVerticalScrollIndicator = AppDefaults.shared.showArticleScrollbar

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

	/// Preface-flash fix (see ao3ChapterFetchDidComplete(_:)/ao3ChapterFetchDidFail(_:)):
	/// re-renders the current article's body HTML and swaps it into the
	/// already-loaded page's `#bodyContainer` via `main_ios.js`'s
	/// `updateArticleBody`, instead of `loadWebView`'s full
	/// `loadHTMLString` reload. `template.html` funnels the synthetic/real
	/// preface, article content, and series footer through one `[[body]]`
	/// substitution into `#bodyContainer`, so this one swap covers all
	/// three without special-casing the preface.
	///
	/// Falls back to a full `loadWebView(reason:)` reload if there's no
	/// existing web view to update in place (e.g. the notification landed
	/// before the first render finished) -- same safety net a `nil` webView
	/// would otherwise just silently no-op against.
	private func updateArticleBodyInPlace(reason: String) {
		guard let webView else {
			loadWebView(reason: reason)
			return
		}
		guard let article else { return }

		let theme = ArticleThemesManager.shared.currentTheme
		let rendering = ArticleRenderer.articleHTML(article: article, theme: theme, timelineFeed: coordinator?.timelineFeed)

		guard let json = try? JSONEncoder().encode(UpdateArticleBodyOptions(html: rendering.html)) else {
			Self.logger.debug("updateArticleBodyInPlace: failed to encode body HTML, falling back to full reload, reason=\(reason, privacy: .public)")
			loadWebView(reason: reason)
			return
		}
		let encoded = json.base64EncodedString()
		Self.logger.debug("updateArticleBodyInPlace: articleID=\(article.articleID, privacy: .public) reason=\(reason, privacy: .public) bodyLength=\(rendering.html.count, privacy: .public)")
		webView.evaluateJavaScript("updateArticleBody(\"\(encoded)\");")
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
			"importStyle": rendering.importStyle,
			"style": rendering.style,
			"body": rendering.html,
			// Device-locale fallback, not per-article language -- no per-feed/
			// per-article language field exists anywhere in Modules/Articles or
			// Modules/Account today (RSS/JSON Feed language isn't parsed), so this
			// is the best available value without a separate, larger feed-parsing
			// change. Needed for hyphens: auto (see ArticleThemeOverrides.hyphenate)
			// to pick the correct hyphenation dictionary in WebKit, which is
			// unreliable without a lang attribute on <html> -- confirmed
			// page.html shipped with none before this change (dir="auto" only).
			"lang": Locale.current.language.languageCode?.identifier ?? "en"
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

		applyResolvedBackgroundColors()

		webView.loadHTMLString(html, baseURL: URL(string: rendering.baseURL))
	}

	// §1a. WKWebView defaults to .systemBackground (see PreloadedWebView.init) until
	// this runs, which is near-black in dark mode -- resolve the theme's actual
	// background before loadHTMLString commits the navigation, so there's no flash
	// of the wrong color. Precedence: override background (if set) -> theme's own
	// background -> ArticleThemeColorExtractor's black/white fallback.
	//
	// Also re-run on its own, without a full renderPage/HTML reload, from the
	// registerForTraitChanges handler installed in viewDidLoad: the webview's own
	// CSS already updates live via @media prefers-color-scheme when the app's
	// Appearance setting or the system trait changes, but these native UIKit-side
	// colors were previously only resolved once per renderPage call and went stale
	// until the article was reopened or the theme changed. See nectar-architecture.md,
	// "Article background/notch color pipeline."
	private func applyResolvedBackgroundColors() {
		guard let webView else { return }

		let isDark = webView.traitCollection.userInterfaceStyle == .dark
		let colors = Self.resolvedArticleColors(isDark: isDark)
		// TEMPORARY (nectar-theme-background-toolbar-plan.md item 2 investigation).
		Self.logger.debug("applyResolvedBackgroundColors: isDark=\(isDark, privacy: .public) background=\(colors.background.cssHexString, privacy: .public) articleID=\(self.article?.articleID ?? "nil", privacy: .public)")
		webView.backgroundColor = colors.background
		webView.underPageBackgroundColor = colors.background
		webView.scrollView.backgroundColor = colors.background

		// Keep the notch cover / page counter in sync with the same resolved color and
		// text color on every render, not just on the next bars-toggle -- otherwise they
		// keep showing whatever was last set, stale, through an article/theme change.
		updateNotchAndPageCounterVisibility(resolvedBackground: colors.background, resolvedText: colors.text)
	}

	// TEMPORARY (nectar-theme-background-toolbar-plan.md item 2 investigation) --
	// confirms whether WKWebView's own prefers-color-scheme media query has
	// actually re-evaluated by the time the native trait-change handler fires,
	// or whether it lags behind. Remove alongside the other temporary logging
	// in this investigation once confirmed. Called only from the
	// registerForTraitChanges closure above, not from inside
	// applyResolvedBackgroundColors() itself -- that function also runs from
	// renderPage() before loadHTMLString has committed a document, where a JS
	// evaluation would just fail harmlessly and add noise. The trait-change
	// path is the one that matters for this repro (already-open article), and
	// it's guaranteed to have a loaded document.
	private func logCSSColorSchemeAgreement(context: String) {
		webView?.evaluateJavaScript("JSON.stringify({prefersDark: window.matchMedia('(prefers-color-scheme: dark)').matches, bodyBackground: getComputedStyle(document.body).backgroundColor})") { result, error in
			if let error {
				Self.logger.debug("\(context, privacy: .public): CSS-side check failed, error=\(error.localizedDescription, privacy: .public)")
				return
			}
			Self.logger.debug("\(context, privacy: .public): CSS-side reports \(String(describing: result), privacy: .public)")
		}
	}

	/// Precedence: override background (if set) -> theme's own background ->
	/// ArticleThemeColorExtractor's black/white fallback -- shared by
	/// applyResolvedBackgroundColors() (once webView exists) and viewDidLoad's
	/// own initial notch-cover resolution (before webView exists), so both
	/// paths agree instead of one of them falling back to whatever's currently
	/// on screen. Static/no webView dependency deliberately: the caller
	/// supplies isDark from whichever trait collection is actually valid at
	/// its own call site.
	private static func resolvedArticleColors(isDark: Bool) -> (background: UIColor, text: UIColor) {
		let theme = ArticleThemesManager.shared.currentTheme
		let overrides = AppDefaults.shared.articleThemeOverrides
		return ArticleResolvedColors.resolved(theme: theme, isDark: isDark, overrideBackgroundColorHex: overrides.backgroundColorHex, overrideBackgroundColorDarkHex: overrides.backgroundColorDarkHex)
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

	// §6/§7. notchCoverView spans the top safe-area inset (the notch/Dynamic
	// Island's own footprint) -- pinned view.topAnchor to
	// view.safeAreaLayoutGuide.topAnchor rather than a fixed height, so it
	// tracks whatever that inset actually is on the current device without
	// needing to recompute anything when it changes. pageCounterLabel sits
	// on top of it, leading-aligned per the current design (a single label,
	// not mirrored on both sides).
	func configureNotchCoverView() {
		notchCoverView = UIView()
		notchCoverView.isHidden = true
		notchCoverView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(notchCoverView)

		NSLayoutConstraint.activate([
			notchCoverView.topAnchor.constraint(equalTo: view.topAnchor),
			notchCoverView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			notchCoverView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			notchCoverView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
		])

		// notchCoverView overlaps topShowBarsView's tap zone whenever the notch is
		// hidden, silently swallowing the tap meant to bring the bars back (it's an
		// opaque UIView added after topShowBarsView, so it sits on top in z-order).
		// Rather than making it pass-through, fold it into the same reveal gesture --
		// the whole masked strip is a reasonable extension of the tap-to-reveal zone.
		notchCoverView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showBars(_:))))

		pageCounterLabel = UILabel()
		pageCounterLabel.font = .preferredFont(forTextStyle: .caption2)
		pageCounterLabel.textColor = .label
		pageCounterLabel.isHidden = true
		pageCounterLabel.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(pageCounterLabel)

		NSLayoutConstraint.activate([
			pageCounterLabel.centerYAnchor.constraint(equalTo: notchCoverView.centerYAnchor),
			// NOTE: was 20pt, reported as still clipped by the corner curvature on
			// iPhone 17 in the simulator -- bumped to Self.pageCounterLeadingInset as a
			// starting point (topShowBarsView's own 44pt tap-zone height, not a fresh
			// guess), but this needs re-checking against an iPhone 17 simulator/device
			// before treating it as correct. Do not further adjust this blind.
			pageCounterLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Self.pageCounterLeadingInset)
		])
	}

	private static let pageCounterLeadingInset: CGFloat = 44

	/// Called from showBars()/hideBars() (no args -- reuses whatever color was last
	/// resolved by renderPage()) and from renderPage() itself (explicit args, so the
	/// notch cover/label track the theme's actual color on every render instead of
	/// only refreshing on the next bars-toggle). Visibility is gated on
	/// isFullScreenAvailable (device + the general "Enable Full Screen
	/// Articles" setting) rather than the momentary articleFullscreenEnabled
	/// flag that showBars()/hideBars() flip on every tap-to-reveal -- the
	/// notch cover sits entirely above where a revealed nav bar renders, so
	/// there's no visual conflict with keeping it up while bars are
	/// momentarily peeked at, and tying it to the peek state was what made it
	/// flicker in and out during ordinary reading/scrolling.
	func updateNotchAndPageCounterVisibility(resolvedBackground: UIColor? = nil, resolvedText: UIColor? = nil) {
		let pageCounterOn = AppDefaults.shared.pageCounterDisplayMode != .off
		// The page counter implies notch-hiding on its own -- a visible
		// counter over a still-visible notch would look broken -- without
		// requiring hideNotchInFullScreen to also be switched on.
		let shouldHideNotch = AppDefaults.shared.hideNotchInFullScreen || pageCounterOn

		// Prefer the just-resolved theme color (renderPage's call); otherwise reuse
		// webView.backgroundColor, which renderPage's §1a fix keeps theme-accurate
		// between renders, rather than falling back to .systemBackground (the stale,
		// often near-black-in-dark-mode default this used to fall back to).
		if let resolvedBackground {
			notchCoverView.backgroundColor = resolvedBackground
		} else if let webViewBackground = webView?.backgroundColor {
			notchCoverView.backgroundColor = webViewBackground
		}
		if let resolvedText {
			pageCounterLabel.textColor = resolvedText
		}
		notchCoverView.isHidden = !(shouldHideNotch && isFullScreenAvailable)
		pageCounterLabel.isHidden = !(pageCounterOn && isFullScreenAvailable)
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
		// circleOpen/circleClosed match ArticleViewController's own toolbar
		// convention (updateUI(): read -> circleOpen, unread -> circleClosed) --
		// this was previously inverted here.
		let readImage = article.status.read ? Assets.Images.circleOpen : Assets.Images.circleClosed
		let action = UIAction(title: title, image: readImage, attributes: .keepsMenuPresented) { [weak self] _ in
			self?.coordinator.toggleReadForCurrentArticle()
			self?.refreshVisibleContextMenu()
		}
		return action
	}

	func toggleStarredAction() -> UIAction {
		let starred = article?.status.starred ?? false
		let title = starred ? NSLocalizedString("Remove from Read Later", comment: "Command") : NSLocalizedString("Add to Read Later", comment: "Command")
		// starClosed/starOpen match ArticleViewController's own toolbar
		// convention (updateUI(): starred -> starClosed, not starred ->
		// starOpen) -- this was previously inverted here.
		let starredImage = starred ? Assets.Images.starClosed : Assets.Images.starOpen
		let action = UIAction(title: title, image: starredImage, attributes: .keepsMenuPresented) { [weak self] _ in
			self?.coordinator.toggleStarredForCurrentArticle()
			self?.refreshVisibleContextMenu()
		}
		return action
	}

	func toggleLovedAction() -> UIAction {
		let loved = article?.status.loved ?? false
		let title = loved ? NSLocalizedString("Remove from Loved", comment: "Command") : NSLocalizedString("Add to Loved", comment: "Command")
		// heartClosed/heartOpen match ArticleViewController's own toolbar
		// convention (updateUI(): loved -> heartClosed, not loved ->
		// heartOpen) -- this was previously inverted here.
		let lovedImage = loved ? Assets.Images.heartClosed : Assets.Images.heartOpen
		let action = UIAction(title: title, image: lovedImage, attributes: .keepsMenuPresented) { [weak self] _ in
			self?.coordinator.toggleLovedForCurrentArticle()
			self?.refreshVisibleContextMenu()
		}
		return action
	}

	func nextUnreadArticleAction() -> UIAction? {
		guard coordinator.isNextUnreadAvailable else { return nil }
		let title = NSLocalizedString("Next Unread Article", comment: "Next Unread Article")
		return UIAction(title: title, image: Assets.Images.nextUnread) { [weak self] _ in
			self?.coordinator.selectNextUnread()
		}
	}

	/// Task 8's explicit per-article "Check for updates" action --
	/// available for any single-AO3-work article (not an anthology/
	/// combined-series bookKey) with no unresolved pending-update diff,
	/// regardless of read state or how "settled" the article currently
	/// looks. Deliberately no bulk "check all" equivalent.
	///
	/// For an Ambrosia-sourced article with `AmbrosiaAO3NetworkPreference.updatesEnabled`
	/// off, this still returns an action (per the plan: disabled with
	/// an explanatory label, not removed) rather than nil, so the menu row
	/// stays present and tells the person why it's inert instead of
	/// silently vanishing.
	func checkForUpdatesAction() -> UIAction? {
		guard let article, AO3ChapterFetcher.shared.canCheckForUpdates(for: article) else { return nil }
		guard AO3ChapterFetcher.isAO3NetworkRequestAllowed(for: article) else {
			let title = NSLocalizedString("Check for Updates (Enable AO3 Updates in Settings)", comment: "Command, disabled: Ambrosia article with the AO3 network toggle off")
			return UIAction(title: title, image: Assets.Images.checkForUpdates, attributes: .disabled) { _ in }
		}
		let title = NSLocalizedString("Check for Updates", comment: "Command")
		return UIAction(title: title, image: Assets.Images.checkForUpdates) { [weak self] _ in
			guard let article = self?.article else { return }
			AO3ChapterFetcher.shared.checkForUpdates(for: article)
		}
	}

	/// Handles a tap on one of the `nectar-series:` links `AO3PrefaceRenderer`
	/// builds into the preface's Series row and the "This work is part
	/// of" footer (plan Phase 3a/3b) -- `first?ao3id=<id>`,
	/// `previous?ao3id=<id>&workurl=<permalink>`, or
	/// `next?ao3id=<id>&workurl=<permalink>`. `url.path` carries the
	/// direction: for a non-hierarchical URI like
	/// `nectar-series:previous?...` (no `//` authority), `URLComponents`
	/// parses everything between the scheme colon and the query string
	/// as `path`, not `host` -- there is no `nectar-series://previous`
	/// form here.
	///
	/// Replaces Task 10's `previousWorkAction`/`nextWorkAction`/
	/// `firstWorkInSeriesAction` context-menu trio and the interim
	/// single-work `handleNectarSeriesLink` shim that called
	/// `AO3SeriesNavigator.fetchAdjacentWork`/`fetchFirstWorkInSeries` --
	/// both deleted. This is the plan's Phase 4c/4d/4e flow: bounded
	/// two-page series-listing walk via `AO3SeriesNavigator.openSeriesWork`,
	/// return to the timeline via `SceneCoordinator.navigateToTimelineAndSelectArticle`
	/// rather than staying inside the reader, and a JS repaint of the
	/// tapped link's own text/disabled state via `updateNectarSeriesLink`
	/// while the fetch is in flight.
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

		// targetIndex (Phase 4c): only meaningful for .previous/.next,
		// derived from this article's own matching series entry's index
		// +/- 1 -- used to compute which listing page the target falls
		// on if openSeriesWork doesn't find it on page 1. Left nil for
		// .first (unused there) and for a series entry that, for
		// whatever reason, isn't present on this article (openSeriesWork
		// then has no page-fetch fallback and reports
		// .seriesListingMismatch instead of guessing a page).
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

			// The person may have navigated to a different article while
			// this was in flight -- state and on-page repaint both
			// belong to whichever article originated the tap, which may
			// no longer be the one showing now.
			guard self.article?.articleID == article.articleID else { return }

			switch result {
			case .success(let newArticleID):
				Self.logger.debug("handleNectarSeriesLink: openSeriesWork succeeded, newArticleID=\(newArticleID, privacy: .public)")
				self.seriesNavState[key] = nil
				self.updateNectarSeriesLinkUI(key: key, disabled: false)
				self.coordinator.navigateToTimelineAndSelectArticle(newArticleID)
			case .failure(let error):
				self.seriesNavState[key] = .failed(error.displayMessage)
				self.updateNectarSeriesLinkUI(key: key, disabled: false)
				UIAccessibility.post(notification: .announcement, argument: error.displayMessage)
				Self.logger.debug("nectar-series link navigation failed: \(error.displayMessage, privacy: .public)")
			}
		}
	}

	/// The label AO3PrefaceRenderer originally rendered for this
	/// direction ("First"/"Previous"/"Next") -- what the link's text is
	/// restored to once its fetch finishes, success or failure alike.
	/// Failure is surfaced via `UIAccessibility.post` above, not by
	/// changing this label, since `updateNectarSeriesLink`'s JS side
	/// only swaps text/disabled state, not styling per-error-message.
	private func seriesNavLabel(for direction: AO3SeriesNavigator.Direction) -> String {
		switch direction {
		case .first: return NSLocalizedString("First", comment: "Inline series navigation link")
		case .previous: return NSLocalizedString("Previous", comment: "Inline series navigation link")
		case .next: return NSLocalizedString("Next", comment: "Inline series navigation link")
		}
	}

	/// Repaints every on-page occurrence of `key`'s link (Phase 4e) --
	/// `main_ios.js`'s `updateNectarSeriesLink` is `querySelectorAll`-shaped
	/// since the same series' link can appear twice (preface row and
	/// footer). `seriesKey` here must match the `data-nectar-series-key`
	/// format `AO3PrefaceRenderer.seriesNavKey(ao3ID:direction:)` stamps
	/// onto the rendered `<a>` (`"<ao3ID>|<direction>"`, lowercase
	/// direction string) -- kept in sync by hand since one side is Swift
	/// and the other is the renderer's own string building.
	private struct UpdateNectarSeriesLinkOptions: Encodable {
		let seriesKey: String
		let label: String
		let disabled: Bool
	}

	/// Options for `main_ios.js`'s `updateArticleBody` -- see
	/// updateArticleBodyInPlace(reason:) above.
	private struct UpdateArticleBodyOptions: Encodable {
		let html: String
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

	/// Routes an in-app link open through the AO3-authenticated browser
	/// (see AO3AuthenticatedWebViewController) when the URL is an AO3
	/// domain, or SFSafariViewController otherwise -- the common case is
	/// unchanged. Every in-app "open this URL" path in this file should
	/// call this rather than openURLInSafariViewController(_:) directly,
	/// so AO3 links get the persistent-session browser regardless of
	/// which path (link tap, share sheet, showActivityDialog) they came
	/// through.
	///
	/// No AO3SessionStore.isSignedIn check here -- unlike the plan's
	/// original sketch. AO3AuthenticatedWebViewController's own
	/// persistent WKWebsiteDataStore remembers a sign-in performed
	/// directly inside it (WebKit's normal cookie persistence, nothing
	/// this code needs to manage), so there's no "signed out" case that
	/// needs to fall back to a different browser -- an AO3 link always
	/// goes to the dedicated browser, whether or not a session exists
	/// yet.
	func openURLInAppBrowser(_ url: URL) {
		if AO3LinkListImporter.isAO3Host(url) {
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
	/// True for Calibre's "Afterword" closer and a one-shot's repeated title
	/// heading. Not used for book/chapter grouping (tagName does that job —
	/// see TableOfContentsViewController.chaptersByBook); kept as a signal
	/// for possible future UI treatment (e.g. visually de-emphasizing these
	/// rows), currently unread elsewhere.
	let isTocHeading: Bool
}

extension WebViewController {

	/// Entries are addressed by `tocIndex` (position among all h1/h2.heading/
	/// h2.toc-heading elements in document order), not `id` — anthology content
	/// reuses the same id (e.g. "calibre_toc_3") across separate concatenated
	/// books, so `id` alone can't distinguish "chapter 3 of book 1" from
	/// "chapter 3 of book 2." See main_ios.js's tocNodes()/getTableOfContents/
	/// scrollToHeading.
	func fetchTableOfContents(completionHandler: @escaping ([TableOfContentsEntry]) -> Void) {
		webView?.evaluateJavaScript("getTableOfContents(\"e30=\")") { result, error in   // "e30=" == base64("{}")
			if let error {
				Self.logger.error("fetchTableOfContents: getTableOfContents() JS call failed: \(error.localizedDescription, privacy: .public)")
				completionHandler([])
				return
			}
			guard let b64 = result as? String, let data = Data(base64Encoded: b64) else {
				Self.logger.error("fetchTableOfContents: getTableOfContents() returned an unexpected result type or invalid base64")
				completionHandler([])
				return
			}
			guard let entries = try? JSONDecoder().decode([TableOfContentsEntry].self, from: data) else {
				Self.logger.error("fetchTableOfContents: failed to decode TableOfContentsEntry array from getTableOfContents() result")
				completionHandler([])
				return
			}
			completionHandler(entries)
		}
	}

	func scrollToHeading(tocIndex: Int) {
		guard let json = try? JSONEncoder().encode(["tocIndex": tocIndex]) else { return }
		let encoded = json.base64EncodedString()
		webView?.evaluateJavaScript("scrollToHeading(\"\(encoded)\")")
	}

}
