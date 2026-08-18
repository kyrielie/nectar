//
//  HighlightPalettePreviewCell.swift
//  NetNewsWire-iOS
//
//  See docs/app-chrome-palette.md ("Highlight Palette"). A live-rendered
//  preview of the currently-selected HighlightPalette, shown on
//  AccentColorTableViewController's Preview section alongside (below)
//  BadgeColorPalettePreviewCell -- see that file's own header comment for
//  why the two sub-previews are separate rows rather than one combined
//  cell.
//
//  Deliberately much simpler than BadgeColorPalettePreviewCell: a
//  highlight has no timeline-row chrome to reproduce (no title/byline/
//  icon layout to match), just five colored swatches over a short label
//  each -- so this draws five UILabel-backed "mark" chips directly in a
//  UIStackView rather than reusing a real UICollectionView/MainTimelineCell
//  the way the badge preview does. No self-measurement/height-constraint
//  dance is needed either, since a UIStackView of fixed-height chips
//  already reports a correct intrinsic content size to the table view's
//  automatic-dimension row height.
//

import UIKit
import Articles

final class HighlightPalettePreviewCell: UITableViewCell {

	static let reuseIdentifier = "HighlightPalettePreviewCell"

	private let stackView = UIStackView()

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

		stackView.axis = .horizontal
		stackView.distribution = .fillEqually
		stackView.spacing = 8
		stackView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(stackView)

		NSLayoutConstraint.activate([
			stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
			stackView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 8),
			stackView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor, constant: -8)
		])
	}

	/// Rebuilds the five "mark"-style chips from
	/// AppDefaults.shared.highlightPalette -- called from cellForRowAt and
	/// again from the controller's .highlightPaletteDidChange reload, same
	/// call pattern as BadgeColorPalettePreviewCell.configure(). Reads
	/// traitCollection.userInterfaceStyle directly (this cell's own, not
	/// UITraitCollection.current) since a real cell in a real view
	/// hierarchy has a trustworthy trait collection to read, unlike the
	/// bare Assets.Colors namespace properties app-chrome-palette.md flags
	/// as fragile for the same UITraitCollection.current pattern.
	func configure() {
		stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

		let palette = AppDefaults.shared.highlightPalette
		let isDark = traitCollection.userInterfaceStyle == .dark
		let hexSet = palette.hexSet(isDark: isDark)

		for color in Annotation.Color.allCases {
			let chip = UILabel()
			chip.text = color.accessibilityLabel
			chip.textAlignment = .center
			chip.font = .preferredFont(forTextStyle: .caption1)
			chip.textColor = .label
			chip.backgroundColor = UIColor(cssHex: hexSet[color]) ?? .systemYellow
			chip.layer.cornerRadius = 6
			chip.layer.masksToBounds = true
			chip.heightAnchor.constraint(equalToConstant: 28).isActive = true
			stackView.addArrangedSubview(chip)
		}
	}

}
