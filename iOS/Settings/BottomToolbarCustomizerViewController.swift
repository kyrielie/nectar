//
//  BottomToolbarCustomizerViewController.swift
//  NetNewsWire-iOS
//
//  Same 2-section UICollectionViewCompositionalLayout list shape as
//  ArticleToolbarCustomizerViewController, applied to
//  ArticleViewController's bottom UIToolbar instead of its top navigation
//  bar: Preview (0), Bottom Toolbar (1).
//
//  Preview (0) is a single BottomToolbarPreviewCell showing the real
//  toolbar icons/order live. Bottom Toolbar (1) is one
//  BottomToolbarToggleCell per BottomToolbarToggle case (read, star,
//  heart, next unread, action, in that fixed order) -- each an
//  independent UISwitch row, flipping one writes straight to its own
//  AppDefaults property and reloads both sections in place.
//
//  Unlike the top toolbar, there's no icon-count cap here: the bottom
//  bar's flexibleSpace-separated layout (see
//  ArticleViewController.bottomToolbarItems()) distributes any number of
//  items evenly across the bar's full width, rather than competing for a
//  handful of fixed-width leading slots the way the top nav bar's
//  rightBarButtonItems() does -- there's no analogous "too many icons"
//  failure mode to cap against.
//
//  Both sections reload on the generic UserDefaults.didChangeNotification,
//  same reasoning as ArticleToolbarCustomizerViewController's own header
//  comment.
//

import UIKit

class BottomToolbarCustomizerViewController: UICollectionViewController, SettingsPaletteBackgroundHosting {

	var paletteBackgroundView: UIView { collectionView }

	private var previewSection: Int { 0 }
	private var pickerSection: Int { 1 }

	override func viewDidLoad() {
		super.viewDidLoad()
		title = NSLocalizedString("Bottom Toolbar", comment: "Article Bottom Toolbar screen title")

		// Same lifetime reasoning as ArticleToolbarCustomizerViewController's
		// own observers: block-based, weakly captures self, left registered
		// for the process lifetime.
		NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}

		NotificationCenter.default.addObserver(forName: .surfaceTintDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.refreshPaletteCellBackgrounds()
			}
		}

		configureCollectionView()
		configureSettingsPaletteBackground()
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

		collectionView.register(BottomToolbarPreviewCell.self, forCellWithReuseIdentifier: BottomToolbarPreviewCell.reuseIdentifier)
		collectionView.register(BottomToolbarToggleCell.self, forCellWithReuseIdentifier: BottomToolbarToggleCell.reuseIdentifier)

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
		return BottomToolbarToggle.allCases.count
	}

	override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		if indexPath.section == previewSection {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BottomToolbarPreviewCell.reuseIdentifier, for: indexPath) as! BottomToolbarPreviewCell
			cell.configure()
			return cell
		}

		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BottomToolbarToggleCell.reuseIdentifier, for: indexPath) as! BottomToolbarToggleCell
		let toggle = BottomToolbarToggle.allCases[indexPath.item]
		cell.configure(toggle: toggle, isOn: AppDefaults.shared.isBottomToolbarToggleEnabled(toggle))
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
			header.label.text = NSLocalizedString("Bottom Toolbar", comment: "Bottom Toolbar")
		default:
			header.label.text = NSLocalizedString("", comment: "")
		}
		return header
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
		CGSize(width: collectionView.bounds.width, height: 50)
	}

	// No shouldSelectItemAt/didSelectItemAt override needed -- same
	// reasoning as ArticleToolbarCustomizerViewController.

	// MARK: Notifications

	func userDefaultsDidChange() {
		collectionView.reloadData()
	}

}
