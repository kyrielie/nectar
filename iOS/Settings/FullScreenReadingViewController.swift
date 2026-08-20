//
//  FullScreenReadingViewController.swift
//  NetNewsWire-iOS
//

import UIKit

final class FullScreenReadingViewController: UITableViewController, SettingsPaletteBackgroundHosting {

	var paletteBackgroundView: UIView { tableView }

	private enum Section: Int {
		case gestures = 0
		case topToolbar = 1
		case fullscreenChrome = 2
	}

	private enum TopToolbarRow: Int {
		case toolbars = 0
	}

	/// Row order within .gestures, matching the storyboard scene's actual
	/// cell order (showFullscreenArticlesSwitch, backSwipeEnabledSwitch,
	/// pagingSwipeEnabledSwitch, then the Article Scrollbar row) -- only
	/// articleScrollbarVisibility needs a case here, since the other
	/// three rows are plain switches handled via valueChanged actions,
	/// not didSelectRowAt.
	private enum GesturesRow: Int {
		case articleScrollbarVisibility = 3
	}

	@IBOutlet var showFullscreenArticlesSwitch: UISwitch!
	@IBOutlet var backSwipeEnabledSwitch: UISwitch!
	@IBOutlet var pagingSwipeEnabledSwitch: UISwitch!
	// Replaces the old showArticleScrollbarSwitch UISwitch: a detail-label
	// push row to a 3-way picker (Off/Only Outside Full Screen/Always),
	// same shape as pageCounterDisplayModeDetailLabel below -- see
	// ArticleScrollbarVisibility. This is now the only entry point for
	// the setting; the old duplicate row in the main Settings screen
	// (SettingsViewController's ArticlesRow.showArticleScrollbar) has
	// been removed.
	@IBOutlet var articleScrollbarVisibilityDetailLabel: UILabel!
	@IBOutlet var toolbarsModeDetailLabel: UILabel!
	@IBOutlet var pageCounterDisplayModeDetailLabel: UILabel!
	@IBOutlet var hideNotchInFullScreenSwitch: UISwitch!

	override func viewDidLoad() {
		super.viewDidLoad()
		NotificationCenter.default.addObserver(self, selector: #selector(surfaceTintDidChange(_:)), name: .surfaceTintDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(accentColorDidChange(_:)), name: .accentColorDidChange, object: nil)
		configureSettingsPaletteBackground()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		showFullscreenArticlesSwitch.isOn = AppDefaults.shared.articleFullscreenAvailable
		backSwipeEnabledSwitch.isOn = AppDefaults.shared.articleBackSwipeEnabled
		pagingSwipeEnabledSwitch.isOn = AppDefaults.shared.articlePagingSwipeEnabled
		updateArticleScrollbarVisibilityLabel()
		updateToolbarsModeLabel()
		updatePageCounterDisplayModeLabel()
		updateHideNotchAvailability()
		applyAccentColorTinting()
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		applySettingsCellBackground(to: cell)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		switch Section(rawValue: indexPath.section) {
		case .gestures:
			switch GesturesRow(rawValue: indexPath.row) {
			case .articleScrollbarVisibility:
				if let sourceView = tableView.cellForRow(at: indexPath) {
					let sourceRect = tableView.rectForRow(at: indexPath)
					presentArticleScrollbarVisibilityPicker(sourceView: sourceView, sourceRect: sourceRect)
				}
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
			case nil:
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
			}
		case .topToolbar:
			switch TopToolbarRow(rawValue: indexPath.row) {
			case .toolbars:
				let toolbars = UIStoryboard.settings.instantiateController(ofType: ToolbarsCustomizerViewController.self)
				self.navigationController?.pushViewController(toolbars, animated: true)
			case nil:
				break
			}
			tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
		case .fullscreenChrome where indexPath.row == 0: // Page Counter
			if let sourceView = tableView.cellForRow(at: indexPath) {
				let sourceRect = tableView.rectForRow(at: indexPath)
				presentPageCounterDisplayModePicker(sourceView: sourceView, sourceRect: sourceRect)
			}
			tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
		default:
			tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
		}
	}

	/// Combined summary across both bars -- counts every ToolbarFunction
	/// enabled inline on either .top or .bottom (a function placed on
	/// both counts once, matching "how many buttons show up somewhere"
	/// rather than a raw sum across bars). Replaces the two
	/// pre-unification per-bar labels (articleTopToolbarModeDetailLabel/
	/// articleBottomToolbarModeDetailLabel) now that both bars are
	/// configured from a single Toolbars row.
	func updateToolbarsModeLabel() {
		let defaults = AppDefaults.shared
		let enabledCount = ToolbarFunction.allCases.filter {
			defaults.isToolbarFunctionEnabled($0, on: .top) || defaults.isToolbarFunctionEnabled($0, on: .bottom)
		}.count
		if enabledCount == 0 {
			toolbarsModeDetailLabel.text = NSLocalizedString("Off", comment: "Toolbars: no buttons shown")
		} else {
			let format = NSLocalizedString("%d Shown", comment: "Toolbars: number of buttons shown")
			toolbarsModeDetailLabel.text = String(format: format, enabledCount)
		}
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
				self?.updateHideNotchAvailability()
			}
			alert.addAction(action)
		}

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		self.present(alert, animated: true)
	}

	func updateArticleScrollbarVisibilityLabel() {
		articleScrollbarVisibilityDetailLabel.text = AppDefaults.shared.articleScrollbarVisibility.title
	}

	func presentArticleScrollbarVisibilityPicker(sourceView: UIView, sourceRect: CGRect) {
		let title = NSLocalizedString("Article Scrollbar", comment: "Article scrollbar picker title")
		let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController {
			popoverController.sourceView = view
			popoverController.sourceRect = sourceRect
		}

		for mode in ArticleScrollbarVisibility.allCases {
			var actionTitle = mode.title
			if mode == AppDefaults.shared.articleScrollbarVisibility {
				actionTitle = "✓ " + actionTitle
			}
			let action = UIAlertAction(title: actionTitle, style: .default) { [weak self] _ in
				AppDefaults.shared.articleScrollbarVisibility = mode
				self?.updateArticleScrollbarVisibilityLabel()
			}
			alert.addAction(action)
		}

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		self.present(alert, animated: true)
	}

	/// WebViewController.updateNotchAndPageCounterVisibility() forces
	/// notch-hiding whenever Page Counter != .off, independent of this
	/// switch's own stored value. Reflects that here by disabling the
	/// switch (not just relabeling it) so it stops silently disagreeing
	/// with actual reading-view behavior. hideNotchInFullScreen's own
	/// AppDefaults value is untouched -- this only affects what the switch
	/// displays and whether it's interactive, not what's persisted.
	func updateHideNotchAvailability() {
		let forcedByPageCounter = AppDefaults.shared.pageCounterDisplayMode != .off
		hideNotchInFullScreenSwitch.isEnabled = !forcedByPageCounter
		hideNotchInFullScreenSwitch.isOn = forcedByPageCounter ? true : AppDefaults.shared.hideNotchInFullScreen
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

	// updateHideNotchAvailability() already disables the switch whenever
	// Page Counter forces it on, and a disabled UISwitch doesn't fire
	// valueChanged, so no extra guard is needed here to avoid writing
	// AppDefaults while the switch is forced.
	@IBAction func switchHideNotchInFullScreen(_ sender: Any) {
		AppDefaults.shared.hideNotchInFullScreen = hideNotchInFullScreenSwitch.isOn
	}

	@objc func accentColorDidChange(_ note: Notification) {
		applyAccentColorTinting()
	}

	@objc func surfaceTintDidChange(_ note: Notification) {
		refreshPaletteCellBackgrounds()
	}

	func refreshPaletteCellBackgrounds() {
		for cell in tableView.visibleCells {
			applySettingsCellBackground(to: cell)
		}
	}

	private func applyAccentColorTinting() {
		let liveTint = Assets.Colors.primaryAccent
		for toggle in [showFullscreenArticlesSwitch, backSwipeEnabledSwitch, pagingSwipeEnabledSwitch,
					   hideNotchInFullScreenSwitch] {
			toggle?.onTintColor = liveTint
		}
	}
}
