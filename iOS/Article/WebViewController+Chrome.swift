//
//  WebViewController+Chrome.swift
//  NetNewsWire-iOS
//
//  Full-screen reading appearance, notch cover, bars management, and context menu.
//

import UIKit
import WebKit
import Articles

// MARK: - UIContextMenuInteractionDelegate

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
	func refreshVisibleContextMenu() {
		contextMenuInteraction.updateVisibleMenu { [weak self] _ in
			self?.buildContextMenu() ?? UIMenu(title: "")
		}
	}

}

// MARK: - Context Menu Actions

extension WebViewController {

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

	/// "Ignore This Work" and "Ignore Author" for the press-and-hold context menu; empty
	/// for anything that is not a single AO3 work. The actions themselves live in
	/// `ArticleIgnoreActions`, shared with the toolbar's Ignore function.
	func ignoreActions() -> [UIAction] {
		return ArticleIgnoreActions.actions(for: article, presenter: self)
	}

	func shareAction() -> UIAction {
		let title = NSLocalizedString("Share", comment: "Share button")
		return UIAction(title: title, image: Assets.Images.share) { [weak self] _ in
			self?.showActivityDialog()
		}
	}

}

// MARK: - Full Screen Chrome & Notch Cover

extension WebViewController {

	@objc func showBars(_ sender: Any) {
		showBars()
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
			// Top side: the notch inset is deliberately left in place so the page starts
			// below notchCoverView (docs/nnwtheme-format.md, "Full-screen reading").
			// Assigning 0 synchronously keeps webView.safeAreaInsets.top from carrying a
			// stale cancelled value into textWasSelected; see also the clamp in
			// presentHighlightColorPopover.
			additionalSafeAreaInsets.top = 0
			setBottomScrollEdgeEffectHidden(true)
			configureContextMenuInteraction()
			updateNotchAndPageCounterVisibility()
			updateScrollbarVisibility()
			coordinator.applyArticleBackSwipeGating()
		}
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

		// Deliberately not safeAreaLayoutGuide.topAnchor: a fixed height kept in sync with
		// the top inset in viewSafeAreaInsetsDidChange is immune to the guide changing
		// while the bars animate.
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
	func updateReadingTimePieIndicatorView(resolvedText: UIColor? = nil) {
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

	@objc func readingTimeUsageDidChange(_ note: Notification) {
		updateReadingTimePieIndicatorView()
	}

	func updateBottomSafeAreaForFullScreen() {
		let rawBottom = view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom
		additionalSafeAreaInsets.bottom = -rawBottom
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

}
