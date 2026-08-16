//
//  Assets.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 11/18/25.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import Foundation
import UIKit

import RSCore
import Account
import Images

typealias RSColor = UIColor

struct Assets {
	@MainActor struct Images {

		// Named starOpen/starClosed for historical reasons — these back the "Read
		// Later" action (Phase 3), not literal starring; the internal ArticleStatus.Key
		// is still `.starred` deliberately (see Phase 3 in the fork plan: UI-copy/icon
		// only, no internal rename, to keep the diff small and behavior unchanged).
		static let starOpen = RSImage(symbol: "bookmark")!
		static let starClosed = RSImage(symbol: "bookmark.fill")!
		static let copy = RSImage(symbol: "document.on.document")
		static var markAllAsRead: RSImage { RSImage(named: "markAllAsRead")! }
		static let nextUnread = RSImage(symbol: "chevron.down.circle")!

		nonisolated static var nnwFeedIcon: RSImage { RSImage(named: "nnwFeedIcon")! }
		// Default per-feed placeholder, colorized per-feed by FaviconGenerator.
		// A book, not a globe -- Nectar feeds are books, not blogs.
		//
		// FaviconGenerator masks this via a raw CGImage (RSImage.maskWithColor),
		// not the live SwiftUI symbol-rendering path the sidebar's other SF
		// Symbol icons (todayFeed, unreadFeed, etc.) use -- so unlike those,
		// this one gets rasterized to a fixed pixel size exactly once and
		// reused for every feed. RSImage(symbol:)'s default point size (~17pt,
		// the system font size) is too small a source to upscale to
		// IconSize.large (48pt) without blurring, so request it explicitly
		// large instead of relying on the default.
		static let faviconTemplate: RSImage = RSImage.symbolImage("book.closed.fill", pointSize: 120)!

		static let share = RSImage(symbol: "square.and.arrow.up")!
		// Task 8 ("Content archival & destructive-update protection") --
		// the explicit per-article "Check for updates" action.
		static let checkForUpdates = RSImage(symbol: "arrow.triangle.2.circlepath")!
		static let folder = RSImage(symbol: "folder")!
		// Was `static let ... preferredColor: Assets.Colors.star`. Now a
		// computed var reading Assets.Colors.iconColor(\.star, ...) so it
		// repaints live when AccentColor changes, same as mainFolder/
		// unreadFeed/etc. below (see IconHexSet's doc comment in
		// AppDefaults.swift for why star was folded into that type).
		static var starredFeed: IconImage {
			IconImage(starClosed, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.iconColor(\.star, fallback: Assets.Colors.star))
		}

		static var accountLocalPadImage: RSImage { RSImage(named: "accountLocalPad")! }
		static var accountLocalPhoneImage: RSImage { RSImage(named: "accountLocalPhone")! }

		static let circleClosed = RSImage(symbol: "largecircle.fill.circle")!
		static let markBelowAsRead = RSImage(symbol: "arrowtriangle.down.circle")!
		static let markAboveAsRead = RSImage(symbol: "arrowtriangle.up.circle")!
		static let more = RSImage(symbol: "ellipsis.circle")!
		static let nextArticle = RSImage(symbol: "chevron.down")!
		static let circleOpen = RSImage(symbol: "circle")!
		static var disclosure: RSImage { RSImage(named: "disclosure")! }
		static let deactivate = RSImage(symbol: "minus.circle")!
		static let currentActivity = RSImage(symbol: "text.pad.header")!
		static let edit = RSImage(symbol: "square.and.pencil")!
		static let filter = RSImage(symbol: "line.3.horizontal.decrease")!
		static let folderOutlinePlus = RSImage(symbol: "folder.badge.plus")!
		static let info = RSImage(symbol: "info.circle")!
		static let opmlImport = RSImage(symbol: "square.and.arrow.down.on.square")!
		static let plus = RSImage(symbol: "plus")!
		static let prevArticle = RSImage(symbol: "chevron.up")!
		static let openInSidebar = RSImage(symbol: "arrow.turn.down.left")!
		static let safari = RSImage(symbol: "safari")!
		static let smartFeed = RSImage(symbol: "gear")!
		static let trash = RSImage(symbol: "trash")!

		// Phase 5/6 fork additions: Loved toolbar/action icons and the Theme
		// nav-bar icon. Symbol-backed like the rest of this section pending a
		// dedicated asset catalog entry (not part of this text-only patch series).
		static let heartOpen = RSImage(symbol: "heart")!
		static let heartClosed = RSImage(symbol: "heart.fill")!
		static let theme = RSImage(symbol: "doc.richtext")!
		static let findInArticle = RSImage(symbol: "magnifyingglass")!
		static let tableOfContents = RSImage(symbol: "list.bullet")!
		static let annotationAddNote = RSImage(symbol: "note.text.badge.plus")!
		static let annotations = RSImage(symbol: "highlighter")!

		// Loved smart feed icon: filled heart, system red by default --
		// replaces the starredFeed-borrowed placeholder in
		// LovedFeedDelegate.swift. Was a hardcoded `static let ...
		// RSColor.systemRed`; now reads IconHexSet.loved so non-default
		// AccentColor palettes can override it, falling back to systemRed
		// unchanged for `.default`.
		static var lovedFeed: IconImage {
			IconImage(heartClosed, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.iconColor(\.loved, fallback: RSColor.systemRed))
		}

		static let searchFeed = IconImage(RSImage(symbol: "magnifyingglass")!, isSymbol: true)
		// mainFolder/unreadFeed/readFeed/lastOpenedFeed/unreadCellIndicator were
		// `static let`s that captured Assets.Colors.secondaryAccent's value once,
		// at first access -- Swift only evaluates a struct's `static let` a single
		// time per process, so AccentColor picker changes never reached these five
		// (see AccentColor's doc comment). Recomputed as `static var`s instead: each
		// access re-reads the live accent color and builds a fresh IconImage.
		// IconImage.init is cheap (no image processing beyond an async luminance
		// preload), so recomputing per access is fine.
		static var mainFolder: IconImage { IconImage(folder, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.iconColor(\.folder, fallback: Assets.Colors.secondaryAccent)) }
		// Was `static let ... preferredColor: UIColor.systemOrange`. Now
		// reads IconHexSet.today, falling back to systemOrange unchanged
		// for `.default`.
		static var todayFeed: IconImage { IconImage(RSImage(symbol: "tray.and.arrow.down.fill")!, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.iconColor(\.today, fallback: UIColor.systemOrange)) }
		static var unreadFeed: IconImage { IconImage(RSImage(symbol: "largecircle.fill.circle")!, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.iconColor(\.unreadFeed, fallback: Assets.Colors.secondaryAccent)) }
		static var readFeed: IconImage { IconImage(RSImage(symbol: "checkmark.circle.fill")!, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.iconColor(\.readFeed, fallback: Assets.Colors.secondaryAccent)) }
		// Last Opened smart feed icon. Placeholder symbol choice -- swap for
		// whatever SF Symbol fits the icon set; not cross-checked against the
		// app's actual icon conventions beyond "recently opened" being a
		// reasonable read for it.
		static var lastOpenedFeed: IconImage { IconImage(RSImage(symbol: "clock.arrow.circlepath")!, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.iconColor(\.lastOpenedFeed, fallback: Assets.Colors.secondaryAccent)) }
		static var timelineStar: RSImage {
			let image = RSImage(symbol: "star.fill")!
			return image.withTintColor(Assets.Colors.iconColor(\.star, fallback: Assets.Colors.star), renderingMode: .alwaysOriginal)
		}
		static var unreadCellIndicator: IconImage { IconImage(RSImage(symbol: "circle.fill")!, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.iconColor(\.unreadCellIndicator, fallback: Assets.Colors.secondaryAccent)) }
	}

	@MainActor static func accountImage(_ accountType: AccountType) -> RSImage {
		switch accountType {
		case .onMyMac:
			if UIDevice.current.userInterfaceIdiom == .pad {
				return Assets.Images.accountLocalPadImage
			} else {
				return Assets.Images.accountLocalPhoneImage
			}
		}
	}

	@MainActor struct Colors {
		// Catalog defaults, kept as the .default fallback and as the base every
		// other accent choice is computed relative to -- unlike BadgeColorTable's
		// palette (fixed hex swatches with no user "off" state), accent color's
		// .default case must keep resolving to whatever these named colors are,
		// not a hardcoded hex duplicate of them, so a catalog update to these
		// colorset entries doesn't silently drift from what .default shows.
		private static let defaultPrimaryAccent = RSColor(named: "primaryAccentColor")!
		private static let defaultSecondaryAccent = RSColor(named: "secondaryAccentColor")!

		/// Live per-read, not cached -- reflects `AppDefaults.shared.accentColor`
		/// immediately. Every call site already goes through `Assets.Colors.*`
		/// rather than a hardcoded literal, so most consumers (tintColor
		/// assignments, updateColors()-style methods) repaint for free on the
		/// next draw once `AccentColor`'s doc comment note on `static let
		/// IconImage`s aside.
		static var primaryAccent: RSColor {
			AppDefaults.shared.accentColor.primaryHex.flatMap { RSColor(cssHex: $0) } ?? defaultPrimaryAccent
		}
		static var secondaryAccent: RSColor {
			AppDefaults.shared.accentColor.secondaryHex.flatMap { RSColor(cssHex: $0) } ?? defaultSecondaryAccent
		}

		/// Per-icon accent override. `AppDefaults.shared.accentColor.iconHexSet`
		/// is nil for `.default`, in which case `fallback` (today's
		/// asset-catalog color or hardcoded literal) is used -- same
		/// "nil means don't override" contract as primaryAccent/secondaryAccent's
		/// use of defaultPrimaryAccent/defaultSecondaryAccent above. Callers
		/// pass a KeyPath literal (e.g. \.unreadFeed) so adding a new slot to
		/// IconHexSet needs no change here.
		static func iconColor(_ keyPath: KeyPath<AccentColor.IconHexSet, String>, fallback: @autoclosure () -> RSColor) -> RSColor {
			guard let hexSet = AppDefaults.shared.accentColor.iconHexSet else { return fallback() }
			return RSColor(cssHex: hexSet[keyPath: keyPath]) ?? fallback()
		}

		static let star = RSColor(named: "starColor")!

		/// Takes an explicit trait collection rather than reading
		/// `UITraitCollection.current` -- Apple documents `.current` as a
		/// thread-local value the system sets automatically only inside
		/// specific framework-invoked callbacks (drawing methods,
		/// dynamic-color/image resolution, trait-change handlers), undefined
		/// elsewhere. Upstream NetNewsWire's own dark/light-branching call
		/// sites (`IconView.iconImage.didSet`,
		/// `WebViewController.applyResolvedBackgroundColors`) never read
		/// `.current`; they always read a real view's own `.traitCollection`.
		/// This property follows that same idiom -- callers pass their own
		/// `traitCollection` (see `ArticleSearchBar.updateBarBackground()`).
		/// `.default` falls back to the asset catalog's colorset value,
		/// unchanged from before `SurfacePalette` existed.
		static func barBackground(for traitCollection: UITraitCollection) -> RSColor {
			let hex = traitCollection.userInterfaceStyle == .dark
				? AppDefaults.shared.surfaceTint.darkHexSet?.barBackground
				: AppDefaults.shared.surfaceTint.lightHexSet?.barBackground
			return hex.flatMap { RSColor(cssHex: $0) } ?? RSColor(named: "barBackgroundColor")!
		}
		static func vibrantText(for traitCollection: UITraitCollection) -> RSColor {
			let hex = traitCollection.userInterfaceStyle == .dark
				? AppDefaults.shared.surfaceTint.darkHexSet?.vibrantText
				: AppDefaults.shared.surfaceTint.lightHexSet?.vibrantText
			return hex.flatMap { RSColor(cssHex: $0) } ?? RSColor(named: "vibrantTextColor")!
		}
		/// Backs the top nav bar's (and, since toolbarStyle's introduction,
		/// the bottom toolbar's) tinted fill when
		/// `AppDefaults.shared.toolbarStyle == .tinted` (see
		/// `SurfacePaletteNavigationBarAware`). Genuinely needs a real fallback --
		/// there's no sensible "leave it unset" for a background fill once tinting
		/// is on and the hex fails to parse -- so this follows the
		/// `barBackground`/`vibrantText`/`fullScreenBackground` pattern above
		/// exactly, unlike `navigationBarTint` below.
		static func navigationBarBackground(for traitCollection: UITraitCollection) -> RSColor {
			let hex = traitCollection.userInterfaceStyle == .dark
				? AppDefaults.shared.surfaceTint.darkHexSet?.navigationBarBackground
				: AppDefaults.shared.surfaceTint.lightHexSet?.navigationBarBackground
			return hex.flatMap { RSColor(cssHex: $0) } ?? RSColor(named: "navigationBarBackgroundColor")!
		}
		/// Deliberately stays `RSColor?`, not a forced fallback: when
		/// `UIColor(cssHex:)` fails to parse, the caller leaves `tintColor` unset,
		/// falling through to the normal accent-color-driven system cascade --
		/// the same "don't override" contract the nil-hexSet reset path uses on
		/// purpose. A named-asset fallback here would override that cascade with
		/// a fixed color instead of deferring to accent color.
		static func navigationBarTint(for traitCollection: UITraitCollection) -> RSColor? {
			let hex = traitCollection.userInterfaceStyle == .dark
				? AppDefaults.shared.surfaceTint.darkHexSet?.navigationBarTint
				: AppDefaults.shared.surfaceTint.lightHexSet?.navigationBarTint
			return hex.flatMap { RSColor(cssHex: $0) }
		}
		static var iconBackground: RSColor { RSColor(named: "iconBackgroundColor")! }
		static func fullScreenBackground(for traitCollection: UITraitCollection) -> RSColor {
			let hex = traitCollection.userInterfaceStyle == .dark
				? AppDefaults.shared.surfaceTint.darkHexSet?.fullScreenBackground
				: AppDefaults.shared.surfaceTint.lightHexSet?.fullScreenBackground
			return hex.flatMap { RSColor(cssHex: $0) } ?? RSColor(named: "fullScreenBackgroundColor")!
		}
		/// See docs/app-chrome-palette.md. Backdrop for
		/// settings/list table and collection views.
		static func settingsBackground(for traitCollection: UITraitCollection) -> RSColor {
			let hex = traitCollection.userInterfaceStyle == .dark
				? AppDefaults.shared.surfaceTint.darkHexSet?.settingsBackground
				: AppDefaults.shared.surfaceTint.lightHexSet?.settingsBackground
			return hex.flatMap { RSColor(cssHex: $0) } ?? RSColor(named: "settingsBackgroundColor")!
		}
		/// Individual settings-cell fill, distinct from `settingsBackground`.
		static func settingsCellBackground(for traitCollection: UITraitCollection) -> RSColor {
			let hex = traitCollection.userInterfaceStyle == .dark
				? AppDefaults.shared.surfaceTint.darkHexSet?.settingsCellBackground
				: AppDefaults.shared.surfaceTint.lightHexSet?.settingsCellBackground
			return hex.flatMap { RSColor(cssHex: $0) } ?? RSColor(named: "settingsCellBackgroundColor")!
		}
		/// Feed list + timeline backdrop.
		static func listBackground(for traitCollection: UITraitCollection) -> RSColor {
			let hex = traitCollection.userInterfaceStyle == .dark
				? AppDefaults.shared.surfaceTint.darkHexSet?.listBackground
				: AppDefaults.shared.surfaceTint.lightHexSet?.listBackground
			return hex.flatMap { RSColor(cssHex: $0) } ?? RSColor(named: "listBackgroundColor")!
		}

		/// A palette-aware fill for a card/row's "pressed" state -- swiped or
		/// selected -- so those states read as a variant of the same surface
		/// (`settingsCellBackground`) instead of falling back to a plain,
		/// palette-blind system fill like `.secondarySystemFill`/
		/// `.tertiarySystemFill`. Used by `MainTimelineCell` (swipe/select) and
		/// `MainFeedCollectionViewCell` (iPad highlighted/selected/focused row).
		/// Blends a small amount of black (light mode) or white (dark mode)
		/// into `settingsCellBackground` so it stays visibly distinct from the
		/// resting-state fill under every palette, including `.default`.
		static func pressedCellBackground(for traitCollection: UITraitCollection) -> RSColor {
			let base = settingsCellBackground(for: traitCollection)
			let overlay: RSColor = traitCollection.userInterfaceStyle == .dark ? .white : .black
			return base.blended(withFraction: 0.12, of: overlay)
		}
	}
}

private extension RSColor {
	/// Simple linear RGBA blend, used only for deriving a "pressed" variant
	/// of a palette color. Not a general-purpose color-mixing utility --
	/// keep it private to this file.
	func blended(withFraction fraction: CGFloat, of other: RSColor) -> RSColor {
		var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
		var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
		getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
		other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
		return RSColor(red: r1 + (r2 - r1) * fraction,
					   green: g1 + (g2 - g1) * fraction,
					   blue: b1 + (b2 - b1) * fraction,
					   alpha: a1 + (a2 - a1) * fraction)
	}
}

extension RSImage {

	convenience init?(symbol: String) {
		self.init(systemName: symbol)
	}

	/// Same as `init?(symbol:)`, but rendered at an explicit point size rather
	/// than the SF Symbol default (~17pt, the system font size). Needed for
	/// any symbol that gets rasterized once and reused at a larger fixed
	/// size (e.g. masked into a colored placeholder via `maskWithColor`)
	/// instead of rendered live through SwiftUI/UIKit's vector
	/// symbol-rendering path, which scales for free at any size.
	static func symbolImage(_ symbol: String, pointSize: CGFloat) -> RSImage? {
		let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
		return UIImage(systemName: symbol, withConfiguration: config)
	}
}
