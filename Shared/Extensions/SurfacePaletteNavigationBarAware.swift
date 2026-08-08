//
//  SurfacePaletteNavigationBarAware.swift
//  NetNewsWire
//
//  Extracted from ArticleViewController.applySurfacePaletteNavigationBarAppearance()
//  (color-palette-plan.md, section 3), which was the only screen wiring its
//  UINavigationBarAppearance to AppDefaults.shared.surfaceTint. Neither
//  MainTimelineModernViewController nor MainFeedCollectionViewController did
//  the same, even though both already track other surface-tint-driven colors
//  (listBackground) via their own .surfaceTintDidChange observers -- so their
//  nav bars, especially the scrollEdgeAppearance shown once a large title has
//  collapsed, stayed on the plain system appearance regardless of palette.
//  Shared here so all three screens (and any future one) can't drift out of
//  sync with each other the way MainTimeline/MainFeed had with Article.
//

import UIKit

@MainActor
protocol SurfacePaletteNavigationBarAware: UIViewController {

	/// Whether the scroll-edge (top-of-content) nav bar appearance should stay
	/// transparent rather than take the palette's opaque `navigationBarBackground`.
	/// `ArticleViewController` wants a fully opaque bar in every state -- there's
	/// no card/list content for the bar to blend with. `MainFeedCollectionViewController`
	/// and `MainTimelineModernViewController` sit on top of a scrolling list of
	/// cards/rows, and rely on the system's normal large-title behavior where the
	/// bar is transparent until the content scrolls underneath it, so the bar
	/// matches whatever's drawn there (cards, listBackground) instead of imposing
	/// its own flat color. Defaults to `false` so adopting this protocol without
	/// overriding the property preserves the original always-opaque behavior.
	var wantsTransparentScrollEdgeAppearance: Bool { get }
}

extension SurfacePaletteNavigationBarAware {

	var wantsTransparentScrollEdgeAppearance: Bool { false }

	/// Call once from `viewDidLoad()` and again from a `.surfaceTintDidChange`
	/// observer. Uses the explicit-trait-collection pattern (`self.traitCollection`,
	/// not `UITraitCollection.current`) established for
	/// `Assets.Colors.barBackground`/`vibrantText`/`fullScreenBackground`.
	///
	/// `.default` palette's `HexSet` is nil, so this intentionally leaves the
	/// system appearance untouched rather than resetting to
	/// `configureWithDefaultBackground()` -- same "nil means don't override"
	/// contract as every other SurfacePalette-driven color. That also means a
	/// controller that previously had a custom palette applied and then
	/// switches to `.default` keeps the last-applied appearance until it's
	/// re-created; none of the three current call sites are long-lived enough
	/// across a palette-to-default transition for this to be visible in
	/// practice, but a future long-lived host should reset standardAppearance/
	/// scrollEdgeAppearance/compactAppearance to nil in the `hexSet == nil` case.
	func applySurfacePaletteNavigationBarAppearance() {
		let isDark = traitCollection.userInterfaceStyle == .dark
		let palette = AppDefaults.shared.surfaceTint
		let hexSet = isDark ? palette.darkHexSet : palette.lightHexSet
		guard let hexSet else { return }

		let appearance = UINavigationBarAppearance()
		appearance.configureWithDefaultBackground()
		if let backgroundColor = UIColor(cssHex: hexSet.navigationBarBackground) {
			appearance.backgroundColor = backgroundColor
		}
		let tintColor = UIColor(cssHex: hexSet.navigationBarTint)
		if let tintColor {
			appearance.titleTextAttributes = [.foregroundColor: tintColor]
			appearance.largeTitleTextAttributes = [.foregroundColor: tintColor]
			navigationController?.navigationBar.tintColor = tintColor
		}
		navigationItem.standardAppearance = appearance
		navigationItem.compactAppearance = appearance

		guard wantsTransparentScrollEdgeAppearance else {
			navigationItem.scrollEdgeAppearance = appearance
			return
		}

		// Keep the background transparent so the bar shows whatever's drawn
		// beneath it (the list/timeline's own listBackground, or a card, seen
		// through the collapsed large title) instead of imposing an opaque
		// fill -- only the title/tint colors come from the palette here.
		let scrollEdgeAppearance = UINavigationBarAppearance()
		scrollEdgeAppearance.configureWithTransparentBackground()
		if let tintColor {
			scrollEdgeAppearance.titleTextAttributes = [.foregroundColor: tintColor]
			scrollEdgeAppearance.largeTitleTextAttributes = [.foregroundColor: tintColor]
		}
		navigationItem.scrollEdgeAppearance = scrollEdgeAppearance
	}
}
