//
//  ArticleToolbarToggleCell.swift
//  NetNewsWire-iOS
//
//  A plain UISwitch row, one per ArticleToolbarToggle case -- same shape
//  as StatsVisibilityCell, applied to a UICollectionViewListCell instead
//  of a UITableViewCell since this screen (like
//  TimelineCustomizerCollectionViewController) is collection-view-based.
//

import UIKit

final class ArticleToolbarToggleCell: UICollectionViewListCell {

	static let reuseIdentifier = "ArticleToolbarToggleCell"

	private let label: UILabel = {
		let label = UILabel()
		label.font = .preferredFont(forTextStyle: .body)
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	private let toggle: UISwitch = {
		let toggle = UISwitch()
		toggle.translatesAutoresizingMaskIntoConstraints = false
		return toggle
	}()

	private var toolbarToggle: ArticleToolbarToggle?

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
		contentView.addSubview(toggle)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
			label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
		])
		toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
	}

	func configure(toggle articleToolbarToggle: ArticleToolbarToggle, isOn: Bool, isEnabled: Bool = true) {
		toolbarToggle = articleToolbarToggle
		label.text = articleToolbarToggle.title
		label.isEnabled = isEnabled
		toggle.isOn = isOn
		toggle.isEnabled = isEnabled
	}

	@objc private func toggleChanged() {
		guard let toolbarToggle else { return }
		AppDefaults.shared.setArticleToolbarToggleEnabled(toolbarToggle, toggle.isOn)
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
