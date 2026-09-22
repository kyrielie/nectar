import Foundation
import UIKit
import Articles

public enum BadgeColorPalette: Int, CaseIterable, Sendable {
	case monochrome = 1
	case `default` = 2
	case semantic = 3
	case transparent = 4
	case accent = 5

	public var description: String {
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
public enum AccentColor: Int, CaseIterable, Sendable {
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

	public var description: String {
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
	public var primaryHex: String? {
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

	public var secondaryHex: String? {
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
	public struct IconHexSet {
		/// Assets.Images.mainFolder
		public var folder: String
		/// Assets.Images.unreadFeed
		public var unreadFeed: String
		/// Assets.Images.readFeed
		public var readFeed: String
		/// Assets.Images.lastOpenedFeed
		public var lastOpenedFeed: String
		/// Assets.Images.unreadCellIndicator
		public var unreadCellIndicator: String
		/// Assets.Images.starredFeed / Assets.Images.timelineStar -- folded
		/// in here so star tracks the same per-palette override path as
		/// every other icon slot instead of being the one exception that
		/// stayed pinned to the asset-catalog "starColor".
		public var star: String
		/// Assets.Images.todayFeed -- was the hardcoded UIColor.systemOrange
		/// literal before this type existed.
		public var today: String
		/// Assets.Images.lovedFeed -- was the hardcoded RSColor.systemRed
		/// literal before this type existed.
		public var loved: String
	}

	/// nil for `.default` -- same "fall back to the existing asset-catalog
	/// color / hardcoded literal" contract as `primaryHex`/`secondaryHex`.
	/// Every other case supplies a complete `IconHexSet`; there is no
	/// per-field fallback within a non-default case, the same way
	/// `SurfacePalette.HexSet` has no per-field fallback -- a palette that
	/// wants "everything from .rosePine except the star" is expressed by
	/// copying .rosePine's set and changing one field, not by leaving a
	/// field unset.
	public var iconHexSet: IconHexSet? {
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
public enum HighlightPalette: Int, CaseIterable, Sendable {
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

	public var description: String {
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
	public struct HexSet {
		public var yellow: String
		public var red: String
		public var green: String
		public var blue: String
		public var purple: String

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

	public var lightHexSet: HexSet {
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
	public var darkHexSet: HexSet {
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

	public func hexSet(isDark: Bool) -> HexSet {
		isDark ? darkHexSet : lightHexSet
	}
}
public enum SurfacePalette: Int, CaseIterable, Sendable {
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

	public var description: String {
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

	public struct HexSet {
		public var barBackground: String
		public var fullScreenBackground: String
		public var vibrantText: String
		/// Nav bar background, consumed by whichever view/controller installs
		/// a `UINavigationBarAppearance` -- see `ArticleViewController.viewDidLoad()`.
		public var navigationBarBackground: String
		/// Nav bar back-button/title tint, paired with `navigationBarBackground`.
		public var navigationBarTint: String
		/// Backdrop for settings/list table and collection views -- see
		/// Assets.Colors.settingsBackground(for:)/listBackground(for:).
		public var settingsBackground: String
		/// Individual settings-cell fill, distinct from `settingsBackground`
		/// so grouped-card contrast survives palette overrides -- see
		/// Assets.Colors.settingsCellBackground(for:).
		public var settingsCellBackground: String
		/// Feed list + timeline backdrop -- see Assets.Colors.listBackground(for:).
		public var listBackground: String
	}

	/// nil for `.default` -- same "fall back to the asset catalog" contract as
	/// AccentColor.primaryHex/secondaryHex.
	public var lightHexSet: HexSet? {
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

	public var darkHexSet: HexSet? {
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
