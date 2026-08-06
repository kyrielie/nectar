//
//  TimelineCustomizerCollectionViewController.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 27/01/2026.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit
import Articles
import Images

class TimelineCustomizerCollectionViewController: UICollectionViewController {
	private var previewArticle: Article {
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

		NotificationCenter.default.addObserver(forName: .badgeColorModeDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}

		NotificationCenter.default.addObserver(forName: .statsVisibilityDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}

		configureCollectionView()
    }

	private func configureCollectionView() {
		collectionView.register(
			TimelineHeaderView.self,
			forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
			withReuseIdentifier: TimelineHeaderView.reuseIdentifier
		)

		collectionView.register(MainTimelineCell.self, forCellWithReuseIdentifier: MainTimelineCell.reuseIdentifier)
		collectionView.register(BadgeColorModeCell.self, forCellWithReuseIdentifier: BadgeColorModeCell.reuseIdentifier)
		collectionView.register(StatsVisibilityCell.self, forCellWithReuseIdentifier: StatsVisibilityCell.reuseIdentifier)

		var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
		config.showsSeparators = false
		config.headerMode = .supplementary

		let layout = UICollectionViewCompositionalLayout.list(using: config)

		collectionView.setCollectionViewLayout(layout, animated: false)
	}

    // MARK: UICollectionViewDataSource

	/// "Badge Colors" (colored-badge toggle) only has any visible effect in
	/// `.badges` tag display mode -- `.compact`/`.expanded` never render
	/// `metadataBadges` pills at all (see `MainTimelineCellData.metadataBadges`),
	/// so showing the toggle there would look actionable while doing nothing.
	private var showsBadgeColorSection: Bool {
		AppDefaults.shared.timelineTagDisplayMode == .badges
	}

	/// Section indices are dynamic: Number of Lines (0), Tag Display (1),
	/// Stats Visibility (2, always present), Badge Colors (3, only when
	/// showsBadgeColorSection), then Preview last. Centralized here rather
	/// than hardcoded per-method so every switch below stays in sync when
	/// the badge section is hidden.
	private var statsVisibilitySection: Int { 2 }

	private var badgeColorSection: Int? {
		showsBadgeColorSection ? 3 : nil
	}

	private var previewSection: Int {
		showsBadgeColorSection ? 4 : 3
	}

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
		return showsBadgeColorSection ? 5 : 4
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

		if let badgeColorSection, indexPath.section == badgeColorSection {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BadgeColorModeCell.reuseIdentifier, for: indexPath) as! BadgeColorModeCell
			cell.configure()
			return cell
		}

		if indexPath.section == previewSection {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MainTimelineCell.reuseIdentifier, for: indexPath) as! MainTimelineCell
			cell.cellData = MainTimelineCellData(article: previewArticle,
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
		case _ where indexPath.section == badgeColorSection:
			header.label.text = NSLocalizedString("Badge Colors", comment: "Badge Colors")
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
		// selection; the stats-visibility and badge-color toggles handle their
		// own touches via UISwitch, and the preview row isn't interactive.
		return indexPath.section == 0 || indexPath.section == 1
	}

	// MARK: Notifications

	func userDefaultsDidChange() {
		// Tag display mode changes can add/remove the Badge Colors section
		// (showsBadgeColorSection), which shifts every subsequent section
		// index including the preview -- a full reload is required rather
		// than reloading a fixed section index, since that index is no
		// longer stable once section count itself changes.
		collectionView.reloadData()
	}

}
