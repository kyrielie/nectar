//
//  SurfacePaletteNavigationBarAware.swift
//  NetNewsWire
//
//  Extracted from ArticleViewController.applySurfacePaletteNavigationBarAppearance()
//  (see docs/app-chrome-palette.md), which was the only screen wiring its
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

	/// Whether this screen supports `ToolbarStyle.blend` -- filling the nav
	/// bar with the *article's* own resolved background color
	/// (`ArticleResolvedColors.current(isDark:)`). Only `ArticleViewController`
	/// has an article to blend with; `MainFeedCollectionViewController` and
	/// `MainTimelineModernViewController` have no article-background concept
	/// at all, so painting their bars with whatever article happens to be
	/// current (or was last read) would be a meaningless, likely-stale color,
	/// not a real "blend." Defaults to `false`; adopters that opt in fall
	/// through to `resetToSystemNavigationBarAppearance()` instead when
	/// `toolbarStyle == .blend`, i.e. those screens simply don't have a
	/// `.blend` state and stay on `.system`'s look regardless of the setting.
	var supportsBlendToolbarStyle: Bool { get }

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
	var supportsBlendToolbarStyle: Bool { false }
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

	/// Symmetric with the tintColor assignment in the tinted/blend branches
	/// below: a previous non-.system palette/style may have left an explicit
	/// tintColor sitting on these items, which -- unlike the bar's own
	/// .tintColor -- doesn't get reset just by clearing the appearance/bar
	/// tint. Reset to nil so they fall back to the normal cascade/dynamic
	/// system color again. Shared by both the `.default`-palette path and
	/// the toolbarStyle == .system path, so there's one reset implementation
	/// instead of two copies drifting apart.
	///
	/// BUGFIX (top-nav-bar-transparent-at-scroll-edge): this used to also
	/// unconditionally nil out standardAppearance/compactAppearance/
	/// scrollEdgeAppearance regardless of wantsTransparentScrollEdgeAppearance.
	/// For ArticleViewController (wantsTransparentScrollEdgeAppearance ==
	/// false), that nil fell through to UINavigationBar's own OS default --
	/// which, since iOS 15, is a fully *transparent* scrollEdgeAppearance
	/// (shown whenever the underlying scroll view, here the WKWebView, is at
	/// content offset zero -- i.e. exactly the state an article opens into),
	/// distinct from standardAppearance's opaque-blur OS default. UIToolbar
	/// has no such standard/scroll-edge split, so the bottom toolbar's
	/// constant translucent-blur default never matched. ArticleViewController's
	/// own viewDidLoad set up an opaque configureWithDefaultBackground()
	/// appearance on all three slots specifically so this screen would never
	/// go transparent, but this function immediately wiped it out again on
	/// every call (viewDidLoad itself, every trait change, every
	/// .surfaceTintDidChange/.accentColorDidChange). Now: only nil
	/// scrollEdgeAppearance (along with the other two) for adopters that
	/// actually want the transparent-until-scrolled system look
	/// (MainFeedCollectionViewController/MainTimelineModernViewController,
	/// wantsTransparentScrollEdgeAppearance == true). Adopters that want a
	/// permanently opaque bar get that opaque baseline rebuilt here instead,
	/// so "reset to system" means "go back to solid," not "go back to
	/// whatever Apple ships by default" -- and ArticleViewController's own
	/// now-redundant viewDidLoad setup of the same appearance can be removed,
	/// since this is the only place that baseline needs to be defined.
	private func resetToSystemNavigationBarAppearance() {
		guard wantsTransparentScrollEdgeAppearance else {
			let appearance = Self.opaqueSystemBackgroundAppearance()
			navigationItem.standardAppearance = appearance
			navigationItem.compactAppearance = appearance
			navigationItem.scrollEdgeAppearance = appearance
			navigationController?.navigationBar.tintColor = nil
			navigationItem.leftBarButtonItem?.tintColor = nil
			navigationItem.rightBarButtonItems?.forEach { $0.tintColor = nil }
			applyPaletteTintToCustomTitleViews(nil)
			return
		}

		navigationItem.standardAppearance = nil
		navigationItem.compactAppearance = nil
		navigationItem.scrollEdgeAppearance = nil
		navigationController?.navigationBar.tintColor = nil
		navigationItem.leftBarButtonItem?.tintColor = nil
		navigationItem.rightBarButtonItems?.forEach { $0.tintColor = nil }
		applyPaletteTintToCustomTitleViews(nil)
	}

	/// The opaque, blurred baseline appearance adopters with
	/// wantsTransparentScrollEdgeAppearance == false want in every scroll
	/// state, regardless of toolbarStyle. Single definition, shared between
	/// resetToSystemNavigationBarAppearance() (the .system case) and
	/// ArticleViewController's former viewDidLoad setup, which duplicated
	/// this and drifted out of sync with the reset path -- see the bugfix
	/// note above.
	private static func opaqueSystemBackgroundAppearance() -> UINavigationBarAppearance {
		let appearance = UINavigationBarAppearance()
		appearance.configureWithDefaultBackground()
		return appearance
	}

	func applySurfacePaletteNavigationBarAppearance() {
		switch AppDefaults.shared.toolbarStyle {
		case .system:
			resetToSystemNavigationBarAppearance()
		case .tinted:
			applyTintedNavigationBarAppearance()
		case .blend:
			// See supportsBlendToolbarStyle's doc comment: MainFeed/MainTimeline
			// have no article-background concept, so they stay on .system's look
			// rather than painting from a meaningless/stale article color.
			guard supportsBlendToolbarStyle else {
				resetToSystemNavigationBarAppearance()
				return
			}
			applyBlendNavigationBarAppearance()
		}
	}

	private func applyTintedNavigationBarAppearance() {
		let isDark = traitCollection.userInterfaceStyle == .dark
		let palette = AppDefaults.shared.surfaceTint
		let hexSet = isDark ? palette.darkHexSet : palette.lightHexSet

		guard hexSet != nil else {
			resetToSystemNavigationBarAppearance()
			return
		}

		let backgroundColor = Assets.Colors.navigationBarBackground(for: traitCollection)
		let tintColor = Assets.Colors.navigationBarTint(for: traitCollection)
		applyOpaqueNavigationBarAppearance(backgroundColor: backgroundColor, titleColor: tintColor, tintColor: tintColor)
	}

	/// "Blend" toolbar style: the top nav bar filled with the article's own
	/// resolved background color instead of a palette hex -- see
	/// ArticleResolvedColors.current(isDark:), the same computation
	/// WebViewController's applyResolvedBackgroundColors()/notchCoverView use,
	/// so the webview background, the notch mask, and the nav bar can never
	/// disagree on what "the article's background" currently is. Title/tint
	/// color comes from the resolved *text* color, for contrast against that
	/// background -- navigationBarTint is a palette concept and doesn't apply
	/// here, since .blend is deliberately palette-independent.
	private func applyBlendNavigationBarAppearance() {
		let isDark = traitCollection.userInterfaceStyle == .dark
		let colors = ArticleResolvedColors.current(isDark: isDark)
		applyOpaqueNavigationBarAppearance(backgroundColor: colors.background, titleColor: colors.text, tintColor: colors.text)
	}

	/// Shared by the tinted and blend paths, which differ only in *which*
	/// colors they resolve, not in how those colors get applied to the bar.
	private func applyOpaqueNavigationBarAppearance(backgroundColor: UIColor, titleColor: UIColor?, tintColor: UIColor?) {
		let appearance = UINavigationBarAppearance()
		appearance.configureWithDefaultBackground()
		appearance.backgroundColor = backgroundColor
		if let titleColor {
			appearance.titleTextAttributes = [.foregroundColor: titleColor]
			appearance.largeTitleTextAttributes = [.foregroundColor: titleColor]
		}
		if let tintColor {
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
		// fill -- only the title/tint colors come from the palette/article here.
		let scrollEdgeAppearance = UINavigationBarAppearance()
		scrollEdgeAppearance.configureWithTransparentBackground()
		if let titleColor {
			scrollEdgeAppearance.titleTextAttributes = [.foregroundColor: titleColor]
			scrollEdgeAppearance.largeTitleTextAttributes = [.foregroundColor: titleColor]
		}
		navigationItem.scrollEdgeAppearance = scrollEdgeAppearance
	}
}
