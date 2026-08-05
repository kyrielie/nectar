//
//  BadgeColorModeCell.swift
//  NetNewsWire-iOS
//
//  Personalization & Theming plan, item 2 ("Toggleable colored badges").
//  A plain UISwitch row, built in code rather than via the storyboard
//  TimelineCustomizerCell/TickMarkSlider machinery the number-of-lines and
//  tag-display-mode rows use -- this setting is a boolean, not a ranged
//  slider value, so it doesn't fit that cell's sliderConfiguration shape.
//

import UIKit

final class BadgeColorModeCell: UICollectionViewListCell {

	static let reuseIdentifier = "BadgeColorModeCell"

	private let label: UILabel = {
		let label = UILabel()
		label.font = .preferredFont(forTextStyle: .body)
		label.text = NSLocalizedString("Colored Badges", comment: "Colored badges toggle")
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
		toggle.isOn = AppDefaults.shared.badgeColorMode == .colored
	}

	@objc private func toggleChanged() {
		AppDefaults.shared.badgeColorMode = toggle.isOn ? .colored : .neutral
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
