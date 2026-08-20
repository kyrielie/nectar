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

/// Which set of five hex values (yellow/red/green/blue/purple, matching
/// Annotation.Color.allCases 1:1) an annotation's fixed color *key*
/// resolves to at render/display time -- a person's saved
/// Annotation.color is always one of the five case names, never a hex
/// value, so switching palettes here re-tints every existing highlight
/// without touching a single row of annotation data. See
/// docs/annotations.md's "Color palette" section.
///
/// Same two-appearance HexSet shape SurfacePalette established just above
/// (lightHexSet/darkHexSet, .default meaning "fall back to the existing
/// fixed hex", one HexSet struct rather than a bare tuple so each field
/// stays named and matched to its Annotation.Color case by name, not
/// position). `.default`'s own light/dark values are *not* nil the way
/// SurfacePalette.default's are, though -- unlike SurfacePalette, there is
/// no pre-existing asset-catalog colorset for highlight colors to fall
/// back to (core.css's mark.nnw-highlight rules previously had only a
/// single hardcoded fallback hex per color, applied unconditionally in
/// both appearances); .default's HexSets below are what that single
/// fallback becomes once it's split into a real light/dark pair, so they
/// carry real values rather than nil.
enum HighlightPalette: Int, CaseIterable, Sendable {
	case `default` = 0
	/// Softer, lower-saturation tones for long reading sessions --
	/// dark-mode values are deepened rather than lightened, so a
	/// highlight stays a wash instead of glowing against a dark
	/// background.
	case muted = 1
	/// Near-fluorescent in light mode for anyone who wants highlights to
	/// pop; dark-mode values are deepened like every other case below --
	/// the original dark set reused these same near-fluorescent light
	/// values unchanged, which read as a light source against dark-mode
	/// article text rather than a wash (see "Dark-mode contrast" in
	/// docs/annotations.md).
	case vivid = 2
	/// Warm, paper-toned hues -- shares its name and aesthetic family
	/// with SurfacePalette.sepia, but is otherwise independent: picking
	/// SurfacePalette.sepia does not imply or require HighlightPalette.sepia,
	/// the same way any other SurfacePalette/HighlightPalette combination
	/// is unrelated.
	case sepia = 3
	/// Soft pastel greens/blues/grays/lavender/rose -- gentle, low-contrast
	/// set. Originally shared this same HexSet for both lightHexSet and
	/// darkHexSet on the assumption that the low saturation made a
	/// separate dark-mode tuning unnecessary; measured contrast showed
	/// that assumption was wrong (several slots under 3:1 against
	/// dark-mode's near-white article text), so darkHexSet below is now
	/// its own deepened set, same as every other case.
	case mint = 4
	/// Saturated pink/orange/yellow/teal/sky-blue -- brighter than Mint.
	/// Same history as Mint above: originally shared lightHexSet/
	/// darkHexSet, now has its own deepened dark set.
	case flourescent = 5
	/// High-energy magenta/red/chartreuse/teal/indigo.
	case refresh = 6
	/// Muted teal/terracotta/gold/mauve/umber -- an earthier set than
	/// Sepia's paper tones.
	case warm = 7
	/// Desaturated rust/tan/peach/steel-blue/olive.
	case neutral = 8

	var description: String {
		switch self {
		case .default:
			return NSLocalizedString("Default", comment: "Default highlight palette")
		case .muted:
			return NSLocalizedString("Muted", comment: "Muted highlight palette")
		case .vivid:
			return NSLocalizedString("Vivid", comment: "Vivid highlight palette")
		case .sepia:
			return NSLocalizedString("Sepia", comment: "Sepia highlight palette")
		case .mint:
			return NSLocalizedString("Mint", comment: "Mint highlight palette")
		case .flourescent:
			return NSLocalizedString("Flourescent", comment: "Flourescent highlight palette")
		case .refresh:
			return NSLocalizedString("Refresh", comment: "Refresh highlight palette")
		case .warm:
			return NSLocalizedString("Warm", comment: "Warm highlight palette")
		case .neutral:
			return NSLocalizedString("Neutral", comment: "Neutral highlight palette")
		}
	}

	/// One hex value per Annotation.Color case, named to match rather than
	/// positional -- see HexSet's own doc comment above for why.
	struct HexSet {
		var yellow: String
		var red: String
		var green: String
		var blue: String
		var purple: String

		/// core.css's mark.nnw-highlight[data-annotation-color="..."] rules
		/// key on Annotation.Color's raw String value -- this maps the
		/// same way, so WebViewController's injection call site can build
		/// the custom-property name/value pairs from one dictionary
		/// instead of a five-way switch.
		var byColorKey: [String: String] {
			[
				Annotation.Color.yellow.rawValue: yellow,
				Annotation.Color.red.rawValue: red,
				Annotation.Color.green.rawValue: green,
				Annotation.Color.blue.rawValue: blue,
				Annotation.Color.purple.rawValue: purple
			]
		}

		subscript(_ color: Annotation.Color) -> String {
			switch color {
			case .yellow: return yellow
			case .red: return red
			case .green: return green
			case .blue: return blue
			case .purple: return purple
			}
		}
	}

	var lightHexSet: HexSet {
		switch self {
		case .default:
			// Apple's own light-mode system-color equivalents -- previously
			// core.css/HighlightColorPopover served the *dark*-mode system
			// colors (below) unconditionally in both appearances; this is
			// the actual light-mode fix, not a newly invented palette.
			return HexSet(yellow: "#FFCC00", red: "#FF3B30", green: "#34C759", blue: "#007AFF", purple: "#AF52DE")
		case .muted:
			return HexSet(yellow: "#E8D48A", red: "#D99C90", green: "#9DC2A0", blue: "#92B8D4", purple: "#B79CC7")
		case .vivid:
			return HexSet(yellow: "#FFEA00", red: "#FF1744", green: "#00C853", blue: "#2962FF", purple: "#D500F9")
		case .sepia:
			return HexSet(yellow: "#D9A441", red: "#C06A4D", green: "#8A9A5B", blue: "#5E8A9E", purple: "#96789A")
		case .mint:
			return HexSet(yellow: "#a0d084", red: "#9cb2e3", green: "#d5d6da", blue: "#b6add8", purple: "#de556f")
		case .flourescent:
			return HexSet(yellow: "#f1a5c7", red: "#f7c18e", green: "#f6e977", blue: "#85cbb3", purple: "#a4d3e6")
		case .refresh:
			return HexSet(yellow: "#e277cd", red: "#f9423a", green: "#cedc00", blue: "#00b2a9", purple: "#7474c1")
		case .warm:
			return HexSet(yellow: "#89afb4", red: "#d6735d", green: "#efcc82", blue: "#c093b2", purple: "#826860")
		case .neutral:
			return HexSet(yellow: "#c57955", red: "#d8b58f", green: "#f8cfb8", blue: "#bdc8d3", purple: "#b8b279")
		}
	}

	/// Every value below is the same hue as its `lightHexSet` counterpart,
	/// darkened in HSL lightness until it clears 4.5:1 contrast against
	/// white (WCAG AA for normal body text) -- see
	/// `UIColor.contrastRatio(against:)` and "Dark-mode contrast" in
	/// docs/annotations.md. `.default`'s previous dark set was the exact
	/// five hex values `core.css`/`HighlightColorPopover` used to
	/// hardcode as their single, appearance-independent fallback
	/// (Apple's dark-mode system colors); measured, every one of those
	/// five failed 4.5:1 against white (yellow's ratio was ~1.41), so
	/// they're deepened the same way as every other case here rather
	/// than kept as-is -- see
	/// `HighlightPaletteHexSetTests.everyDarkHexSetColorMeetsWCAGAAContrastForWhiteText`.
	var darkHexSet: HexSet {
		switch self {
		case .default:
			return HexSet(yellow: "#8B7300", red: "#EA0D00", green: "#1E8738", blue: "#0072E6", purple: "#B033EF")
		case .muted:
			// red/green/blue/purple already cleared 4.5:1 as hand-tuned;
			// only yellow needed deepening further.
			return HexSet(yellow: "#8A7333", red: "#8A5147", green: "#4F7A56", blue: "#4A7396", purple: "#7C5F91")
		case .vivid:
			return HexSet(yellow: "#837600", red: "#EC0000", green: "#0D874B", blue: "#1E6AFF", purple: "#C605E6")
		case .sepia:
			// red/green/blue/purple already cleared 4.5:1 as hand-tuned;
			// only yellow needed deepening further.
			return HexSet(yellow: "#976E29", red: "#8F4E38", green: "#64703F", blue: "#456B7A", purple: "#6B5470")
		case .mint:
			return HexSet(yellow: "#4F8232", red: "#4A72CC", green: "#727581", blue: "#7A6AB8", purple: "#D83654")
		case .flourescent:
			return HexSet(yellow: "#DD2376", red: "#B45E0D", green: "#837609", blue: "#378269", purple: "#2C7E9F")
		case .refresh:
			return HexSet(yellow: "#CD2CAE", red: "#EA1107", green: "#737B00", blue: "#00837D", purple: "#6D6DBE")
		case .warm:
			// purple already cleared 4.5:1 as hand-tuned; the other four
			// needed deepening.
			return HexSet(yellow: "#527C82", red: "#C74E32", green: "#986E13", blue: "#A25F8D", purple: "#826860")
		case .neutral:
			return HexSet(yellow: "#AE603C", red: "#9C6B36", green: "#C35313", blue: "#607890", purple: "#7C7742")
		}
	}

	func hexSet(isDark: Bool) -> HexSet {
		isDark ? darkHexSet : lightHexSet
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

/// When the article web view shows its native vertical scroll indicator.
/// Replaces the old Bool-backed showArticleScrollbar -- see
/// AppDefaults.migrateArticleScrollbarVisibilityIfNeeded() for the
/// one-time upgrade path (old `true` -> .whenNotFullScreen, old `false`
/// -> .off, so nobody's prior "hide it" choice silently reappears).
enum ArticleScrollbarVisibility: String, CaseIterable, Sendable {
	case off
	case whenNotFullScreen
	case always

	var title: String {
		switch self {
		case .off:
			return NSLocalizedString("Off", comment: "Article scrollbar: off")
		case .whenNotFullScreen:
			return NSLocalizedString("Only Outside Full Screen", comment: "Article scrollbar: only outside full screen")
		case .always:
			return NSLocalizedString("Always", comment: "Article scrollbar: always")
		}
	}
}

/// Which of the article reader's two toolbars a ToolbarFunction placement
/// or query refers to. Replaces the formerly-implicit split between
/// ArticleToolbarToggle (top only) and BottomToolbarToggle (bottom only)
/// -- see ToolbarFunction's own doc comment for why unification requires
/// this explicit parameter rather than two disjoint enums.
enum ToolbarBar: Sendable {
	case top
	case bottom
}

/// A function assignable to the article reader's top toolbar, bottom
/// toolbar, or both at once -- see AppDefaults.isToolbarFunctionEnabled(_:on:)
/// and setToolbarFunctionEnabled(_:on:_:). Unifies the formerly-separate
/// ArticleToolbarToggle (theme...checkForUpdates, top only) and
/// BottomToolbarToggle (read...action, bottom only) into one type so a
/// function's identity no longer implies which bar it can appear on.
///
/// Each (function, bar) pair is an independent on/off switch, and unlike
/// the pre-unification model, the *same* function can be on for both
/// .top and .bottom simultaneously (duplicates across bars are allowed;
/// duplicates within the *same* bar are not -- there is exactly one Bool
/// per (function, bar), not a count). See
/// AppDefaults.migrateUnifiedToolbarsIfNeeded() for the one-time
/// migration off the pre-unification per-bar toggles.
///
/// String-backed (unlike CaseIterable alone would require) so a
/// person's chosen per-bar display order (AppDefaults.toolbarFunctionOrder(for:))
/// can be persisted as an array of stable identifiers rather than
/// depending on this enum's declaration order, which must stay free to
/// gain new cases without silently reordering anyone's existing choice.
/// Do not rename an existing rawValue once shipped -- that would orphan
/// it from any already-persisted order array the same way renaming a
/// UserDefaults key would.
enum ToolbarFunction: String, CaseIterable, Sendable {
	case theme
	case tableOfContents
	case find
	case prevNext
	case lock
	case annotations
	case settings
	case checkForUpdates
	case read
	case star
	case heart
	case nextUnread
	case action
}

/// Single source of truth for each function's display name and icon --
/// previously duplicated between ArticleToolbarToggleCell/BottomToolbarToggleCell
/// (title) and ArticleToolbarPreviewCell (icons), and previously absent
/// entirely for the five bottom-bar cases (read/star/heart/nextUnread/
/// action had no centralized title/icon before unification -- each
/// bottom-bar cell hardcoded its own). Consumers: ToolbarFunctionCell,
/// ToolbarPreviewCell, ArticleViewController.rebuildOverflowMenu().
extension ToolbarFunction {

	var title: String {
		switch self {
		case .theme:
			return NSLocalizedString("Theme", comment: "Toolbar function: theme")
		case .tableOfContents:
			return NSLocalizedString("Table of Contents", comment: "Toolbar function: table of contents")
		case .find:
			return NSLocalizedString("Find in Article", comment: "Toolbar function: find")
		case .prevNext:
			return NSLocalizedString("Previous & Next Article", comment: "Toolbar function: previous and next article")
		case .lock:
			return NSLocalizedString("Lock Gestures", comment: "Toolbar function: lock gestures")
		case .annotations:
			return NSLocalizedString("Highlights", comment: "Toolbar function: annotations")
		case .settings:
			return NSLocalizedString("Settings", comment: "Toolbar function: settings")
		case .checkForUpdates:
			return NSLocalizedString("Check for Updates", comment: "Toolbar function: check for updates")
		case .read:
			return NSLocalizedString("Toggle Read", comment: "Toolbar function: toggle read")
		case .star:
			return NSLocalizedString("Read Later", comment: "Toolbar function: read later")
		case .heart:
			return NSLocalizedString("Loved", comment: "Toolbar function: loved")
		case .nextUnread:
			return NSLocalizedString("Next Unread", comment: "Toolbar function: next unread")
		case .action:
			return NSLocalizedString("Share", comment: "Toolbar function: share/action")
		}
	}

	/// Static icon for this function. .lock and .prevNext have
	/// runtime-only meaning beyond this (lock's open/closed state,
	/// prevNext's available/unavailable state) -- callers that need that
	/// dynamic state (ArticleViewController.rebuildOverflowMenu()) build
	/// their own UIAction for those two cases instead of using this
	/// property. Safe for ToolbarPreviewCell, which never shows dynamic
	/// state (see its own doc comment on the lock preview always being
	/// unlocked).
	///
	/// read/star/heart/nextUnread/action icons and titles are carried
	/// over verbatim from BottomToolbarPreviewCell.configure()'s
	/// `candidates` array and BottomToolbarToggleCell.title(for:)
	/// respectively (confirmed by reading both), not guessed --
	/// Assets.Images.circleOpen/starOpen/heartOpen/nextUnread/action, and
	/// "Read Later" for .star specifically (not "Toggle Starred" --
	/// Assets.Images.starOpen's own historical-naming comment explains
	/// the bookmark-vs-star mismatch between the asset name and the
	/// display copy).
	@MainActor
	var icon: UIImage? {
		switch self {
		case .theme: return Assets.Images.theme
		case .tableOfContents: return Assets.Images.tableOfContents
		case .find: return Assets.Images.findInArticle
		case .prevNext: return Assets.Images.nextArticle
		case .lock: return UIImage(systemName: "lock.open")
		case .annotations: return Assets.Images.annotations
		case .settings: return Assets.Images.settings
		case .checkForUpdates: return Assets.Images.checkForUpdates
		case .read: return Assets.Images.circleOpen
		case .star: return Assets.Images.starOpen
		case .heart: return Assets.Images.heartOpen
		case .nextUnread: return Assets.Images.nextUnread
		case .action: return Assets.Images.action
		}
	}
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
	public static let highlightPaletteDidChange = Notification.Name("HighlightPaletteDidChangeNotification")
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
		static let hasMigratedArticleScrollbarVisibility = "hasMigratedArticleScrollbarVisibility"
		static let timelineGroupByFeed = "timelineGroupByFeed"
		static let refreshClearsReadArticles = "refreshClearsReadArticles"
		static let timelineNumberOfLines = "timelineNumberOfLines"
		static let timelineIconDimension = "timelineIconSize"
		static let timelineTagDisplayMode = "timelineTagDisplayMode"
		static let badgeColorMode = "badgeColorMode"
		static let accentColor = "accentColor"
		static let surfaceTint = "surfaceTint"
		static let highlightPalette = "highlightPalette"
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
		static let articleToolbarShowSettings = "articleToolbarShowSettings"
		static let articleToolbarShowCheckForUpdates = "articleToolbarShowCheckForUpdates"
		/// Legacy Bool keys, pre-unification. No longer backed by a live
		/// property -- read directly via AppDefaults.store by
		/// migrateUnifiedToolbarsIfNeeded() only, to carry a person's
		/// prior top/bottom placement and overflow choice onto the
		/// toolbarFunctionEnabled(_:on:) keys below. Do not reintroduce
		/// properties for these keys.
		static let articleToolbarUseOverflowMenu = "articleToolbarUseOverflowMenu"
		static let bottomToolbarShowRead = "bottomToolbarShowRead"
		static let bottomToolbarShowStar = "bottomToolbarShowStar"
		static let bottomToolbarShowHeart = "bottomToolbarShowHeart"
		static let bottomToolbarShowNextUnread = "bottomToolbarShowNextUnread"
		static let bottomToolbarShowAction = "bottomToolbarShowAction"
		/// Unified toolbar-customization keys. One Bool per (ToolbarFunction,
		/// ToolbarBar, inline-or-overflow) triple -- see
		/// isToolbarFunctionEnabled(_:on:)/setToolbarFunctionEnabled(_:on:_:)
		/// and isToolbarFunctionInOverflow(_:on:)/setToolbarFunctionInOverflow(_:on:_:)
		/// for the dispatch. Named toolbarFn{Function}{Bar}/
		/// toolbarFn{Function}{Bar}Overflow rather than reusing the legacy
		/// articleToolbarShow*/bottomToolbarShow* names, since those names
		/// are retained above as migration-source-only keys and must keep
		/// their old on-disk values untouched until migration reads them.
		static let toolbarFnThemeTop = "toolbarFnThemeTop"
		static let toolbarFnThemeTopOverflow = "toolbarFnThemeTopOverflow"
		static let toolbarFnThemeBottom = "toolbarFnThemeBottom"
		static let toolbarFnThemeBottomOverflow = "toolbarFnThemeBottomOverflow"
		static let toolbarFnTableOfContentsTop = "toolbarFnTableOfContentsTop"
		static let toolbarFnTableOfContentsTopOverflow = "toolbarFnTableOfContentsTopOverflow"
		static let toolbarFnTableOfContentsBottom = "toolbarFnTableOfContentsBottom"
		static let toolbarFnTableOfContentsBottomOverflow = "toolbarFnTableOfContentsBottomOverflow"
		static let toolbarFnFindTop = "toolbarFnFindTop"
		static let toolbarFnFindTopOverflow = "toolbarFnFindTopOverflow"
		static let toolbarFnFindBottom = "toolbarFnFindBottom"
		static let toolbarFnFindBottomOverflow = "toolbarFnFindBottomOverflow"
		static let toolbarFnPrevNextTop = "toolbarFnPrevNextTop"
		static let toolbarFnPrevNextTopOverflow = "toolbarFnPrevNextTopOverflow"
		static let toolbarFnPrevNextBottom = "toolbarFnPrevNextBottom"
		static let toolbarFnPrevNextBottomOverflow = "toolbarFnPrevNextBottomOverflow"
		static let toolbarFnLockTop = "toolbarFnLockTop"
		static let toolbarFnLockTopOverflow = "toolbarFnLockTopOverflow"
		static let toolbarFnLockBottom = "toolbarFnLockBottom"
		static let toolbarFnLockBottomOverflow = "toolbarFnLockBottomOverflow"
		static let toolbarFnAnnotationsTop = "toolbarFnAnnotationsTop"
		static let toolbarFnAnnotationsTopOverflow = "toolbarFnAnnotationsTopOverflow"
		static let toolbarFnAnnotationsBottom = "toolbarFnAnnotationsBottom"
		static let toolbarFnAnnotationsBottomOverflow = "toolbarFnAnnotationsBottomOverflow"
		static let toolbarFnSettingsTop = "toolbarFnSettingsTop"
		static let toolbarFnSettingsTopOverflow = "toolbarFnSettingsTopOverflow"
		static let toolbarFnSettingsBottom = "toolbarFnSettingsBottom"
		static let toolbarFnSettingsBottomOverflow = "toolbarFnSettingsBottomOverflow"
		static let toolbarFnCheckForUpdatesTop = "toolbarFnCheckForUpdatesTop"
		static let toolbarFnCheckForUpdatesTopOverflow = "toolbarFnCheckForUpdatesTopOverflow"
		static let toolbarFnCheckForUpdatesBottom = "toolbarFnCheckForUpdatesBottom"
		static let toolbarFnCheckForUpdatesBottomOverflow = "toolbarFnCheckForUpdatesBottomOverflow"
		static let toolbarFnReadTop = "toolbarFnReadTop"
		static let toolbarFnReadTopOverflow = "toolbarFnReadTopOverflow"
		static let toolbarFnReadBottom = "toolbarFnReadBottom"
		static let toolbarFnReadBottomOverflow = "toolbarFnReadBottomOverflow"
		static let toolbarFnStarTop = "toolbarFnStarTop"
		static let toolbarFnStarTopOverflow = "toolbarFnStarTopOverflow"
		static let toolbarFnStarBottom = "toolbarFnStarBottom"
		static let toolbarFnStarBottomOverflow = "toolbarFnStarBottomOverflow"
		static let toolbarFnHeartTop = "toolbarFnHeartTop"
		static let toolbarFnHeartTopOverflow = "toolbarFnHeartTopOverflow"
		static let toolbarFnHeartBottom = "toolbarFnHeartBottom"
		static let toolbarFnHeartBottomOverflow = "toolbarFnHeartBottomOverflow"
		static let toolbarFnNextUnreadTop = "toolbarFnNextUnreadTop"
		static let toolbarFnNextUnreadTopOverflow = "toolbarFnNextUnreadTopOverflow"
		static let toolbarFnNextUnreadBottom = "toolbarFnNextUnreadBottom"
		static let toolbarFnNextUnreadBottomOverflow = "toolbarFnNextUnreadBottomOverflow"
		static let toolbarFnActionTop = "toolbarFnActionTop"
		static let toolbarFnActionTopOverflow = "toolbarFnActionTopOverflow"
		static let toolbarFnActionBottom = "toolbarFnActionBottom"
		static let toolbarFnActionBottomOverflow = "toolbarFnActionBottomOverflow"
		/// Whether each bar collapses its overflow-flagged functions into
		/// a single trailing menu icon. Two independent switches (top and
		/// bottom no longer share one Bool) -- replaces the pre-unification
		/// articleToolbarUseOverflowMenu, which only existed for the top
		/// bar.
		static let toolbarTopUseOverflowMenu = "toolbarTopUseOverflowMenu"
		static let toolbarBottomUseOverflowMenu = "toolbarBottomUseOverflowMenu"
		/// Persisted per-bar display order -- an array of ToolbarFunction.rawValue
		/// strings. See AppDefaults.toolbarFunctionOrder(for:)/
		/// setToolbarFunctionOrder(_:for:). Registered in registerDefaults()
		/// to the same order the three pre-persisted-order call sites
		/// (ArticleViewController.displayOrder(for:), ToolbarPreviewCell.configure(bar:),
		/// ToolbarsCustomizerViewController's functions table) used to
		/// hardcode independently, so a fresh install's rendering is
		/// unchanged from before this key existed.
		static let toolbarTopFunctionOrder = "toolbarTopFunctionOrder"
		static let toolbarBottomFunctionOrder = "toolbarBottomFunctionOrder"
		static let hasMigratedUnifiedToolbars = "hasMigratedUnifiedToolbars"
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

	/// Backup/restore plan: the explicit allowlist of `Key.*` entries that
	/// are person-facing preferences, safe to write into a backup's
	/// `Settings.plist` and safe to replay onto another device (or back
	/// onto this one, on restore) if the person opts in.
	///
	/// This is deliberately an allowlist, not "every Key minus known
	/// system/migration keys" -- `Key` is a plain struct of `static let`
	/// strings, not a `CaseIterable` enum, so there's no `allCases` to
	/// subtract from, and a subtraction approach would silently include
	/// any new bookkeeping key added later unless someone remembered to
	/// also add it to an exclusion list. An allowlist fails safe: a key
	/// added to `Key` and forgotten here is simply never backed up, never
	/// wrongly replayed onto a fresh install.
	///
	/// This array requires manual maintenance -- there is no compiler
	/// check tying it to `Key`'s contents (119 keys as of this writing;
	/// 98 included below, 22 excluded, after adding the 54
	/// unified-toolbar keys). `AppDefaultsBackupTests` has a named test
	/// per excluded key below; adding a new `Key` entry without deciding
	/// whether it belongs here is a review-time responsibility, not
	/// something either the compiler or a generic test can catch.
	///
	/// Excluded, and why (not merely omitted -- see the corresponding
	/// named test in AppDefaultsBackupTests for each):
	/// - `firstRunDate`, `hasShownAO3Onboarding`,
	///   `hasMigratedNavigationBarTintingDefault`,
	///   `hasMigratedToolbarStyleDefault`, `hasMigratedArticleToolbarToggles`,
	///   `hasMigratedUnifiedToolbars`, `hasMigratedArticleScrollbarVisibility`,
	///   `didMigrateLegacyStateRestorationInfo`: one-time migration/onboarding
	///   gates. Replaying `true` onto a fresh install would skip onboarding
	///   or a migration step that install actually needs to run.
	/// - `useTintedNavigationBar`: dead migration-source-of-truth only, per
	///   its own doc comment above ("do not reintroduce a property for
	///   this key") -- there's no live property reading this key for a
	///   backup to meaningfully capture.
	/// - `lastImageCacheFlushDate`, `lastRefresh`: bookkeeping timestamps,
	///   not preferences a person set.
	/// - `selectedArticle`, `selectedSidebarItem`: state restoration, not
	///   a preference -- a stale value from a different device points at
	///   nothing on this one.
	/// - `hideReadFeeds`, `expandedContainers`, `smartFeedsHidingReadArticles`,
	///   `feedsHidingReadArticles`, `foldersShowingReadArticles`,
	///   `splitViewPreferredDisplayMode`: back `StateRestorationInfo`
	///   (sidebar/timeline UI state), not a Settings-screen row.
	/// - `articleFullscreenAvailable`: a device-capability flag (is
	///   fullscreen even possible on this device), not a person-set
	///   preference -- `articleFullscreenEnabled`, the actual toggle, is
	///   included below.
	/// - `addFeedAccountID`, `addFeedFolderName`, `addFolderAccountID`:
	///   ephemeral last-used-account/folder state for the "Add Feed"
	///   sheet, not something a person thinks of as a setting to back up.
	static let backupEligibleKeys: [String] = [
		Key.userInterfaceColorPalette,
		Key.timelineGroupByFeed,
		Key.refreshClearsReadArticles,
		Key.timelineNumberOfLines,
		Key.timelineIconDimension,
		Key.timelineTagDisplayMode,
		Key.badgeColorMode,
		Key.accentColor,
		Key.surfaceTint,
		Key.highlightPalette,
		Key.toolbarStyle,
		Key.statsVisible,
		Key.timelineSortDirection,
		Key.timelineSortField,
		Key.articleFullscreenEnabled,
		Key.articleBackSwipeEnabled,
		Key.articlePagingSwipeEnabled,
		Key.showFeedNameInReaderView,
		Key.showPrevNextArticleButtons,
		Key.showTableOfContentsAndFind,
		Key.articleToolbarShowTheme,
		Key.articleToolbarShowTableOfContents,
		Key.articleToolbarShowFind,
		Key.articleToolbarShowPrevNext,
		Key.articleToolbarShowLock,
		Key.articleToolbarShowAnnotations,
		Key.articleToolbarShowSettings,
		Key.articleToolbarShowCheckForUpdates,
		Key.articleToolbarUseOverflowMenu,
		Key.bottomToolbarShowRead,
		Key.bottomToolbarShowStar,
		Key.bottomToolbarShowHeart,
		Key.bottomToolbarShowNextUnread,
		Key.bottomToolbarShowAction,
		// Unified toolbar-customization keys (see ToolbarFunction). These
		// are the keys the new Toolbars settings screen actually writes
		// to going forward; the legacy articleToolbarShow*/
		// bottomToolbarShow*/articleToolbarUseOverflowMenu keys above stay
		// in this allowlist too rather than being removed, since
		// migrateUnifiedToolbarsIfNeeded() is gated to run once per
		// device and a restored backup's legacy values must still be
		// present for that migration to read correctly on a fresh
		// install that hasn't run it yet.
		Key.toolbarFnThemeTop, Key.toolbarFnThemeTopOverflow, Key.toolbarFnThemeBottom, Key.toolbarFnThemeBottomOverflow,
		Key.toolbarFnTableOfContentsTop, Key.toolbarFnTableOfContentsTopOverflow, Key.toolbarFnTableOfContentsBottom, Key.toolbarFnTableOfContentsBottomOverflow,
		Key.toolbarFnFindTop, Key.toolbarFnFindTopOverflow, Key.toolbarFnFindBottom, Key.toolbarFnFindBottomOverflow,
		Key.toolbarFnPrevNextTop, Key.toolbarFnPrevNextTopOverflow, Key.toolbarFnPrevNextBottom, Key.toolbarFnPrevNextBottomOverflow,
		Key.toolbarFnLockTop, Key.toolbarFnLockTopOverflow, Key.toolbarFnLockBottom, Key.toolbarFnLockBottomOverflow,
		Key.toolbarFnAnnotationsTop, Key.toolbarFnAnnotationsTopOverflow, Key.toolbarFnAnnotationsBottom, Key.toolbarFnAnnotationsBottomOverflow,
		Key.toolbarFnSettingsTop, Key.toolbarFnSettingsTopOverflow, Key.toolbarFnSettingsBottom, Key.toolbarFnSettingsBottomOverflow,
		Key.toolbarFnCheckForUpdatesTop, Key.toolbarFnCheckForUpdatesTopOverflow, Key.toolbarFnCheckForUpdatesBottom, Key.toolbarFnCheckForUpdatesBottomOverflow,
		Key.toolbarFnReadTop, Key.toolbarFnReadTopOverflow, Key.toolbarFnReadBottom, Key.toolbarFnReadBottomOverflow,
		Key.toolbarFnStarTop, Key.toolbarFnStarTopOverflow, Key.toolbarFnStarBottom, Key.toolbarFnStarBottomOverflow,
		Key.toolbarFnHeartTop, Key.toolbarFnHeartTopOverflow, Key.toolbarFnHeartBottom, Key.toolbarFnHeartBottomOverflow,
		Key.toolbarFnNextUnreadTop, Key.toolbarFnNextUnreadTopOverflow, Key.toolbarFnNextUnreadBottom, Key.toolbarFnNextUnreadBottomOverflow,
		Key.toolbarFnActionTop, Key.toolbarFnActionTopOverflow, Key.toolbarFnActionBottom, Key.toolbarFnActionBottomOverflow,
		Key.toolbarTopUseOverflowMenu,
		Key.toolbarBottomUseOverflowMenu,
		Key.defaultAnnotationColor,
		Key.annotationCreationMethod,
		Key.hideNotchInFullScreen,
		Key.pageCounterDisplayMode,
		Key.disableArticleLinks,
		Key.showArticleScrollbar,
		Key.showLastUpdatedLabel,
		Key.articleThemeOverrides,
		Key.useSystemBrowser,
		Key.currentThemeName
	]

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

	/// Off by default, same reasoning as articleToolbarShowLock/
	/// articleToolbarShowAnnotations above: an opt-in extra, not something
	/// everyone needs cluttering the bar. Opens Settings, scrolled to the
	/// Articles section -- see ArticleViewController.showSettingsFromToolbar.
	var articleToolbarShowSettings: Bool {
		get {
			return AppDefaults.bool(for: Key.articleToolbarShowSettings)
		}
		set {
			AppDefaults.setBool(for: Key.articleToolbarShowSettings, newValue)
		}
	}

	/// Off by default, same reasoning as the other opt-in toolbar extras
	/// above. Unlike those, this one's bar-button item also has per-article
	/// eligibility on top of this toggle -- see
	/// ArticleViewController.updateUI()'s checkForUpdatesBarButtonItem
	/// handling, gated on AO3ChapterFetcher.canCheckForUpdates(for:).
	var articleToolbarShowCheckForUpdates: Bool {
		get {
			return AppDefaults.bool(for: Key.articleToolbarShowCheckForUpdates)
		}
		set {
			AppDefaults.setBool(for: Key.articleToolbarShowCheckForUpdates, newValue)
		}
	}

	/// Off by default -- an opt-in display mode, not something existing
	/// users should suddenly see change. Explicitly registered false in
	/// registerDefaults(), same as articleToolbarShowLock (unlike
	/// articleToolbarShowAnnotations/articleToolbarShowSettings/
	/// articleToolbarShowCheckForUpdates above, which rely on
	/// AppDefaults.bool(for:)'s implicit-false fallback instead).
	///
	/// No live property here anymore -- replaced by
	/// toolbarTopUseOverflowMenu/toolbarBottomUseOverflowMenu below (see
	/// ToolbarFunction). Key.articleToolbarUseOverflowMenu is retained as
	/// a migration-source-only key, same "do not reintroduce a property
	/// for this key" convention as Key.useTintedNavigationBar above --
	/// read directly via AppDefaults.bool(for:) by
	/// migrateUnifiedToolbarsIfNeeded() only.

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

	/// Table-driven key lookup for the unified toolbar model: (inline key,
	/// overflow key) per (ToolbarFunction, ToolbarBar). A hand-written
	/// 13-function x 2-bar x 2-role switch would be 52 near-identical
	/// cases; this keeps the mapping in one place and the read/write
	/// dispatch functions below as thin wrappers. Force-unwrapped
	/// dictionary lookups are safe here because ToolbarFunction/ToolbarBar
	/// are both closed enums fully enumerated in toolbarFunctionKeys'
	/// literal below -- AppDefaultsBackupTests / a unit test should assert
	/// every ToolbarFunction x ToolbarBar pair resolves, so an
	/// accidentally-omitted case fails a test rather than crashing at
	/// runtime on first use.
	private static let toolbarFunctionKeys: [ToolbarFunction: [ToolbarBar: (inline: String, overflow: String)]] = [
		.theme: [.top: (Key.toolbarFnThemeTop, Key.toolbarFnThemeTopOverflow), .bottom: (Key.toolbarFnThemeBottom, Key.toolbarFnThemeBottomOverflow)],
		.tableOfContents: [.top: (Key.toolbarFnTableOfContentsTop, Key.toolbarFnTableOfContentsTopOverflow), .bottom: (Key.toolbarFnTableOfContentsBottom, Key.toolbarFnTableOfContentsBottomOverflow)],
		.find: [.top: (Key.toolbarFnFindTop, Key.toolbarFnFindTopOverflow), .bottom: (Key.toolbarFnFindBottom, Key.toolbarFnFindBottomOverflow)],
		.prevNext: [.top: (Key.toolbarFnPrevNextTop, Key.toolbarFnPrevNextTopOverflow), .bottom: (Key.toolbarFnPrevNextBottom, Key.toolbarFnPrevNextBottomOverflow)],
		.lock: [.top: (Key.toolbarFnLockTop, Key.toolbarFnLockTopOverflow), .bottom: (Key.toolbarFnLockBottom, Key.toolbarFnLockBottomOverflow)],
		.annotations: [.top: (Key.toolbarFnAnnotationsTop, Key.toolbarFnAnnotationsTopOverflow), .bottom: (Key.toolbarFnAnnotationsBottom, Key.toolbarFnAnnotationsBottomOverflow)],
		.settings: [.top: (Key.toolbarFnSettingsTop, Key.toolbarFnSettingsTopOverflow), .bottom: (Key.toolbarFnSettingsBottom, Key.toolbarFnSettingsBottomOverflow)],
		.checkForUpdates: [.top: (Key.toolbarFnCheckForUpdatesTop, Key.toolbarFnCheckForUpdatesTopOverflow), .bottom: (Key.toolbarFnCheckForUpdatesBottom, Key.toolbarFnCheckForUpdatesBottomOverflow)],
		.read: [.top: (Key.toolbarFnReadTop, Key.toolbarFnReadTopOverflow), .bottom: (Key.toolbarFnReadBottom, Key.toolbarFnReadBottomOverflow)],
		.star: [.top: (Key.toolbarFnStarTop, Key.toolbarFnStarTopOverflow), .bottom: (Key.toolbarFnStarBottom, Key.toolbarFnStarBottomOverflow)],
		.heart: [.top: (Key.toolbarFnHeartTop, Key.toolbarFnHeartTopOverflow), .bottom: (Key.toolbarFnHeartBottom, Key.toolbarFnHeartBottomOverflow)],
		.nextUnread: [.top: (Key.toolbarFnNextUnreadTop, Key.toolbarFnNextUnreadTopOverflow), .bottom: (Key.toolbarFnNextUnreadBottom, Key.toolbarFnNextUnreadBottomOverflow)],
		.action: [.top: (Key.toolbarFnActionTop, Key.toolbarFnActionTopOverflow), .bottom: (Key.toolbarFnActionBottom, Key.toolbarFnActionBottomOverflow)],
	]

	private func toolbarKeys(_ function: ToolbarFunction, _ bar: ToolbarBar) -> (inline: String, overflow: String) {
		guard let keys = AppDefaults.toolbarFunctionKeys[function]?[bar] else {
			fatalError("Missing toolbarFunctionKeys entry for \(function)/\(bar) -- every ToolbarFunction x ToolbarBar pair must be present in the table above.")
		}
		return keys
	}

	/// Whether `function` is placed inline (not in the overflow menu) on
	/// `bar`. Used anywhere placement needs to be read generically --
	/// ToolbarsCustomizerViewController's row loop, ArticleViewController's
	/// bar-building, SettingsViewController's summary label -- instead of
	/// a per-function switch at each call site.
	func isToolbarFunctionEnabled(_ function: ToolbarFunction, on bar: ToolbarBar) -> Bool {
		AppDefaults.bool(for: toolbarKeys(function, bar).inline)
	}

	/// Setting a function inline on a bar also clears that same function's
	/// overflow flag on that same bar -- inline and overflow are mutually
	/// exclusive *per bar* (the ToolbarsCustomizerViewController mockup's
	/// rule: an overflow-menu table only offers functions not already
	/// placed inline in that same bar). This enforces the invariant at
	/// the model layer, not just in the UI that happens to filter the
	/// overflow list -- a future direct writer of this property can't
	/// leave both flags set for the same (function, bar).
	func setToolbarFunctionEnabled(_ function: ToolbarFunction, on bar: ToolbarBar, _ enabled: Bool) {
		let keys = toolbarKeys(function, bar)
		AppDefaults.setBool(for: keys.inline, enabled)
		if enabled {
			AppDefaults.setBool(for: keys.overflow, false)
		}
	}

	/// Whether `function` is placed in `bar`'s overflow menu. Only
	/// meaningful when that bar's own toolbarTopUseOverflowMenu/
	/// toolbarBottomUseOverflowMenu is also true -- ToolbarsCustomizerViewController
	/// hides the overflow-picks section entirely when the bar's overflow
	/// switch is off, same as this property being false for everything
	/// in that state.
	func isToolbarFunctionInOverflow(_ function: ToolbarFunction, on bar: ToolbarBar) -> Bool {
		AppDefaults.bool(for: toolbarKeys(function, bar).overflow)
	}

	/// Setting a function into a bar's overflow also clears that same
	/// function's inline flag on that same bar -- same mutual-exclusion
	/// invariant as setToolbarFunctionEnabled(_:on:_:) above, enforced
	/// symmetrically from this direction too.
	func setToolbarFunctionInOverflow(_ function: ToolbarFunction, on bar: ToolbarBar, _ inOverflow: Bool) {
		let keys = toolbarKeys(function, bar)
		AppDefaults.setBool(for: keys.overflow, inOverflow)
		if inOverflow {
			AppDefaults.setBool(for: keys.inline, false)
		}
	}

	/// Slots `function` costs toward its bar's icon cap when placed
	/// inline -- prevNext counts as 2 (it renders both prev and next as
	/// separate bar items), everything else counts as 1. Does not apply
	/// to overflow placement (see ToolbarsCustomizerViewController's cap
	/// logic: the cap protects each bar's fixed-width leading/trailing
	/// icon cluster, and a function inside the overflow menu doesn't
	/// occupy a slot in that cluster).
	static func toolbarFunctionSlotCost(_ function: ToolbarFunction) -> Int {
		function == .prevNext ? 2 : 1
	}

	/// Shipped default display order per bar -- also what registerDefaults()
	/// seeds the persisted order keys to, and what resetToolbarDefaults(for:)
	/// restores by removing the persisted key entirely (so the default only
	/// has to be correct in this one place). Matches the pre-order-persistence
	/// hardcoded arrays that used to live independently in
	/// ArticleViewController.displayOrder(for:) and ToolbarPreviewCell.configure(bar:).
	static func defaultToolbarFunctionOrder(for bar: ToolbarBar) -> [ToolbarFunction] {
		let native: [ToolbarFunction] = bar == .top
			? [.theme, .tableOfContents, .find, .prevNext, .lock, .annotations, .settings, .checkForUpdates]
			: [.read, .star, .heart, .nextUnread, .action]
		let rest = ToolbarFunction.allCases.filter { !native.contains($0) }
		return native + rest
	}

	/// The person's current display order for `bar` -- read by
	/// ArticleViewController.displayOrder(for:) (the real reader),
	/// ToolbarPreviewCell.configure(bar:) (the settings preview), and
	/// ToolbarsCustomizerViewController's functions table (the reorderable
	/// list itself), so all three stay on one source instead of the three
	/// independent hardcoded arrays this replaced.
	///
	/// Decodes the persisted rawValue array back into ToolbarFunction,
	/// silently dropping any string that no longer maps to a case (e.g.
	/// a case removed in a future version) and appending, in
	/// defaultToolbarFunctionOrder(for:) order, any ToolbarFunction
	/// missing from the stored array (covers a case added after someone
	/// already saved a custom order, and covers a first run before
	/// registerDefaults() has populated the key in an unregistered
	/// UserDefaults suite such as a unit test).
	func toolbarFunctionOrder(for bar: ToolbarBar) -> [ToolbarFunction] {
		let key = bar == .top ? Key.toolbarTopFunctionOrder : Key.toolbarBottomFunctionOrder
		let stored = (AppDefaults.stringArray(for: key) ?? []).compactMap { ToolbarFunction(rawValue: $0) }
		let missing = ToolbarFunction.allCases.filter { !stored.contains($0) }
		return stored + AppDefaults.defaultToolbarFunctionOrder(for: bar).filter { missing.contains($0) }
	}

	/// Persists a new display order for `bar` -- written by
	/// ToolbarsCustomizerViewController's collectionView(_:moveItemAt:to:)
	/// after a drag-reorder. `order` should contain every ToolbarFunction
	/// exactly once; toolbarFunctionOrder(for:) tolerates a short/stale
	/// array on read, but callers should still pass a complete list.
	func setToolbarFunctionOrder(_ order: [ToolbarFunction], for bar: ToolbarBar) {
		let key = bar == .top ? Key.toolbarTopFunctionOrder : Key.toolbarBottomFunctionOrder
		AppDefaults.setStringArray(for: key, order.map(\.rawValue))
	}

	/// Resets every ToolbarFunction's placement (inline/overflow, both
	/// cleared to off), that bar's overflow-menu switch, and that bar's
	/// display order back to the shipped defaults -- scoped to `bar`
	/// only, matching ToolbarsCustomizerViewController's per-bar-tab
	/// framing (its "Reset" button resets whichever bar is active, not
	/// both at once).
	///
	/// Implemented as key removal, not as re-writing the literal default
	/// values -- removing a UserDefaults key falls back to whatever
	/// registerDefaults() already registered for it, so the default only
	/// needs to be correct in registerDefaults() (for placement/overflow)
	/// and defaultToolbarFunctionOrder(for:) (for order), not duplicated
	/// a third time here. UserDefaults.removeObject(forKey:) posts
	/// .didChangeNotification on .standard, so
	/// ToolbarsCustomizerViewController's existing generic-notification
	/// reload picks this up with no additional wiring.
	func resetToolbarDefaults(for bar: ToolbarBar) {
		for function in ToolbarFunction.allCases {
			let keys = toolbarKeys(function, bar)
			AppDefaults.store.removeObject(forKey: keys.inline)
			AppDefaults.store.removeObject(forKey: keys.overflow)
		}
		let overflowKey = bar == .top ? Key.toolbarTopUseOverflowMenu : Key.toolbarBottomUseOverflowMenu
		AppDefaults.store.removeObject(forKey: overflowKey)
		let orderKey = bar == .top ? Key.toolbarTopFunctionOrder : Key.toolbarBottomFunctionOrder
		AppDefaults.store.removeObject(forKey: orderKey)
	}

	/// Whether the "Toggle Read" button appears in the article reader's
	/// bottom toolbar. Defaults to true -- see BottomToolbarToggle's own
	/// doc comment for why this group's default differs from
	/// ArticleToolbarToggle's opt-in-off-by-default extras.
	var bottomToolbarShowRead: Bool {
		get {
			return AppDefaults.bool(for: Key.bottomToolbarShowRead)
		}
		set {
			AppDefaults.setBool(for: Key.bottomToolbarShowRead, newValue)
		}
	}

	/// Whether the "Toggle Starred" (Read Later) button appears in the
	/// article reader's bottom toolbar. Defaults to true.
	var bottomToolbarShowStar: Bool {
		get {
			return AppDefaults.bool(for: Key.bottomToolbarShowStar)
		}
		set {
			AppDefaults.setBool(for: Key.bottomToolbarShowStar, newValue)
		}
	}

	/// Whether the "Loved" heart button appears in the article reader's
	/// bottom toolbar. Defaults to true.
	var bottomToolbarShowHeart: Bool {
		get {
			return AppDefaults.bool(for: Key.bottomToolbarShowHeart)
		}
		set {
			AppDefaults.setBool(for: Key.bottomToolbarShowHeart, newValue)
		}
	}

	/// Whether the "Next Unread" button appears in the article reader's
	/// bottom toolbar. Defaults to true.
	var bottomToolbarShowNextUnread: Bool {
		get {
			return AppDefaults.bool(for: Key.bottomToolbarShowNextUnread)
		}
		set {
			AppDefaults.setBool(for: Key.bottomToolbarShowNextUnread, newValue)
		}
	}

	/// Whether the share/action button appears in the article reader's
	/// bottom toolbar. Defaults to true.
	var bottomToolbarShowAction: Bool {
		get {
			return AppDefaults.bool(for: Key.bottomToolbarShowAction)
		}
		set {
			AppDefaults.setBool(for: Key.bottomToolbarShowAction, newValue)
		}
	}

	/// No live dispatch functions here anymore -- isBottomToolbarToggleEnabled(_:)/
	/// setBottomToolbarToggleEnabled(_:_:) switched over BottomToolbarToggle,
	/// which no longer exists post-unification. Replaced by
	/// isToolbarFunctionEnabled(_:on:)/setToolbarFunctionEnabled(_:on:_:)
	/// (see ToolbarFunction), parameterized by ToolbarBar instead of
	/// being two separate top/bottom dispatch pairs. The individual
	/// bottomToolbarShowRead/ShowStar/ShowHeart/ShowNextUnread/ShowAction
	/// properties above are retained as migration-source-only reads for
	/// migrateUnifiedToolbarsIfNeeded() -- do not reintroduce a switch
	/// dispatch over a per-bar toggle enum for them.

	/// Whether the top toolbar collapses its overflow-flagged functions
	/// into a single trailing menu icon. Replaces the pre-unification
	/// articleToolbarUseOverflowMenu (top-only, no bottom counterpart) --
	/// see migrateUnifiedToolbarsIfNeeded() for the one-time carry-over.
	var toolbarTopUseOverflowMenu: Bool {
		get {
			return AppDefaults.bool(for: Key.toolbarTopUseOverflowMenu)
		}
		set {
			AppDefaults.setBool(for: Key.toolbarTopUseOverflowMenu, newValue)
		}
	}

	/// Whether the bottom toolbar collapses its overflow-flagged
	/// functions into a single trailing menu icon. New with unification
	/// -- the bottom bar had no overflow concept at all before (see
	/// ToolbarFunction's own doc comment on the pre-unification bottom
	/// bar never having a cap or an overflow menu).
	var toolbarBottomUseOverflowMenu: Bool {
		get {
			return AppDefaults.bool(for: Key.toolbarBottomUseOverflowMenu)
		}
		set {
			AppDefaults.setBool(for: Key.toolbarBottomUseOverflowMenu, newValue)
		}
	}

	/// Dispatch over toolbarTopUseOverflowMenu/toolbarBottomUseOverflowMenu
	/// by ToolbarBar, for call sites that already have a bar value in
	/// hand (ToolbarsCustomizerViewController's per-tab logic) rather
	/// than a hardcoded .top or .bottom.
	func isToolbarOverflowMenuEnabled(on bar: ToolbarBar) -> Bool {
		switch bar {
		case .top: return toolbarTopUseOverflowMenu
		case .bottom: return toolbarBottomUseOverflowMenu
		}
	}

	func setToolbarOverflowMenuEnabled(on bar: ToolbarBar, _ enabled: Bool) {
		switch bar {
		case .top: toolbarTopUseOverflowMenu = enabled
		case .bottom: toolbarBottomUseOverflowMenu = enabled
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

	/// When the article web view shows its native vertical scroll
	/// indicator. .whenNotFullScreen by default (via registerDefaults),
	/// preserving the system's normal scrollbar behavior outside of
	/// fullscreen reading, where the app's own chrome is already hidden.
	/// Read fresh (not cached) wherever it's consulted -- same
	/// "reasserted on every dequeue" convention this file already uses
	/// for pinchGestureRecognizer.isEnabled on the pooled
	/// PreloadedWebView -- so a Settings change takes effect the next
	/// time an article (re)loads, and
	/// WebViewController.updateScrollbarVisibility() can also re-derive
	/// visibility live as fullscreen is entered/exited without a reload.
	var articleScrollbarVisibility: ArticleScrollbarVisibility {
		get {
			guard let raw = AppDefaults.string(for: Key.showArticleScrollbar),
				  let value = ArticleScrollbarVisibility(rawValue: raw) else {
				return .whenNotFullScreen
			}
			return value
		}
		set {
			AppDefaults.setString(for: Key.showArticleScrollbar, newValue.rawValue)
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

	/// Which HighlightPalette an annotation's fixed color key resolves to.
	/// Posts synchronously on set, same contract as accentColor/surfaceTint
	/// above -- see those two setters' shared "Live-update pipeline shape"
	/// writeup in docs/app-chrome-palette.md, which now also covers this
	/// property.
	var highlightPalette: HighlightPalette {
		get {
			let rawValue = AppDefaults.store.integer(forKey: Key.highlightPalette)
			return HighlightPalette(rawValue: rawValue) ?? .default
		}
		set {
			AppDefaults.store.set(newValue.rawValue, forKey: Key.highlightPalette)
			NotificationCenter.default.post(name: .highlightPaletteDidChange, object: nil)
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

	/// One-time upgrade off the old Bool-backed showArticleScrollbar key
	/// onto ArticleScrollbarVisibility's String rawValue, sharing the
	/// same on-disk key name (Key.showArticleScrollbar) -- see
	/// articleScrollbarVisibility's own doc comment. Gated on a value
	/// actually being present as a Bool: a fresh install has nothing
	/// under this key yet, so registerDefaults()'s own String default is
	/// left alone rather than being immediately overwritten here.
	@MainActor func migrateArticleScrollbarVisibilityIfNeeded() {
		guard !AppDefaults.bool(for: Key.hasMigratedArticleScrollbarVisibility) else { return }
		AppDefaults.setBool(for: Key.hasMigratedArticleScrollbarVisibility, true)
		guard AppDefaults.store.object(forKey: Key.showArticleScrollbar) is Bool else { return }
		let wasOn = AppDefaults.bool(for: Key.showArticleScrollbar)
		articleScrollbarVisibility = wasOn ? .whenNotFullScreen : .off
	}

	/// One-time migration off the pre-unification split model (top-only
	/// ArticleToolbarToggle backed by articleToolbarShow*, bottom-only
	/// BottomToolbarToggle backed by bottomToolbarShow*, and a single
	/// articleToolbarUseOverflowMenu Bool that only ever applied to the
	/// top bar) onto the unified ToolbarFunction model, where every
	/// function has an independent inline/overflow flag per bar.
	///
	/// Must run after migrateArticleToolbarTogglesIfNeeded() -- this
	/// function reads the *properties* that one writes
	/// (articleToolbarShowTableOfContents etc.), not the older raw
	/// showTableOfContentsAndFind/showPrevNextArticleButtons keys
	/// directly, so an upgrader coming from before *that* migration ran
	/// still ends up with correct placement here. AppDelegate calls both,
	/// in that order.
	///
	/// Placement, not just on/off: every legacy top toggle becomes that
	/// function placed inline on .top; every legacy bottom toggle becomes
	/// that function placed inline on .bottom. Nothing is placed on the
	/// *other* bar (e.g. .theme does not appear on .bottom just because
	/// duplicates-across-bars is now allowed) -- migration preserves
	/// prior behavior exactly, it doesn't opt anyone into the new
	/// cross-bar duplication feature.
	///
	/// Overflow: the legacy articleToolbarUseOverflowMenu Bool becomes
	/// toolbarTopUseOverflowMenu. There is no legacy concept of *which*
	/// functions were "in" the overflow menu (the old switch collapsed
	/// everything-that-was-already-enabled into the menu, with no
	/// separate per-function membership), so migration does not populate
	/// any toolbarFn*Overflow keys -- an upgrader who had the top overflow
	/// switch on keeps seeing the same functions, just now via the
	/// isToolbarFunctionEnabled(_:on:.top) inline flags feeding the
	/// overflow menu the same way they did pre-unification, until they
	/// visit the new Toolbars screen and choose to move something into
	/// overflow explicitly. toolbarBottomUseOverflowMenu has no legacy
	/// counterpart at all (the bottom bar never had an overflow concept)
	/// and stays at its registered-default false.
	@MainActor func migrateUnifiedToolbarsIfNeeded() {
		guard !AppDefaults.bool(for: Key.hasMigratedUnifiedToolbars) else { return }
		AppDefaults.setBool(for: Key.hasMigratedUnifiedToolbars, true)

		let legacyTopEnabled: [ToolbarFunction: Bool] = [
			.theme: articleToolbarShowTheme,
			.tableOfContents: articleToolbarShowTableOfContents,
			.find: articleToolbarShowFind,
			.prevNext: articleToolbarShowPrevNext,
			.lock: articleToolbarShowLock,
			.annotations: articleToolbarShowAnnotations,
			.settings: articleToolbarShowSettings,
			.checkForUpdates: articleToolbarShowCheckForUpdates,
		]
		for (function, wasEnabled) in legacyTopEnabled where wasEnabled {
			setToolbarFunctionEnabled(function, on: .top, true)
		}

		let legacyBottomEnabled: [ToolbarFunction: Bool] = [
			.read: bottomToolbarShowRead,
			.star: bottomToolbarShowStar,
			.heart: bottomToolbarShowHeart,
			.nextUnread: bottomToolbarShowNextUnread,
			.action: bottomToolbarShowAction,
		]
		for (function, wasEnabled) in legacyBottomEnabled where wasEnabled {
			setToolbarFunctionEnabled(function, on: .bottom, true)
		}

		AppDefaults.setBool(for: Key.toolbarTopUseOverflowMenu, AppDefaults.bool(for: Key.articleToolbarUseOverflowMenu))
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
									Key.bottomToolbarShowRead: true,
									Key.bottomToolbarShowStar: true,
									Key.bottomToolbarShowHeart: true,
									Key.bottomToolbarShowNextUnread: true,
									Key.bottomToolbarShowAction: true,
									// Fresh-install defaults for the unified model, mirroring the
									// legacy per-bar defaults just above -- upgraders instead get
									// these keys populated by migrateUnifiedToolbarsIfNeeded()
									// reading the legacy keys, so these registered values only
									// take effect for a install that never had the legacy keys set.
									// Top bar: theme/tableOfContents/find on, prevNext/lock off
									// (matches articleToolbarShow* above). Bottom bar: all five
									// on (matches bottomToolbarShow* above, "existing always-on
									// bottom bar" -- see ToolbarFunction's own doc comment).
									// Every function defaults off on the bar it doesn't belong to
									// pre-unification (e.g. .read on .top, .theme on .bottom) --
									// AppDefaults.bool(for:)'s implicit-false fallback covers those,
									// so only the "on" cases need an explicit entry here.
									Key.toolbarFnThemeTop: true,
									Key.toolbarFnTableOfContentsTop: true,
									Key.toolbarFnFindTop: true,
									Key.toolbarFnReadBottom: true,
									Key.toolbarFnStarBottom: true,
									Key.toolbarFnHeartBottom: true,
									Key.toolbarFnNextUnreadBottom: true,
									Key.toolbarFnActionBottom: true,
									// Display order, one array per bar, registered from the
									// single defaultToolbarFunctionOrder(for:) source rather
									// than a fourth hand-copied literal -- see that function's
									// own doc comment for what previously held this order
									// (three independent hardcoded arrays).
									Key.toolbarTopFunctionOrder: AppDefaults.defaultToolbarFunctionOrder(for: .top).map(\.rawValue),
									Key.toolbarBottomFunctionOrder: AppDefaults.defaultToolbarFunctionOrder(for: .bottom).map(\.rawValue),
									Key.hideNotchInFullScreen: true,
									Key.pageCounterDisplayMode: PageCounterDisplayMode.percentage.rawValue,
									Key.showLastUpdatedLabel: false,
									Key.showArticleScrollbar: ArticleScrollbarVisibility.whenNotFullScreen.rawValue,
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

	static func stringArray(for key: String) -> [String]? {
		return AppDefaults.store.array(forKey: key) as? [String]
	}

	static func setStringArray(for key: String, _ value: [String]?) {
		AppDefaults.store.set(value, forKey: key)
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
