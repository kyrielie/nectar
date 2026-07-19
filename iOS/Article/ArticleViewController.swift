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

final class ArticleViewController: UIViewController {

	@IBOutlet private weak var nextUnreadBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var prevArticleBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var nextArticleBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var readBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var starBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var actionBarButtonItem: UIBarButtonItem!

	// Phase 5/6 fork additions. Code-constructed rather than @IBOutlet like the
	// items above -- toolbarItems/navigationItem are already fully assembled in
	// code in viewDidLoad, so there's no need to touch the storyboard for these.
	// TODO: Assets.Images.heartOpen/heartClosed and Assets.Images.theme need
	// actual asset catalog entries; not part of this patch series since asset
	// catalogs aren't diffable as text.
	private lazy var heartBarButtonItem = UIBarButtonItem(image: Assets.Images.heartOpen, style: .plain, target: self, action: #selector(toggleLoved(_:)))
	private lazy var themeBarButtonItem = UIBarButtonItem(image: Assets.Images.theme, style: .plain, target: self, action: #selector(showThemePicker(_:)))

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
	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ArticleViewController")

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

		let appearance = UINavigationBarAppearance()
		appearance.configureWithDefaultBackground()
		navigationItem.standardAppearance = appearance
		navigationItem.scrollEdgeAppearance = appearance
		navigationItem.compactAppearance = appearance

		let fullScreenTapZone = UIView()
		fullScreenTapZone.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			fullScreenTapZone.widthAnchor.constraint(equalToConstant: 150),
			fullScreenTapZone.heightAnchor.constraint(equalToConstant: 44)
		])
		fullScreenTapZone.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapNavigationBar)))
		navigationItem.titleView = fullScreenTapZone
		navigationItem.rightBarButtonItems = [themeBarButtonItem, nextArticleBarButtonItem, prevArticleBarButtonItem]

		let flex = { UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil) }
		toolbarItems = [
			readBarButtonItem,
			flex(),
			starBarButtonItem,
			flex(),
			heartBarButtonItem,
			flex(),
			nextUnreadBarButtonItem,
			flex(),
			actionBarButtonItem
		]

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
		pageViewController.scrollViewInsidePageControl?.isScrollEnabled = AppDefaults.shared.articlePagingSwipeEnabled
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
		pageViewController.scrollViewInsidePageControl?.isScrollEnabled = AppDefaults.shared.articlePagingSwipeEnabled
		super.viewWillAppear(animated)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(true)
		if #available(iOS 26, *) {
			navigationController?.navigationBar.topItem?.subtitle = nil
		}
		coordinator.isArticleViewControllerPending = false
		searchBar.shouldBeginEditing = true
		if let navigationController {
			poppableDelegate.navigationController = navigationController
			// This column's own navigationController only ever contains the
			// article itself (viewControllers.count == 1), even when Feed and
			// Timeline are visually behind it, because ArticleViewController is
			// shown via rootSplitViewController.show(.secondary) rather than a
			// push onto a shared stack. An article only ever appears here after
			// being selected from a timeline, so whenever the split view is
			// collapsed there's always a timeline to go back to.
			poppableDelegate.canGoBack = { [weak self] in
				self?.coordinator.isRootSplitCollapsed ?? false
			}
			poppableDelegate.isAdditionallyBlocked = {
				!AppDefaults.shared.articleBackSwipeEnabled
			}
			navigationController.interactivePopGestureRecognizer?.delegate = poppableDelegate
			// iOS 26 split the pop gesture in two: interactivePopGestureRecognizer stays
			// edge-only, while the new interactiveContentPopGestureRecognizer recognizes
			// swipe-to-pop anywhere in the content area. Without installing poppableDelegate
			// here too, articleBackSwipeEnabled = false only blocked the edge swipe --
			// content-area swipe-back still popped the article unconditionally.
			if #available(iOS 26, *) {
				navigationController.interactiveContentPopGestureRecognizer?.delegate = poppableDelegate
			}
			Self.logger.debug("ArticleViewController: viewDidAppear installed poppableDelegate as interactivePopGestureRecognizer.delegate (articleBackSwipeEnabled=\(AppDefaults.shared.articleBackSwipeEnabled), isRootSplitCollapsed=\(self.coordinator.isRootSplitCollapsed), navigationController.viewControllers.count=\(navigationController.viewControllers.count))")
			// DIAGNOSTIC (temporary): correlate this navigationController's identity
			// against the "new observer <UINavigationController: 0x...> / removing old
			// observer <UINavigationController: 0x...>" console lines UIKit prints when
			// a *different* mechanism -- not interactivePopGestureRecognizer -- registers
			// itself as an observer of the paging scroll view to support swipe-back from
			// within horizontally-scrolling content. If the pointer here never matches
			// the "new observer" pointer at gesture time, that confirms the real
			// back-swipe the person feels is driven by that separate path, which our
			// delegate has no say over.
			let popGesture = navigationController.interactivePopGestureRecognizer
			Self.logger.debug("ArticleViewController: viewDidAppear diagnostic navigationController=\(navigationController), interactivePopGestureRecognizer=\(String(describing: popGesture)), isEnabled=\(popGesture?.isEnabled ?? false), delegateIsPoppableDelegate=\(popGesture?.delegate === self.poppableDelegate)")
			// DIAGNOSTIC (temporary): confirm poppableDelegate actually took on the
			// content-area pop gesture too -- remove once verified alongside the
			// diagnostic above.
			if #available(iOS 26, *) {
				let contentPopGesture = navigationController.interactiveContentPopGestureRecognizer
				Self.logger.debug("ArticleViewController: viewDidAppear diagnostic interactiveContentPopGestureRecognizer=\(String(describing: contentPopGesture)), isEnabled=\(contentPopGesture?.isEnabled ?? false), delegateIsPoppableDelegate=\(contentPopGesture?.delegate === self.poppableDelegate)")
			}
			if let scrollView = pageViewController.scrollViewInsidePageControl {
				let recognizers = scrollView.gestureRecognizers ?? []
				Self.logger.debug("ArticleViewController: viewDidAppear diagnostic scrollViewInsidePageControl=\(scrollView) gestureRecognizers=\(recognizers.map { "\(type(of: $0)) delegate=\(String(describing: $0.delegate.map { type(of: $0) })) enabled=\($0.isEnabled)" })")
			} else {
				Self.logger.debug("ArticleViewController: viewDidAppear diagnostic scrollViewInsidePageControl is nil")
			}
		} else {
			Self.logger.debug("ArticleViewController: viewDidAppear found navigationController == nil -- poppableDelegate was NOT installed, interactivePopGestureRecognizer.delegate is whatever UIKit's default is")
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if searchBar != nil && !searchBar.isHidden {
			endFind()
			searchBar.shouldBeginEditing = false
		}
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

	@objc func showThemePicker(_ sender: Any) {
		let articleThemes = UIHostingController(rootView: ArticleThemeListView())
		navigationController?.pushViewController(articleThemes, animated: true)
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

	func setScrollPosition(articleWindowScrollY: Int) {
		currentWebViewController?.setScrollPosition(articleWindowScrollY: articleWindowScrollY)
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
		// poppableDelegate.isAdditionallyBlocked in viewDidAppear.
		Self.logger.debug("ArticleViewController: edge-detection gestureRecognizerShouldBegin -> true (gestureRecognizer=\(gestureRecognizer))")
		return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		let point = gestureRecognizer.location(in: nil)
		let result = point.x > 40
		Self.logger.debug("ArticleViewController: edge-detection shouldRecognizeSimultaneouslyWith -> \(result) (point.x=\(point.x), gestureRecognizer=\(gestureRecognizer), otherGestureRecognizer=\(otherGestureRecognizer))")
		return result
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

}
