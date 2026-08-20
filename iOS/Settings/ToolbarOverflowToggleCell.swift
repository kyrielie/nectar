//
//  ToolbarOverflowToggleCell.swift
//  NetNewsWire-iOS
//
//  A single switch row for AppDefaults.toolbarTopUseOverflowMenu/
//  toolbarBottomUseOverflowMenu (see isToolbarOverflowMenuEnabled(on:)/
//  setToolbarOverflowMenuEnabled(on:_:)) -- replaces
//  ArticleToolbarOverflowToggleCell, now parameterized by ToolbarBar so
//  the same cell type serves both tabs of
//  ToolbarsCustomizerViewController. Shown as item 0 of the Functions
//  section, ahead of the per-ToolbarFunction rows -- same position
//  ArticleToolbarOverflowToggleCell held pre-unification.
//

import UIKit

final class ToolbarOverflowToggleCell: UICollectionViewListCell {

	static let reuseIdentifier = "ToolbarOverflowToggleCell"

	// Assets.Images.command -- the same glyph ArticleViewController's
	// topOverflowBarButtonItem/bottomOverflowBarButtonItem and
	// ToolbarPreviewCell's collapsed-state item already render, so this
	// row visually previews what turning the switch on actually produces
	// rather than being the one row in this section with no icon.
	private let iconView: UIImageView = {
		let imageView = UIImageView(image: Assets.Images.command)
		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.contentMode = .scaleAspectFit
		return imageView
	}()

	private let label: UILabel = {
		let label = UILabel()
		label.font = .preferredFont(forTextStyle: .body)
		label.text = NSLocalizedString("Collapse into Overflow Menu", comment: "Toolbar: overflow display-mode switch")
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	private let toggle: UISwitch = {
		let toggle = UISwitch()
		toggle.translatesAutoresizingMaskIntoConstraints = false
		return toggle
	}()

	private var bar: ToolbarBar?

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		contentView.addSubview(iconView)
		contentView.addSubview(label)
		contentView.addSubview(toggle)
		NSLayoutConstraint.activate([
			iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
			iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 20),
			iconView.heightAnchor.constraint(equalToConstant: 20),
			label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
			label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
		])
		toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
	}

	/// `isEnabled` mirrors ToolbarFunctionCell's own parameter of the same
	/// name -- greys out the label and switch (without changing the
	/// stored value or moving the row) when turning this switch on would
	/// push slotsUsed() past maxSlots(for:), same disabled-but-visible
	/// treatment the function rows already get at the cap.
	func configure(bar: ToolbarBar, isOn: Bool, isEnabled: Bool = true) {
		self.bar = bar
		label.isEnabled = isEnabled
		toggle.isOn = isOn
		toggle.isEnabled = isEnabled
	}

	@objc private func toggleChanged() {
		guard let bar else { return }
		AppDefaults.shared.setToolbarOverflowMenuEnabled(on: bar, toggle.isOn)
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
