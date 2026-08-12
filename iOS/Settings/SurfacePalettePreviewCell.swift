//
//  SurfacePalettePreviewCell.swift
//  NetNewsWire-iOS
//
//  color-palette-plan.md, section 4 ("Preview UI"). A live-rendered
//  preview of the currently-selected SurfacePalette, built in code (no
//  storyboard prototype). Originally registered on the standalone
//  SurfacePaletteTableViewController screen; that screen was merged into
//  ColorPaletteTableViewController (surface-palette-and-badge-colors-plan,
//  section 1), which now registers and reloads this cell instead -- the
//  cell itself is unchanged, it doesn't care which controller owns it.
//  This stays inside the existing UITableViewController/storyboard scene
//  rather than converting it to a UICollectionViewController, since that
//  conversion would require hand-editing the storyboard's controller/view
//  type in raw XML with no way to verify the result in Interface Builder.
//  Functionally this still delivers the same "real component, live
//  colors, reloads on the palette-change notification" behavior the plan
//  calls for.
//
//  Reads Assets.Colors.barBackground(for:)/vibrantText(for:)/
//  fullScreenBackground(for:)/settingsBackground(for:)/
//  settingsCellBackground(for:)/listBackground(for:) directly rather than
//  re-deriving hex values from AppDefaults.shared.surfaceTint itself --
//  those accessors already encode the exact fallback contract (.default ->
//  asset catalog) this preview needs, so reusing them avoids a second,
//  possibly-drifting copy of that logic. There's no equivalent
//  Assets.Colors accessor for the two nav-bar properties (they're only
//  ever read directly, in
//  ArticleViewController.applySurfacePaletteNavigationBarAppearance()), so
//  this cell falls back to .systemBackground/.label for those when the
//  active palette's hex set is nil -- the same "no override -> system
//  default" contract, just inlined since there's no shared accessor to
//  call.
//
//  surface-palette-and-badge-colors-plan, section 2.4: three more swatches
//  (Settings background, Settings cell, List background) added alongside
//  the original five, wrapped into two rows of four rather than shrinking
//  swatch size to fit eight in one line -- five columns at the existing
//  80pt swatch width plus 12pt spacing already ran wider than a
//  375pt-class screen before this change.
//

import UIKit

final class SurfacePalettePreviewCell: UITableViewCell {

	static let reuseIdentifier = "SurfacePalettePreviewCell"

	private let searchBarSwatch = SurfacePalettePreviewCell.makeSwatch()
	private let navBarSwatch = SurfacePalettePreviewCell.makeSwatch()
	private let fullScreenSwatch = SurfacePalettePreviewCell.makeSwatch()
	private let settingsBackgroundSwatch = SurfacePalettePreviewCell.makeSwatch()
	private let settingsCellSwatch = SurfacePalettePreviewCell.makeSwatch()
	private let listBackgroundSwatch = SurfacePalettePreviewCell.makeSwatch()

	private let searchBarLabel = SurfacePalettePreviewCell.makeCaptionLabel(
		text: NSLocalizedString("Search Bar", comment: "Surface palette preview: search bar swatch caption"))
	private let navBarLabel = SurfacePalettePreviewCell.makeCaptionLabel(
		text: NSLocalizedString("Nav Bar", comment: "Surface palette preview: nav bar swatch caption"))
	private let fullScreenLabel = SurfacePalettePreviewCell.makeCaptionLabel(
		text: NSLocalizedString("Full Screen", comment: "Surface palette preview: full screen swatch caption"))
	private let settingsBackgroundLabel = SurfacePalettePreviewCell.makeCaptionLabel(
		text: NSLocalizedString("Settings", comment: "Surface palette preview: settings background swatch caption"))
	private let settingsCellLabel = SurfacePalettePreviewCell.makeCaptionLabel(
		text: NSLocalizedString("Settings Cell", comment: "Surface palette preview: settings cell swatch caption"))
	private let listBackgroundLabel = SurfacePalettePreviewCell.makeCaptionLabel(
		text: NSLocalizedString("List", comment: "Surface palette preview: list background swatch caption"))

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

		// Deployment target is iOS 17+ (xcconfig/NetNewsWire_project.xcconfig,
		// IPHONEOS_DEPLOYMENT_TARGET = 17.0), so use registerForTraitChanges
		// rather than the traitCollectionDidChange override it deprecated --
		// same reasoning and pattern as WebViewController.viewDidLoad().
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: SurfacePalettePreviewCell, previousTraitCollection: UITraitCollection) in
			guard self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle else { return }
			self.configure()
		}

		let topRow = UIStackView(arrangedSubviews: [
			column(swatch: searchBarSwatch, caption: searchBarLabel),
			column(swatch: navBarSwatch, caption: navBarLabel),
			column(swatch: fullScreenSwatch, caption: fullScreenLabel),
			column(swatch: settingsBackgroundSwatch, caption: settingsBackgroundLabel)
		])
		topRow.axis = .horizontal
		topRow.distribution = .fillEqually
		topRow.spacing = 12

		let bottomRow = UIStackView(arrangedSubviews: [
			column(swatch: settingsCellSwatch, caption: settingsCellLabel),
			column(swatch: listBackgroundSwatch, caption: listBackgroundLabel),
			UIView(),
			UIView()
		])
		bottomRow.axis = .horizontal
		bottomRow.distribution = .fillEqually
		bottomRow.spacing = 12

		let stack = UIStackView(arrangedSubviews: [topRow, bottomRow])
		stack.axis = .vertical
		stack.spacing = 12
		stack.translatesAutoresizingMaskIntoConstraints = false

		contentView.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
			stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
			stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
		])
	}

	/// Reads the live, currently-persisted `AppDefaults.shared.surfaceTint`
	/// for `traitCollection` -- called on `cellForRowAt` and again from the
	/// controller's `.surfaceTintDidChange` reload, so the swatches always
	/// reflect whichever palette is selected right now, not a stale value
	/// captured at first layout.
	func configure() {
		searchBarSwatch.backgroundColor = Assets.Colors.barBackground(for: traitCollection)
		searchBarSwatch.subviews.first?.backgroundColor = Assets.Colors.vibrantText(for: traitCollection)

		let palette = AppDefaults.shared.surfaceTint
		let hexSet = traitCollection.userInterfaceStyle == .dark ? palette.darkHexSet : palette.lightHexSet
		// With the toggle off, the real nav bar won't be tinted regardless of
		// palette (see SurfacePaletteNavigationBarAware), so the preview needs to
		// match rather than always showing what the palette *would* look like.
		let navigationBarBackgroundHex = AppDefaults.shared.useTintedNavigationBar ? hexSet?.navigationBarBackground : nil
		let navigationBarTintHex = AppDefaults.shared.useTintedNavigationBar ? hexSet?.navigationBarTint : nil
		navBarSwatch.backgroundColor = navigationBarBackgroundHex.flatMap { UIColor(cssHex: $0) } ?? .systemBackground
		navBarSwatch.subviews.first?.backgroundColor = navigationBarTintHex.flatMap { UIColor(cssHex: $0) } ?? .label

		fullScreenSwatch.backgroundColor = Assets.Colors.fullScreenBackground(for: traitCollection)
		fullScreenSwatch.subviews.first?.isHidden = true

		settingsBackgroundSwatch.backgroundColor = Assets.Colors.settingsBackground(for: traitCollection)
		settingsBackgroundSwatch.subviews.first?.isHidden = true

		settingsCellSwatch.backgroundColor = Assets.Colors.settingsCellBackground(for: traitCollection)
		settingsCellSwatch.subviews.first?.isHidden = true

		listBackgroundSwatch.backgroundColor = Assets.Colors.listBackground(for: traitCollection)
		listBackgroundSwatch.subviews.first?.isHidden = true
	}

	// MARK: - Swatch construction

	private static let swatchSize = CGSize(width: 80, height: 44)

	/// A rounded-rect swatch with a single small "accent dot" subview inside
	/// it -- the dot stands in for vibrant text (search bar) or the nav
	/// bar's title/tint color; `configure()` hides the dot for the
	/// full-screen swatch, which has no second color to show.
	private static func makeSwatch() -> UIView {
		let swatch = UIView()
		swatch.translatesAutoresizingMaskIntoConstraints = false
		swatch.layer.cornerRadius = 8
		swatch.layer.borderWidth = 1
		swatch.layer.borderColor = UIColor.separator.cgColor
		swatch.clipsToBounds = true

		let dot = UIView()
		dot.translatesAutoresizingMaskIntoConstraints = false
		dot.layer.cornerRadius = 6
		swatch.addSubview(dot)

		NSLayoutConstraint.activate([
			swatch.widthAnchor.constraint(equalToConstant: swatchSize.width),
			swatch.heightAnchor.constraint(equalToConstant: swatchSize.height),
			dot.widthAnchor.constraint(equalToConstant: 12),
			dot.heightAnchor.constraint(equalToConstant: 12),
			dot.centerXAnchor.constraint(equalTo: swatch.centerXAnchor),
			dot.centerYAnchor.constraint(equalTo: swatch.centerYAnchor)
		])

		return swatch
	}

	private static func makeCaptionLabel(text: String) -> UILabel {
		let label = UILabel()
		label.text = text
		label.font = .preferredFont(forTextStyle: .caption1)
		label.textColor = .secondaryLabel
		label.textAlignment = .center
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}

	private func column(swatch: UIView, caption: UILabel) -> UIView {
		let stack = UIStackView(arrangedSubviews: [swatch, caption])
		stack.axis = .vertical
		stack.alignment = .center
		stack.spacing = 4
		return stack
	}

}
