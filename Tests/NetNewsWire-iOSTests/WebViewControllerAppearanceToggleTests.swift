//
//  WebViewControllerAppearanceToggleTests.swift
//  NetNewsWire-iOSTests
//
//  Regression coverage for the "notch/webview background color goes stale
//  one appearance-toggle behind" bug fixed in applyResolvedBackgroundColors()
//  (see the BUG FIX comment there and docs/article-color-pipeline.md).
//
//  Pre-fix, applyResolvedBackgroundColors() read isDark off webView.traitCollection
//  -- the pooled PreloadedWebView, which can lag one trait-change cycle behind
//  this view controller's own traitCollection because it's detached/reattached
//  outside plain UIKit view lifecycle. That made a Settings -> Appearance (or
//  system) toggle resolve against the *previous* appearance's trait: always one
//  step behind, self-correcting only when a third toggle happened to land the
//  stale read back in sync.
//
//  WebViewController itself can't be exercised here -- applyResolvedBackgroundColors()
//  and webView are both private, and building a working instance needs a live
//  SceneCoordinator (coordinator.webViewProvider.dequeueWebView), which nothing
//  in this test target currently sets up. Instead this targets
//  WebViewController.isDarkForColorResolution(selfTraitCollection:webViewTraitCollection:),
//  the small internal seam the fix was extracted into: it takes two independently
//  constructed UITraitCollections, so the self-vs-webView divergence the bug
//  depended on can be reproduced deterministically (UITraitCollection(userInterfaceStyle:)
//  is a plain, synchronous initializer) instead of relying on real UIKit trait
//  propagation timing, which would be flaky. Composed with the already-pure
//  ArticleResolvedColors.resolved(...), this reproduces the manual QA repro chain
//  (enable a background override with distinct light/dark hexes, then toggle
//  appearance back and forth) as a fast, deterministic unit test.
//

import Testing
import UIKit
@testable import Nectar
@testable import HexColor
@testable import ArticleTheming

@Suite struct WebViewControllerAppearanceToggleTests {

	/// Pins the fix's actual invariant: the resolved isDark always tracks
	/// self's trait collection, never webView's -- regardless of what webView's
	/// (possibly stale) trait collection independently reports.
	@Test func isDarkAlwaysTracksSelfTraitCollectionNotWebView() {
		#expect(WebViewController.isDarkForColorResolution(
			selfTraitCollection: UITraitCollection(userInterfaceStyle: .dark),
			webViewTraitCollection: UITraitCollection(userInterfaceStyle: .light)) == true)

		#expect(WebViewController.isDarkForColorResolution(
			selfTraitCollection: UITraitCollection(userInterfaceStyle: .light),
			webViewTraitCollection: UITraitCollection(userInterfaceStyle: .dark)) == false)

		// Also correct, trivially, when both agree -- the common case, and what
		// the pre-fix code happened to get right whenever webView wasn't stale.
		#expect(WebViewController.isDarkForColorResolution(
			selfTraitCollection: UITraitCollection(userInterfaceStyle: .dark),
			webViewTraitCollection: UITraitCollection(userInterfaceStyle: .dark)) == true)
	}

	/// Reproduces the manual QA repro chain: enable the background override with
	/// distinct light/dark hexes, then toggle appearance back and forth while
	/// webView's trait collection is held stale one step behind self's -- exactly
	/// the scenario the BUG FIX comment describes. Run against the pre-fix line
	/// (isDark keyed off webViewTraitCollection instead of selfTraitCollection),
	/// the light-mode and second dark-mode assertions below fail; post-fix they pass.
	@Test func overrideBackgroundTracksSelfTraitAcrossStaleWebViewToggles() throws {
		let theme = ArticleTheme.defaultTheme
		let overrides = ArticleThemeOverrides(backgroundColorHex: "#ffffff", backgroundColorDarkHex: "#111111")
		let lightOverride = try #require(UIColor(cssHex: "#ffffff"))
		let darkOverride = try #require(UIColor(cssHex: "#111111"))

		func resolvedBackground(selfStyle: UIUserInterfaceStyle, webViewStyle: UIUserInterfaceStyle) -> UIColor {
			let isDark = WebViewController.isDarkForColorResolution(
				selfTraitCollection: UITraitCollection(userInterfaceStyle: selfStyle),
				webViewTraitCollection: UITraitCollection(userInterfaceStyle: webViewStyle))
			return ArticleResolvedColors.resolved(
				theme: theme,
				isDark: isDark,
				overrideBackgroundColorHex: overrides.backgroundColorHex,
				overrideBackgroundColorDarkHex: overrides.backgroundColorDarkHex
			).background
		}

		// Step 2: already in dark mode, webView agrees -- dark override color.
		#expect(resolvedBackground(selfStyle: .dark, webViewStyle: .dark) == darkOverride)

		// Step 3: system toggles to light; webView's trait collection is still
		// (stale) dark, simulating the pooled PreloadedWebView lag. Must resolve
		// to the light override color, not the stale dark one.
		#expect(resolvedBackground(selfStyle: .light, webViewStyle: .dark) == lightOverride)

		// Step 4: system toggles back to dark; webView's trait collection is now
		// (stale) light, one step behind again. Must resolve to the dark override
		// color, not the stale light one.
		#expect(resolvedBackground(selfStyle: .dark, webViewStyle: .light) == darkOverride)
	}
}
