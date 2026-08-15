//
//  BadgeColorPalettePreviewCell.swift
//  NetNewsWire-iOS
//
//  See docs/app-chrome-palette.md ("Badge Colors"). A live-rendered
//  preview of the currently-selected BadgeColorPalette, shown on
//  AccentColorTableViewController below the badge-palette picker rows.
//  Reuses TimelineCustomizerCollectionViewController.previewArticle
//  (made `internal` for this) rather than inventing a second preview
//  article.
//
//  Audit correction 6 flagged an unresolved, unverifiable-in-this-sandbox
//  risk: instantiating MainTimelineCell bare (`MainTimelineCell(frame:)`)
//  inside a UITableViewCell might not drive its
//  updateConfiguration(using:)-based background/corner styling, since that
//  styling is normally refreshed by a live UICollectionView's
//  configuration-state cycle. Rather than ship the unverified bare
//  approach, this cell uses a single-cell UICollectionView up front, with the same
//  UICollectionLayoutListConfiguration Timeline Layout's own preview uses,
//  embedded in contentView -- MainTimelineCell is dequeued the normal way,
//  not instantiated directly, so its configuration-state-driven styling
//  applies exactly as it does everywhere else this cell is used.
//
//  Constructs MainTimelineCellData with tagDisplayMode: .badges hardcoded,
//  not AppDefaults.shared.timelineTagDisplayMode -- if this screen read the
//  real global setting, a person whose Timeline Layout is still set to
//  .compact/.expanded would open Badge Colors and see a preview with no
//  badges at all, since those two modes never build metadataBadges pills
//  regardless of palette. Forcing .badges here (preview construction only,
//  not the persisted setting) is what makes "preview what badges will look
//  like before turning them on" work.
//

import UIKit
import Images

final class BadgeColorPalettePreviewCell: UITableViewCell {

	static let reuseIdentifier = "BadgeColorPalettePreviewCell"

	private var collectionView: UICollectionView!
	private var collectionViewHeightConstraint: NSLayoutConstraint!

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		selectionStyle = .none

		var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
		config.showsSeparators = false
		let layout = UICollectionViewCompositionalLayout.list(using: config)

		collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
		collectionView.translatesAutoresizingMaskIntoConstraints = false
		collectionView.isScrollEnabled = false
		collectionView.backgroundColor = .clear
		collectionView.dataSource = self
		collectionView.register(MainTimelineCell.self, forCellWithReuseIdentifier: MainTimelineCell.reuseIdentifier)

		contentView.addSubview(collectionView)

		// Fixed, explicitly-updated height rather than pinning collectionView's
		// bottom to contentView's bottom -- with isScrollEnabled = false, a
		// nested UICollectionView reports its intrinsic size through
		// contentSize, not through auto layout, so nothing here grows to fit
		// self-sized MainTimelineCell rows on its own. configure() below
		// measures the real content height after each reload and updates this
		// constraint's constant, which is what actually fixes the row's
		// height rather than clipping at a fixed floor.
		collectionViewHeightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 100)
		NSLayoutConstraint.activate([
			collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			collectionView.topAnchor.constraint(equalTo: contentView.topAnchor),
			collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			collectionViewHeightConstraint
		])
	}

	/// Reloads the single preview row so it reflects whichever
	/// BadgeColorPalette is currently selected -- called on
	/// cellForRowAt and again from the controller's
	/// .badgeColorModeDidChange reload. Measures MainTimelineCell's real,
	/// self-sized height (driven by preferredLayoutAttributesFitting) after
	/// layout and pushes that into collectionViewHeightConstraint, then
	/// asks the owning table view to recompute this row's automatic-dimension
	/// height -- without that second step, the table view keeps using
	/// whatever height it estimated before the real content size was known.
	func configure() {
		collectionView.reloadData()
		collectionView.layoutIfNeeded()

		let measuredHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
		guard measuredHeight > 0, collectionViewHeightConstraint.constant != measuredHeight else { return }
		collectionViewHeightConstraint.constant = measuredHeight

		if let tableView = enclosingTableView() {
			// Deferred to the next run loop turn: configure() can be called
			// from within cellForRowAt(_:), and beginUpdates()/endUpdates()
			// re-entrantly during that same dequeue pass is undefined
			// behavior for UITableView.
			DispatchQueue.main.async {
				UIView.performWithoutAnimation {
					tableView.beginUpdates()
					tableView.endUpdates()
				}
			}
		}
	}

	private func enclosingTableView() -> UITableView? {
		var view: UIView? = superview
		while let candidate = view {
			if let tableView = candidate as? UITableView { return tableView }
			view = candidate.superview
		}
		return nil
	}

}

extension BadgeColorPalettePreviewCell: UICollectionViewDataSource {

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return 1
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MainTimelineCell.reuseIdentifier, for: indexPath) as! MainTimelineCell

		cell.cellData = MainTimelineCellData(article: TimelineCustomizerCollectionViewController.previewArticle,
											 showFeedName: .byline,
											 feedName: "The Fellowship of the Ring",
											 byline: "J. R. R. Tolkien",
											 iconImage: IconImage(Assets.Images.nnwFeedIcon),
											 showIcon: false,
											 numberOfLines: AppDefaults.shared.timelineNumberOfLines,
											 iconSize: AppDefaults.shared.timelineIconSize,
											 tagDisplayMode: .badges)
		cell.isPreview = true
		return cell
	}

}
