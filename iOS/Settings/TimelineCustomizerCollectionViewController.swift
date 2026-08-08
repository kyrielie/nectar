//
//  TimelineCustomizerCollectionViewController.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 27/01/2026.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//
//  surface-palette-and-badge-colors-plan, section 3.4: the Badge Colors
//  toggle section is removed from this screen -- badge palette selection
//  now lives on AccentColorTableViewController instead, with its own live
//  preview. Every push of this screen is a fresh instance
//  (UIStoryboard.settings.instantiateController, SettingsViewController.swift),
//  so there's no live-staleness case to worry about from removing the
//  .badgeColorModeDidChange observer here. Section layout is now fixed
//  (Number of Lines 0, Tag Display 1, Stats Visibility 2, Preview 3)
//  rather than the previous conditional 4/5-section toggle.
//

import UIKit
import Articles
import Images

class TimelineCustomizerCollectionViewController: UICollectionViewController, SettingsPaletteBackgroundHosting {

	var paletteBackgroundView: UIView { collectionView }
	/// Static rather than merely internal: this fixture article carries no
	/// instance state, and BadgeColorPalettePreviewCell (surface-palette-
	/// and-badge-colors-plan, section 3.3) needs to reach it without
	/// instantiating this whole view controller just to read one property.
	static var previewArticle: Article {
		var components = DateComponents()
		components.year = 1954
		components.month = 7
		components.day = 29

		let calendar = Calendar.current
		let date = calendar.date(from: components)!

		return Article(accountID: "_testID",
				articleID: "_testArticleID",
				feedID: "_testFeedID",
				uniqueID: UUID().uuidString,
				title: "At The Sign Of The Prancing Pony",
				contentHTML: nil,
				contentText: "Bree was the chief village of Bree-land, a small country a few miles broad whose chief claim to fame was its aluminum siding industry. The Men of Bree were cheerful and independent: they belonged to nobody but themselves. In the lands beyond Bree there were mysterious wanderers.",
				markdown: nil,
				url: nil,
				externalURL: nil,
				summary: nil,
				imageURL: nil,
				datePublished: date,
				dateModified: nil,
				authors: Set([Author(authorID: "_testAuthorID", name: "J. R. R. Tolkien", url: nil, avatarURL: nil, emailAddress: nil)!]),
				wordCount: 4231,
				isComplete: false,
				fandoms: ["The Lord of the Rings - J. R. R. Tolkien"],
				relationships: ["Aragorn/Arwen"],
				characters: ["Aragorn", "Frodo Baggins", "Barliman Butterbur"],
				ratings: ["Teen And Up Audiences"],
				warnings: ["No Archive Warnings Apply"],
				categories: ["Fluff", "Canon-Compliant", "Introspection"],
				status: ArticleStatus(articleID: "_testArticleID", read: false, starred: false, dateArrived: .now))
	}

    override func viewDidLoad() {
        super.viewDidLoad()
		title = NSLocalizedString("Timeline Layout", comment: "Timeline Layout")

		NotificationCenter.default.addObserver(forName: .timelineNumberOfLinesDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}

		NotificationCenter.default.addObserver(forName: .timelineTagDisplayModeDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}

		NotificationCenter.default.addObserver(forName: .statsVisibilityDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}

		// Reload so TimelineCustomizerCell's sliders re-run their
		// sliderConfiguration didSet and pick up the new
		// Assets.Colors.primaryAccent -- otherwise the thumb tint stays
		// whatever it was when this screen was last opened.
		NotificationCenter.default.addObserver(forName: .accentColorDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}

		// TimelineCustomizerCell/StatsVisibilityCell compute
		// Assets.Colors.settingsCellBackground(for:) inside their own
		// updateConfiguration(using:), but UIKit only re-invokes that when a
		// cell's own state changes (highlight/selection), not on an external
		// notification. configureSettingsPaletteBackground()'s own
		// .surfaceTintDidChange observer only repaints paletteBackgroundView
		// (this collection view's container background), so without this,
		// switching SurfacePalette while this screen is visible leaves every
		// row showing the previous palette's settingsCellBackground until
		// the screen is torn down and re-pushed. Reusing userDefaultsDidChange()
		// (a plain reloadData()) forces each cell to rebuild and re-run
		// updateConfiguration(using:) with the live palette, same as
		// accentColorDidChange above already does for thumb tints.
		NotificationCenter.default.addObserver(forName: .surfaceTintDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.refreshPaletteCellBackgrounds()
			}
		}

		configureCollectionView()
		configureSettingsPaletteBackground()
    }

	// SettingsPaletteBackgroundHosting -- also called on a light/dark trait
	// change now, not just a palette switch; see SettingsBackgroundPalette.swift.
	// Reuses userDefaultsDidChange() (a plain reloadData()), same fix shape
	// as the .surfaceTintDidChange observer above.
	func refreshPaletteCellBackgrounds() {
		userDefaultsDidChange()
	}
	private func configureCollectionView() {
		collectionView.register(
			TimelineHeaderView.self,
			forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
			withReuseIdentifier: TimelineHeaderView.reuseIdentifier
		)

		collectionView.register(MainTimelineCell.self, forCellWithReuseIdentifier: MainTimelineCell.reuseIdentifier)
		collectionView.register(StatsVisibilityCell.self, forCellWithReuseIdentifier: StatsVisibilityCell.reuseIdentifier)

		var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
		config.showsSeparators = false
		config.headerMode = .supplementary

		let layout = UICollectionViewCompositionalLayout.list(using: config)

		collectionView.setCollectionViewLayout(layout, animated: false)
	}

    // MARK: UICollectionViewDataSource

	/// Fixed section layout: Number of Lines (0), Tag Display (1),
	/// Stats Visibility (2), Preview (3). Badge Colors moved to
	/// AccentColorTableViewController (section 3.2 of the
	/// surface-palette-and-badge-colors-plan).
	private var statsVisibilitySection: Int { 2 }
	private var previewSection: Int { 3 }

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
		return 4
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of items
        return 1
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

		if indexPath.section == 0 {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "NumberOfLinesSelector", for: indexPath) as! TimelineCustomizerCell
			cell.sliderConfiguration = .numberOfLines
			return cell
		}

		if indexPath.section == 1 {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TagDisplayModeSelector", for: indexPath) as! TimelineCustomizerCell
			cell.sliderConfiguration = .tagDisplayMode
			return cell
		}

		if indexPath.section == statsVisibilitySection {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StatsVisibilityCell.reuseIdentifier, for: indexPath) as! StatsVisibilityCell
			cell.configure()
			return cell
		}

		if indexPath.section == previewSection {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MainTimelineCell.reuseIdentifier, for: indexPath) as! MainTimelineCell
			cell.cellData = MainTimelineCellData(article: Self.previewArticle,
												 showFeedName: .byline,
												 feedName: "The Fellowship of the Ring",
												 byline: "J. R. R. Tolkien",
												 iconImage: IconImage(Assets.Images.nnwFeedIcon),
												 showIcon: false,
												 numberOfLines: AppDefaults.shared.timelineNumberOfLines,
												 iconSize: AppDefaults.shared.timelineIconSize,
												 tagDisplayMode: AppDefaults.shared.timelineTagDisplayMode)
			cell.isPreview = true
			return cell
		}

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MainTimelineCell.reuseIdentifier, for: indexPath)
        return cell
    }

	// MARK: UICollectionViewDelegate

	override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath
	) -> UICollectionReusableView {

		guard kind == UICollectionView.elementKindSectionHeader else {
			return UICollectionReusableView()
		}

		let header = collectionView.dequeueReusableSupplementaryView(
			ofKind: kind,
			withReuseIdentifier: TimelineHeaderView.reuseIdentifier,
			for: indexPath
		) as! TimelineHeaderView

		switch indexPath.section {
		case 0:
			header.label.text = NSLocalizedString("Number of Lines", comment: "Number of Lines")
		case 1:
			header.label.text = NSLocalizedString("Tag Display", comment: "Tag Display")
		case statsVisibilitySection:
			header.label.text = NSLocalizedString("Stats Visibility", comment: "Stats Visibility")
		case previewSection:
			header.label.text = NSLocalizedString("Preview", comment: "Preview")
		default:
			header.label.text = NSLocalizedString("", comment: "")
		}
		return header
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int
	) -> CGSize {
		CGSize(width: collectionView.bounds.width, height: 50)
	}

	override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
		// Only the Number of Lines (0) and Tag Display (1) slider rows respond to
		// selection; the stats-visibility toggle handles its own touches via
		// UISwitch, and the preview row isn't interactive.
		return indexPath.section == 0 || indexPath.section == 1
	}

	// MARK: Notifications

	func userDefaultsDidChange() {
		collectionView.reloadData()
	}

}
