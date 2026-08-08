//
//  SettingsViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 4/24/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import CoreServices
import SwiftUI
import RSCore
import Account
import ActivityLog
import Articles

final class SettingsViewController: UITableViewController, SettingsPaletteBackgroundHosting {

	var paletteBackgroundView: UIView { tableView }

	private enum Section: Int {
		case feeds = 0
		case timeline = 1
		case articles = 2
		case appearance = 3
		case troubleshooting = 4
		case help = 5
		case ao3Account = 6
	}

	/// surface-palette-followup-plan, Issue B. Wraps `rootView` with
	/// `SurfacePaletteAware` and wires a `SurfacePaletteObserver` to the
	/// hosting controller's own `traitCollection` (never
	/// `UITraitCollection.current` -- see `SurfacePaletteObserver`'s doc
	/// comment). Shared by all six SwiftUI-hosted settings screens so the
	/// observer/registerForTraitChanges wiring is written once.
	private static func makeSurfacePaletteAwareHostingController<RootView: View>(rootView: RootView) -> UIHostingController<AnyView> {
		let hostingController = UIHostingController(rootView: AnyView(rootView))
		let observer = SurfacePaletteObserver(traitCollection: hostingController.traitCollection)
		hostingController.rootView = AnyView(rootView.surfacePaletteAware(observer: observer))
		hostingController.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: UIHostingController<AnyView>, previous: UITraitCollection) in
			guard vc.traitCollection.userInterfaceStyle != previous.userInterfaceStyle else { return }
			observer.refresh(for: vc.traitCollection)
		}
		return hostingController
	}

	private enum AppearanceRow: Int, CaseIterable {
		case colorPalette = 0
		case accentColor = 1
	}

	private enum TroubleshootingRow: Int {
		case errorLog = 0
		case activityLog = 1
		case accountStats = 2
		case dinosaurs = 3
		case manageStorage = 4
	}

	private enum FeedsRow: Int {
		case importSubscriptions = 0
		case exportSubscriptions = 1
		case exportArticles = 2
	}

	private enum TimelineRow: Int {
		case sortField = 0
		case sortDirection = 1
		case groupByFeed = 2
		case refreshClearsReadArticles = 3
		case timelineLayout = 4
		case showLastUpdatedLabel = 5
	}

	private enum ArticlesRow: Int, CaseIterable {
		case theme = 0
		case openLinksInNetNewsWire = 1
		case enableFullScreenArticles = 2
		case enableBackSwipe = 3
		case enablePagingSwipe = 4
		case showFeedNameInReaderView = 5
		case showPrevNextArticleButtons = 6
		case showTableOfContentsAndFind = 7
		case hideNotchInFullScreen = 8
		case pageCounterDisplayMode = 9
		case disableArticleLinks = 10
	}

	private enum HelpRow: Int {
		case about = 0
	}

	private weak var exportOPMLAccount: Account?
	private weak var exportArticlesCSVAccount: Account?

	@IBOutlet var timelineSortFieldDetailLabel: UILabel!
	@IBOutlet var timelineSortDirectionDetailLabel: UILabel!
	@IBOutlet var groupByFeedSwitch: UISwitch!
	@IBOutlet var ambrosiaSQLiteTransferSwitch: UISwitch!
	@IBOutlet var refreshClearsReadArticlesSwitch: UISwitch!
	@IBOutlet var articleThemeDetailLabel: UILabel!
	@IBOutlet var showLastUpdatedLabelSwitch: UISwitch!
	@IBOutlet var showFullscreenArticlesSwitch: UISwitch!
	@IBOutlet var backSwipeEnabledSwitch: UISwitch!
	@IBOutlet var pagingSwipeEnabledSwitch: UISwitch!
	@IBOutlet var showFeedNameInReaderViewSwitch: UISwitch!
	@IBOutlet var showPrevNextArticleButtonsSwitch: UISwitch!
	@IBOutlet var showTableOfContentsAndFindSwitch: UISwitch!
	@IBOutlet var hideNotchInFullScreenSwitch: UISwitch!
	@IBOutlet var pageCounterDisplayModeDetailLabel: UILabel!
	@IBOutlet var disableArticleLinksSwitch: UISwitch!
	@IBOutlet var colorPaletteDetailLabel: UILabel!
	@IBOutlet var accentColorDetailLabel: UILabel!
	@IBOutlet var openLinksInNetNewsWire: UISwitch!

	var scrollToArticlesSection = false
	weak var presentingParentController: UIViewController?

	override func viewDidLoad() {
		// This hack mostly works around a bug in static tables with dynamic type.  See: https://spin.atomicobject.com/2018/10/15/dynamic-type-static-uitableview/
		NotificationCenter.default.removeObserver(tableView!, name: UIContentSizeCategory.didChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange), name: UIContentSizeCategory.didChangeNotification, object: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(accountsDidChange), name: .UserDidAddAccount, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(accountsDidChange), name: .UserDidDeleteAccount, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(displayNameDidChange), name: .DisplayNameDidChange, object: nil)
		// Bug fix: this screen never observed .accentColorDidChange, so picking a
		// new accent color on AccentColorTableViewController (which no longer pops --
		// see that controller's didSelectRowAt) left accentColorDetailLabel showing
		// the old name, and every switch below still tinted with the color that was
		// live when this screen's nib last loaded, until the whole Settings sheet was
		// dismissed and re-presented from scratch. Applying it here, live, removes
		// the need to close and reopen Settings to see the change take effect.
		NotificationCenter.default.addObserver(self, selector: #selector(accentColorDidChange(_:)), name: .accentColorDidChange, object: nil)
		// willDisplay only fires for cells newly scrolling on screen, so a
		// palette change while this screen is already visible needs an
		// explicit repaint of the rows already on screen.
		NotificationCenter.default.addObserver(self, selector: #selector(surfaceTintDidChange(_:)), name: .surfaceTintDidChange, object: nil)

		tableView.register(UINib(nibName: "SettingsComboTableViewCell", bundle: nil), forCellReuseIdentifier: "SettingsComboTableViewCell")
		tableView.register(UINib(nibName: "SettingsTableViewCell", bundle: nil), forCellReuseIdentifier: "SettingsTableViewCell")

		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 44

		configureSettingsPaletteBackground()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		updateTimelineSortLabels()

		if AppDefaults.shared.timelineGroupByFeed {
			groupByFeedSwitch.isOn = true
		} else {
			groupByFeedSwitch.isOn = false
		}

		ambrosiaSQLiteTransferSwitch.isOn = (AmbrosiaTransferFormatPreference.current == .sqlite)

		if AppDefaults.shared.refreshClearsReadArticles {
			refreshClearsReadArticlesSwitch.isOn = true
		} else {
			refreshClearsReadArticlesSwitch.isOn = false
		}

		articleThemeDetailLabel.text = ArticleThemesManager.shared.currentTheme.name

		showLastUpdatedLabelSwitch.isOn = AppDefaults.shared.showLastUpdatedLabel

		if AppDefaults.shared.articleFullscreenAvailable {
			showFullscreenArticlesSwitch.isOn = true
		} else {
			showFullscreenArticlesSwitch.isOn = false
		}

		backSwipeEnabledSwitch.isOn = AppDefaults.shared.articleBackSwipeEnabled
		pagingSwipeEnabledSwitch.isOn = AppDefaults.shared.articlePagingSwipeEnabled
		showFeedNameInReaderViewSwitch.isOn = AppDefaults.shared.showFeedNameInReaderView
		showPrevNextArticleButtonsSwitch.isOn = AppDefaults.shared.showPrevNextArticleButtons
		showTableOfContentsAndFindSwitch.isOn = AppDefaults.shared.showTableOfContentsAndFind
		hideNotchInFullScreenSwitch.isOn = AppDefaults.shared.hideNotchInFullScreen
		updatePageCounterDisplayModeLabel()
		disableArticleLinksSwitch.isOn = AppDefaults.shared.disableArticleLinks

		colorPaletteDetailLabel.text = String(describing: AppDefaults.userInterfaceColorPalette)
		applyAccentColorTinting()

		openLinksInNetNewsWire.isOn = !AppDefaults.shared.useSystemBrowser

		let buildLabel = NonIntrinsicLabel(frame: CGRect(x: 32.0, y: 0.0, width: 0.0, height: 0.0))
		buildLabel.font = UIFont.systemFont(ofSize: 11.0)
		buildLabel.textColor = UIColor.gray
		buildLabel.text = "\(Bundle.main.appName) \(Bundle.main.versionNumber) (Build \(Bundle.main.buildNumber))"
		buildLabel.sizeToFit()
		buildLabel.translatesAutoresizingMaskIntoConstraints = false

		let wrapperView = UIView(frame: CGRect(x: 0, y: 0, width: buildLabel.frame.width, height: buildLabel.frame.height + 10.0))
		wrapperView.translatesAutoresizingMaskIntoConstraints = false
		wrapperView.addSubview(buildLabel)
		tableView.tableFooterView = wrapperView

	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		self.tableView.selectRow(at: nil, animated: true, scrollPosition: .none)

		if scrollToArticlesSection {
			tableView.scrollToRow(at: IndexPath(row: 0, section: Section.articles.rawValue), at: .top, animated: true)
			scrollToArticlesSection = false
		}

	}

	// MARK: UITableView

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {

		switch Section(rawValue: section) {
		case .articles:
			// This app is iPhone-only, so all ArticlesRow cases are always shown.
			// (Previously this branched on userInterfaceIdiom == .phone, which left
			// the row count stuck at the pre-Phase-5/6 case count on non-phone
			// idioms; since there is no non-phone idiom here, that branch was both
			// dead and, after ArticlesRow grew to 6 cases, wrong.)
			return ArticlesRow.allCases.count
		case .troubleshooting:
			// The storyboard's troubleshooting section still has a trailing
			// cloudKit-zone-stats row after Manage Storage; it's unreachable
			// now that cloudKit accounts don't exist, so it's always
			// excluded (Manage Storage is inserted before it, not after, so
			// this still only ever hides that one dead row).
			return super.tableView(tableView, numberOfRowsInSection: section) - 1
		default:
			return super.tableView(tableView, numberOfRowsInSection: section)
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

		switch Section(rawValue: indexPath.section) {
		case .feeds:
			switch FeedsRow(rawValue: indexPath.row) {
			case .importSubscriptions:
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
				if let sourceView = tableView.cellForRow(at: indexPath) {
					let sourceRect = tableView.rectForRow(at: indexPath)
					OPMLImportCoordinator.begin(presentingController: self, sourceView: sourceView, sourceRect: sourceRect)
				}
			case .exportSubscriptions:
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
				if let sourceView = tableView.cellForRow(at: indexPath) {
					let sourceRect = tableView.rectForRow(at: indexPath)
					exportOPML(sourceView: sourceView, sourceRect: sourceRect)
				}
			case .exportArticles:
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
				if let sourceView = tableView.cellForRow(at: indexPath) {
					let sourceRect = tableView.rectForRow(at: indexPath)
					exportArticlesCSV(sourceView: sourceView, sourceRect: sourceRect)
				}
			default:
				break
			}
		case .timeline:
			switch TimelineRow(rawValue: indexPath.row) {
			case .sortField:
				if let sourceView = tableView.cellForRow(at: indexPath) {
					let sourceRect = tableView.rectForRow(at: indexPath)
					presentSortFieldPicker(sourceView: sourceView, sourceRect: sourceRect)
				}
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
			case .sortDirection:
				if let sourceView = tableView.cellForRow(at: indexPath) {
					let sourceRect = tableView.rectForRow(at: indexPath)
					presentSortDirectionPicker(sourceView: sourceView, sourceRect: sourceRect)
				}
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
			case .timelineLayout:
				let timeline = UIStoryboard.settings.instantiateController(ofType: TimelineCustomizerCollectionViewController.self)
				self.navigationController?.pushViewController(timeline, animated: true)
			default:
				break
			}
		case .articles:
			switch ArticlesRow(rawValue: indexPath.row) {
			case .theme:
				// Scope note (surface-palette-followup-plan, Issue B): this is
				// the only one of the six SurfacePaletteAware screens with its
				// own internal color-picking UI (the ColorPicker below, bound
				// to article-theme colors, unrelated to Assets.Colors). The
				// .tint(observer.accentColor) applied by surfacePaletteAware
				// has been confirmed not to bleed into that ColorPicker.
				let hostingController = Self.makeSurfacePaletteAwareHostingController(rootView: ArticleThemeListView())
				self.navigationController?.pushViewController(hostingController, animated: true)
			case .pageCounterDisplayMode:
				if let sourceView = tableView.cellForRow(at: indexPath) {
					let sourceRect = tableView.rectForRow(at: indexPath)
					presentPageCounterDisplayModePicker(sourceView: sourceView, sourceRect: sourceRect)
				}
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
			default:
				break
			}
		case .appearance:
			switch AppearanceRow(rawValue: indexPath.row) {
			case .colorPalette:
				let colorPalette = UIStoryboard.settings.instantiateController(ofType: ColorPaletteTableViewController.self)
				self.navigationController?.pushViewController(colorPalette, animated: true)
			case .accentColor:
				let accentColor = UIStoryboard.settings.instantiateController(ofType: AccentColorTableViewController.self)
				self.navigationController?.pushViewController(accentColor, animated: true)
			case nil:
				break
			}
		case .troubleshooting:
			let viewController: UIViewController? = {
				switch TroubleshootingRow(rawValue: indexPath.row) {
				case .errorLog:
					return Self.makeSurfacePaletteAwareHostingController(rootView: ErrorLogView())
				case .accountStats:
					return Self.makeSurfacePaletteAwareHostingController(rootView: AccountStatsView())
				case .activityLog:
					return Self.makeSurfacePaletteAwareHostingController(rootView: ActivityLogView())
				case .dinosaurs:
					return UIHostingController(rootView: DinosaursView(dismissAndPresent: { [weak self] dinosaur in
						guard let self else {
							return
						}
						self.dismiss(animated: true) {
							if let rootSplit = self.presentingParentController as? RootSplitViewController {
								rootSplit.coordinator.discloseFeed(dinosaur.feed, animations: [.scroll, .navigation])
							}
						}
					}))
				case .manageStorage:
					return ManageStorageCollectionViewController()
				default:
					return nil
				}
			}()
			if let viewController {
				self.navigationController?.pushViewController(viewController, animated: true)
			}
		case .help:
			switch HelpRow(rawValue: indexPath.row) {
			case .about:
				let hosting = Self.makeSurfacePaletteAwareHostingController(rootView: AboutView())
				self.navigationController?.pushViewController(hosting, animated: true)
			default:
				break
			}
		case .ao3Account:
			let hosting = Self.makeSurfacePaletteAwareHostingController(rootView: AO3AccountSettingsView())
			self.navigationController?.pushViewController(hosting, animated: true)
		default:
			tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
		}
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		applySettingsCellBackground(to: cell)
	}

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		return false
	}

	override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
		return false
	}

	override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
		return .none
	}

	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		return UITableView.automaticDimension
	}

	override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
		// This hack works around a bug in static tables with dynamic type (see
		// viewDidLoad's comment above) -- it's not accounts-specific logic, just a
		// reference-point row. Repointed to .feeds (now the first section) since
		// .accounts was removed; picked because it's the first still-live section,
		// same rationale the original hack likely used when .accounts was section 0.
		// NOTE: couldn't verify the original NetNewsWire commit/blame that introduced
		// this hack in this environment -- confirm this doesn't reintroduce the
		// dynamic-type bug it was working around before merging.
		return super.tableView(tableView, indentationLevelForRowAt: IndexPath(row: 0, section: Section.feeds.rawValue))
	}

	// MARK: Actions

	@IBAction func done(_ sender: Any) {
		dismiss(animated: true)
	}

	/// Keeps both sort rows' detail labels in sync with the current
	/// `timelineSortField`/`timelineSortDirection`. The direction label is
	/// worded per-field (`ascendingLabel`/`descendingLabel`) rather than a
	/// fixed "Oldest to Newest," since that phrasing doesn't mean anything
	/// once the field is Title, Author, or Word Count. Called on appearance
	/// and whenever either value changes from this screen.
	func updateTimelineSortLabels() {
		let field = AppDefaults.shared.timelineSortField
		let direction = AppDefaults.shared.timelineSortDirection
		timelineSortFieldDetailLabel.text = field.displayName
		timelineSortDirectionDetailLabel.text = direction == .orderedAscending ? field.ascendingLabel : field.descendingLabel
	}

	func updatePageCounterDisplayModeLabel() {
		switch AppDefaults.shared.pageCounterDisplayMode {
		case .off:
			pageCounterDisplayModeDetailLabel.text = NSLocalizedString("Off", comment: "Page counter off")
		case .percentage:
			pageCounterDisplayModeDetailLabel.text = NSLocalizedString("Percentage", comment: "Page counter percentage")
		case .pageCount:
			pageCounterDisplayModeDetailLabel.text = NSLocalizedString("Page Count", comment: "Page counter page count")
		}
	}

	@IBAction func switchGroupByFeed(_ sender: Any) {
		if groupByFeedSwitch.isOn {
			AppDefaults.shared.timelineGroupByFeed = true
		} else {
			AppDefaults.shared.timelineGroupByFeed = false
		}
	}

	/// Phase 2f's settings toggle: "Ambrosia transfer format: JSON / SQLite,"
	/// applied uniformly to every Ambrosia-paired feed via
	/// AmbrosiaTransferFormatPreference (read by LocalAccountRefresher.url(for:)
	/// on each refresh) -- no per-feed override, no automatic size-based
	/// switching, per the plan.
	@IBAction func switchAmbrosiaTransferFormat(_ sender: Any) {
		AmbrosiaTransferFormatPreference.current = ambrosiaSQLiteTransferSwitch.isOn ? .sqlite : .json
	}

	@IBAction func switchClearsReadArticles(_ sender: Any) {
		if refreshClearsReadArticlesSwitch.isOn {
			AppDefaults.shared.refreshClearsReadArticles = true
		} else {
			AppDefaults.shared.refreshClearsReadArticles = false
		}
	}

	@IBAction func switchShowLastUpdatedLabel(_ sender: Any) {
		AppDefaults.shared.showLastUpdatedLabel = showLastUpdatedLabelSwitch.isOn
	}

	@IBAction func switchFullscreenArticles(_ sender: Any) {
		if showFullscreenArticlesSwitch.isOn {
			AppDefaults.shared.articleFullscreenAvailable = true
		} else {
			AppDefaults.shared.articleFullscreenAvailable = false
		}
	}

	@IBAction func switchBackSwipeEnabled(_ sender: Any) {
		AppDefaults.shared.articleBackSwipeEnabled = backSwipeEnabledSwitch.isOn
	}

	@IBAction func switchPagingSwipeEnabled(_ sender: Any) {
		AppDefaults.shared.articlePagingSwipeEnabled = pagingSwipeEnabledSwitch.isOn
	}

	@IBAction func switchShowFeedNameInReaderView(_ sender: Any) {
		AppDefaults.shared.showFeedNameInReaderView = showFeedNameInReaderViewSwitch.isOn
	}

	@IBAction func switchShowPrevNextArticleButtons(_ sender: Any) {
		AppDefaults.shared.showPrevNextArticleButtons = showPrevNextArticleButtonsSwitch.isOn
	}

	@IBAction func switchShowTableOfContentsAndFind(_ sender: Any) {
		AppDefaults.shared.showTableOfContentsAndFind = showTableOfContentsAndFindSwitch.isOn
	}

	@IBAction func switchHideNotchInFullScreen(_ sender: Any) {
		AppDefaults.shared.hideNotchInFullScreen = hideNotchInFullScreenSwitch.isOn
	}

	@IBAction func switchDisableArticleLinks(_ sender: Any) {
		AppDefaults.shared.disableArticleLinks = disableArticleLinksSwitch.isOn
	}

	@IBAction func switchBrowserPreference(_ sender: Any) {
		if openLinksInNetNewsWire.isOn {
			AppDefaults.shared.useSystemBrowser = false
		} else {
			AppDefaults.shared.useSystemBrowser = true
		}
	}

	// MARK: - Notifications

	@objc func contentSizeCategoryDidChange() {
		tableView.reloadData()
	}

	@objc func accountsDidChange() {
		tableView.reloadData()
	}

	@objc func displayNameDidChange() {
		tableView.reloadData()
	}

	@objc func accentColorDidChange(_ note: Notification) {
		applyAccentColorTinting()
	}

	@objc func surfaceTintDidChange(_ note: Notification) {
		for cell in tableView.visibleCells {
			applySettingsCellBackground(to: cell)
		}
	}

	/// Refreshes everything on this screen that depends on
	/// `AppDefaults.shared.accentColor`: the detail label showing the current
	/// choice, and every switch's `onTintColor`, which `Settings.storyboard`
	/// binds to the static `primaryAccentColor` asset rather than the live,
	/// accent-aware `Assets.Colors.primaryAccent` -- so that static binding is
	/// only ever a first-launch placeholder; this call is what actually keeps
	/// switches in sync with the person's accent choice, both on initial
	/// appearance and on every subsequent change.
	private func applyAccentColorTinting() {
		accentColorDetailLabel.text = AppDefaults.shared.accentColor.description

		let liveTint = Assets.Colors.primaryAccent
		for toggle in [groupByFeedSwitch, ambrosiaSQLiteTransferSwitch, refreshClearsReadArticlesSwitch,
					   showLastUpdatedLabelSwitch, showFullscreenArticlesSwitch, backSwipeEnabledSwitch,
					   pagingSwipeEnabledSwitch, showFeedNameInReaderViewSwitch, showPrevNextArticleButtonsSwitch,
					   showTableOfContentsAndFindSwitch, hideNotchInFullScreenSwitch, disableArticleLinksSwitch,
					   openLinksInNetNewsWire] {
			toggle?.onTintColor = liveTint
		}
	}

	@objc func browserPreferenceDidChange() {
		tableView.reloadData()
	}

}

// MARK: - Private

private extension SettingsViewController {

	func addFeed() {
		self.dismiss(animated: true)

		let addNavViewController = UIStoryboard.add.instantiateViewController(withIdentifier: "AddFeedViewControllerNav") as! UINavigationController
		let addViewController = addNavViewController.topViewController as! AddFeedViewController
		addViewController.initialFeed = AccountManager.netNewsWireNewsURL
		addViewController.initialFeedName = NSLocalizedString("NetNewsWire News", comment: "NetNewsWire News")
		addNavViewController.modalPresentationStyle = .formSheet
		addNavViewController.preferredContentSize = AddFeedViewController.preferredContentSizeForFormSheetDisplay

		presentingParentController?.present(addNavViewController, animated: true)
	}

	func exportOPML(sourceView: UIView, sourceRect: CGRect) {
		if AccountManager.shared.accounts.count == 1 {
			exportOPMLAccount = AccountManager.shared.accounts.first!
			exportOPMLDocumentPicker()
		} else {
			exportOPMLAccountPicker(sourceView: sourceView, sourceRect: sourceRect)
		}
	}

	func exportOPMLAccountPicker(sourceView: UIView, sourceRect: CGRect) {
		let title = NSLocalizedString("Choose an account with the subscriptions to export", comment: "Export Account")
		let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController {
			popoverController.sourceView = view
			popoverController.sourceRect = sourceRect
		}

		for account in AccountManager.shared.sortedAccounts {
			let action = UIAlertAction(title: account.nameForDisplay, style: .default) { [weak self] _ in
				self?.exportOPMLAccount = account
				self?.exportOPMLDocumentPicker()
			}
			alert.addAction(action)
		}

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		self.present(alert, animated: true)
	}

	func exportArticlesCSV(sourceView: UIView, sourceRect: CGRect) {
		if AccountManager.shared.accounts.count == 1 {
			exportArticlesCSVAccount = AccountManager.shared.accounts.first!
			presentExportArticlesFormatPicker(sourceView: sourceView, sourceRect: sourceRect)
		} else {
			exportArticlesCSVAccountPicker(sourceView: sourceView, sourceRect: sourceRect)
		}
	}

	func exportArticlesCSVAccountPicker(sourceView: UIView, sourceRect: CGRect) {
		let title = NSLocalizedString("Choose an account with the articles to export", comment: "Export Account")
		let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController {
			popoverController.sourceView = view
			popoverController.sourceRect = sourceRect
		}

		for account in AccountManager.shared.sortedAccounts {
			let action = UIAlertAction(title: account.nameForDisplay, style: .default) { [weak self] _ in
				self?.exportArticlesCSVAccount = account
				self?.presentExportArticlesFormatPicker(sourceView: sourceView, sourceRect: sourceRect)
			}
			alert.addAction(action)
		}

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		self.present(alert, animated: true)
	}

	// "Export All", so unlike MainFeedCollectionViewController's per-feed
	// picker, SQLite is always offered here -- there's no smart-feed-shaped
	// SidebarItem in play, just the account's every feedID (feedIDs: nil).
	func presentExportArticlesFormatPicker(sourceView: UIView, sourceRect: CGRect) {
		let title = NSLocalizedString("Choose an export format", comment: "Export Format")
		let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController {
			popoverController.sourceView = view
			popoverController.sourceRect = sourceRect
		}

		let csvTitle = NSLocalizedString("CSV", comment: "Export format")
		alert.addAction(UIAlertAction(title: csvTitle, style: .default) { [weak self] _ in
			self?.exportArticlesCSVDocumentPicker()
		})

		let sqliteTitle = NSLocalizedString("SQLite", comment: "Export format")
		alert.addAction(UIAlertAction(title: sqliteTitle, style: .default) { [weak self] _ in
			self?.exportArticlesSQLiteDocumentPicker()
		})

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		self.present(alert, animated: true)
	}

	func exportArticlesCSVDocumentPicker() {
		guard let account = exportArticlesCSVAccount else { return }

		let accountName = account.nameForDisplay.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
		let filename = "Articles-\(accountName).csv"
		let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
		do {
			let articles = account.flattenedFeeds().reduce(into: Set<Article>()) { result, feed in
				result.formUnion(feed.fetchArticles())
			}
			let csvString = ArticleCSVExporter.CSVString(with: Array(articles))
			try csvString.write(to: tempFile, atomically: true, encoding: String.Encoding.utf8)
		} catch {
			self.presentError(title: "CSV Export Error", message: error.localizedDescription)
			return
		}

		let docPicker = UIDocumentPickerViewController(forExporting: [tempFile])
		docPicker.modalPresentationStyle = .formSheet
		self.present(docPicker, animated: true)
	}

	func exportArticlesSQLiteDocumentPicker() {
		guard let account = exportArticlesCSVAccount else { return }

		let accountName = account.nameForDisplay.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
		let filename = "Articles-\(accountName).sqlite"
		let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
		// exportArticlesSQLite ATTACHes destinationPath as a new database and
		// requires it not already exist.
		try? FileManager.default.removeItem(at: tempFile)
		do {
			try account.exportArticlesSQLite(feedIDs: nil, toPath: tempFile.path)
		} catch {
			self.presentError(title: "SQLite Export Error", message: error.localizedDescription)
			return
		}

		let docPicker = UIDocumentPickerViewController(forExporting: [tempFile])
		docPicker.modalPresentationStyle = .formSheet
		self.present(docPicker, animated: true)
	}

	func exportOPMLDocumentPicker() {
		guard let account = exportOPMLAccount else { return }

		let accountName = account.nameForDisplay.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
		let filename = "Subscriptions-\(accountName).opml"
		let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
		do {
			try account.logActivity(kind: .exportOPML, detail: filename) {
				let opmlString = OPMLExporter.OPMLString(with: account, title: filename)
				try opmlString.write(to: tempFile, atomically: true, encoding: String.Encoding.utf8)
			}
		} catch {
			self.presentError(title: "OPML Export Error", message: error.localizedDescription)
		}

		let docPicker = UIDocumentPickerViewController(forExporting: [tempFile])
		docPicker.modalPresentationStyle = .formSheet
		self.present(docPicker, animated: true)
	}

	func presentPageCounterDisplayModePicker(sourceView: UIView, sourceRect: CGRect) {
		let title = NSLocalizedString("Page Counter", comment: "Page counter picker title")
		let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController {
			popoverController.sourceView = view
			popoverController.sourceRect = sourceRect
		}

		let options: [(PageCounterDisplayMode, String)] = [
			(.off, NSLocalizedString("Off", comment: "Page counter off")),
			(.percentage, NSLocalizedString("Percentage", comment: "Page counter percentage")),
			(.pageCount, NSLocalizedString("Page Count", comment: "Page counter page count"))
		]

		for (mode, label) in options {
			var actionTitle = label
			if mode == AppDefaults.shared.pageCounterDisplayMode {
				actionTitle = "✓ " + actionTitle
			}
			let action = UIAlertAction(title: actionTitle, style: .default) { [weak self] _ in
				AppDefaults.shared.pageCounterDisplayMode = mode
				self?.updatePageCounterDisplayModeLabel()
			}
			alert.addAction(action)
		}

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		self.present(alert, animated: true)
	}

	func presentSortFieldPicker(sourceView: UIView, sourceRect: CGRect) {
		let title = NSLocalizedString("Sort Timeline By", comment: "Sort field picker title")
		let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController {
			popoverController.sourceView = view
			popoverController.sourceRect = sourceRect
		}

		for field in ArticleSorter.SortField.allCases {
			var actionTitle = field.displayName
			if field == AppDefaults.shared.timelineSortField {
				actionTitle = "✓ " + actionTitle
			}
			let action = UIAlertAction(title: actionTitle, style: .default) { [weak self] _ in
				AppDefaults.shared.timelineSortField = field
				self?.updateTimelineSortLabels()
			}
			alert.addAction(action)
		}

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		self.present(alert, animated: true)
	}

	func presentSortDirectionPicker(sourceView: UIView, sourceRect: CGRect) {
		let title = NSLocalizedString("Order", comment: "Sort direction picker title")
		let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController {
			popoverController.sourceView = view
			popoverController.sourceRect = sourceRect
		}

		let field = AppDefaults.shared.timelineSortField
		let directions: [(ComparisonResult, String)] = [
			(.orderedDescending, field.descendingLabel),
			(.orderedAscending, field.ascendingLabel)
		]

		for (direction, label) in directions {
			var actionTitle = label
			if direction == AppDefaults.shared.timelineSortDirection {
				actionTitle = "✓ " + actionTitle
			}
			let action = UIAlertAction(title: actionTitle, style: .default) { [weak self] _ in
				AppDefaults.shared.timelineSortDirection = direction
				self?.updateTimelineSortLabels()
			}
			alert.addAction(action)
		}

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		self.present(alert, animated: true)
	}

}
