//
//  ArticleToolbarCustomizerViewController.swift
//  NetNewsWire-iOS
//
//  Replaces the two independent, silently-conflicting
//  showTableOfContentsAndFind/showPrevNextArticleButtons switches (formerly
//  ArticlesRow 6-7) with a push row -- same pattern as the existing
//  Timeline Layout row -- to a 2-section UICollectionViewCompositionalLayout
//  list, modeled on TimelineCustomizerCollectionViewController's shape but
//  with the preview above the toggles rather than below: Preview (0),
//  Top Toolbar (1).
//
//  Preview (0) is a single ArticleToolbarPreviewCell showing the real nav
//  bar icons/order live, so the person sees the actual bar-button icons
//  update as they flip switches, rather than inferring behavior from
//  labels. Top Toolbar (1) is one ArticleToolbarToggleCell per
//  ArticleToolbarToggle case (theme, table of contents, find, prev/next,
//  lock, annotations, settings, check for updates, in that fixed order)
//  -- each an independent UISwitch row, freely combinable up to a 4-icon
//  cap (prevNext counts as 2 slots); flipping one writes straight to its
//  own AppDefaults property and reloads both sections in place. See
//  slotsUsed(excluding:) for the cap.
//
//  Both sections reload on the generic UserDefaults.didChangeNotification --
//  the toggle setters don't post a dedicated notification, and
//  ArticleViewController itself already relies on this same generic
//  notification to repaint its real nav bar (see
//  ArticleViewController.userDefaultsDidChange(_:)), so this screen's
//  preview and the real reader deliberately stay on the same live-update
//  path rather than gaining a second, parallel one.
//

import UIKit

class ArticleToolbarCustomizerViewController: UICollectionViewController, SettingsPaletteBackgroundHosting {

	var paletteBackgroundView: UIView { collectionView }

	private var previewSection: Int { 0 }
	private var pickerSection: Int { 1 }

	override func viewDidLoad() {
		super.viewDidLoad()
		title = NSLocalizedString("Top Toolbar", comment: "Article Top Toolbar screen title")

		// Block-based observers only weakly capture self and are safe to
		// leave registered for the process lifetime -- same as
		// TimelineCustomizerCollectionViewController's own observers below,
		// which don't store a token or remove themselves in deinit either.
		// (Storing the returned token would also be a non-Sendable
		// NSObjectProtocol stored property, which nonisolated deinit can't
		// touch under Swift 6 strict concurrency.)
		NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
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
		collectionView.register(ArticleToolbarToggleCell.self, forCellWithReuseIdentifier: ArticleToolbarToggleCell.reuseIdentifier)

		var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
		config.showsSeparators = false
		config.headerMode = .supplementary

		let layout = UICollectionViewCompositionalLayout.list(using: config)

		collectionView.setCollectionViewLayout(layout, animated: false)
	}

	// MARK: Icon cap

	/// Top-toolbar icon slots this cap applies to (matches
	/// ArticleViewController.rightBarButtonItems()'s fixed-width leading
	/// cluster) -- prevNext counts as 2 slots since it appends both
	/// nextArticleBarButtonItem and prevArticleBarButtonItem.
	private static let maxSlots = 4

	private func slotsUsed(excluding toggle: ArticleToolbarToggle? = nil) -> Int {
		ArticleToolbarToggle.allCases
			.filter { $0 != toggle && AppDefaults.shared.isArticleToolbarToggleEnabled($0) }
			.reduce(0) { $0 + ($1 == .prevNext ? 2 : 1) }
	}

	// MARK: UICollectionViewDataSource

	override func numberOfSections(in collectionView: UICollectionView) -> Int {
		return 2
	}

	override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		if section == previewSection {
			return 1
		}
		return ArticleToolbarToggle.allCases.count
	}

	override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		if indexPath.section == previewSection {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ArticleToolbarPreviewCell.reuseIdentifier, for: indexPath) as! ArticleToolbarPreviewCell
			cell.configure()
			return cell
		}

		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ArticleToolbarToggleCell.reuseIdentifier, for: indexPath) as! ArticleToolbarToggleCell
		let toggle = ArticleToolbarToggle.allCases[indexPath.item]
		let isOn = AppDefaults.shared.isArticleToolbarToggleEnabled(toggle)
		// A row already on stays interactive (so it can be turned back
		// off); an off row past the cap becomes non-interactive, disabled
		// like the same-shape precedent in
		// FullScreenReadingViewController.updateHideNotchAvailability().
		// Forward-only: existing over-cap configurations (from before this
		// cap existed) aren't trimmed, they just can't add further icons.
		let wouldAdd = toggle == .prevNext ? 2 : 1
		let capReached = !isOn && (slotsUsed(excluding: toggle) + wouldAdd > Self.maxSlots)
		cell.configure(toggle: toggle, isOn: isOn, isEnabled: !capReached)
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

	// No shouldSelectItemAt/didSelectItemAt override needed: neither the
	// preview row nor the toggle rows respond to a tap on the row itself --
	// each ArticleToolbarToggleCell's own UISwitch valueChanged target
	// writes back to AppDefaults directly (see ArticleToolbarToggleCell),
	// closer to StatsVisibilityCell's pattern than the old checkmark-row
	// single-select this screen used to be.

	// MARK: Notifications

	func userDefaultsDidChange() {
		collectionView.reloadData()
	}

}
