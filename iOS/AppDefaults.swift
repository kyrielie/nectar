//
//  AppDefaults.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/22/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import UIKit
import os
import Account
import Articles
import Images

enum UserInterfaceColorPalette: Int, CustomStringConvertible, CaseIterable {
	case automatic = 0
	case light = 1
	case dark = 2

	var description: String {
		switch self {
		case .automatic:
			return NSLocalizedString("Automatic", comment: "Automatic")
		case .light:
			return NSLocalizedString("Light", comment: "Light")
		case .dark:
			return NSLocalizedString("Dark", comment: "Dark")
		}
	}
}

/// How the timeline card renders word count / completion / fandom / rating /
/// warnings. `.compact` is the default (today's single truncating line);
/// `.expanded` and `.badges` are alternative modes chosen via Settings →
/// Timeline Layout, independent of the number-of-lines slider, which continues
/// to govern the summary/description text.
enum TagDisplayMode: Int, CaseIterable, Sendable {
	/// Today's single truncating `metadataString`-style line.
	case compact = 1
	/// Word count / completion / fandom / rating / warnings, each on its own row.
	case expanded = 2
	/// Word count / completion stays on one line; fandom + rating + warnings
	/// wrap as small pill badges below it.
	case badges = 3

	var description: String {
		switch self {
		case .compact:
			return NSLocalizedString("Compact", comment: "Compact tag display mode")
		case .expanded:
			return NSLocalizedString("Expanded", comment: "Expanded tag display mode")
		case .badges:
			return NSLocalizedString("Badges", comment: "Badges tag display mode")
		}
	}
}

/// Whether, and how, `.badges` mode's rating/warning/category pills render
/// with their own tint. Fandom pills stay neutral in every palette -- see
/// MainTimelineCellData's BadgeCategory doc comment for why.
///
/// Renamed from `BadgeColorMode` (see docs/app-chrome-palette.md, "Badge Colors") -- what used to be a plain on/off is now a real palette,
/// grown the same incremental way `AccentColor`/`SurfacePalette` did.
///
/// Five cases, two tiers:
///  - Fixed-palette tier (`.default`, `.semantic`, `.monochrome`,
///    `.transparent`): hue/no-hue choice is baked into the case itself,
///    independent of whatever `AccentColor` is active.
///  - Accent-following tier (`.accent`): rating/category/warning colors
///    are derived at read time from `AppDefaults.shared.accentColor`, so
///    this one case's rendered colors change whenever the person's accent
///    choice changes, without a badge-specific setting change.
///
/// `.monochrome` is a rename of the original `.neutral` case, not a new
/// one -- it keeps raw value `1` so this rename needs no `UserDefaults`
/// migration; anyone with `badgeColorMode == 1` already saved keeps
/// exactly the palette they had, now spelled `.monochrome` because that
/// name describes what it actually renders (`.tertiarySystemFill`
/// background / `.secondaryLabel` text, no hue at all) instead of reading
/// like "off" or "muted-but-still-tinted." `.default`/`.semantic` keep
/// their original raw values (2/3) unchanged. `.transparent` and
/// `.accent` are genuinely new and take the next free raw values (4/5).
enum BadgeColorPalette: Int, CaseIterable, Sendable {
	case monochrome = 1
	case `default` = 2
	case semantic = 3
	case transparent = 4
	case accent = 5

	var description: String {
		switch self {
		case .monochrome:
			return NSLocalizedString("Monochrome", comment: "Monochrome badge color palette")
		case .default:
			return NSLocalizedString("Default", comment: "Default badge color palette")
		case .semantic:
			return NSLocalizedString("Semantic", comment: "Semantic badge color palette")
		case .transparent:
			return NSLocalizedString("Transparent", comment: "Transparent badge color palette")
		case .accent:
			return NSLocalizedString("Accent", comment: "Accent-following badge color palette")
		}
	}
}

/// App-wide accent hue (Settings → Appearance), independent of light/dark.
/// `.default` preserves today's fixed primaryAccentColor/secondaryAccentColor
/// asset-catalog values exactly; the other cases are a fixed palette rather
/// than a free color picker, so every choice stays legible against both
/// .label/.secondaryLabel text and system backgrounds in both appearances.
///
/// Scope note: `Assets.Colors.primaryAccent`/`.secondaryAccent` are read live
/// by most call sites (tintColor assignments, updateColors()-style methods),
/// so those repaint immediately via `accentColorDidChange`. The
/// `Assets.Images` entries this used to warn about (mainFolder, unreadFeed,
/// readFeed, lastOpenedFeed, unreadCellIndicator) were `static let
/// IconImage`s that captured `preferredColor` once at process launch -- see
/// `Assets.swift`'s own comment on those properties, which were converted to
/// `static var`s (recomputed per access) to fix exactly this. That fix is
/// why this note used to describe a launch-time-only limitation that no
/// longer applies; kept here in case any *new* `Assets.Images` entry
/// reintroduces the same `static let` pattern.
enum AccentColor: Int, CaseIterable, Sendable {
	case `default` = 0
	case rosePine = 1
	case sepia = 2
	case forest = 3
	case slate = 4
	case berry = 5
	/// See docs/app-chrome-palette.md ("Badge Colors"): four additional theme cases,
	/// added instead of building a per-icon override UI (explicitly out of
	/// scope, see IconHexSet's doc comment above) -- the variety a person
	/// wants from customizable icon colors is delivered by adding more
	/// complete `AccentColor` cases to this picker, the same way
	/// `.rosePine` through `.berry` already work, rather than by exposing
	/// IconHexSet's individual fields to per-field editing. Raw values 6-9
	/// are genuinely new and take the next free slots after `.berry`.
	case ocean = 6
	case sunset = 7
	case lavender = 8
	case graphite = 9

	var description: String {
		switch self {
		case .default:
			return NSLocalizedString("Default", comment: "Default accent color")
		case .rosePine:
			return NSLocalizedString("Rosé Pine", comment: "Rosé Pine accent color")
		case .sepia:
			return NSLocalizedString("Sepia", comment: "Sepia accent color")
		case .forest:
			return NSLocalizedString("Forest", comment: "Forest accent color")
		case .slate:
			return NSLocalizedString("Slate", comment: "Slate accent color")
		case .berry:
			return NSLocalizedString("Berry", comment: "Berry accent color")
		case .ocean:
			return NSLocalizedString("Ocean", comment: "Ocean accent color")
		case .sunset:
			return NSLocalizedString("Sunset", comment: "Sunset accent color")
		case .lavender:
			return NSLocalizedString("Lavender", comment: "Lavender accent color")
		case .graphite:
			return NSLocalizedString("Graphite", comment: "Graphite accent color")
		}
	}

	/// nil for `.default`, meaning "fall back to the existing asset-catalog
	/// color" -- these hex values aren't independently chosen, they're the
	/// same swatches BadgeColorTable already uses for the AO3-derived palette
	/// (see that file's header comment for why hex-via-UIColor(cssHex:)
	/// rather than colorset entries), reused here so the accent choices read
	/// as part of one consistent palette rather than a second unrelated set
	/// of hues.
	var primaryHex: String? {
		switch self {
		case .default: return nil
		case .rosePine: return "#3e8fb0"
		case .sepia: return "#b5835a"
		case .forest: return "#5a8a6b"
		case .slate: return "#5f7a8a"
		case .berry: return "#c4507a"
		case .ocean: return "#2f6690"
		case .sunset: return "#d9622b"
		case .lavender: return "#7c6bab"
		case .graphite: return "#6b6b6b"
		}
	}

	var secondaryHex: String? {
		switch self {
		case .default: return nil
		case .rosePine: return "#9ccfd8"
		case .sepia: return "#d4a574"
		case .forest: return "#8fb89c"
		case .slate: return "#8ea3b0"
		case .berry: return "#eb6f92"
		case .ocean: return "#7ec8e3"
		case .sunset: return "#f2a65a"
		case .lavender: return "#b8a9d9"
		case .graphite: return "#a8a8a8"
		}
	}

	/// Per-icon color slots for this accent case, mirroring
	/// `SurfacePalette.HexSet`'s shape: one named field per icon rather
	/// than a single shared hue, so `.rosePine`/`.sepia`/etc. can decide
	/// independently whether `unreadFeed` and `readFeed` should share a
	/// hue or contrast, instead of every icon being forced through
	/// `secondaryAccent` the way it was before this type existed.
	struct IconHexSet {
		/// Assets.Images.mainFolder
		var folder: String
		/// Assets.Images.unreadFeed
		var unreadFeed: String
		/// Assets.Images.readFeed
		var readFeed: String
		/// Assets.Images.lastOpenedFeed
		var lastOpenedFeed: String
		/// Assets.Images.unreadCellIndicator
		var unreadCellIndicator: String
		/// Assets.Images.starredFeed / Assets.Images.timelineStar -- folded
		/// in here so star tracks the same per-palette override path as
		/// every other icon slot instead of being the one exception that
		/// stayed pinned to the asset-catalog "starColor".
		var star: String
		/// Assets.Images.todayFeed -- was the hardcoded UIColor.systemOrange
		/// literal before this type existed.
		var today: String
		/// Assets.Images.lovedFeed -- was the hardcoded RSColor.systemRed
		/// literal before this type existed.
		var loved: String
	}

	/// nil for `.default` -- same "fall back to the existing asset-catalog
	/// color / hardcoded literal" contract as `primaryHex`/`secondaryHex`.
	/// Every other case supplies a complete `IconHexSet`; there is no
	/// per-field fallback within a non-default case, the same way
	/// `SurfacePalette.HexSet` has no per-field fallback -- a palette that
	/// wants "everything from .rosePine except the star" is expressed by
	/// copying .rosePine's set and changing one field, not by leaving a
	/// field unset.
	var iconHexSet: IconHexSet? {
		switch self {
		case .default:
			return nil
		case .rosePine:
			return IconHexSet(
				folder: "#3e8fb0", unreadFeed: "#3e8fb0", readFeed: "#9ccfd8",
				lastOpenedFeed: "#3e8fb0", unreadCellIndicator: "#3e8fb0",
				star: "#ebbcba", today: "#eb6f92", loved: "#eb6f92"
			)
		case .sepia:
			return IconHexSet(
				folder: "#b5835a", unreadFeed: "#b5835a", readFeed: "#d4a574",
				lastOpenedFeed: "#b5835a", unreadCellIndicator: "#b5835a",
				star: "#d4a574", today: "#c4703a", loved: "#a8503a"
			)
		case .forest:
			return IconHexSet(
				folder: "#5a8a6b", unreadFeed: "#5a8a6b", readFeed: "#8fb89c",
				lastOpenedFeed: "#5a8a6b", unreadCellIndicator: "#5a8a6b",
				star: "#8fb89c", today: "#b5893a", loved: "#a8503a"
			)
		case .slate:
			return IconHexSet(
				folder: "#5f7a8a", unreadFeed: "#5f7a8a", readFeed: "#8ea3b0",
				lastOpenedFeed: "#5f7a8a", unreadCellIndicator: "#5f7a8a",
				star: "#8ea3b0", today: "#b5893a", loved: "#a8503a"
			)
		case .berry:
			return IconHexSet(
				folder: "#c4507a", unreadFeed: "#c4507a", readFeed: "#eb6f92",
				lastOpenedFeed: "#c4507a", unreadCellIndicator: "#c4507a",
				star: "#eb6f92", today: "#d97f3f", loved: "#c0483f"
			)
		case .ocean:
			return IconHexSet(
				folder: "#2f6690", unreadFeed: "#2f6690", readFeed: "#7ec8e3",
				lastOpenedFeed: "#2f6690", unreadCellIndicator: "#2f6690",
				star: "#7ec8e3", today: "#d97f3f", loved: "#c0483f"
			)
		case .sunset:
			return IconHexSet(
				folder: "#d9622b", unreadFeed: "#d9622b", readFeed: "#f2a65a",
				lastOpenedFeed: "#d9622b", unreadCellIndicator: "#d9622b",
				star: "#f2a65a", today: "#d9622b", loved: "#c0483f"
			)
		case .lavender:
			return IconHexSet(
				folder: "#7c6bab", unreadFeed: "#7c6bab", readFeed: "#b8a9d9",
				lastOpenedFeed: "#7c6bab", unreadCellIndicator: "#7c6bab",
				star: "#b8a9d9", today: "#d97f3f", loved: "#c0483f"
			)
		case .graphite:
			return IconHexSet(
				folder: "#6b6b6b", unreadFeed: "#6b6b6b", readFeed: "#a8a8a8",
				lastOpenedFeed: "#6b6b6b", unreadCellIndicator: "#6b6b6b",
				star: "#a8a8a8", today: "#c4703a", loved: "#a8503a"
			)
		}
	}
}

/// Tints the native-chrome surface colors (bar backgrounds, nav bar, and the
/// vibrant-text tint) as a set, independent of AccentColor -- this affects
/// UIKit chrome backgrounds, never the WKWebView article content, and
/// deliberately stays a separate picker rather than merging into AccentColor's
/// contract (which today only tints icons/progress fill, never backgrounds).
/// Also independent of the light/dark/automatic `UserInterfaceColorPalette`
/// setting: a palette tints chrome colors on top of whichever mode is
/// active, and does not itself force a mode. See docs/nnwtheme-format.md's
/// native-surface-color section for the reasoning.
///
/// Named `SurfacePalette`, not `ColorPalette` -- `UserInterfaceColorPalette`
/// (and its `ColorPaletteTableViewController` / `AppearanceRow.colorPalette`)
/// already exist and mean something unrelated: the light/dark/automatic
/// appearance picker above. This type keeps the `surfaceTint` name at the
/// `AppDefaults.shared` property, `UserDefaults` key, and notification-name
/// level (all unchanged below) purely to avoid a migration -- only the
/// Swift-level type name changes, from `SurfaceTint` to `SurfacePalette`.
///
/// `.default` preserves the existing colorset values unchanged, same contract as
/// AccentColor.default. Started with a single alternative (.slate); grown here
/// to four the same incremental way AccentColor grew from its own starting set,
/// now that there's more than one real design to validate against. `.sepia`,
/// `.forest`, and `.berry` are genuinely new and take the next free raw values
/// after `.slate` (2/3/4) -- same "append, never renumber" contract `.slate`
/// itself already established relative to `.default`.
enum SurfacePalette: Int, CaseIterable, Sendable {
	case `default` = 0
	case slate = 1
	/// Warm parchment tone, aimed at the reading experience specifically --
	/// a paper-like alternative to Slate's cool chrome, using the same
	/// browns/tans a sepia-toned photo or an aged book page would.
	case sepia = 2
	/// Muted, desaturated green -- calmer than Slate's blue-gray without
	/// reading as a literal "forest" hue; the same restrained-saturation
	/// approach Slate takes, just shifted toward green.
	case forest = 3
	/// Soft plum/mauve -- a gentle nod to AO3's own maroon branding without
	/// reproducing it directly; warmer and cozier than Slate or Forest.
	case berry = 4

	var description: String {
		switch self {
		case .default:
			return NSLocalizedString("Default", comment: "Default surface palette")
		case .slate:
			return NSLocalizedString("Slate", comment: "Slate surface palette")
		case .sepia:
			return NSLocalizedString("Sepia", comment: "Sepia surface palette")
		case .forest:
			return NSLocalizedString("Forest", comment: "Forest surface palette")
		case .berry:
			return NSLocalizedString("Berry", comment: "Berry surface palette")
		}
	}

	struct HexSet {
		var barBackground: String
		var fullScreenBackground: String
		var vibrantText: String
		/// Nav bar background, consumed by whichever view/controller installs
		/// a `UINavigationBarAppearance` -- see `ArticleViewController.viewDidLoad()`.
		var navigationBarBackground: String
		/// Nav bar back-button/title tint, paired with `navigationBarBackground`.
		var navigationBarTint: String
		/// Backdrop for settings/list table and collection views -- see
		/// Assets.Colors.settingsBackground(for:)/listBackground(for:).
		var settingsBackground: String
		/// Individual settings-cell fill, distinct from `settingsBackground`
		/// so grouped-card contrast survives palette overrides -- see
		/// Assets.Colors.settingsCellBackground(for:).
		var settingsCellBackground: String
		/// Feed list + timeline backdrop -- see Assets.Colors.listBackground(for:).
		var listBackground: String
	}

	/// nil for `.default` -- same "fall back to the asset catalog" contract as
	/// AccentColor.primaryHex/secondaryHex.
	var lightHexSet: HexSet? {
		switch self {
		case .default: return nil
		case .slate:
			return HexSet(
				barBackground: "#E4E7EB",
				fullScreenBackground: "#1C2128",
				vibrantText: "#F5F6F8",
				navigationBarBackground: "#E4E7EB",
				navigationBarTint: "#20242B",
				settingsBackground: "#DADFE6",
				settingsCellBackground: "#F0F2F5",
				listBackground: "#DADFE6"
			)
		case .sepia:
			return HexSet(
				barBackground: "#EDE4D3",
				fullScreenBackground: "#2B2318",
				vibrantText: "#FBF6EC",
				navigationBarBackground: "#EDE4D3",
				navigationBarTint: "#3A2E1D",
				settingsBackground: "#E3D7BF",
				settingsCellBackground: "#F7EFDE",
				listBackground: "#E3D7BF"
			)
		case .forest:
			return HexSet(
				barBackground: "#E2E8DE",
				fullScreenBackground: "#1A2420",
				vibrantText: "#F2F7EE",
				navigationBarBackground: "#E2E8DE",
				navigationBarTint: "#22301F",
				settingsBackground: "#D6E0D1",
				settingsCellBackground: "#EEF3EA",
				listBackground: "#D6E0D1"
			)
		case .berry:
			return HexSet(
				barBackground: "#EDE1E6",
				fullScreenBackground: "#241620",
				vibrantText: "#F8EEF3",
				navigationBarBackground: "#EDE1E6",
				navigationBarTint: "#3D2030",
				settingsBackground: "#E2D2DA",
				settingsCellBackground: "#F5EAEF",
				listBackground: "#E2D2DA"
			)
		}
	}

	var darkHexSet: HexSet? {
		switch self {
		case .default: return nil
		case .slate:
			return HexSet(
				barBackground: "#20242B",
				fullScreenBackground: "#0B0D10",
				vibrantText: "#F5F6F8",
				navigationBarBackground: "#20242B",
				navigationBarTint: "#F5F6F8",
				settingsBackground: "#16191E",
				settingsCellBackground: "#262B33",
				listBackground: "#16191E"
			)
		case .sepia:
			return HexSet(
				barBackground: "#2B2318",
				fullScreenBackground: "#150F09",
				vibrantText: "#FBF6EC",
				navigationBarBackground: "#2B2318",
				navigationBarTint: "#F3E7CE",
				settingsBackground: "#1E1810",
				settingsCellBackground: "#332A1D",
				listBackground: "#1E1810"
			)
		case .forest:
			return HexSet(
				barBackground: "#22301F",
				fullScreenBackground: "#0D1310",
				vibrantText: "#F2F7EE",
				navigationBarBackground: "#22301F",
				navigationBarTint: "#EAF1E5",
				settingsBackground: "#162014",
				settingsCellBackground: "#26331F",
				listBackground: "#162014"
			)
		case .berry:
			return HexSet(
				barBackground: "#3D2030",
				fullScreenBackground: "#150B12",
				vibrantText: "#F8EEF3",
				navigationBarBackground: "#3D2030",
				navigationBarTint: "#F3E2EA",
				settingsBackground: "#1E1119",
				settingsCellBackground: "#32202A",
				listBackground: "#1E1119"
			)
		}
	}
}

/// Replaces the old boolean `useTintedNavigationBar` with three
/// mutually-exclusive states, applied to both the article reader's top nav
/// bar and bottom toolbar together -- see `SurfacePaletteNavigationBarAware`
/// and `app-chrome-palette.md`. `system` takes the place of the old `false`
/// (plain system appearance, both bars translucent); `tinted` takes the
/// place of the old `true` (both bars filled from the active Surface
/// Palette's `navigationBarBackground`/`navigationBarTint`); `blend` is new
/// (both bars filled with the article's own resolved background color, via
/// `ArticleResolvedColors.current(isDark:)`). Named `system` rather than
/// `default` because `default` collides with Swift's `switch`/`case`
/// keyword in every exhaustive switch over this type.
enum ToolbarStyle: String, CaseIterable, Sendable {
	case system
	case blend
	case tinted

	var description: String {
		switch self {
		case .system:
			return NSLocalizedString("Default", comment: "Default toolbar style")
		case .blend:
			return NSLocalizedString("Blend", comment: "Blend toolbar style")
		case .tinted:
			return NSLocalizedString("Tinted", comment: "Tinted toolbar style")
		}
	}
}

enum PageCounterDisplayMode: String, CaseIterable, Sendable {
	case off
	case percentage
	case pageCount
}

/// Which buttons appear in the article reader's top toolbar, alongside
/// the theme button -- see ArticleViewController.rightBarButtonItems()
/// and ArticleToolbarCustomizerViewController. Each case is an
/// independent on/off switch (AppDefaults.articleToolbarShowTheme/
/// ShowTableOfContents/ShowFind/ShowPrevNext/ShowLock), freely
/// combinable, rather than a single mutually-exclusive picker -- see
/// AppDefaults.migrateArticleToolbarTogglesIfNeeded() for the one-time
/// migration off the older showTableOfContentsAndFind/
/// showPrevNextArticleButtons pair. lock has no legacy switch to migrate
/// from (like theme), so it just keeps its registered default below.
enum ArticleToolbarToggle: CaseIterable, Sendable {
	case theme
	case tableOfContents
	case find
	case prevNext
	case lock
	case annotations
}

/// How a new highlight can be created from a text selection in an
/// article -- a mutually-exclusive picker (unlike ArticleToolbarToggle
/// above), not two independent booleans, since "both on at once" isn't a
/// supported combination. Read fresh (not cached) by
/// WebViewController.initAnnotations() on every navigation, same
/// "reasserted on every dequeue" convention this file already uses for
/// showArticleScrollbar/pinchGestureRecognizer.isEnabled on the pooled
/// PreloadedWebView -- a change here takes effect the next time an
/// article is (re)loaded, not instantly for whatever's on screen.
enum AnnotationCreationMethod: String, CaseIterable, Sendable {
	/// HighlightColorPopover: a small floating color-swatch popup shown
	/// near the selection.
	case popup
	/// A "Highlight" item injected into WKWebView's own native
	/// text-selection menu -- see PreloadedWebView.buildMenu(with:).
	case nativeMenu
	/// Neither -- selecting text does nothing. Existing highlights
	/// remain fully viewable/editable via the annotations list and by
	/// tapping an existing <mark>.
	case off
}

extension Notification.Name {
	public static let userInterfaceColorPaletteDidUpdate = Notification.Name("UserInterfaceColorPaletteDidUpdateNotification")
	public static let timelineIconSizeDidChange = Notification.Name("TimelineIconSizeDidChangeNotification")
	public static let timelineNumberOfLinesDidChange = Notification.Name("TimelineNumberOfLinesDidChangeNotification")
	public static let timelineTagDisplayModeDidChange = Notification.Name("TimelineTagDisplayModeDidChangeNotification")
	public static let badgeColorModeDidChange = Notification.Name("BadgeColorModeDidChangeNotification")
	public static let accentColorDidChange = Notification.Name("AccentColorDidChangeNotification")
	public static let surfaceTintDidChange = Notification.Name("SurfaceTintDidChangeNotification")
	public static let statsVisibilityDidChange = Notification.Name("StatsVisibilityDidChangeNotification")
	public static let articleThemeOverridesDidChange = Notification.Name("ArticleThemeOverridesDidChangeNotification")
}

final class AppDefaults: Sendable {
	static let shared = AppDefaults()
	static let defaultThemeName = "Default"
	fileprivate static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDefaults")

	private init() {}

	nonisolated(unsafe) static let store: UserDefaults = .standard

	struct Key {
		static let userInterfaceColorPalette = "userInterfaceColorPalette"
		static let lastImageCacheFlushDate = "lastImageCacheFlushDate"
		static let firstRunDate = "firstRunDate"
		static let hasShownAO3Onboarding = "hasShownAO3Onboarding"
		/// Unused as of toolbarStyle's introduction -- kept only so the
		/// now-dead migrateNavigationBarTintingDefaultIfNeeded() history
		/// (removed) is still legible from an old value on-disk. See
		/// hasMigratedToolbarStyleDefault below for the current migration's
		/// own gate.
		static let hasMigratedNavigationBarTintingDefault = "hasMigratedNavigationBarTintingDefault"
		static let hasMigratedToolbarStyleDefault = "hasMigratedToolbarStyleDefault"
		static let hasMigratedArticleToolbarToggles = "hasMigratedArticleToolbarToggles"
		static let timelineGroupByFeed = "timelineGroupByFeed"
		static let refreshClearsReadArticles = "refreshClearsReadArticles"
		static let timelineNumberOfLines = "timelineNumberOfLines"
		static let timelineIconDimension = "timelineIconSize"
		static let timelineTagDisplayMode = "timelineTagDisplayMode"
		static let badgeColorMode = "badgeColorMode"
		static let accentColor = "accentColor"
		static let surfaceTint = "surfaceTint"
		/// Legacy Bool key, no longer backed by a live property -- read
		/// directly via AppDefaults.store by migrateToolbarStyleDefaultIfNeeded()
		/// only, to carry an upgrader's prior tinted/not-tinted choice onto
		/// the new toolbarStyle key below. Do not reintroduce a property for
		/// this key.
		static let useTintedNavigationBar = "useTintedNavigationBar"
		static let toolbarStyle = "toolbarStyle"
		static let statsVisible = "statsVisible"
		static let timelineSortDirection = "timelineSortDirection"
		static let timelineSortField = "timelineSortField"
		static let articleFullscreenAvailable = "articleFullscreenAvailable"
		static let articleFullscreenEnabled = "articleFullscreenEnabled"
		static let articleBackSwipeEnabled = "articleBackSwipeEnabled"
		static let articlePagingSwipeEnabled = "articlePagingSwipeEnabled"
		static let showFeedNameInReaderView = "showFeedNameInReaderView"
		static let showPrevNextArticleButtons = "showPrevNextArticleButtons"
		static let showTableOfContentsAndFind = "showTableOfContentsAndFind"
		static let articleToolbarShowTheme = "articleToolbarShowTheme"
		static let articleToolbarShowTableOfContents = "articleToolbarShowTableOfContents"
		static let articleToolbarShowFind = "articleToolbarShowFind"
		static let articleToolbarShowPrevNext = "articleToolbarShowPrevNext"
		static let articleToolbarShowLock = "articleToolbarShowLock"
		static let articleToolbarShowAnnotations = "articleToolbarShowAnnotations"
		static let defaultAnnotationColor = "defaultAnnotationColor"
		static let annotationCreationMethod = "annotationCreationMethod"
		static let hideNotchInFullScreen = "hideNotchInFullScreen"
		static let pageCounterDisplayMode = "pageCounterDisplayMode"
		static let disableArticleLinks = "disableArticleLinks"
		static let showArticleScrollbar = "showArticleScrollbar"
		static let showLastUpdatedLabel = "showLastUpdatedLabel"
		static let articleThemeOverrides = "articleThemeOverrides"
		static let lastRefresh = "lastRefresh"
		static let addFeedAccountID = "addFeedAccountID"
		static let addFeedFolderName = "addFeedFolderName"
		static let addFolderAccountID = "addFolderAccountID"
		static let useSystemBrowser = "useSystemBrowser"
		static let currentThemeName = "currentThemeName"
		static let hideReadFeeds = "hideReadFeeds"
		static let expandedContainers = "expandedContainers"
		static let smartFeedsHidingReadArticles = "smartFeedsHidingReadArticles"
		static let feedsHidingReadArticles = "feedsHidingReadArticles"
		static let foldersShowingReadArticles = "foldersShowingReadArticles"
		static let selectedSidebarItem = "selectedSidebarItem"
		static let selectedArticle = "selectedArticle"
		static let didMigrateLegacyStateRestorationInfo = "didMigrateLegacyStateRestorationInfo"
		static let splitViewPreferredDisplayMode = "splitViewPreferredDisplayMode"
	}

	let isDeveloperBuild: Bool = {
		if let dev = Bundle.main.object(forInfoDictionaryKey: "DeveloperEntitlements") as? String, dev == "-dev" {
			return true
		}
		return false
	}()

	let isFirstRun: Bool = {
		if AppDefaults.store.object(forKey: Key.firstRunDate) is Date {
			return false
		}
		firstRunDate = Date()
		return true
	}()

	static var userInterfaceColorPalette: UserInterfaceColorPalette {
		get {
			if let result = UserInterfaceColorPalette(rawValue: int(for: Key.userInterfaceColorPalette)) {
				return result
			}
			return .automatic
		}
		set {
			setInt(for: Key.userInterfaceColorPalette, newValue.rawValue)
			NotificationCenter.default.post(name: .userInterfaceColorPaletteDidUpdate, object: self)
		}
	}

	var addFeedAccountID: String? {
		get {
			return AppDefaults.string(for: Key.addFeedAccountID)
		}
		set {
			AppDefaults.setString(for: Key.addFeedAccountID, newValue)
		}
	}

	var addFeedFolderName: String? {
		get {
			return AppDefaults.string(for: Key.addFeedFolderName)
		}
		set {
			AppDefaults.setString(for: Key.addFeedFolderName, newValue)
		}
	}

	var addFolderAccountID: String? {
		get {
			return AppDefaults.string(for: Key.addFolderAccountID)
		}
		set {
			AppDefaults.setString(for: Key.addFolderAccountID, newValue)
		}
	}

	var useSystemBrowser: Bool {
		get {
			return UserDefaults.standard.bool(forKey: Key.useSystemBrowser)
		}
		set {
			UserDefaults.standard.setValue(newValue, forKey: Key.useSystemBrowser)
		}
	}

	var lastImageCacheFlushDate: Date? {
		get {
			return AppDefaults.date(for: Key.lastImageCacheFlushDate)
		}
		set {
			AppDefaults.setDate(for: Key.lastImageCacheFlushDate, newValue)
		}
	}

	var timelineGroupByFeed: Bool {
		get {
			return AppDefaults.bool(for: Key.timelineGroupByFeed)
		}
		set {
			AppDefaults.setBool(for: Key.timelineGroupByFeed, newValue)
		}
	}

	var refreshClearsReadArticles: Bool {
		get {
			return AppDefaults.bool(for: Key.refreshClearsReadArticles)
		}
		set {
			AppDefaults.setBool(for: Key.refreshClearsReadArticles, newValue)
		}
	}

	var timelineSortDirection: ComparisonResult {
		get {
			return AppDefaults.sortDirection(for: Key.timelineSortDirection)
		}
		set {
			AppDefaults.setSortDirection(for: Key.timelineSortDirection, newValue)
		}
	}

	var timelineSortField: ArticleSorter.SortField {
		get {
			let rawValue = AppDefaults.int(for: Key.timelineSortField)
			return ArticleSorter.SortField(rawValue: rawValue) ?? .date
		}
		set {
			AppDefaults.setInt(for: Key.timelineSortField, newValue.rawValue)
		}
	}

	var articleFullscreenAvailable: Bool {
		get {
			return AppDefaults.bool(for: Key.articleFullscreenAvailable)
		}
		set {
			AppDefaults.setBool(for: Key.articleFullscreenAvailable, newValue)
		}
	}

	var articleFullscreenEnabled: Bool {
		get {
			return articleFullscreenAvailable && AppDefaults.bool(for: Key.articleFullscreenEnabled)
		}
		set {
			AppDefaults.setBool(for: Key.articleFullscreenEnabled, newValue)
		}
	}

	var logicalArticleFullscreenEnabled: Bool {
		articleFullscreenAvailable && articleFullscreenEnabled
	}

	/// Controls the article view's edge-swipe-back-to-timeline gesture (the
	/// standard interactive pop gesture). Independent of fullscreen state.
	/// Default: true.
	var articleBackSwipeEnabled: Bool {
		get {
			return AppDefaults.bool(for: Key.articleBackSwipeEnabled)
		}
		set {
			AppDefaults.setBool(for: Key.articleBackSwipeEnabled, newValue)
		}
	}

	/// Controls the article view's swipe-to-next/previous-article gesture
	/// (paging on ArticleViewController's UIPageViewController). Independent
	/// of fullscreen state. Default: true.
	var articlePagingSwipeEnabled: Bool {
		get {
			return AppDefaults.bool(for: Key.articlePagingSwipeEnabled)
		}
		set {
			AppDefaults.setBool(for: Key.articlePagingSwipeEnabled, newValue)
		}
	}

	/// Off by default: a book's feed name becomes ambiguous once smart-feed
	/// deduplication can surface it from more than one feed (see
	/// SmartFeedArticleGrouping), so the reader view hides it by default
	/// rather than showing only one of several feeds it happens to belong to.
	/// When turned on, ArticleRenderer shows the single feed name for
	/// articles opened from a real feed, or every feed a book appeared in
	/// (comma-separated) for articles opened from a smart feed where it was
	/// deduplicated across more than one.
	var showFeedNameInReaderView: Bool {
		get {
			return AppDefaults.bool(for: Key.showFeedNameInReaderView)
		}
		set {
			AppDefaults.setBool(for: Key.showFeedNameInReaderView, newValue)
		}
	}

	/// Whether the reader view toolbar shows the previous/next article buttons.
	///
	/// Retained read/write for migrateArticleToolbarTogglesIfNeeded() and
	/// for anyone who still has this key on disk; ArticleViewController and
	/// SettingsViewController no longer read this directly --
	/// articleToolbarShowPrevNext below is the source of truth.
	var showPrevNextArticleButtons: Bool {
		get {
			return AppDefaults.bool(for: Key.showPrevNextArticleButtons)
		}
		set {
			AppDefaults.setBool(for: Key.showPrevNextArticleButtons, newValue)
		}
	}

	/// Whether the reader view toolbar shows Table of Contents/Find buttons.
	///
	/// Retained read/write for migrateArticleToolbarTogglesIfNeeded() and
	/// for anyone who still has this key on disk; ArticleViewController and
	/// SettingsViewController no longer read this directly --
	/// articleToolbarShowTableOfContents/articleToolbarShowFind below are
	/// the source of truth.
	var showTableOfContentsAndFind: Bool {
		get {
			return AppDefaults.bool(for: Key.showTableOfContentsAndFind)
		}
		set {
			AppDefaults.setBool(for: Key.showTableOfContentsAndFind, newValue)
		}
	}

	/// Whether the theme button appears in the article reader's top
	/// toolbar. Defaults to true, matching the button's former
	/// unconditional presence before this became a setting.
	var articleToolbarShowTheme: Bool {
		get {
			return AppDefaults.bool(for: Key.articleToolbarShowTheme)
		}
		set {
			AppDefaults.setBool(for: Key.articleToolbarShowTheme, newValue)
		}
	}

	/// Whether the table-of-contents button appears in the article
	/// reader's top toolbar. Defaults to true, matching the legacy
	/// showTableOfContentsAndFind registered default.
	var articleToolbarShowTableOfContents: Bool {
		get {
			return AppDefaults.bool(for: Key.articleToolbarShowTableOfContents)
		}
		set {
			AppDefaults.setBool(for: Key.articleToolbarShowTableOfContents, newValue)
		}
	}

	/// Whether the find-in-article button appears in the article reader's
	/// top toolbar. Defaults to true, matching the legacy
	/// showTableOfContentsAndFind registered default.
	var articleToolbarShowFind: Bool {
		get {
			return AppDefaults.bool(for: Key.articleToolbarShowFind)
		}
		set {
			AppDefaults.setBool(for: Key.articleToolbarShowFind, newValue)
		}
	}

	/// Whether the previous/next article buttons appear in the article
	/// reader's top toolbar. Defaults to false, matching the legacy
	/// showPrevNextArticleButtons registered default.
	var articleToolbarShowPrevNext: Bool {
		get {
			return AppDefaults.bool(for: Key.articleToolbarShowPrevNext)
		}
		set {
			AppDefaults.setBool(for: Key.articleToolbarShowPrevNext, newValue)
		}
	}

	/// Whether the temporary gesture-lock button appears in the article
	/// reader's top toolbar. Off by default -- this is an opt-in extra,
	/// not something everyone needs cluttering the bar. See
	/// ArticleViewController.lockBarButtonItem/toggleGesturesLocked(_:)
	/// and SceneCoordinator.isArticleGesturesLocked for the lock itself,
	/// which is a transient, in-memory, per-session state -- unlike this
	/// property, it is deliberately not backed by AppDefaults/UserDefaults.
	var articleToolbarShowLock: Bool {
		get {
			return AppDefaults.bool(for: Key.articleToolbarShowLock)
		}
		set {
			AppDefaults.setBool(for: Key.articleToolbarShowLock, newValue)
		}
	}

	/// Off by default, same reasoning as articleToolbarShowLock just above:
	/// this is an opt-in extra, not something everyone needs cluttering the
	/// bar. See WebViewController's annotations extension for the feature
	/// this button surfaces.
	var articleToolbarShowAnnotations: Bool {
		get {
			return AppDefaults.bool(for: Key.articleToolbarShowAnnotations)
		}
		set {
			AppDefaults.setBool(for: Key.articleToolbarShowAnnotations, newValue)
		}
	}

	/// The color HighlightColorPopover's note-icon path (which creates a
	/// highlight without the person picking a color) falls back to, and
	/// the starting selection in the annotations toolbar menu's "Default
	/// Highlight Color" submenu below. Yellow, matching
	/// HighlightColorPopover/AnnotationEditorView's own fallback default.
	var defaultAnnotationColor: Annotation.Color {
		get {
			guard let rawValue = AppDefaults.string(for: Key.defaultAnnotationColor),
				  let color = Annotation.Color(rawValue: rawValue) else {
				return .yellow
			}
			return color
		}
		set {
			AppDefaults.setString(for: Key.defaultAnnotationColor, newValue.rawValue)
		}
	}

	/// How a new highlight gets created from a text selection --
	/// HighlightColorPopover.swift (popup), a native-menu "Highlight"
	/// item (PreloadedWebView.buildMenu(with:)), or neither. Popup is
	/// the default, matching this feature's original (only) behavior
	/// before this setting existed.
	var annotationCreationMethod: AnnotationCreationMethod {
		get {
			guard let rawValue = AppDefaults.string(for: Key.annotationCreationMethod),
				  let method = AnnotationCreationMethod(rawValue: rawValue) else {
				return .popup
			}
			return method
		}
		set {
			AppDefaults.setString(for: Key.annotationCreationMethod, newValue.rawValue)
		}
	}

	/// Single dispatch point over the six articleToolbarShowX properties,
	/// keyed by ArticleToolbarToggle case -- used anywhere the toggles
	/// need to be read or written generically (ArticleToolbarCustomizerViewController's
	/// row loop, SettingsViewController's summary label) instead of via a
	/// six-way switch at each call site.
	func isArticleToolbarToggleEnabled(_ toggle: ArticleToolbarToggle) -> Bool {
		switch toggle {
		case .theme: return articleToolbarShowTheme
		case .tableOfContents: return articleToolbarShowTableOfContents
		case .find: return articleToolbarShowFind
		case .prevNext: return articleToolbarShowPrevNext
		case .lock: return articleToolbarShowLock
		case .annotations: return articleToolbarShowAnnotations
		}
	}

	func setArticleToolbarToggleEnabled(_ toggle: ArticleToolbarToggle, _ enabled: Bool) {
		switch toggle {
		case .theme: articleToolbarShowTheme = enabled
		case .tableOfContents: articleToolbarShowTableOfContents = enabled
		case .find: articleToolbarShowFind = enabled
		case .prevNext: articleToolbarShowPrevNext = enabled
		case .lock: articleToolbarShowLock = enabled
		case .annotations: articleToolbarShowAnnotations = enabled
		}
	}

	/// Whether the notch/Dynamic Island area is masked (solid black) while in
	/// fullscreen reading mode, instead of showing through as normal. Exposed
	/// as its own toggle -- independent of the page counter below -- for
	/// people who want the notch hidden but don't care about the counter.
	/// The page counter turning on also hides the notch (see
	/// WebViewController.updateNotchAndPageCounterVisibility()) without
	/// requiring this setting to also be switched on: showing a page counter
	/// in a space that still displays the notch would look broken.
	var hideNotchInFullScreen: Bool {
		get {
			return AppDefaults.bool(for: Key.hideNotchInFullScreen)
		}
		set {
			AppDefaults.setBool(for: Key.hideNotchInFullScreen, newValue)
		}
	}

	/// Page counter shown in the notch's leading side space while in
	/// fullscreen reading mode. Off by default; when on, implies hiding the
	/// notch regardless of hideNotchInFullScreen's own value (see above).
	var pageCounterDisplayMode: PageCounterDisplayMode {
		get {
			guard let rawValue = AppDefaults.string(for: Key.pageCounterDisplayMode),
				  let mode = PageCounterDisplayMode(rawValue: rawValue) else {
				return .off
			}
			return mode
		}
		set {
			AppDefaults.setString(for: Key.pageCounterDisplayMode, newValue.rawValue)
		}
	}

	/// When on, tapping any link in the article body (including target=_blank
	/// links) is suppressed entirely rather than navigating anywhere. Off by
	/// default, since it changes existing behavior.
	var disableArticleLinks: Bool {
		get {
			return AppDefaults.bool(for: Key.disableArticleLinks)
		}
		set {
			AppDefaults.setBool(for: Key.disableArticleLinks, newValue)
		}
	}

	/// Whether the article web view shows its native vertical scroll
	/// indicator. On by default (via registerDefaults), preserving the
	/// system's normal scrollbar behavior.
	var showArticleScrollbar: Bool {
		get {
			return AppDefaults.bool(for: Key.showArticleScrollbar)
		}
		set {
			AppDefaults.setBool(for: Key.showArticleScrollbar, newValue)
		}
	}

	/// The "Updated X ago" / "Updated Just Now" label shown under the feed
	/// list while idle. On by default, preserving current behavior.
	var showLastUpdatedLabel: Bool {
		get {
			return AppDefaults.bool(for: Key.showLastUpdatedLabel)
		}
		set {
			AppDefaults.setBool(for: Key.showLastUpdatedLabel, newValue)
		}
	}

	/// Whether the AO3 first-run onboarding screen (shown once, only when
	/// the local account has zero subscribed feeds) has already been shown.
	/// Off by default; set once the screen is dismissed (by either action)
	/// so it never shows again regardless of the account's feed count
	/// afterward. See MainFeedCollectionViewController.presentAO3OnboardingIfNeeded().
	var hasShownAO3Onboarding: Bool {
		get {
			return AppDefaults.bool(for: Key.hasShownAO3Onboarding)
		}
		set {
			AppDefaults.setBool(for: Key.hasShownAO3Onboarding, newValue)
		}
	}

	/// layered on top of whichever theme (default or imported) is active. See
	/// ArticleThemeOverrides.cssOverrideBlock and ArticleRenderer.styleString().
	var articleThemeOverrides: ArticleThemeOverrides {
		get {
			guard let json = AppDefaults.string(for: Key.articleThemeOverrides),
				  let data = json.data(using: .utf8),
				  let decoded = try? JSONDecoder().decode(ArticleThemeOverrides.self, from: data) else {
				return ArticleThemeOverrides()
			}
			return decoded
		}
		set {
			if let data = try? JSONEncoder().encode(newValue), let json = String(data: data, encoding: .utf8) {
				AppDefaults.setString(for: Key.articleThemeOverrides, json)
			}
			NotificationCenter.default.post(name: .articleThemeOverridesDidChange, object: self)
		}
	}

	var splitViewPreferredDisplayMode: Int {
		get {
			return AppDefaults.int(for: Key.splitViewPreferredDisplayMode)
		}
		set {
			AppDefaults.setInt(for: Key.splitViewPreferredDisplayMode, newValue)
		}
	}

	var lastRefresh: Date? {
		get {
			return AppDefaults.date(for: Key.lastRefresh)
		}
		set {
			AppDefaults.setDate(for: Key.lastRefresh, newValue)
		}
	}

	var timelineNumberOfLines: Int {
		get {
			return AppDefaults.int(for: Key.timelineNumberOfLines)
		}
		set {
			AppDefaults.setInt(for: Key.timelineNumberOfLines, newValue)
			NotificationCenter.default.post(name: .timelineNumberOfLinesDidChange, object: nil)
		}
	}

	var timelineIconSize: IconSize {
		get {
			let rawValue = AppDefaults.store.integer(forKey: Key.timelineIconDimension)
			return IconSize(rawValue: rawValue) ?? IconSize.medium
		}
		set {
			AppDefaults.store.set(newValue.rawValue, forKey: Key.timelineIconDimension)
			NotificationCenter.default.post(name: .timelineIconSizeDidChange, object: nil)
		}
	}

	var timelineTagDisplayMode: TagDisplayMode {
		get {
			let rawValue = AppDefaults.store.integer(forKey: Key.timelineTagDisplayMode)
			return TagDisplayMode(rawValue: rawValue) ?? .compact
		}
		set {
			AppDefaults.store.set(newValue.rawValue, forKey: Key.timelineTagDisplayMode)
			NotificationCenter.default.post(name: .timelineTagDisplayModeDidChange, object: nil)
		}
	}

	var badgeColorMode: BadgeColorPalette {
		get {
			let rawValue = AppDefaults.store.integer(forKey: Key.badgeColorMode)
			return BadgeColorPalette(rawValue: rawValue) ?? .monochrome
		}
		set {
			AppDefaults.store.set(newValue.rawValue, forKey: Key.badgeColorMode)
			NotificationCenter.default.post(name: .badgeColorModeDidChange, object: nil)
		}
	}

	var accentColor: AccentColor {
		get {
			let rawValue = AppDefaults.store.integer(forKey: Key.accentColor)
			return AccentColor(rawValue: rawValue) ?? .default
		}
		set {
			AppDefaults.store.set(newValue.rawValue, forKey: Key.accentColor)
			NotificationCenter.default.post(name: .accentColorDidChange, object: nil)
		}
	}

	var surfaceTint: SurfacePalette {
		get {
			let rawValue = AppDefaults.store.integer(forKey: Key.surfaceTint)
			return SurfacePalette(rawValue: rawValue) ?? .default
		}
		set {
			AppDefaults.store.set(newValue.rawValue, forKey: Key.surfaceTint)
			NotificationCenter.default.post(name: .surfaceTintDidChange, object: nil)
		}
	}

	/// Which of the three ToolbarStyle states the article reader's top nav
	/// bar and bottom toolbar render in -- see ToolbarStyle and
	/// SurfacePaletteNavigationBarAware. Default `.system`: a fresh install
	/// gets the bottom toolbar's simpler, always-correct plain-system
	/// behavior for both bars. Existing installs on a non-.default palette
	/// with the old useTintedNavigationBar on are migrated to `.tinted` once
	/// at launch -- see migrateToolbarStyleDefaultIfNeeded() below -- so this
	/// default doesn't silently strip an already-chosen palette's most
	/// visible chrome on upgrade.
	var toolbarStyle: ToolbarStyle {
		get {
			guard let rawValue = AppDefaults.string(for: Key.toolbarStyle),
				  let style = ToolbarStyle(rawValue: rawValue) else {
				return .system
			}
			return style
		}
		set {
			AppDefaults.setString(for: Key.toolbarStyle, newValue.rawValue)
			NotificationCenter.default.post(name: .surfaceTintDidChange, object: nil)
		}
	}

	/// Personalization plan item 6 ("Stats-visibility toggles"): one shared
	/// boolean consumed by both `MainTimelineCellData` (list) and
	/// `AO3PrefaceRenderer`/`ao3SyntheticPrefaceHTML` (reader), since both
	/// already route the same Ambrosia-derived fields (word count,
	/// completion, fandoms, ratings, warnings) through one shared
	/// row-building path. Default `true` -- today's behavior, unchanged
	/// until someone opts out.
	var statsVisible: Bool {
		get {
			return AppDefaults.bool(for: Key.statsVisible)
		}
		set {
			AppDefaults.setBool(for: Key.statsVisible, newValue)
			NotificationCenter.default.post(name: .statsVisibilityDidChange, object: nil)
		}
	}

	var currentThemeName: String? {
		get {
			return AppDefaults.string(for: Key.currentThemeName)
		}
		set {
			AppDefaults.setString(for: Key.currentThemeName, newValue)
		}
	}

	var hideReadFeeds: Bool {
		get {
			UserDefaults.standard.bool(forKey: Key.hideReadFeeds)
		}
		set {
			UserDefaults.standard.set(newValue, forKey: Key.hideReadFeeds)
		}
	}

	var expandedContainers: Set<ContainerIdentifier> {
		get {
			guard let rawIdentifiers = UserDefaults.standard.array(forKey: Key.expandedContainers) as? [[String: String]] else {
				return Set<ContainerIdentifier>()
			}
			let containerIdentifiers = rawIdentifiers.compactMap { ContainerIdentifier(userInfo: $0) }
			return Set(containerIdentifiers)
		}
		set {
			Self.logger.debug("AppDefaults: set expandedContainers: \(newValue)")
			let containerIdentifierUserInfos = newValue.compactMap { $0.userInfo }
			UserDefaults.standard.set(containerIdentifierUserInfos, forKey: Key.expandedContainers)
		}
	}

	var smartFeedsHidingReadArticles: Set<String> {
		get {
			let smartFeedIDs = UserDefaults.standard.array(forKey: Key.smartFeedsHidingReadArticles) as? [String] ?? []
			return Set(smartFeedIDs)
		}
		set {
			let array = Array(newValue)
			UserDefaults.standard.set(array, forKey: Key.smartFeedsHidingReadArticles)
		}
	}

	var feedsHidingReadArticles: [String: Set<String>] { // Account id: Set<feed.feedID>
		get {
			guard let d = UserDefaults.standard.dictionary(forKey: Key.feedsHidingReadArticles) as? [String: [String]] else {
				return [String: Set<String>]()
			}
			return d.mapValues { Set($0) }
		}
		set {
			let d = newValue.mapValues { Array($0) }
			UserDefaults.standard.set(d, forKey: Key.feedsHidingReadArticles)
		}
	}

	var foldersShowingReadArticles: [String: Set<String>] { // Account id: Set<folder.nameForDisplay>
		get {
			guard let d = UserDefaults.standard.dictionary(forKey: Key.foldersShowingReadArticles) as? [String: [String]] else {
				return [String: Set<String>]()
			}
			return d.mapValues { Set($0) }
		}
		set {
			let d = newValue.mapValues { Array($0) }
			UserDefaults.standard.set(d, forKey: Key.foldersShowingReadArticles)
		}
	}

	var selectedSidebarItem: SidebarItemIdentifier? {
		get {
			guard let userInfo = UserDefaults.standard.dictionary(forKey: Key.selectedSidebarItem) as? [String: String] else {
				return nil
			}
			return SidebarItemIdentifier(userInfo: userInfo)
		}
		set {
			guard let newValue else {
				UserDefaults.standard.removeObject(forKey: Key.selectedSidebarItem)
				return
			}
			UserDefaults.standard.set(newValue.userInfo, forKey: Key.selectedSidebarItem)
		}
	}

	var selectedArticle: ArticleSpecifier? {
		get {
			guard let d = UserDefaults.standard.dictionary(forKey: Key.selectedArticle) as? [String: String] else {
				return nil
			}
			return ArticleSpecifier(dictionary: d)
		}
		set {
			guard let newValue else {
				UserDefaults.standard.removeObject(forKey: Key.selectedArticle)
				return
			}
			UserDefaults.standard.set(newValue.dictionary, forKey: Key.selectedArticle)
		}
	}

	var didMigrateLegacyStateRestorationInfo: Bool {
		get {
			UserDefaults.standard.bool(forKey: Key.didMigrateLegacyStateRestorationInfo)
		}
		set {
			UserDefaults.standard.set(newValue, forKey: Key.didMigrateLegacyStateRestorationInfo)
		}
	}

	/// One-shot: ports an upgrader's prior tinted-bar choice onto the new
	/// three-state toolbarStyle, so shipping toolbarStyle's .system default
	/// doesn't read as a regression for anyone who'd already turned tinting
	/// on. Two cases, checked in order:
	///   1. The old useTintedNavigationBar Bool key is true (a real prior
	///      install that had the switch on, whether the person set it
	///      themselves or case 2 below already set it for them on an
	///      earlier launch) -> toolbarStyle = .tinted.
	///   2. useTintedNavigationBar is absent/false, but surfaceTint is
	///      already non-.default -- the same "predates this setting
	///      entirely" case the original migrateNavigationBarTintingDefaultIfNeeded()
	///      handled, preserved here so an install upgrading directly from
	///      before useTintedNavigationBar existed still lands on .tinted
	///      instead of silently losing its palette's most visible chrome.
	/// Otherwise toolbarStyle keeps its registered .system default, so no
	/// write happens. Call once at launch, after registerDefaults(). Writes
	/// directly via AppDefaults.store rather than the toolbarStyle property
	/// setter, to avoid posting .surfaceTintDidChange to a view hierarchy
	/// that doesn't exist yet this early in launch. Gated by its own flag
	/// (hasMigratedToolbarStyleDefault), separate from the now-unused
	/// hasMigratedNavigationBarTintingDefault, since an install that already
	/// ran that older migration still needs this one to actually populate
	/// toolbarStyle.
	@MainActor func migrateToolbarStyleDefaultIfNeeded() {
		guard !AppDefaults.bool(for: Key.hasMigratedToolbarStyleDefault) else { return }
		AppDefaults.setBool(for: Key.hasMigratedToolbarStyleDefault, true)
		guard AppDefaults.bool(for: Key.useTintedNavigationBar) || surfaceTint != .default else { return }
		AppDefaults.setString(for: Key.toolbarStyle, ToolbarStyle.tinted.rawValue)
	}

	/// One-time migration off the two independent showTableOfContentsAndFind/
	/// showPrevNextArticleButtons switches onto the four independent
	/// articleToolbarShowTheme/ShowTableOfContents/ShowFind/ShowPrevNext
	/// toggles (ArticleToolbarCustomizerViewController). The legacy pair
	/// maps directly, since each was already tracking a single concept
	/// that's now split into its own toggle: showTableOfContentsAndFind
	/// becomes both articleToolbarShowTableOfContents and
	/// articleToolbarShowFind, and showPrevNextArticleButtons becomes
	/// articleToolbarShowPrevNext. The theme button had no legacy switch
	/// (it was always present), so articleToolbarShowTheme just keeps its
	/// registered true default here.
	@MainActor func migrateArticleToolbarTogglesIfNeeded() {
		guard !AppDefaults.bool(for: Key.hasMigratedArticleToolbarToggles) else { return }
		AppDefaults.setBool(for: Key.hasMigratedArticleToolbarToggles, true)
		let legacyTableOfContentsAndFind = AppDefaults.bool(for: Key.showTableOfContentsAndFind)
		articleToolbarShowTableOfContents = legacyTableOfContentsAndFind
		articleToolbarShowFind = legacyTableOfContentsAndFind
		articleToolbarShowPrevNext = AppDefaults.bool(for: Key.showPrevNextArticleButtons)
	}

	@MainActor static func registerDefaults() {
		let defaults: [String: Any] = [Key.userInterfaceColorPalette: UserInterfaceColorPalette.automatic.rawValue,
										Key.timelineGroupByFeed: false,
										Key.refreshClearsReadArticles: false,
										Key.timelineNumberOfLines: 3,
										Key.timelineIconDimension: IconSize.medium.rawValue,
										Key.timelineTagDisplayMode: TagDisplayMode.badges.rawValue,
									Key.badgeColorMode: BadgeColorPalette.default.rawValue,
										Key.accentColor: AccentColor.default.rawValue,
										Key.timelineSortDirection: ComparisonResult.orderedDescending.rawValue,
								Key.timelineSortField: ArticleSorter.SortField.date.rawValue,
										Key.articleFullscreenAvailable: false,
										Key.articleFullscreenEnabled: true,
										Key.articleBackSwipeEnabled: false,
									Key.articlePagingSwipeEnabled: true,
										Key.showFeedNameInReaderView: false,
									Key.showPrevNextArticleButtons: false,
									Key.showTableOfContentsAndFind: true,
									Key.articleToolbarShowTheme: true,
									Key.articleToolbarShowTableOfContents: true,
									Key.articleToolbarShowFind: true,
									Key.articleToolbarShowPrevNext: false,
									Key.articleToolbarShowLock: false,
									Key.hideNotchInFullScreen: true,
									Key.pageCounterDisplayMode: PageCounterDisplayMode.percentage.rawValue,
									Key.showLastUpdatedLabel: false,
									Key.showArticleScrollbar: true,
									Key.toolbarStyle: ToolbarStyle.system.rawValue,
									Key.statsVisible: true,
										// "Promenade" (Themes/Promenade.nnwtheme), not Self.defaultThemeName --
										// that constant is a sentinel meaning "use the app's built-in fallback
										// ArticleTheme.defaultTheme" (see ArticleThemesManager), a distinct
										// concept from "which theme a fresh install starts on." Changing
										// Self.defaultThemeName itself would repurpose that fallback sentinel.
										Key.currentThemeName: "Promenade",
									   Key.splitViewPreferredDisplayMode: UISplitViewController.DisplayMode.oneBesideSecondary.rawValue]
		AppDefaults.store.register(defaults: defaults)
	}
}

extension AppDefaults {

	static var firstRunDate: Date? {
		get {
			return date(for: Key.firstRunDate)
		}
		set {
			setDate(for: Key.firstRunDate, newValue)
		}
	}

	static func string(for key: String) -> String? {
		return UserDefaults.standard.string(forKey: key)
	}

	static func setString(for key: String, _ value: String?) {
		UserDefaults.standard.set(value, forKey: key)
	}

	static func bool(for key: String) -> Bool {
		return AppDefaults.store.bool(forKey: key)
	}

	static func setBool(for key: String, _ flag: Bool) {
		AppDefaults.store.set(flag, forKey: key)
	}

	static func int(for key: String) -> Int {
		return AppDefaults.store.integer(forKey: key)
	}

	static func setInt(for key: String, _ x: Int) {
		AppDefaults.store.set(x, forKey: key)
	}

	static func date(for key: String) -> Date? {
		return AppDefaults.store.object(forKey: key) as? Date
	}

	static func setDate(for key: String, _ date: Date?) {
		AppDefaults.store.set(date, forKey: key)
	}

	static func sortDirection(for key: String) -> ComparisonResult {
		let rawInt = int(for: key)
		if rawInt == ComparisonResult.orderedAscending.rawValue {
			return .orderedAscending
		}
		return .orderedDescending
	}

	static func setSortDirection(for key: String, _ value: ComparisonResult) {
		if value == .orderedAscending {
			setInt(for: key, ComparisonResult.orderedAscending.rawValue)
		} else {
			setInt(for: key, ComparisonResult.orderedDescending.rawValue)
		}
	}
}

struct StateRestorationInfo {
	let hideReadFeeds: Bool
	let expandedContainers: Set<ContainerIdentifier>
	let selectedSidebarItem: SidebarItemIdentifier?
	let smartFeedsHidingReadArticles: Set<String>
	let feedsHidingReadArticles: [String: Set<String>]
	let foldersShowingReadArticles: [String: Set<String>]
	let selectedArticle: ArticleSpecifier?

	init(hideReadFeeds: Bool,
	     expandedContainers: Set<ContainerIdentifier>,
	     selectedSidebarItem: SidebarItemIdentifier?,
	     smartFeedsHidingReadArticles: Set<String>,
	     feedsHidingReadArticles: [String: Set<String>],
	     foldersShowingReadArticles: [String: Set<String>],
	     selectedArticle: ArticleSpecifier?) {
		self.hideReadFeeds = hideReadFeeds
		self.expandedContainers = expandedContainers
		self.selectedSidebarItem = selectedSidebarItem
		self.smartFeedsHidingReadArticles = smartFeedsHidingReadArticles
		self.feedsHidingReadArticles = feedsHidingReadArticles
		self.foldersShowingReadArticles = foldersShowingReadArticles
		self.selectedArticle = selectedArticle

		AppDefaults.logger.debug("AppDefaults: StateRestorationInfo:\nexpandedContainers: \(expandedContainers)\nselectedSidebarItem: \(selectedSidebarItem?.userInfo ?? [String: String]())\nsmartFeedsHidingReadArticles: \(smartFeedsHidingReadArticles)\nfeedsHidingReadArticles: \(feedsHidingReadArticles)\nfoldersShowingReadArticles: \(foldersShowingReadArticles)\nselectedArticle: \(selectedArticle?.dictionary ?? [String: String]())")
	}

	init() {
		self.init(hideReadFeeds: AppDefaults.shared.hideReadFeeds,
				  expandedContainers: AppDefaults.shared.expandedContainers,
				  selectedSidebarItem: AppDefaults.shared.selectedSidebarItem,
				  smartFeedsHidingReadArticles: AppDefaults.shared.smartFeedsHidingReadArticles,
				  feedsHidingReadArticles: AppDefaults.shared.feedsHidingReadArticles,
				  foldersShowingReadArticles: AppDefaults.shared.foldersShowingReadArticles,
				  selectedArticle: AppDefaults.shared.selectedArticle)
	}

	// TODO: Delete for NetNewsWire 7.1.
	init(legacyState: NSUserActivity?) {
		if AppDefaults.shared.didMigrateLegacyStateRestorationInfo {
			self.init()
			return
		}

		AppDefaults.shared.didMigrateLegacyStateRestorationInfo = true

		// Extract legacy window state if available
		guard let windowState = legacyState?.userInfo?[UserInfoKey.windowState] as? [AnyHashable: Any] else {
			self.init()
			return
		}

		let hideReadFeeds: Bool
		if let legacyValue = windowState[UserInfoKey.readFeedsFilterState] as? Bool {
			hideReadFeeds = legacyValue
		} else {
			hideReadFeeds = AppDefaults.shared.hideReadFeeds
		}

		let expandedContainers: Set<ContainerIdentifier>
		if let legacyState = windowState[UserInfoKey.containerExpandedWindowState] as? [[AnyHashable: AnyHashable]] {
			let convertedState = legacyState.compactMap { dict -> [String: String]? in
				var stringDict = [String: String]()
				for (key, value) in dict {
					if let keyString = key as? String, let valueString = value as? String {
						stringDict[keyString] = valueString
					}
				}
				return stringDict.isEmpty ? nil : stringDict
			}
			let containerIdentifiers = convertedState.compactMap { ContainerIdentifier(userInfo: $0) }
			expandedContainers = Set(containerIdentifiers)
		} else {
			expandedContainers = AppDefaults.shared.expandedContainers
		}

		let sidebarItemsHidingReadArticles: Set<SidebarItemIdentifier>
		if let legacyState = windowState[UserInfoKey.readArticlesFilterState] as? [[AnyHashable: AnyHashable]: Bool] {
			let enabledFeeds = legacyState.filter { $0.value == true }
			let convertedState = enabledFeeds.keys.compactMap { key -> [String: String]? in
				var stringDict = [String: String]()
				for (k, v) in key {
					if let keyString = k as? String, let valueString = v as? String {
						stringDict[keyString] = valueString
					}
				}
				return stringDict.isEmpty ? nil : stringDict
			}
			let sidebarItemIdentifiers = convertedState.compactMap { SidebarItemIdentifier(userInfo: $0) }
			sidebarItemsHidingReadArticles = Set(sidebarItemIdentifiers)
		} else {
			sidebarItemsHidingReadArticles = Set<SidebarItemIdentifier>()
		}

		var smartFeedsHidingReadArticles = Set<String>()
		var feedsHidingReadArticles = [String: Set<String>]()
		for sidebarItem in sidebarItemsHidingReadArticles {
			switch sidebarItem {
			case .smartFeed(let id):
				smartFeedsHidingReadArticles.insert(id)
			case .feed(let accountID, let feedID):
				var feedIDs = feedsHidingReadArticles[accountID] ?? Set<String>()
				feedIDs.insert(feedID)
				feedsHidingReadArticles[accountID] = feedIDs
			default:
				continue
			}
		}

		let selectedSidebarItem: SidebarItemIdentifier?
		if let legacyState = windowState[UserInfoKey.feedIdentifier] as? [String: String],
		   let sidebarItemIdentifier = SidebarItemIdentifier(userInfo: legacyState) {
			selectedSidebarItem = sidebarItemIdentifier
		} else {
			selectedSidebarItem = AppDefaults.shared.selectedSidebarItem
		}

		self.init(hideReadFeeds: hideReadFeeds,
				  expandedContainers: expandedContainers,
				  selectedSidebarItem: selectedSidebarItem,
				  smartFeedsHidingReadArticles: smartFeedsHidingReadArticles,
				  feedsHidingReadArticles: feedsHidingReadArticles,
				  foldersShowingReadArticles: AppDefaults.shared.foldersShowingReadArticles,
				  selectedArticle: AppDefaults.shared.selectedArticle)
	}
}
