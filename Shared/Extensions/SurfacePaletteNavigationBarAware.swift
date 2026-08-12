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
import os

// TEMPORARY, alongside the debug logging in applySurfacePaletteNavigationBarAppearance()
// below -- see that method's doc comment. Remove both together once the
// top-toolbar-colors-wrong-on-live-switch fix is confirmed on-device.
private enum SurfacePaletteNavigationBarAwareLogging {
	static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.ranchero.Nectar", category: "SurfacePaletteNavigationBarAware")
}

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

	/// Called every time `applySurfacePaletteNavigationBarAppearance()` runs,
	/// with the same resolved tint color it just applied to
	/// `UINavigationBarAppearance.titleTextAttributes`/`largeTitleTextAttributes`
	/// (`nil` for the `.default` palette, meaning "use normal dynamic system
	/// colors"). `UINavigationBarAppearance`'s text attributes only affect
	/// `navigationItem.title` rendered by the system's own title view --
	/// they have **no effect** on a custom `navigationItem.titleView`/
	/// `subtitleView`. Any screen that installs one of those (e.g.
	/// `MainTimelineModernViewController`'s `navigationBarTitleLabel`/
	/// `navigationBarSubtitleTitleLabel`) must override this and recolor its
	/// own label(s) here, or they'll silently keep whatever color they had
	/// regardless of the active SurfacePalette. Default is a no-op, which is
	/// correct for any screen relying on `navigationItem.title` directly.
	func applyPaletteTintToCustomTitleViews(_ tintColor: UIColor?)
}

extension SurfacePaletteNavigationBarAware {

	var wantsTransparentScrollEdgeAppearance: Bool { false }
	func applyPaletteTintToCustomTitleViews(_ tintColor: UIColor?) {}

	/// Call once from `viewDidLoad()` and again from a `.surfaceTintDidChange`
	/// observer. Uses the explicit-trait-collection pattern (`self.traitCollection`,
	/// not `UITraitCollection.current`) established for
	/// `Assets.Colors.barBackground`/`vibrantText`/`fullScreenBackground`.
	///
	/// `.default` palette's `HexSet` is nil, meaning "don't override" -- the
	/// same contract as every other SurfacePalette-driven color. Unlike a
	/// plain color property, though, a `UINavigationBarAppearance` set on
	/// this controller sticks around until something explicitly clears it,
	/// so "don't override" on the way *back* to `.default` has to mean
	/// "clear whatever a previous custom palette left behind," not "leave
	/// it untouched": `MainFeedCollectionViewController` and
	/// `MainTimelineModernViewController` are the app's long-lived root
	/// screens (not re-created per push the way Settings' screens are), so
	/// picking Slate, backing out, then switching to Default while either
	/// stays on screen is a real, reachable transition -- not the
	/// hypothetical this comment used to assume away. Reset to nil (the
	/// system's own appearance) in that case instead of returning early.
	func applySurfacePaletteNavigationBarAppearance() {
		let isDark = traitCollection.userInterfaceStyle == .dark
		let palette = AppDefaults.shared.surfaceTint
		let hexSet = isDark ? palette.darkHexSet : palette.lightHexSet

		// TEMPORARY diagnostic logging (top-toolbar-colors-wrong-on-live-switch
		// investigation, see ArticleViewController's dedicated-notification
		// observers) -- prints who's calling, and the resolved palette, so a
		// console trace during a live in-app palette switch shows whether/when
		// each adopting screen actually repaints. Remove once confirmed.
		SurfacePaletteNavigationBarAwareLogging.logger.debug("applySurfacePaletteNavigationBarAppearance: \(type(of: self)) palette=\(String(describing: palette), privacy: .public) isDark=\(isDark, privacy: .public) hexSet=\(hexSet == nil ? "nil" : "present", privacy: .public)")

		guard let hexSet else {
			navigationItem.standardAppearance = nil
			navigationItem.compactAppearance = nil
			navigationItem.scrollEdgeAppearance = nil
			navigationController?.navigationBar.tintColor = nil
			// Symmetric with the tintColor assignment below: a previous non-.default
			// palette may have left an explicit tintColor sitting on these items,
			// which -- unlike the bar's own .tintColor -- doesn't get reset just by
			// clearing the appearance/bar tint above. Reset to nil so they fall back
			// to the normal cascade/dynamic system color again.
			navigationItem.leftBarButtonItem?.tintColor = nil
			navigationItem.rightBarButtonItems?.forEach { $0.tintColor = nil }
			applyPaletteTintToCustomTitleViews(nil)
			return
		}

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
		// Set each bar button item's own tintColor explicitly rather than relying
		// solely on the bar-level cascade above: a UIBarButtonItem that's already
		// on screen doesn't reliably repaint just because navigationBar.tintColor
		// was reassigned after the fact (as opposed to at layout time) -- this
		// produced dark-on-dark/light-on-light toolbar icons after toggling
		// appearance (system or in-app) while the screen was already visible. The
		// buttons stayed hit-testable (frames/targets unchanged) but kept showing
		// whatever color they'd last actually rendered.
		navigationItem.leftBarButtonItem?.tintColor = tintColor
		navigationItem.rightBarButtonItems?.forEach { $0.tintColor = tintColor }
		applyPaletteTintToCustomTitleViews(tintColor)

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
