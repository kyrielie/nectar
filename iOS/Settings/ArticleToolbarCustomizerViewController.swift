//
//  ArticleToolbarCustomizerViewController.swift
//  NetNewsWire-iOS
//
//  Article view top toolbar settings plan. Replaces the two independent,
//  silently-conflicting showTableOfContentsAndFind/showPrevNextArticleButtons
//  switches (formerly ArticlesRow 6-7) with a single push row -- same
//  pattern as the existing Timeline Layout row -- to a 2-section
//  UICollectionViewCompositionalLayout list, modeled on
//  TimelineCustomizerCollectionViewController's shape but with the preview
//  above the picker rather than below it: Preview (0), Top Toolbar (1).
//
//  Preview (0) is a single ArticleToolbarPreviewCell showing the real nav
//  bar icons/order/either-or shape live, so the person sees the actual
//  bar-button icons update as they choose, rather than inferring behavior
//  from switch labels. Top Toolbar (1) is one ArticleTopToolbarModeCell per
//  ArticleTopToolbarMode case, checkmark-style single-select -- selecting a
//  row sets AppDefaults.shared.articleTopToolbarMode directly and reloads
//  both sections in place (no pop-on-select, matching
//  AccentColorTableViewController's reload-in-place shape).
//
//  Both sections reload on the generic UserDefaults.didChangeNotification --
//  unlike Timeline Layout's per-setting notifications, articleTopToolbarMode's
//  setter doesn't post a dedicated one, and ArticleViewController itself
//  already relies on this same generic notification to repaint its real nav
//  bar (see ArticleViewController.userDefaultsDidChange(_:)), so this
//  screen's preview and the real reader deliberately stay on the same
//  live-update path rather than gaining a second, parallel one.
//

import UIKit

class ArticleToolbarCustomizerViewController: UICollectionViewController, SettingsPaletteBackgroundHosting {

	var paletteBackgroundView: UIView { collectionView }

	private var notificationObserver: NSObjectProtocol?

	private var previewSection: Int { 0 }
	private var pickerSection: Int { 1 }

	override func viewDidLoad() {
		super.viewDidLoad()
		title = NSLocalizedString("Top Toolbar", comment: "Article Top Toolbar screen title")

		notificationObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}

		// Same fix shape as TimelineCustomizerCollectionViewController: force
		// a reload so both cell types re-run updateConfiguration(using:)
		// with the live palette when SurfacePalette changes while this
		// screen is visible.
		NotificationCenter.default.addObserver(forName: .surfaceTintDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.refreshPaletteCellBackgrounds()
			}
		}

		configureCollectionView()
		configureSettingsPaletteBackground()
	}

	deinit {
		if let notificationObserver {
			NotificationCenter.default.removeObserver(notificationObserver)
		}
	}

	// SettingsPaletteBackgroundHosting
	func refreshPaletteCellBackgrounds() {
		userDefaultsDidChange()
	}

	private func configureCollectionView() {
		collectionView.register(
			TimelineHeaderView.self,
			forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
			withReuseIdentifier: TimelineHeaderView.reuseIdentifier
		)

		collectionView.register(ArticleToolbarPreviewCell.self, forCellWithReuseIdentifier: ArticleToolbarPreviewCell.reuseIdentifier)
		collectionView.register(ArticleTopToolbarModeCell.self, forCellWithReuseIdentifier: ArticleTopToolbarModeCell.reuseIdentifier)

		var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
		config.showsSeparators = false
		config.headerMode = .supplementary

		let layout = UICollectionViewCompositionalLayout.list(using: config)

		collectionView.setCollectionViewLayout(layout, animated: false)
	}

	// MARK: UICollectionViewDataSource

	override func numberOfSections(in collectionView: UICollectionView) -> Int {
		return 2
	}

	override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		if section == previewSection {
			return 1
		}
		return ArticleTopToolbarMode.allCases.count
	}

	override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		if indexPath.section == previewSection {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ArticleToolbarPreviewCell.reuseIdentifier, for: indexPath) as! ArticleToolbarPreviewCell
			cell.configure(mode: AppDefaults.shared.articleTopToolbarMode)
			return cell
		}

		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ArticleTopToolbarModeCell.reuseIdentifier, for: indexPath) as! ArticleTopToolbarModeCell
		let mode = ArticleTopToolbarMode.allCases[indexPath.item]
		cell.configure(mode: mode, isSelected: mode == AppDefaults.shared.articleTopToolbarMode)
		return cell
	}

	// MARK: UICollectionViewDelegate

	override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
		guard kind == UICollectionView.elementKindSectionHeader else {
			return UICollectionReusableView()
		}

		let header = collectionView.dequeueReusableSupplementaryView(
			ofKind: kind,
			withReuseIdentifier: TimelineHeaderView.reuseIdentifier,
			for: indexPath
		) as! TimelineHeaderView

		switch indexPath.section {
		case previewSection:
			header.label.text = NSLocalizedString("Preview", comment: "Preview")
		case pickerSection:
			header.label.text = NSLocalizedString("Top Toolbar", comment: "Top Toolbar")
		default:
			header.label.text = NSLocalizedString("", comment: "")
		}
		return header
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
		CGSize(width: collectionView.bounds.width, height: 50)
	}

	override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
		// Only the picker rows are interactive; the preview row isn't.
		return indexPath.section == pickerSection
	}

	override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		guard indexPath.section == pickerSection else { return }
		let mode = ArticleTopToolbarMode.allCases[indexPath.item]
		AppDefaults.shared.articleTopToolbarMode = mode
		collectionView.reloadSections(IndexSet([previewSection, pickerSection]))
	}

	// MARK: Notifications

	func userDefaultsDidChange() {
		collectionView.reloadData()
	}

}
