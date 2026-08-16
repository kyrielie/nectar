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

	@IBOutlet var showFullscreenArticlesSwitch: UISwitch!
	@IBOutlet var backSwipeEnabledSwitch: UISwitch!
	@IBOutlet var pagingSwipeEnabledSwitch: UISwitch!
	@IBOutlet var showArticleScrollbarSwitch: UISwitch!
	@IBOutlet var articleTopToolbarModeDetailLabel: UILabel!
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
		showArticleScrollbarSwitch.isOn = AppDefaults.shared.showArticleScrollbar
		updateArticleTopToolbarModeLabel()
		updatePageCounterDisplayModeLabel()
		updateHideNotchAvailability()
		applyAccentColorTinting()
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		applySettingsCellBackground(to: cell)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		switch Section(rawValue: indexPath.section) {
		case .topToolbar:
			let articleToolbar = UIStoryboard.settings.instantiateController(ofType: ArticleToolbarCustomizerViewController.self)
			self.navigationController?.pushViewController(articleToolbar, animated: true)
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

	func updateArticleTopToolbarModeLabel() {
		let enabledCount = ArticleToolbarToggle.allCases.filter(AppDefaults.shared.isArticleToolbarToggleEnabled).count
		if enabledCount == 0 {
			articleTopToolbarModeDetailLabel.text = NSLocalizedString("Off", comment: "Article top toolbar: no buttons shown")
		} else {
			let format = NSLocalizedString("%d Shown", comment: "Article top toolbar: number of buttons shown")
			articleTopToolbarModeDetailLabel.text = String(format: format, enabledCount)
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

	@IBAction func switchShowArticleScrollbar(_ sender: Any) {
		AppDefaults.shared.showArticleScrollbar = showArticleScrollbarSwitch.isOn
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
					   showArticleScrollbarSwitch, hideNotchInFullScreenSwitch] {
			toggle?.onTintColor = liveTint
		}
	}
}
