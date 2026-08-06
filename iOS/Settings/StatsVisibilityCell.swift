//
//  StatsVisibilityCell.swift
//  NetNewsWire-iOS
//
//  Personalization & Theming plan, item 6 ("Stats-visibility toggles").
//  A plain UISwitch row, same shape as BadgeColorModeCell -- this setting
//  is a boolean, not a ranged slider value, so it doesn't fit the
//  TimelineCustomizerCell/TickMarkSlider machinery the number-of-lines and
//  tag-display-mode rows use.
//

import UIKit

final class StatsVisibilityCell: UICollectionViewListCell {

	static let reuseIdentifier = "StatsVisibilityCell"

	private let label: UILabel = {
		let label = UILabel()
		label.font = .preferredFont(forTextStyle: .body)
		label.text = NSLocalizedString("Show Stats", comment: "Stats visibility toggle")
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	private let toggle: UISwitch = {
		let toggle = UISwitch()
		toggle.translatesAutoresizingMaskIntoConstraints = false
		return toggle
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

	func configure() {
		toggle.isOn = AppDefaults.shared.statsVisible
	}

	@objc private func toggleChanged() {
		AppDefaults.shared.statsVisible = toggle.isOn
	}

	override func updateConfiguration(using state: UICellConfigurationState) {
		var backgroundConfig: UIBackgroundConfiguration
		if #available(iOS 18, *) {
			backgroundConfig = UIBackgroundConfiguration.listCell().updated(for: state)
		} else {
			backgroundConfig = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
		}
		backgroundConfig.backgroundColor = traitCollection.userInterfaceStyle == .dark ? .secondarySystemBackground : .white
		backgroundConfig.cornerRadius = 20
		self.backgroundConfiguration = backgroundConfig
	}
}
