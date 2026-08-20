//
//  ToolbarOverflowEmptyStateCell.swift
//  NetNewsWire-iOS
//
//  Single-label row shown in place of the overflow-picks list when that
//  bar's overflow switch is on but every ToolbarFunction is already
//  placed inline on that bar -- ToolbarsCustomizerViewController's
//  overflowCandidates is empty in that state, so without this row the
//  Functions section would just end right after the last inline toggle
//  with no explanation of why there's nothing to pick from. Matches the
//  toolbar customization mockup's equivalent placeholder row.
//

import UIKit

final class ToolbarOverflowEmptyStateCell: UICollectionViewListCell {

	static let reuseIdentifier = "ToolbarOverflowEmptyStateCell"

	private let label: UILabel = {
		let label = UILabel()
		label.font = .preferredFont(forTextStyle: .footnote)
		label.textColor = .secondaryLabel
		label.numberOfLines = 0
		label.text = NSLocalizedString("All functions are already placed in this bar.", comment: "Toolbar: overflow-picks empty state")
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		contentView.addSubview(label)
		NSLayoutConstraint.activate([
			// 40pt leading, matching ToolbarFunctionCell's indentedLeading --
			// this row reads as nested under the overflow-toggle row, same
			// as the overflow-picks rows it stands in for.
			label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
			label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
			label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9),
			contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
		])
	}

	override func updateConfiguration(using state: UICellConfigurationState) {
		var backgroundConfig: UIBackgroundConfiguration
		if #available(iOS 18, *) {
			backgroundConfig = UIBackgroundConfiguration.listCell().updated(for: state)
		} else {
			backgroundConfig = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
		}
		backgroundConfig.backgroundColor = Assets.Colors.settingsCellBackground(for: traitCollection)
		backgroundConfig.cornerRadius = 20
		self.backgroundConfiguration = backgroundConfig
	}
}
