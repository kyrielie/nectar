//
//  BottomToolbarToggleCell.swift
//  NetNewsWire-iOS
//
//  A plain UISwitch row, one per BottomToolbarToggle case -- same shape
//  as ArticleToolbarToggleCell, kept as its own type (rather than a
//  generic over both toggle enums) since the two enums have unrelated
//  case sets and title(for:) switches, and there's no other call site
//  that would benefit from sharing the type.
//

import UIKit

final class BottomToolbarToggleCell: UICollectionViewListCell {

	static let reuseIdentifier = "BottomToolbarToggleCell"

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

	private var toolbarToggle: BottomToolbarToggle?

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

	// No isEnabled/cap parameter here unlike ArticleToolbarToggleCell.configure(_:isOn:isEnabled:):
	// the bottom bar has no icon-count cap (see BottomToolbarCustomizerViewController's
	// header comment), so every row stays interactive regardless of how
	// many others are currently on.
	func configure(toggle bottomToolbarToggle: BottomToolbarToggle, isOn: Bool) {
		toolbarToggle = bottomToolbarToggle
		label.text = Self.title(for: bottomToolbarToggle)
		toggle.isOn = isOn
	}

	private static func title(for toggle: BottomToolbarToggle) -> String {
		switch toggle {
		case .read:
			return NSLocalizedString("Toggle Read", comment: "Article bottom toolbar toggle: read")
		case .star:
			return NSLocalizedString("Read Later", comment: "Article bottom toolbar toggle: read later")
		case .heart:
			return NSLocalizedString("Loved", comment: "Article bottom toolbar toggle: loved")
		case .nextUnread:
			return NSLocalizedString("Next Unread", comment: "Article bottom toolbar toggle: next unread")
		case .action:
			return NSLocalizedString("Share", comment: "Article bottom toolbar toggle: share")
		}
	}

	@objc private func toggleChanged() {
		guard let toolbarToggle else { return }
		AppDefaults.shared.setBottomToolbarToggleEnabled(toolbarToggle, toggle.isOn)
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
