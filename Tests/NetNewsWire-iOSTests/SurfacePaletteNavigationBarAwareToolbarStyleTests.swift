//
//  SurfacePaletteNavigationBarAwareToolbarStyleTests.swift
//  NetNewsWire-iOSTests
//
//  toolbar-style-plan.md, Part 1 + 2.2: regression coverage for
//  - the top-nav-bar-transparent-at-scroll-edge bugfix
//    (resetToSystemNavigationBarAppearance() now respects
//    wantsTransparentScrollEdgeAppearance instead of always nil-ing
//    standardAppearance/compactAppearance/scrollEdgeAppearance), and
//  - the three-way switch on AppDefaults.shared.toolbarStyle, including
//    supportsBlendToolbarStyle scoping .blend to screens that opt in
//    (ArticleViewController) and falling the rest back to .system's look
//    (MainFeedCollectionViewController/MainTimelineModernViewController).
//
//  Exercised against minimal SurfacePaletteNavigationBarAware test doubles
//  rather than the real screens: ArticleViewController/MainFeedCollectionViewController/
//  MainTimelineModernViewController all need a fully wired storyboard scene
//  (webview, collection view, etc.) to loadViewIfNeeded() safely, which is
//  more than this bug's actual surface (a UIViewController conforming to the
//  protocol, wrapped in a UINavigationController so navigationItem/
//  navigationController are populated) needs. The doubles mirror the two
//  real per-screen configurations documented on wantsTransparentScrollEdgeAppearance/
//  supportsBlendToolbarStyle exactly.
//

import Testing
import UIKit
@testable import Nectar

/// Mirrors ArticleViewController's configuration: opaque bar in every scroll
/// state, opts in to .blend.
private final class OpaqueBlendCapableScreen: UIViewController, SurfacePaletteNavigationBarAware {
	var supportsBlendToolbarStyle: Bool { true }
}

/// Mirrors MainFeedCollectionViewController/MainTimelineModernViewController's
/// configuration: transparent-until-scrolled, no .blend concept.
private final class TransparentScrollEdgeScreen: UIViewController, SurfacePaletteNavigationBarAware {
	var wantsTransparentScrollEdgeAppearance: Bool { true }
}

@Suite struct SurfacePaletteNavigationBarAwareToolbarStyleTests {

	@MainActor
	private func makeLoaded<T: UIViewController>(_ makeScreen: () -> T) -> T {
		let screen = makeScreen()
		_ = UINavigationController(rootViewController: screen) // populates navigationController/navigationItem
		screen.loadViewIfNeeded()
		return screen
	}

	private func resetDefaults() {
		AppDefaults.shared.toolbarStyle = .system
		AppDefaults.shared.surfaceTint = .default
	}

	// MARK: Part 1 bugfix

	@MainActor
	@Test func opaqueAdopterKeepsAnOpaqueScrollEdgeAppearanceUnderToolbarStyleSystem() {
		defer { resetDefaults() }
		resetDefaults()

		let screen = makeLoaded(OpaqueBlendCapableScreen.init)
		screen.applySurfacePaletteNavigationBarAppearance()

		// The bug: this used to be nil, which falls through to UINavigationBar's
		// own OS default -- fully transparent at scroll-offset-zero since iOS 15.
		#expect(screen.navigationItem.scrollEdgeAppearance != nil)
		#expect(screen.navigationItem.standardAppearance != nil)
		#expect(screen.navigationItem.compactAppearance != nil)
	}

	@MainActor
	@Test func transparentScrollEdgeAdopterStaysNilUnderToolbarStyleSystem() {
		// The other half of the fix: MainFeed/MainTimeline's large-title
		// transparent-until-scrolled look must be untouched by the
		// wantsTransparentScrollEdgeAppearance branch -- still nil, not an
		// opaque appearance.
		defer { resetDefaults() }
		resetDefaults()

		let screen = makeLoaded(TransparentScrollEdgeScreen.init)
		screen.applySurfacePaletteNavigationBarAppearance()

		#expect(screen.navigationItem.scrollEdgeAppearance == nil)
		#expect(screen.navigationItem.standardAppearance == nil)
		#expect(screen.navigationItem.compactAppearance == nil)
	}

	// MARK: Three-way switch

	@MainActor
	@Test func tintedStyleAppliesAnOpaqueBackgroundOnBothAdopterKinds() {
		defer { resetDefaults() }
		resetDefaults()
		AppDefaults.shared.surfaceTint = .slate
		AppDefaults.shared.toolbarStyle = .tinted

		let opaqueScreen = makeLoaded(OpaqueBlendCapableScreen.init)
		opaqueScreen.applySurfacePaletteNavigationBarAppearance()
		#expect(opaqueScreen.navigationItem.standardAppearance?.backgroundColor != nil)
		#expect(opaqueScreen.navigationItem.scrollEdgeAppearance?.backgroundColor != nil)

		// wantsTransparentScrollEdgeAppearance == true still applies under
		// .tinted -- only the scroll-edge slot stays transparent; standard
		// still picks up the palette color once scrolled.
		let transparentScreen = makeLoaded(TransparentScrollEdgeScreen.init)
		transparentScreen.applySurfacePaletteNavigationBarAppearance()
		#expect(transparentScreen.navigationItem.standardAppearance?.backgroundColor != nil)
	}

	@MainActor
	@Test func blendStyleAppliesOnlyToAdoptersThatOptIn() {
		defer { resetDefaults() }
		resetDefaults()
		AppDefaults.shared.toolbarStyle = .blend

		let blendCapableScreen = makeLoaded(OpaqueBlendCapableScreen.init)
		blendCapableScreen.applySurfacePaletteNavigationBarAppearance()
		#expect(blendCapableScreen.navigationItem.standardAppearance?.backgroundColor != nil)

		// supportsBlendToolbarStyle == false (the default MainFeed/MainTimeline
		// use): .blend has no meaning for a screen with no article on screen,
		// so it must fall back to .system's own (transparent, per that
		// screen's wantsTransparentScrollEdgeAppearance == true) look rather
		// than painting from a stale/meaningless article color.
		let nonBlendScreen = makeLoaded(TransparentScrollEdgeScreen.init)
		nonBlendScreen.applySurfacePaletteNavigationBarAppearance()
		#expect(nonBlendScreen.navigationItem.standardAppearance == nil)
		#expect(nonBlendScreen.navigationItem.scrollEdgeAppearance == nil)
	}
}
