//
//  AccentColorAssetsResolutionTests.swift
//  NetNewsWire-iOSTests
//
//  See docs/app-chrome-palette.md ("Badge Colors" -- "independently
//  assignable icon colors per AccentColor case"): app-side coverage of
//  Assets.Colors.iconColor(_:fallback:), which resolves an AccentColor's
//  IconHexSet through AppDefaults. `.default` must resolve every icon to
//  its pre-change fallback, unchanged, and each icon slot must be
//  independently assignable. The pure IconHexSet tests (every non-default
//  case supplies a complete, parseable set) live in
//  Modules/AppChrome/Tests/AppChromeTests/AccentColorIconHexSetTests.swift.
//

import Testing
import UIKit
@testable import Nectar
@testable import HexColor
import AppChrome

@Suite struct AccentColorAssetsResolutionTests {

	// MARK: - Assets.Colors.iconColor(_:fallback:)

	@MainActor
	@Test func iconColorFallsBackToDefaultAccentColorFallback() {
		AppDefaults.shared.accentColor = .default
		let fallback = UIColor.systemPink
		let resolved = Assets.Colors.iconColor(\.folder, fallback: fallback)
		#expect(resolved == fallback)
	}

	@MainActor
	@Test func iconColorUsesIconHexSetWhenAccentColorIsNotDefault() {
		AppDefaults.shared.accentColor = .rosePine
		defer { AppDefaults.shared.accentColor = .default }

		let resolved = Assets.Colors.iconColor(\.folder, fallback: .systemPink)
		let expected = UIColor(cssHex: AccentColor.rosePine.iconHexSet!.folder)!
		#expect(resolved.cssHexString == expected.cssHexString)
		#expect(resolved.cssHexString != UIColor.systemPink.cssHexString)
	}

	@MainActor
	@Test func iconColorDistinguishesUnreadFromReadForRosePine() {
		// Directly guards the reported bug: before IconHexSet existed,
		// unreadFeed and readFeed both resolved to the same
		// secondaryAccent value. This confirms they're independently
		// assignable, using .rosePine (where they're chosen to differ) as
		// the regression case.
		AppDefaults.shared.accentColor = .rosePine
		defer { AppDefaults.shared.accentColor = .default }

		let unread = Assets.Colors.iconColor(\.unreadFeed, fallback: .systemGray)
		let read = Assets.Colors.iconColor(\.readFeed, fallback: .systemGray)
		#expect(unread.cssHexString != read.cssHexString)
	}

	@MainActor
	@Test func iconColorLiveUpdatesWhenAccentColorChanges() {
		// The whole point of IconHexSet living behind computed `static
		// var`s in Assets.Images rather than `static let`s: no app
		// restart needed. This test exercises the resolver function
		// directly (iconColor(_:fallback:)) rather than an Assets.Images
		// property, since the properties themselves are the thing that
		// must stay `var`, not `let` -- see the AppDefaults.swift comment
		// this change updated.
		defer { AppDefaults.shared.accentColor = .default }

		AppDefaults.shared.accentColor = .forest
		let forestFolder = Assets.Colors.iconColor(\.folder, fallback: .systemGray)

		AppDefaults.shared.accentColor = .berry
		let berryFolder = Assets.Colors.iconColor(\.folder, fallback: .systemGray)

		#expect(forestFolder.cssHexString != berryFolder.cssHexString)
	}
}
