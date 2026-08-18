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
		label.text = Self.title(for: articleToolbarToggle)
		label.isEnabled = isEnabled
		toggle.isOn = isOn
		toggle.isEnabled = isEnabled
	}

	private static func title(for toggle: ArticleToolbarToggle) -> String {
		switch toggle {
		case .theme:
			return NSLocalizedString("Theme", comment: "Article top toolbar toggle: theme")
		case .tableOfContents:
			return NSLocalizedString("Table of Contents", comment: "Article top toolbar toggle: table of contents")
		case .find:
			return NSLocalizedString("Find in Article", comment: "Article top toolbar toggle: find")
		case .prevNext:
			return NSLocalizedString("Previous & Next Article", comment: "Article top toolbar toggle: previous and next article")
		case .lock:
			return NSLocalizedString("Lock Gestures", comment: "Article top toolbar toggle: lock gestures")
		case .annotations:
			return NSLocalizedString("Highlights", comment: "Article top toolbar toggle: annotations")
		case .settings:
			return NSLocalizedString("Settings", comment: "Article top toolbar toggle: settings")
		case .checkForUpdates:
			return NSLocalizedString("Check for Updates", comment: "Article top toolbar toggle: check for updates")
		}
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
