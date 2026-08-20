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
		case backup = 7
	}

	/// See docs/app-chrome-palette.md ("Badge Colors"). Wraps `rootView` with
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
		case feedTransferFormat = 3
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
		case disableArticleLinks = 2
		case showFeedNameInReaderView = 3
		case fullScreenReading = 4
		case annotations = 5
	}

	private enum HelpRow: Int {
		case about = 0
	}

	private enum BackupRow: Int {
		case backup = 0
		case restore = 1
	}

	private weak var exportOPMLAccount: Account?
	private weak var exportArticlesCSVAccount: Account?
	private weak var exportAnnotationsAccount: Account?

	@IBOutlet var timelineSortFieldDetailLabel: UILabel!
	@IBOutlet var timelineSortDirectionDetailLabel: UILabel!
	@IBOutlet var groupByFeedSwitch: UISwitch!
	@IBOutlet var groupByFeedReasonLabel: UILabel!
	@IBOutlet var feedTransferFormatDetailLabel: UILabel!
	@IBOutlet var refreshClearsReadArticlesSwitch: UISwitch!
	@IBOutlet var clearReadArticlesReasonLabel: UILabel!
	@IBOutlet var articleThemeDetailLabel: UILabel!
	@IBOutlet var showLastUpdatedLabelSwitch: UISwitch!
	@IBOutlet var showFeedNameInReaderViewSwitch: UISwitch!
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
		updateGroupByFeedAvailability()

		updateFeedTransferFormatLabel()

		if AppDefaults.shared.refreshClearsReadArticles {
			refreshClearsReadArticlesSwitch.isOn = true
		} else {
			refreshClearsReadArticlesSwitch.isOn = false
		}
		updateClearReadArticlesReasonLabel()

		articleThemeDetailLabel.text = ArticleThemesManager.shared.currentTheme.name

		showLastUpdatedLabelSwitch.isOn = AppDefaults.shared.showLastUpdatedLabel

		showFeedNameInReaderViewSwitch.isOn = AppDefaults.shared.showFeedNameInReaderView
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
			// the row count stuck at a stale case count on non-phone idioms; since
			// there is no non-phone idiom here, that branch was both dead and, once
			// ArticlesRow's case count changed, wrong.)
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
			case .feedTransferFormat:
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
				if let sourceView = tableView.cellForRow(at: indexPath) {
					let sourceRect = tableView.rectForRow(at: indexPath)
					presentFeedTransferFormatPicker(sourceView: sourceView, sourceRect: sourceRect)
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
				// Scope note (see docs/app-chrome-palette.md, "Badge Colors"): this is
				// the only one of the six SurfacePaletteAware screens with its
				// own internal color-picking UI (the ColorPicker below, bound
				// to article-theme colors, unrelated to Assets.Colors). The
				// .tint(observer.accentColor) applied by surfacePaletteAware
				// has been confirmed not to bleed into that ColorPicker.
				let hostingController = Self.makeSurfacePaletteAwareHostingController(rootView: ArticleThemeListView())
				self.navigationController?.pushViewController(hostingController, animated: true)
			case .fullScreenReading:
				let fullScreenReading = UIStoryboard.settings.instantiateController(ofType: FullScreenReadingViewController.self)
				self.navigationController?.pushViewController(fullScreenReading, animated: true)
			case .annotations:
				let hostingController = Self.makeSurfacePaletteAwareHostingController(rootView: AnnotationsSettingsView(
					onExportCSV: { [weak self] sourceView, sourceRect in
						self?.exportAnnotationsCSVAccountPicker(sourceView: sourceView, sourceRect: sourceRect)
					},
					onExportSQLite: { [weak self] sourceView, sourceRect in
						self?.exportAnnotationsSQLiteAccountPicker(sourceView: sourceView, sourceRect: sourceRect)
					},
					onNavigateToAnnotation: { [weak self] annotation, account in
						self?.navigateToAnnotationFromSettings(annotation, account: account)
					}
				))
				self.navigationController?.pushViewController(hostingController, animated: true)
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
		case .backup:
			switch BackupRow(rawValue: indexPath.row) {
			case .backup:
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
				if let sourceView = tableView.cellForRow(at: indexPath) {
					let sourceRect = tableView.rectForRow(at: indexPath)
					exportBackupDocumentPicker(sourceView: sourceView, sourceRect: sourceRect)
				}
			case .restore:
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
				if let sourceView = tableView.cellForRow(at: indexPath) {
					let sourceRect = tableView.rectForRow(at: indexPath)
					BackupRestoreCoordinator.begin(presentingController: self, sourceView: sourceView, sourceRect: sourceRect)
				}
			case nil:
				break
			}
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
		updateGroupByFeedAvailability()
	}

	/// Reflects ArticleArray.sorted(by:sortDirection:groupByFeed:)'s actual
	/// gating: groupByFeed only affects output when sortField == .date.
	/// Called from viewWillAppear and from updateTimelineSortLabels(), so
	/// picking a different Sort Field updates this row's state in the same
	/// pass that updates the Sort By/Order labels.
	func updateGroupByFeedAvailability() {
		let available = AppDefaults.shared.timelineSortField == .date
		groupByFeedSwitch.isEnabled = available
		groupByFeedReasonLabel.text = available ? nil : NSLocalizedString("Only applies when sorted by Date", comment: "Group by Feed inapplicable reason")
		groupByFeedReasonLabel.isHidden = available
	}

	/// Best-effort snapshot of SceneCoordinator.isReadArticlesFiltered for
	/// whatever feed/folder is currently open, taken once per appearance --
	/// not live while Settings is open, since Filter Read Articles has no
	/// dedicated change notification to observe. Unlike
	/// updateGroupByFeedAvailability(), this never disables the switch: the
	/// setting takes effect the moment the Read Articles filter is next
	/// turned on for any feed, so disabling it here would overclaim a
	/// precision this snapshot doesn't have.
	func updateClearReadArticlesReasonLabel() {
		let coordinator = (presentingParentController as? RootSplitViewController)?.coordinator
		let filterOnNow = coordinator?.isReadArticlesFiltered ?? false
		clearReadArticlesReasonLabel.text = filterOnNow ? nil : NSLocalizedString("Only applies when the Read Articles filter is on", comment: "Clear read articles inapplicable reason")
		clearReadArticlesReasonLabel.isHidden = filterOnNow
	}

	@IBAction func switchGroupByFeed(_ sender: Any) {
		if groupByFeedSwitch.isOn {
			AppDefaults.shared.timelineGroupByFeed = true
		} else {
			AppDefaults.shared.timelineGroupByFeed = false
		}
	}

	func updateFeedTransferFormatLabel() {
		feedTransferFormatDetailLabel.text = AmbrosiaTransferFormatPreference.current == .sqlite
			? NSLocalizedString("SQLite", comment: "Feed transfer format")
			: NSLocalizedString("JSON", comment: "Feed transfer format")
	}

	/// "Ambrosia transfer format: JSON / SQLite," applied uniformly to
	/// every Ambrosia-paired feed via AmbrosiaTransferFormatPreference
	/// (read by LocalAccountRefresher.url(for:) on each refresh) -- no
	/// per-feed override, no automatic size-based switching. A single
	/// global picker is simpler for a person to reason about than a
	/// format that silently varies by feed or by response size; see
	/// docs/sqlite-transfer.md for the format itself.
	func presentFeedTransferFormatPicker(sourceView: UIView, sourceRect: CGRect) {
		let title = NSLocalizedString("Feed Transfer Format", comment: "Feed transfer format picker title")
		let message = NSLocalizedString("Affects only feeds that support the SQLite transfer protocol. Most feeds are unaffected.", comment: "Feed transfer format picker explanation")
		let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController {
			popoverController.sourceView = view
			popoverController.sourceRect = sourceRect
		}

		let options: [(AmbrosiaTransferFormat, String)] = [
			(.json, NSLocalizedString("JSON", comment: "Feed transfer format")),
			(.sqlite, NSLocalizedString("SQLite", comment: "Feed transfer format"))
		]

		for (format, label) in options {
			var actionTitle = label
			if format == AmbrosiaTransferFormatPreference.current {
				actionTitle = "✓ " + actionTitle
			}
			let action = UIAlertAction(title: actionTitle, style: .default) { [weak self] _ in
				AmbrosiaTransferFormatPreference.current = format
				self?.updateFeedTransferFormatLabel()
			}
			alert.addAction(action)
		}

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		self.present(alert, animated: true)
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

	@IBAction func switchShowFeedNameInReaderView(_ sender: Any) {
		AppDefaults.shared.showFeedNameInReaderView = showFeedNameInReaderViewSwitch.isOn
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
		refreshPaletteCellBackgrounds()
	}

	// SettingsPaletteBackgroundHosting -- also called on a light/dark trait
	// change now, not just a palette switch; see SettingsBackgroundPalette.swift.
	func refreshPaletteCellBackgrounds() {
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
		for toggle in [groupByFeedSwitch, refreshClearsReadArticlesSwitch,
					   showLastUpdatedLabelSwitch, showFeedNameInReaderViewSwitch,
					   disableArticleLinksSwitch, openLinksInNetNewsWire] {
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

	// MARK: - Backup export
	//
	// Direct analogue of exportArticlesSQLiteDocumentPicker above, matching
	// the same UIDocumentPickerViewController(forExporting:) idiom
	// (Correction 1) -- unlike the CSV/SQLite exports, this isn't scoped to
	// a single account: BackupManager.exportBackup() covers every account,
	// custom themes, and (if opted in) settings in one archive.

	func exportBackupDocumentPicker(sourceView: UIView, sourceRect: CGRect) {
		let includeSettings = AppDefaults.backupEligibleKeys.contains { AppDefaults.store.object(forKey: $0) != nil }

		let zipURL: URL
		do {
			zipURL = try ActivityLog.shared.logActivity(owner: .app, kind: .exportBackup) {
				try BackupManager.exportBackup(includeSettings: includeSettings)
			}
		} catch {
			self.presentError(title: "Backup Error", message: error.localizedDescription)
			return
		}

		let docPicker = UIDocumentPickerViewController(forExporting: [zipURL])
		docPicker.modalPresentationStyle = .formSheet
		self.present(docPicker, animated: true)
		// BackupManager leaves zipURL's containing temp folder in place for
		// the document picker to read from; nothing further to clean up
		// here since it's already inside FileManager's temporaryDirectory,
		// which the system reclaims on its own schedule -- matching every
		// other tempFile export above, none of which explicitly delete
		// their own temp output either.
	}

	// MARK: - Annotations export
	//
	// Direct analogue of exportArticlesCSV/exportArticlesCSVDocumentPicker
	// above: account picker (skipped if only one account), then straight
	// to CSV -- unlike the article export flow there's no separate
	// format-picker step here, since SQLite export for annotations is
	// reached through the existing "Export Articles" SQLite flow already
	// (annotations ride along automatically, see
	// ArticleSQLiteExportTable.copyItems), not a second, annotations-only
	// SQLite path. This entry point is reachable only from
	// AnnotationsSettingsView -- unlike article export, there's no
	// separate Feeds-section duplicate of this row, since the two calls
	// would be identical and the annotations screen is already the
	// natural place to find it.

	func exportAnnotationsCSVAccountPicker(sourceView: UIView, sourceRect: CGRect) {
		if AccountManager.shared.accounts.count == 1 {
			exportAnnotationsAccount = AccountManager.shared.accounts.first!
			exportAnnotationsCSVDocumentPicker()
			return
		}

		let title = NSLocalizedString("Choose an account with the highlights to export", comment: "Export Account")
		let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController {
			popoverController.sourceView = view
			popoverController.sourceRect = sourceRect
		}

		for account in AccountManager.shared.sortedAccounts {
			let action = UIAlertAction(title: account.nameForDisplay, style: .default) { [weak self] _ in
				self?.exportAnnotationsAccount = account
				self?.exportAnnotationsCSVDocumentPicker()
			}
			alert.addAction(action)
		}

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		self.present(alert, animated: true)
	}

	func exportAnnotationsCSVDocumentPicker() {
		guard let account = exportAnnotationsAccount else { return }

		let accountName = account.nameForDisplay.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
		let filename = "Highlights-\(accountName).csv"
		let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

		Task {
			let annotations = await account.fetchAllAnnotations()
			let articleIDs = Set(annotations.map(\.articleID))
			let articles = await account.fetchArticlesAsync(.articleIDs(articleIDs))
			let articlesByID = Dictionary(uniqueKeysWithValues: articles.map { ($0.articleID, $0) })
			let rows = annotations.map { annotation in (annotation, articlesByID[annotation.articleID]) }

			do {
				let csvString = AnnotationCSVExporter.CSVString(with: rows)
				try csvString.write(to: tempFile, atomically: true, encoding: String.Encoding.utf8)
			} catch {
				self.presentError(title: "CSV Export Error", message: error.localizedDescription)
				return
			}

			let docPicker = UIDocumentPickerViewController(forExporting: [tempFile])
			docPicker.modalPresentationStyle = .formSheet
			self.present(docPicker, animated: true)
		}
	}

	// SQLite export for annotations doesn't have its own document-picker
	// path: annotations already ride along with the existing "Export
	// Articles" -> SQLite flow (exportArticlesSQLiteDocumentPicker above),
	// since ArticleSQLiteExportTable now copies the annotations table as
	// part of that same full-database snapshot. This just routes to that
	// existing flow with the account already chosen, rather than
	// duplicating the SQLite export logic here.
	func exportAnnotationsSQLiteAccountPicker(sourceView: UIView, sourceRect: CGRect) {
		if AccountManager.shared.accounts.count == 1 {
			exportArticlesCSVAccount = AccountManager.shared.accounts.first!
			exportArticlesSQLiteDocumentPicker()
			return
		}
		exportArticlesCSVAccountPicker(sourceView: sourceView, sourceRect: sourceRect)
	}

	/// Settings' unscoped annotations list has no open article behind it
	/// (unlike ArticleViewController.navigateToAnnotation's same-article
	/// case), so this always dismisses Settings first, then delegates to
	/// ArticleViewController.navigateToAnnotation(_:account:) itself via
	/// SceneCoordinator.currentArticleViewController -- reusing that
	/// method's own selectArticleDirectly + awaitNextPageLoad + scroll
	/// sequence rather than re-deriving it here. If there's no article
	/// column pushed yet (compact-width, timeline still on screen),
	/// selectArticleDirectly on the coordinator alone still selects and
	/// pushes the article; navigateToAnnotation's same-article fast path
	/// then finds articleID already matching and just scrolls.
	func navigateToAnnotationFromSettings(_ annotation: Annotation, account: Account) {
		guard let rootSplit = presentingParentController as? RootSplitViewController else { return }
		let coordinator = rootSplit.coordinator

		self.dismiss(animated: true) {
			Task {
				await coordinator?.selectArticleDirectly(annotation.articleID, account: account)
				coordinator?.currentArticleViewController?.navigateToAnnotation(annotation, account: account)
			}
		}
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
