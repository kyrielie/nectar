//
//  ArticleViewController.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 4/8/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import SwiftUI
import os
import SafariServices
import WebKit
import RSCore
import Account
import Articles

final class ArticleViewController: UIViewController, SurfacePaletteNavigationBarAware {

	// The only SurfacePaletteNavigationBarAware adopter with an actual article
	// on screen to blend the bar with -- see supportsBlendToolbarStyle's own
	// doc comment. MainFeed/MainTimeline stay on the protocol's default false.
	var supportsBlendToolbarStyle: Bool { true }

	// Strong (see comment on the block below): conditionally left out of
	// toolbarItems by bottomToolbarItems() same as the other four.
	@IBOutlet private var nextUnreadBarButtonItem: UIBarButtonItem!
	// Strong, unlike a plain @IBOutlet weak var: these five are now
	// conditionally left out of toolbarItems by bottomToolbarItems() (see
	// BottomToolbarToggle/AppDefaults.isBottomToolbarToggleEnabled(_:)), and
	// nothing else retains them when they're not currently in that array.
	// Weak outlets with no other owner get deallocated, which crashed
	// updateUI()'s isEnabled assignments below when a toggle was off
	// (Fatally unwrapped Optional value) -- same failure mode
	// prevArticleBarButtonItem/nextArticleBarButtonItem already guard
	// against below for the top-toolbar prevNext toggle, now needed here
	// too since these five are no longer unconditionally in toolbarItems.
	@IBOutlet private var prevArticleBarButtonItem: UIBarButtonItem!
	@IBOutlet private var nextArticleBarButtonItem: UIBarButtonItem!
	@IBOutlet private var readBarButtonItem: UIBarButtonItem!
	@IBOutlet private var starBarButtonItem: UIBarButtonItem!
	@IBOutlet private var actionBarButtonItem: UIBarButtonItem!

	// Phase 5/6 fork additions. Code-constructed rather than @IBOutlet like the
	// items above -- toolbarItems/navigationItem are already fully assembled in
	// code in viewDidLoad, so there's no need to touch the storyboard for these.
	// heartOpen/heartClosed/theme are SF Symbols (Assets.swift), not custom
	// asset catalog entries -- no catalog work was ever needed here.
	private lazy var heartBarButtonItem = UIBarButtonItem(image: Assets.Images.heartOpen, style: .plain, target: self, action: #selector(toggleLoved(_:)))
	private lazy var themeBarButtonItem = UIBarButtonItem(image: Assets.Images.theme, style: .plain, target: self, action: #selector(showThemePicker(_:)))
	private lazy var findInArticleBarButtonItem = UIBarButtonItem(image: Assets.Images.findInArticle, style: .plain, target: self, action: #selector(beginFind(_:)))
	private lazy var tableOfContentsBarButtonItem = UIBarButtonItem(image: Assets.Images.tableOfContents, style: .plain, target: self, action: #selector(showTableOfContents(_:)))
	// Optional gesture-lock toggle (AppDefaults.articleToolbarShowLock). SF
	// Symbol rather than an Assets.Images entry, unlike the other three bar
	// buttons above -- see toggleGesturesLocked(_:), which flips the image
	// between "lock"/"lock.open" in place, the same way toggleLoved(_:)
	// flips heartBarButtonItem's image, rather than rebuilding
	// rightBarButtonItems() on every tap.
	private lazy var lockBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "lock.open"), style: .plain, target: self, action: #selector(toggleGesturesLocked(_:)))
	// Direct action, like tableOfContentsBarButtonItem above -- this used
	// to open a two-item menu (This Chapter / All of This Book), but
	// showAnnotationsList now always shows one grouped, whole-book view
	// (see showAnnotationsList's own doc comment), so there's no longer a
	// choice to present a menu for.
	private lazy var annotationsBarButtonItem = UIBarButtonItem(image: Assets.Images.annotations, style: .plain, target: self, action: #selector(showAnnotationsList(_:)))
	// Opens Settings scrolled to the Articles section -- independent of
	// whatever's on screen in the reader, so safe to call regardless of
	// the reader's own presentation state. See showSettingsFromToolbar(_:).
	private lazy var settingsBarButtonItem = UIBarButtonItem(image: Assets.Images.settings, style: .plain, target: self, action: #selector(showSettingsFromToolbar(_:)))
	// Per-article eligibility (AO3ChapterFetcher.canCheckForUpdates(for:))
	// is not evaluated here -- this item is always constructed; updateUI()
	// toggles isEnabled per-article each time `article` changes. See
	// updateUI()'s checkForUpdatesBarButtonItem handling.
	private lazy var checkForUpdatesBarButtonItem = UIBarButtonItem(image: Assets.Images.checkForUpdates, style: .plain, target: self, action: #selector(checkForUpdatesFromToolbar(_:)))
	// Optional collapsed-toolbar mode (AppDefaults.articleToolbarUseOverflowMenu).
	// Menu is rebuilt in place by rebuildOverflowMenu() rather than this item
	// being recreated -- same shape as MainTimelineModernViewController's
	// markAllAsReadButton/rebuildMarkAllAsReadMenu().
	private lazy var overflowBarButtonItem = UIBarButtonItem(image: Assets.Images.command, menu: nil)

	@IBOutlet private var searchBar: ArticleSearchBar!
	@IBOutlet private var searchBarBottomConstraint: NSLayoutConstraint!
	private var defaultControls: [UIBarButtonItem]?

	private var pageViewController: UIPageViewController!
	private var isPageTransitionInProgress = false
	private var pendingSetViewController: WebViewController?

	private var currentWebViewController: WebViewController? {
		return pageViewController?.viewControllers?.first as? WebViewController
	}

	weak var coordinator: SceneCoordinator!

	private let poppableDelegate = PoppableGestureRecognizerDelegate()
	// nonisolated: userDefaultsDidChange(_:) below is itself `nonisolated`
	// (it can arrive off the main thread via UserDefaults.didChangeNotification)
	// and logs through this before hopping to @MainActor -- Logger is Sendable,
	// so there's no isolation reason for the property itself to be MainActor-only.
	nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ArticleViewController")

	// Set once require(toFail:) has been established between the paging
	// scroll view's pan gesture and interactiveContentPopGestureRecognizer,
	// so repeated viewDidAppear calls don't keep re-adding the dependency.
	private var hasConfiguredContentPopFailureRequirement = false

	// Set once the nav-bar tap-to-hide-bars gesture recognizer has been added
	// to parentNavController.navigationBar, so repeated viewDidAppear calls
	// don't keep re-adding it. Mirrors hasConfiguredContentPopFailureRequirement
	// above.
	private var hasConfiguredNavigationBarTapGesture = false

	var article: Article? {
		didSet {
			Self.logger.debug("ArticleViewController: article didSet: \(self.article?.accountID ?? "nil") \(self.article?.articleID ?? "nil") \(self.article?.title ?? "nil")")

			if let controller = currentWebViewController, controller.article != article {
				controller.setArticle(article)
				if isPageTransitionInProgress {
					// Calling setViewControllers during an active page transition trips a UIPageViewController
					// internal assertion (NSInternalInconsistencyException) and crashes the app. Stash the
					// controller and flush it from didFinishAnimating once the transition has ended.
					pendingSetViewController = controller
				} else {
					DispatchQueue.main.async {
						// You have to set the view controller to clear out the UIPageViewController child controller cache.
						// You also have to do it in an async call or you will get a strange assertion error.
						// Re-check the transition state: a user swipe between enqueue and execution can flip
						// isPageTransitionInProgress to true, and calling setViewControllers then would crash.
						if self.isPageTransitionInProgress {
							self.pendingSetViewController = controller
						} else {
							self.pageViewController.setViewControllers([controller], direction: .forward, animated: false, completion: nil)
						}
					}
				}
			}
			updateUI()
		}
	}

	private let keyboardManager = KeyboardManager(type: .detail)
	override var keyCommands: [UIKeyCommand]? {
		return keyboardManager.keyCommands
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(statusesDidChange(_:)), name: .StatusesDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange(_:)), name: UIContentSizeCategory.didChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange(_:)), name: UserDefaults.didChangeNotification, object: nil)
		// Top-toolbar-colors-wrong-on-live-switch bug: this screen used to rely
		// solely on the generic UserDefaults.didChangeNotification observer
		// above to repaint the nav bar on a Surface Palette change, unlike
		// every other SurfacePaletteNavigationBarAware-adopting screen (see
		// app-chrome-palette.md, "Live-update pipeline shape" -- its own
		// observer list never included ArticleViewController). That generic
		// notification carries none of the same-thread, synchronous-before-
		// the-setter-returns guarantee .surfaceTintDidChange/.accentColorDidChange
		// do, and is dispatched via a Task { @MainActor } hop here on top of
		// that, so the nav bar's repaint had no ordering guarantee relative to
		// the palette actually changing -- reliably correct after a fresh
		// viewDidLoad (exiting and re-entering the article), unreliable on a
		// live switch while this screen stayed on screen. Observing the
		// dedicated notifications directly closes that gap; matches
		// MainFeedCollectionViewController/MainTimelineModernViewController.
		NotificationCenter.default.addObserver(self, selector: #selector(surfaceTintDidChange(_:)), name: .surfaceTintDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(accentColorDidChange(_:)), name: .accentColorDidChange, object: nil)

		// Deployment target is iOS 17+ (xcconfig/NetNewsWire_project.xcconfig,
		// IPHONEOS_DEPLOYMENT_TARGET = 17.0), so use registerForTraitChanges
		// rather than the traitCollectionDidChange override it deprecated --
		// same reasoning and pattern as WebViewController.viewDidLoad().
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: ArticleViewController, previousTraitCollection: UITraitCollection) in
			guard self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle else { return }
			self.applyToolbarStyle()
		}

		// .blend's top-nav-bar color and both toolbarStyle branches' bottom-
		// toolbar color depend on the current article theme and any theme
		// override, neither of which .surfaceTintDidChange/.accentColorDidChange
		// cover -- without these, switching themes or editing an override color
		// with an article already open would leave a stale toolbar color
		// showing until the article is re-entered. See app-chrome-palette.md,
		// "Live-update pipeline shape."
		NotificationCenter.default.addObserver(self, selector: #selector(articleThemeDidChange(_:)), name: .CurrentArticleThemeDidChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(articleThemeOverridesDidChange(_:)), name: .articleThemeOverridesDidChange, object: nil)

		// The opaque baseline this screen always wants, regardless of
		// toolbarStyle's scroll-edge behavior, now lives entirely inside
		// SurfacePaletteNavigationBarAware.resetToSystemNavigationBarAppearance()
		// (wantsTransparentScrollEdgeAppearance == false, the default this
		// screen doesn't override) -- setting it here too used to immediately
		// get wiped out by that same reset path running one line below,
		// which was the top-nav-bar-transparent-at-scroll-edge bug. One
		// definition of the baseline now, not two that can drift.
		applyToolbarStyle()

		// The nav-bar tap-to-hide-bars target used to live in a fullScreenTapZone
		// UIView set as navigationItem.titleView, width-capped at <= 150pt. That
		// cap only bounded the view's max width -- the actual width came from the
		// system's _UINavigationBarTitleControl, which was observed squeezing the
		// title area down to ~83pt independent of our constraint, with no public
		// way to force it wider even when fewer right bar buttons were showing.
		// As long as the tap target lived inside titleView its size couldn't
		// track button count. Replaced with a gesture recognizer on the bar
		// itself (added in configureNavigationBarTapGestureIfNeeded(on:), called
		// from viewDidAppear) plus an exclusion-zone delegate check in
		// gestureRecognizer(_:shouldReceive:) below, which recomputes the
		// excluded bands from rightBarButtonItems().count on every touch. No
		// title text is ever set on this screen, so titleView is simply left nil.
		navigationItem.rightBarButtonItems = rightBarButtonItems()
		toolbarItems = bottomToolbarItems()

		pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [:])
		pageViewController.delegate = self
		pageViewController.dataSource = self

		// This code is to disallow paging if we scroll from the left edge.  If this code is removed
		// PoppableGestureRecognizerDelegate will allow us to both navigate back and page back at the
		// same time. That is really weird when it happens.
		let panGestureRecognizer = UIPanGestureRecognizer()
		panGestureRecognizer.delegate = self
		pageViewController.scrollViewInsidePageControl?.addGestureRecognizer(panGestureRecognizer)

		pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(pageViewController.view)
		addChild(pageViewController!)
		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: pageViewController.view.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: pageViewController.view.trailingAnchor),
			view.topAnchor.constraint(equalTo: pageViewController.view.topAnchor),
			view.bottomAnchor.constraint(equalTo: pageViewController.view.bottomAnchor)
		])

		let controller = createWebViewController(article, updateView: true)

		self.pageViewController.setViewControllers([controller], direction: .forward, animated: false, completion: nil)
		pageViewController.scrollViewInsidePageControl?.isScrollEnabled = AppDefaults.shared.articlePagingSwipeEnabled && !coordinator.isArticleGesturesLocked
		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			controller.hideBars()
		}

		// Search bar
		searchBar.translatesAutoresizingMaskIntoConstraints = false
		NotificationCenter.default.addObserver(self, selector: #selector(beginFind(_:)), name: .FindInArticle, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(endFind(_:)), name: .EndFindInArticle, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIWindow.keyboardWillChangeFrameNotification, object: nil)
		searchBar.delegate = self
		view.bringSubviewToFront(searchBar)

		updateUI()
	}

	override func viewWillAppear(_ animated: Bool) {
		let hideToolbars = AppDefaults.shared.logicalArticleFullscreenEnabled
		if hideToolbars {
			currentWebViewController?.hideBars()
		} else {
			currentWebViewController?.showBars()
		}
		// Home-indicator auto-hide (system fade-after-inactivity, reappear-on-touch) is
		// independent of the fullscreen bars toggle above -- it should be available
		// whenever an article is on screen at all, not only once the person has
		// explicitly hidden the toolbars. Previously this was only set from
		// WebViewController.showBars()/hideBars(), so it never took effect unless
		// fullscreen reading mode was in use.
		coordinator.hideHomeIndicator()
		pageViewController.scrollViewInsidePageControl?.isScrollEnabled = AppDefaults.shared.articlePagingSwipeEnabled && !coordinator.isArticleGesturesLocked
		super.viewWillAppear(animated)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(true)
		if #available(iOS 26, *) {
			navigationController?.navigationBar.topItem?.subtitle = nil
		}
		coordinator.isArticleViewControllerPending = false
		searchBar.shouldBeginEditing = true
		if let parentNavController = navigationController?.parent as? UINavigationController {
			poppableDelegate.navigationController = parentNavController
			// ArticleViewController's own navigationController is an inner,
			// per-column wrapper that UISplitViewController creates around
			// each column's bare content controller; it only ever contains
			// the article itself (viewControllers.count == 1), even when
			// Feed and Timeline are visually behind it. The navigation
			// controller that actually performs the push/pop when the split
			// view is collapsed is reached via .parent -- this is also how
			// upstream NetNewsWire resolves it, and it's what makes canGoBack
			// able to fall back to the default viewControllers.count > 1
			// check instead of needing an override.
			parentNavController.interactivePopGestureRecognizer?.delegate = poppableDelegate
			// iOS 26 splits the pop gesture in two: interactivePopGestureRecognizer stays
			// edge-only, while the new interactiveContentPopGestureRecognizer recognizes
			// swipe-to-pop anywhere in the content area. poppableDelegate needs to be
			// installed on both so canGoBack applies consistently; actually enabling/
			// disabling the back-swipe setting itself is done via isEnabled in
			// coordinator.applyArticleBackSwipeGating(), since Apple documents
			// interactiveContentPopGestureRecognizer's delegate as only being for
			// setting up failure requirements, not vetoing recognition.
			if #available(iOS 26, *) {
				parentNavController.interactiveContentPopGestureRecognizer?.delegate = poppableDelegate
			}
			coordinator.applyArticleBackSwipeGating()
			configureContentPopFailureRequirementIfNeeded(on: parentNavController)
			configureNavigationBarTapGestureIfNeeded(on: parentNavController)
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if searchBar != nil && !searchBar.isHidden {
			endFind()
			searchBar.shouldBeginEditing = false
		}
		coordinator.showHomeIndicator()
		// Pass animated: false — animating the nav bar / toolbar visibility change during the
		// disappear transition triggers an Auto Layout assertion (NSISEngine) and crashes.
		currentWebViewController?.showBars(animated: false)
	}

	override func viewSafeAreaInsetsDidChange() {
		// This will animate if the show/hide bars animation is happening.
		view.layoutIfNeeded()
	}

	func updateUI() {

		guard isViewLoaded else {
			return
		}

		guard let article = article else {
			nextUnreadBarButtonItem.isEnabled = false
			prevArticleBarButtonItem.isEnabled = false
			nextArticleBarButtonItem.isEnabled = false
			readBarButtonItem.isEnabled = false
			starBarButtonItem.isEnabled = false
			heartBarButtonItem.isEnabled = false
			actionBarButtonItem.isEnabled = false
			checkForUpdatesBarButtonItem.isEnabled = false
			rebuildOverflowMenu()
			return
		}

		nextUnreadBarButtonItem.isEnabled = coordinator.isNextUnreadAvailable
		prevArticleBarButtonItem.isEnabled = coordinator.isPrevArticleAvailable
		nextArticleBarButtonItem.isEnabled = coordinator.isNextArticleAvailable
		readBarButtonItem.isEnabled = true
		starBarButtonItem.isEnabled = true
		heartBarButtonItem.isEnabled = true

		let permalinkPresent = article.preferredLink != nil
		actionBarButtonItem.isEnabled = permalinkPresent

		if article.status.read {
			readBarButtonItem.image = Assets.Images.circleOpen
			readBarButtonItem.isEnabled = article.isAvailableToMarkUnread
			readBarButtonItem.accLabelText = NSLocalizedString("Mark Article Unread", comment: "Mark Article Unread")
		} else {
			readBarButtonItem.image = Assets.Images.circleClosed
			readBarButtonItem.isEnabled = true
			readBarButtonItem.accLabelText = NSLocalizedString("Selected - Mark Article Unread", comment: "Selected - Mark Article Unread")
		}

		if article.status.starred {
			starBarButtonItem.image = Assets.Images.starClosed
			starBarButtonItem.accLabelText = NSLocalizedString("Selected - Read Later", comment: "Selected - Read Later")
		} else {
			starBarButtonItem.image = Assets.Images.starOpen
			starBarButtonItem.accLabelText = NSLocalizedString("Read Later", comment: "Read Later")
		}

		if article.status.loved {
			heartBarButtonItem.image = Assets.Images.heartClosed
			heartBarButtonItem.accLabelText = NSLocalizedString("Selected - Loved", comment: "Selected - Loved")
		} else {
			heartBarButtonItem.image = Assets.Images.heartOpen
			heartBarButtonItem.accLabelText = NSLocalizedString("Loved", comment: "Loved")
		}

		// Per-article eligibility for the top-toolbar Check for Updates
		// button -- unlike the other top-toolbar toggles (theme/table of
		// contents/find/prevNext/lock/annotations/settings), which only
		// depend on a static AppDefaults toggle, this one also depends on
		// AO3ChapterFetcher.canCheckForUpdates(for:), which varies per
		// article and isn't re-evaluated by rightBarButtonItems() itself.
		// Always-reserved-slot approach (shown, disabled, for an ineligible
		// article) rather than vanishing entirely -- consistent with
		// actionBarButtonItem's isEnabled-toggling shape just above, and
		// keeps which icons occupy the top bar's slots stable article to
		// article.
		if AppDefaults.shared.isArticleToolbarToggleEnabled(.checkForUpdates) {
			let eligible = AO3ChapterFetcher.shared.canCheckForUpdates(for: article)
			checkForUpdatesBarButtonItem.isEnabled = eligible && AO3ChapterFetcher.isAO3NetworkRequestAllowed(for: article)
		}

		rebuildOverflowMenu()
	}

	// MARK: Notifications

	@objc dynamic func unreadCountDidChange(_ notification: Notification) {
		updateUI()
	}

	@objc func statusesDidChange(_ note: Notification) {
		guard let articleIDs = note.userInfo?[Account.UserInfoKey.articleIDs] as? Set<String> else {
			return
		}
		guard let article = article else {
			return
		}
		if articleIDs.contains(article.articleID) {
			updateUI()
		}
	}

	@objc func contentSizeCategoryDidChange(_ note: Notification) {
		currentWebViewController?.fullReload()
	}

	private func flexibleSpaceBarButtonItem() -> UIBarButtonItem {
		UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
	}

	// Order: read, star, heart, next unread, action -- each driven by its
	// own independent AppDefaults toggle (BottomToolbarCustomizerViewController),
	// so any combination (including none) is valid, matching
	// rightBarButtonItems()'s shape just below. flexibleSpace is only
	// inserted between two consecutive present items, not before the
	// first or after the last, so the bar doesn't start/end with dead
	// space when fewer than five are enabled.
	private func bottomToolbarItems() -> [UIBarButtonItem] {
		let defaults = AppDefaults.shared
		var items: [UIBarButtonItem] = []
		let candidates: [(BottomToolbarToggle, UIBarButtonItem)] = [
			(.read, readBarButtonItem), (.star, starBarButtonItem), (.heart, heartBarButtonItem),
			(.nextUnread, nextUnreadBarButtonItem), (.action, actionBarButtonItem)
		]
		for (toggle, item) in candidates where defaults.isBottomToolbarToggleEnabled(toggle) {
			if !items.isEmpty {
				items.append(flexibleSpaceBarButtonItem())
			}
			items.append(item)
		}
		return items
	}

	// Order: theme, table of contents, find, previous/next -- each driven
	// by its own independent AppDefaults toggle
	// (ArticleToolbarCustomizerViewController), so any combination of the
	// four can be present at once.
	private func rightBarButtonItems() -> [UIBarButtonItem] {
		let defaults = AppDefaults.shared

		if defaults.articleToolbarUseOverflowMenu {
			rebuildOverflowMenu()
			return overflowBarButtonItem.menu == nil ? [] : [overflowBarButtonItem]
		}

		var items: [UIBarButtonItem] = []
		if defaults.isArticleToolbarToggleEnabled(.theme) {
			items.append(themeBarButtonItem)
		}
		if defaults.isArticleToolbarToggleEnabled(.tableOfContents) {
			items.append(tableOfContentsBarButtonItem)
		}
		if defaults.isArticleToolbarToggleEnabled(.find) {
			items.append(findInArticleBarButtonItem)
		}
		if defaults.isArticleToolbarToggleEnabled(.prevNext) {
			items.append(contentsOf: [nextArticleBarButtonItem, prevArticleBarButtonItem])
		}
		if defaults.isArticleToolbarToggleEnabled(.lock) {
			items.append(lockBarButtonItem)
		}
		if defaults.isArticleToolbarToggleEnabled(.annotations) {
			items.append(annotationsBarButtonItem)
		}
		if defaults.isArticleToolbarToggleEnabled(.settings) {
			items.append(settingsBarButtonItem)
		}
		if defaults.isArticleToolbarToggleEnabled(.checkForUpdates) {
			items.append(checkForUpdatesBarButtonItem)
		}
		return items
	}

	/// Rebuilds overflowBarButtonItem.menu from the currently-enabled
	/// ArticleToolbarToggle set plus live per-article/session state --
	/// mirrors rightBarButtonItems()'s own ordering (theme, table of
	/// contents, find, prev/next, lock, annotations, settings, check for
	/// updates) so the two modes present functions in the same order.
	/// Called from rightBarButtonItems() itself, and separately from
	/// updateUI() and toggleGesturesLocked(_:), wherever those currently
	/// mutate a bar item's isEnabled/image in place -- a static UIMenu
	/// doesn't observe those mutations the way an on-screen
	/// UIBarButtonItem's own properties do. No-op (menu cleared, not
	/// left stale) when overflow mode is off -- updateUI()/
	/// toggleGesturesLocked(_:) call this unconditionally on every
	/// state change regardless of which display mode is active, so
	/// without this guard overflowBarButtonItem would carry a live,
	/// populated (if unused) menu even in icon mode.
	private func rebuildOverflowMenu() {
		let defaults = AppDefaults.shared
		guard defaults.articleToolbarUseOverflowMenu else {
			overflowBarButtonItem.menu = nil
			return
		}

		var actions: [UIAction] = []

		if defaults.isArticleToolbarToggleEnabled(.theme) {
			actions.append(UIAction(title: ArticleToolbarToggle.theme.title, image: ArticleToolbarToggle.theme.icon) { [weak self] _ in
				self?.showThemePicker(self as Any)
			})
		}
		if defaults.isArticleToolbarToggleEnabled(.tableOfContents) {
			actions.append(UIAction(title: ArticleToolbarToggle.tableOfContents.title, image: ArticleToolbarToggle.tableOfContents.icon) { [weak self] _ in
				self?.showTableOfContents(self as Any)
			})
		}
		if defaults.isArticleToolbarToggleEnabled(.find) {
			actions.append(UIAction(title: ArticleToolbarToggle.find.title, image: ArticleToolbarToggle.find.icon) { [weak self] _ in
				self?.beginFind()
			})
		}
		if defaults.isArticleToolbarToggleEnabled(.prevNext) {
			let nextTitle = NSLocalizedString("Next Article", comment: "Overflow menu: next article")
			let prevTitle = NSLocalizedString("Previous Article", comment: "Overflow menu: previous article")
			actions.append(UIAction(title: nextTitle, image: Assets.Images.nextArticle, attributes: coordinator.isNextArticleAvailable ? [] : .disabled) { [weak self] _ in
				self?.coordinator.selectNextArticle()
			})
			actions.append(UIAction(title: prevTitle, image: Assets.Images.prevArticle, attributes: coordinator.isPrevArticleAvailable ? [] : .disabled) { [weak self] _ in
				self?.coordinator.selectPrevArticle()
			})
		}
		if defaults.isArticleToolbarToggleEnabled(.lock) {
			let locked = coordinator.isArticleGesturesLocked
			let title = locked
				? NSLocalizedString("Unlock Gestures", comment: "Overflow menu: unlock gestures")
				: NSLocalizedString("Lock Gestures", comment: "Overflow menu: lock gestures")
			actions.append(UIAction(title: title, image: UIImage(systemName: locked ? "lock" : "lock.open")) { [weak self] _ in
				self?.toggleGesturesLocked(self as Any)
			})
		}
		if defaults.isArticleToolbarToggleEnabled(.annotations) {
			actions.append(UIAction(title: ArticleToolbarToggle.annotations.title, image: ArticleToolbarToggle.annotations.icon) { [weak self] _ in
				self?.showAnnotationsList(self as Any)
			})
		}
		if defaults.isArticleToolbarToggleEnabled(.settings) {
			actions.append(UIAction(title: ArticleToolbarToggle.settings.title, image: ArticleToolbarToggle.settings.icon) { [weak self] _ in
				self?.showSettingsFromToolbar(self as Any)
			})
		}
		if defaults.isArticleToolbarToggleEnabled(.checkForUpdates), let article {
			let eligible = AO3ChapterFetcher.shared.canCheckForUpdates(for: article)
				&& AO3ChapterFetcher.isAO3NetworkRequestAllowed(for: article)
			actions.append(UIAction(title: ArticleToolbarToggle.checkForUpdates.title, image: ArticleToolbarToggle.checkForUpdates.icon, attributes: eligible ? [] : .disabled) { [weak self] _ in
				self?.checkForUpdatesFromToolbar(self as Any)
			})
		}

		overflowBarButtonItem.menu = actions.isEmpty ? nil : UIMenu(title: "", children: actions)
	}

	@objc nonisolated func userDefaultsDidChange(_ note: Notification) {
		Task { @MainActor in
			coordinator.applyArticleBackSwipeGating()
			navigationItem.rightBarButtonItems = rightBarButtonItems()
			// A live change from BottomToolbarCustomizerViewController must
			// repaint the open article's bottom bar immediately, matching
			// how the top bar already behaves via rightBarButtonItems()
			// just above.
			toolbarItems = bottomToolbarItems()
			// applySurfacePaletteNavigationBarAppearance() intentionally no
			// longer runs from here -- see surfaceTintDidChange(_:) below.
			// Left commented, not deleted, so the "before" behavior this patch
			// changes is visible in the diff/blame rather than silently gone:
			// applySurfacePaletteNavigationBarAppearance()
		}
	}

	@objc func surfaceTintDidChange(_ note: Notification) {
		applyToolbarStyle()
	}

	@objc func accentColorDidChange(_ note: Notification) {
		// Accent Color doesn't currently drive anything in
		// applySurfacePaletteNavigationBarAppearance() (that reads surfaceTint
		// only, per app-chrome-palette.md's own table), but this screen's
		// bar-button icons render via the system tint cascade same as
		// everywhere else, so observing this too keeps
		// ArticleViewController's story consistent with the documented
		// observer list rather than silently only covering Surface Palette.
		applyToolbarStyle()
	}

	// toolbarStyle == .blend reads the current article theme and any
	// per-theme override for its color -- see applyBottomToolbarStyle()/
	// SurfacePaletteNavigationBarAware.applyBlendNavigationBarAppearance().
	// Neither of these notifications existed on this screen's observer list
	// before .blend needed them.
	@objc func articleThemeDidChange(_ note: Notification) {
		applyToolbarStyle()
	}

	@objc func articleThemeOverridesDidChange(_ note: Notification) {
		applyToolbarStyle()
	}

	/// Single call site for both halves of toolbarStyle: the shared top nav
	/// bar appearance (SurfacePaletteNavigationBarAware, also adopted by
	/// MainFeed/MainTimeline) and this screen's own bottom UIToolbar, which
	/// has no equivalent shared protocol -- MainFeed/MainTimeline don't have
	/// a bottom toolbar at all. Called together, always, from every place
	/// either one used to be called alone, so the two bars can't drift out
	/// of sync with each other, which is the entire point of this setting.
	func applyToolbarStyle() {
		applySurfacePaletteNavigationBarAppearance()
		applyBottomToolbarStyle()
	}

	/// Bottom UIToolbar equivalent of SurfacePaletteNavigationBarAware's nav
	/// bar handling. No prior appearance customization existed for this
	/// toolbar at all (it only ever set toolbarItems, the buttons) -- confirmed
	/// by grep, zero UIToolbarAppearance/standardAppearance/isTranslucent
	/// references anywhere in the tree before this. UIToolbar has no
	/// standard/scroll-edge split the way UINavigationBar does, so there's
	/// only one appearance slot pair (standardAppearance/compactAppearance)
	/// to set, not three.
	private func applyBottomToolbarStyle() {
		guard let toolbar = navigationController?.toolbar else { return }

		let toolbarButtonItems: [UIBarButtonItem] = [readBarButtonItem, starBarButtonItem, heartBarButtonItem, nextUnreadBarButtonItem, actionBarButtonItem]

		switch AppDefaults.shared.toolbarStyle {
		case .system:
			// UIToolbar.standardAppearance is non-optional (unlike
			// UINavigationItem.standardAppearance, and unlike this toolbar's
			// own compactAppearance) -- nil cannot be assigned to it, full
			// stop, so there's no way to "clear" it back to an absent value
			// the way the nav bar's own .system reset can for adopters with
			// wantsTransparentScrollEdgeAppearance == true. A fresh,
			// unconfigured UIToolbarAppearance() is standardAppearance's own
			// implicit default value on a toolbar nothing has ever touched
			// (confirmed by grep: zero UIToolbarAppearance/standardAppearance
			// references anywhere in the tree before this feature) -- so
			// assigning a new one back is what reproduces that untouched
			// look, not a workaround for the compiler.
			toolbar.standardAppearance = UIToolbarAppearance()
			toolbar.compactAppearance = nil
			toolbar.tintColor = nil
			toolbarButtonItems.forEach { $0.tintColor = nil }
		case .tinted:
			let backgroundColor = Assets.Colors.navigationBarBackground(for: traitCollection)
			let tintColor = Assets.Colors.navigationBarTint(for: traitCollection)
			applyOpaqueBottomToolbarAppearance(toolbar, buttonItems: toolbarButtonItems, backgroundColor: backgroundColor, tintColor: tintColor)
		case .blend:
			let isDark = traitCollection.userInterfaceStyle == .dark
			let colors = ArticleResolvedColors.current(isDark: isDark)
			applyOpaqueBottomToolbarAppearance(toolbar, buttonItems: toolbarButtonItems, backgroundColor: colors.background, tintColor: colors.text)
		}
	}

	private func applyOpaqueBottomToolbarAppearance(_ toolbar: UIToolbar, buttonItems: [UIBarButtonItem], backgroundColor: UIColor, tintColor: UIColor?) {
		let appearance = UIToolbarAppearance()
		appearance.configureWithDefaultBackground()
		appearance.backgroundColor = backgroundColor
		toolbar.standardAppearance = appearance
		toolbar.compactAppearance = appearance
		if let tintColor {
			toolbar.tintColor = tintColor
		}
		// Same reasoning as the nav bar's own per-item tint reassignment in
		// SurfacePaletteNavigationBarAware.applyOpaqueNavigationBarAppearance():
		// a UIBarButtonItem already on screen doesn't reliably repaint just
		// because the toolbar's own .tintColor was reassigned after the fact.
		buttonItems.forEach { $0.tintColor = tintColor }
	}

	// See docs/app-chrome-palette.md.
	// applySurfacePaletteNavigationBarAppearance() now comes
	// from the shared SurfacePaletteNavigationBarAware protocol (see
	// Shared/Extensions/SurfacePaletteNavigationBarAware.swift) so
	// MainTimelineModernViewController/MainFeedCollectionViewController can
	// reuse the exact same nav-bar wiring this screen already had.

	@objc func willEnterForeground(_ note: Notification) {
		// The toolbar will come back on you if you don't hide it again
		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			currentWebViewController?.hideBars()
		}
	}

	// MARK: Actions

	@objc func didTapNavigationBar() {
		currentWebViewController?.hideBars()
	}

	@objc func showBars(_ sender: Any) {
		currentWebViewController?.showBars()
	}

	@IBAction func nextUnread(_ sender: Any) {
		coordinator.selectNextUnread()
	}

	@IBAction func prevArticle(_ sender: Any) {
		coordinator.selectPrevArticle()
	}

	@IBAction func nextArticle(_ sender: Any) {
		coordinator.selectNextArticle()
	}

	@IBAction func toggleRead(_ sender: Any) {
		coordinator.toggleReadForCurrentArticle()
	}

	@IBAction func toggleStar(_ sender: Any) {
		// Flip the icon immediately so the tap feels instant -- the real
		// mark still round-trips through the DB and posts
		// .StatusesDidChange, which calls updateUI() again and confirms
		// (or corrects) this optimistic state. article.status itself is
		// left untouched here, so MarkStatusCommand's diffing is unaffected.
		if let article {
			let newFlag = !article.status.starred
			starBarButtonItem.image = newFlag ? Assets.Images.starClosed : Assets.Images.starOpen
			starBarButtonItem.accLabelText = newFlag
				? NSLocalizedString("Selected - Read Later", comment: "Selected - Read Later")
				: NSLocalizedString("Read Later", comment: "Read Later")
		}
		coordinator.toggleStarredForCurrentArticle()
	}

	@objc func toggleLoved(_ sender: Any) {
		if let article {
			let newFlag = !article.status.loved
			heartBarButtonItem.image = newFlag ? Assets.Images.heartClosed : Assets.Images.heartOpen
			heartBarButtonItem.accLabelText = newFlag
				? NSLocalizedString("Selected - Loved", comment: "Selected - Loved")
				: NSLocalizedString("Loved", comment: "Loved")
		}
		coordinator.toggleLovedForCurrentArticle()
	}

	/// Flips the transient, session-only SceneCoordinator.isArticleGesturesLocked
	/// flag and immediately re-applies both gates it feeds: back-swipe (via
	/// applyArticleBackSwipeGating(), same call viewDidAppear/
	/// userDefaultsDidChange(_:) already make) and paging (isScrollEnabled,
	/// set directly here since nothing else re-derives it outside
	/// viewDidLoad/viewWillAppear). Locked always wins over whichever swipe
	/// settings the person has chosen; unlocking simply falls back to
	/// AppDefaults.shared.articlePagingSwipeEnabled/articleBackSwipeEnabled,
	/// unchanged.
	@objc func toggleGesturesLocked(_ sender: Any) {
		let newFlag = !coordinator.isArticleGesturesLocked
		coordinator.isArticleGesturesLocked = newFlag
		lockBarButtonItem.image = UIImage(systemName: newFlag ? "lock" : "lock.open")
		lockBarButtonItem.accLabelText = newFlag
			? NSLocalizedString("Selected - Lock Gestures", comment: "Selected - Lock Gestures")
			: NSLocalizedString("Lock Gestures", comment: "Lock Gestures")
		coordinator.applyArticleBackSwipeGating()
		pageViewController.scrollViewInsidePageControl?.isScrollEnabled = AppDefaults.shared.articlePagingSwipeEnabled && !newFlag
		rebuildOverflowMenu()
	}

	@objc func showThemePicker(_ sender: Any) {
		let hostingController = UIHostingController(rootView: ArticleThemeListView())
		navigationController?.pushViewController(hostingController, animated: true)
	}

	@objc func showTableOfContents(_ sender: Any) {
		guard let webViewController = currentWebViewController else { return }
		webViewController.fetchTableOfContents { [weak self] entries in
			guard let self else { return }
			guard !entries.isEmpty else {
				Self.logger.error("showTableOfContents: fetchTableOfContents returned no entries; see WebViewController's log for the underlying cause")
				return
			}
			let tocViewController = TableOfContentsViewController(entries: entries) { [weak self] tocIndex in
				self?.currentWebViewController?.scrollToHeading(tocIndex: tocIndex)
			}
			let navController = UINavigationController(rootViewController: tocViewController)
			navController.modalPresentationStyle = .fullScreen
			self.present(navController, animated: true)
		}
	}

	/// Always shows the whole book's annotations, grouped by chapter --
	/// there used to be a menu here choosing between "This Chapter" and
	/// "All of This Book" as two separate screens, but a whole-book view
	/// grouped by chapter (mirroring how TableOfContentsViewController
	/// groups an anthology's chapters under each book heading) makes that
	/// choice unnecessary: the chapter you were already reading is just
	/// one of the groups in the same list. `article` is re-read here at
	/// call time, not captured earlier, so this stays correct even if the
	/// person paged to a different article before tapping the button.
	@objc private func showAnnotationsList(_ sender: Any) {
		guard let article, let account = article.account else { return }

		let listView = AnnotationsListView(account: account, scope: .book(bookKey: article.bookKey), title: article.title, onClose: { [weak self] in
			self?.navigationController?.popViewController(animated: true)
		}, onNavigateToAnnotation: { [weak self] annotation in
			self?.navigateToAnnotation(annotation, account: account)
		})
		// Pushed directly onto this controller's own navigation stack
		// (same pattern as showThemePicker/showTableOfContents elsewhere
		// in this file) rather than presented modally -- a modal
		// present/dismiss here left the person on the article's screen
		// with no way back to the annotations list, since dismissing a
		// modal and popping a nav stack are different operations and
		// navigateToAnnotation's cross-article path relies on the latter
		// (see that method's own doc comment). listView is NOT wrapped in
		// its own NavigationStack -- it's going straight onto a UIKit
		// UINavigationController (this one), and SwiftUI's
		// navigationTitle/toolbar already propagate to the nearest
		// UINavigationController's navigationItem without one. Wrapping it
		// in a NavigationStack first used to create a second, independent
		// nav bar (SwiftUI's own) nested inside the UIKit one, so the
		// title -- and only the inner bar's close button -- rendered
		// twice, stacked on top of each other.
		let hostingController = UIHostingController(rootView: listView)
		navigationController?.pushViewController(hostingController, animated: true)
	}

	@objc private func showSettingsFromToolbar(_ sender: Any) {
		coordinator.showSettings(scrollToArticlesSection: true)
	}

	@objc private func checkForUpdatesFromToolbar(_ sender: Any) {
		guard let article else { return }
		guard AO3ChapterFetcher.isAO3NetworkRequestAllowed(for: article) else {
			// The button is disabled (see updateUI()) whenever this guard
			// would fail, so this shouldn't normally fire -- no user-visible
			// messaging here, unlike the context-menu version's disabled
			// title text (WebViewController.checkForUpdatesAction()), since
			// a toolbar button has no room for that. Silent no-op.
			return
		}
		AO3ChapterFetcher.shared.checkForUpdates(for: article)
	}

	/// Shared by both the toolbar-button list (showAnnotationsList above)
	/// and the Settings unscoped list -- tapping a row either scrolls the
	/// already-open article (same articleID) or navigates there first via
	/// SceneCoordinator.selectArticleDirectly, then scrolls, mirroring the
	/// direct-navigation pattern that method's own doc comment describes
	/// for "open a specific article and land in a specific spot." Takes
	/// `account` explicitly rather than re-deriving it, since Annotation
	/// doesn't store an accountID -- account is whatever AnnotationsListView
	/// itself fetched the annotation from.
	///
	/// The toolbar-button list is pushed onto this controller's own
	/// navigation stack (see showAnnotationsList), so returning to the
	/// article here means popping that stack, not dismissing a modal --
	/// selectArticleDirectly mutates this same ArticleViewController
	/// instance's `article` property in place (SceneCoordinator.swift's
	/// selectArticleDirectly) rather than pushing a new view controller,
	/// so the stack underneath the pushed AnnotationsListView is still
	/// exactly [ArticleViewController] regardless of which annotation was
	/// tapped -- popping always reveals the right thing, for both the
	/// same-article and cross-article paths below. The Settings unscoped
	/// list (AnnotationsSettingsView) is reached by an entirely different
	/// presentation chain owned by SettingsViewController, not this one,
	/// so popViewController(animated:) here only ever affects the
	/// toolbar-button path's own stack.
	func navigateToAnnotation(_ annotation: Annotation, account: Account) {
		if article?.articleID == annotation.articleID {
			currentWebViewController?.scrollToAnnotation(annotationID: annotation.annotationID)
			navigationController?.popViewController(animated: true)
			return
		}

		Task { [weak self] in
			guard let self else { return }
			await self.coordinator.selectArticleDirectly(annotation.articleID, account: account)
			// selectArticleDirectly resolves once the Article model is
			// selected, not once the new WebViewController has actually
			// finished loading that content -- scrollToAnnotation would
			// find nothing yet if fired immediately. awaitNextPageLoad
			// resolves off WebViewController's own didFinish navigation
			// callback (loadAndRenderAnnotations' own hook point), so
			// this waits for the real signal rather than guessing at a
			// delay.
			await self.currentWebViewController?.awaitNextPageLoad()
			self.currentWebViewController?.scrollToAnnotation(annotationID: annotation.annotationID)
			self.navigationController?.popViewController(animated: true)
		}
	}

	@IBAction func showActivityDialog(_ sender: Any) {
		currentWebViewController?.showActivityDialog(popOverBarButtonItem: actionBarButtonItem)
	}

	// MARK: Keyboard Shortcuts

	@objc func navigateToTimeline(_ sender: Any?) {
		coordinator.navigateToTimeline()
	}

	// MARK: API

	func focus() {
		currentWebViewController?.focus()
	}

	func canScrollDown() -> Bool {
		return currentWebViewController?.canScrollDown() ?? false
	}

	func canScrollUp() -> Bool {
		return currentWebViewController?.canScrollUp() ?? false
	}

	func scrollPageDown() {
		currentWebViewController?.scrollPageDown()
	}

	func scrollPageUp() {
		currentWebViewController?.scrollPageUp()
	}

	func openInAppBrowser() {
		currentWebViewController?.openInAppBrowser()
	}
}

// MARK: Find in Article
public extension Notification.Name {
	static let FindInArticle = Notification.Name("FindInArticle")
	static let EndFindInArticle = Notification.Name("EndFindInArticle")
}

extension ArticleViewController: SearchBarDelegate {

	func searchBar(_ searchBar: ArticleSearchBar, textDidChange searchText: String) {
		currentWebViewController?.searchText(searchText) { found in
			searchBar.resultsCount = found.count

			if let index = found.index {
				searchBar.selectedResult = index + 1
			}
		}
	}

	func doneWasPressed(_ searchBar: ArticleSearchBar) {
		NotificationCenter.default.post(name: .EndFindInArticle, object: nil)
	}

	func nextWasPressed(_ searchBar: ArticleSearchBar) {
		if searchBar.selectedResult < searchBar.resultsCount {
			currentWebViewController?.selectNextSearchResult()
			searchBar.selectedResult += 1
		}
	}

	func previousWasPressed(_ searchBar: ArticleSearchBar) {
		if searchBar.selectedResult > 1 {
			currentWebViewController?.selectPreviousSearchResult()
			searchBar.selectedResult -= 1
		}
	}
}

extension ArticleViewController {

	@objc func beginFind(_ _: Any? = nil) {
		searchBar.isHidden = false
		navigationController?.setToolbarHidden(true, animated: true)
		currentWebViewController?.additionalSafeAreaInsets.bottom = searchBar.frame.height
		searchBar.becomeFirstResponder()
	}

	@objc func endFind(_ _: Any? = nil) {
		searchBar.resignFirstResponder()
		searchBar.isHidden = true
		navigationController?.setToolbarHidden(false, animated: true)
		currentWebViewController?.additionalSafeAreaInsets.bottom = 0
		currentWebViewController?.endSearch()
	}

	@objc func keyboardWillChangeFrame(_ notification: Notification) {
		if !searchBar.isHidden,
			let duration = notification.userInfo?[UIWindow.keyboardAnimationDurationUserInfoKey] as? Double,
			let curveRaw = notification.userInfo?[UIWindow.keyboardAnimationCurveUserInfoKey] as? UInt,
			let frame = notification.userInfo?[UIWindow.keyboardFrameEndUserInfoKey] as? CGRect {

			let curve = UIView.AnimationOptions(rawValue: curveRaw)
			let newHeight = view.safeAreaLayoutGuide.layoutFrame.maxY - frame.minY
			currentWebViewController?.additionalSafeAreaInsets.bottom = newHeight + searchBar.frame.height + 10
			self.searchBarBottomConstraint.constant = newHeight
			UIView.animate(withDuration: duration, delay: 0, options: curve, animations: {
				self.view.layoutIfNeeded()
			})
		}
	}

}

// MARK: UIPageViewControllerDataSource

extension ArticleViewController: UIPageViewControllerDataSource {

	func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
		guard let webViewController = viewController as? WebViewController,
			let currentArticle = webViewController.article,
			let article = coordinator.findPrevArticle(currentArticle) else {
			return nil
		}
		return createWebViewController(article)
	}

	func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
		guard let webViewController = viewController as? WebViewController,
			let currentArticle = webViewController.article,
			let article = coordinator.findNextArticle(currentArticle) else {
			return nil
		}
		return createWebViewController(article)
	}

}

// MARK: UIPageViewControllerDelegate

extension ArticleViewController: UIPageViewControllerDelegate {

	func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
		isPageTransitionInProgress = true
	}

	func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
		isPageTransitionInProgress = false

		if let pending = pendingSetViewController {
			pendingSetViewController = nil
			pageViewController.setViewControllers([pending], direction: .forward, animated: false, completion: nil)
		}

		guard finished, completed else { return }
		guard let article = currentWebViewController?.article else { return }

		coordinator.selectArticle(article, animations: [.select, .scroll, .navigation])

		for viewController in previousViewControllers {
			if let webViewController = viewController as? WebViewController {
				webViewController.stopWebViewActivity()
			}
		}
	}
}

// MARK: UIGestureRecognizerDelegate

extension ArticleViewController: UIGestureRecognizerDelegate {

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		// This gates the extra edge-detection pan added to
		// pageViewController.scrollViewInsidePageControl in viewDidLoad, used only
		// to resolve conflicts with the interactive pop gesture at the left edge
		// (see shouldRecognizeSimultaneouslyWith below). Enabling/disabling the
		// paging swipe itself is done via isScrollEnabled in viewDidLoad/
		// viewWillAppear; enabling/disabling the back-swipe is done via
		// coordinator.applyArticleBackSwipeGating().
		return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		let point = gestureRecognizer.location(in: nil)
		return point.x > 40
    }

	// Tap-passthrough with an exclusion zone: the nav-bar tap gesture added in
	// configureNavigationBarTapGestureIfNeeded(on:) covers the whole bar, so
	// this rejects touches that fall over the back button or the visible right
	// bar button items and lets those controls handle them instead. Both
	// exclusion widths below are estimates, not measured -- same category of
	// approximation the old titleView <= 150pt cap already was, just now
	// correctly tracking button count instead of a fixed number:
	//   - trailing: 44pt per visible right bar button item, matching the
	//     standard system tap-target width used elsewhere in the app.
	//   - leading: a conservative 80pt constant for the back button. Its actual
	//     width varies with chevron-only vs. chevron+label, which depends on
	//     the previous screen's title and available space, and there's no
	//     public API to read its real frame.
	// If bug 5 turns out to be a hit-testing problem (the gesture never
	// receiving touches at all) rather than an undersized tap zone, this
	// change won't fix that on its own -- but it removes titleView layout as a
	// variable, which was one of the two live hypotheses in that
	// investigation. isFullScreenAvailable (and this whole flow) is
	// phone-only, so no iPad-specific exclusion logic is needed here.
	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
		// Same parentNavController resolution used in viewDidAppear/
		// configureNavigationBarTapGestureIfNeeded(on:): this is the nav bar the
		// gesture was actually installed on.
		guard let parentNavController = navigationController?.parent as? UINavigationController else {
			return true
		}
		let navigationBar = parentNavController.navigationBar

		let location = touch.location(in: navigationBar)

		let backButtonExclusionWidth: CGFloat = 80
		if location.x < backButtonExclusionWidth {
			return false
		}

		let perButtonWidth: CGFloat = 44
		let rightButtonCount = navigationItem.rightBarButtonItems?.count ?? 0
		let trailingExclusionWidth = CGFloat(rightButtonCount) * perButtonWidth
		if location.x > navigationBar.bounds.width - trailingExclusionWidth {
			return false
		}

		return true
	}

}

// MARK: Private

private extension ArticleViewController {

	func createWebViewController(_ article: Article?, updateView: Bool = true) -> WebViewController {
		let controller = WebViewController()
		controller.coordinator = coordinator
		controller.setArticle(article, updateView: updateView)
		return controller
	}

	/// Requires interactiveContentPopGestureRecognizer to fail before the
	/// article pager's own pan gesture is preempted by it, so that when both
	/// paging and back-swipe are enabled, a content-area swipe pages the
	/// article instead of racing to pop it. This is the explicit failure
	/// requirement Apple's iOS 26 UIKit guidance calls for when a view's own
	/// gesture recognizers compete with content-area swipe-back.
	func configureContentPopFailureRequirementIfNeeded(on navigationController: UINavigationController) {
		guard !hasConfiguredContentPopFailureRequirement else { return }
		guard #available(iOS 26, *),
			  let contentPopGesture = navigationController.interactiveContentPopGestureRecognizer,
			  let pagingPanGesture = pageViewController.scrollViewInsidePageControl?.panGestureRecognizer else {
			return
		}
		contentPopGesture.require(toFail: pagingPanGesture)
		hasConfiguredContentPopFailureRequirement = true
	}

	/// Adds the tap-to-hide-bars gesture recognizer directly to the nav bar,
	/// replacing the old titleView-hosted tap zone. No subview is added to the
	/// bar and no private view internals are touched; gestureRecognizer(_:
	/// shouldReceive:) below rejects touches that land in the back-button or
	/// right-bar-button-item bands so taps on those controls still reach them
	/// normally.
	func configureNavigationBarTapGestureIfNeeded(on parentNavController: UINavigationController) {
		guard !hasConfiguredNavigationBarTapGesture else { return }
		let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapNavigationBar))
		tapGesture.delegate = self
		parentNavController.navigationBar.addGestureRecognizer(tapGesture)
		hasConfiguredNavigationBarTapGesture = true
	}

}
