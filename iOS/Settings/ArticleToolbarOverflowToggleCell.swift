//
//  ArticleToolbarOverflowToggleCell.swift
//  NetNewsWire-iOS
//
//  A single switch row for AppDefaults.articleToolbarUseOverflowMenu --
//  same UISwitch-row shape as ArticleToolbarToggleCell, but this one
//  writes straight to the display-mode flag instead of dispatching
//  through ArticleToolbarToggle/isArticleToolbarToggleEnabled(_:), since
//  it isn't one of the eight per-function toggles. Shown as item 0 of
//  ArticleToolbarCustomizerViewController's pickerSection, ahead of the
//  per-ArticleToolbarToggle rows.
//

import UIKit

final class ArticleToolbarOverflowToggleCell: UICollectionViewListCell {

	static let reuseIdentifier = "ArticleToolbarOverflowToggleCell"

	private let label: UILabel = {
		let label = UILabel()
		label.font = .preferredFont(forTextStyle: .body)
		label.text = NSLocalizedString("Collapse into Overflow Menu", comment: "Article top toolbar: overflow display-mode switch")
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

	func configure(isOn: Bool) {
		toggle.isOn = isOn
	}

	@objc private func toggleChanged() {
		AppDefaults.shared.articleToolbarUseOverflowMenu = toggle.isOn
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
