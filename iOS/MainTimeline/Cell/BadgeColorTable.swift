//
//  BadgeColorTable.swift
//  NetNewsWire-iOS
//
//  Toggleable colored badges, restructured (see docs/app-chrome-palette.md,
//  "Badge Colors") from a
//  single hardcoded hex set into one set per BadgeColorPalette case --
//  `.default` is today's set, renamed not redesigned; `.semantic` is new.
//  Literal-string lookup tables for rating/category/warning pill tinting
//  under any non-monochrome BadgeColorPalette -- fandom pills stay neutral
//  in every palette (see BadgeCategory's doc comment in
//  MainTimelineCellData.swift).
//
//  Colors here are built directly from hex values via UIColor(cssHex:)
//  (ArticleThemeColorExtractor.swift) rather than as Assets.xcassets
//  colorset entries, the way primaryAccentColor/etc. are -- these are
//  per-value lookup tables (five ratings, six categories, six warnings,
//  per palette), which doesn't map cleanly onto one colorset per swatch
//  the way a small fixed set of chrome colors does. Same visual result,
//  light/dark-adaptive; migrating these to real colorset entries later is
//  a mechanical follow-up, not a behavior change.
//
//  See docs/app-chrome-palette.md ("Badge Colors"): BadgeColorPalette grew from three cases
//  (neutral/default/semantic) to five (monochrome/default/semantic/
//  transparent/accent). `.neutral` was renamed to `.monochrome` --
//  same behavior, clearer name (it's not "no color," it's specifically
//  no-hue tertiarySystemFill/secondaryLabel). `.transparent` and
//  `.accent` are new -- see their respective sections below.
//

import UIKit

enum BadgeColorTable {

	/// Ratings (5): Not Rated, General Audiences, Teen And Up Audiences,
	/// Mature, Explicit -- AO3's fixed rating vocabulary.
	private static let defaultRatingBackgrounds: [String: String] = [
		"General Audiences": "#9ccfd8",
		"Teen And Up Audiences": "#3e8fb0",
		"Mature": "#ebbcba",
		"Explicit": "#eb6f92"
		// "Not Rated" and anything unrecognized fall through to neutralBackground.
	]

	/// Categories (6): F/F, F/M, Gen, M/M, Multi, Other -- AO3's fixed
	/// relationship-category vocabulary (article.categories, not
	/// article.relationships -- see BadgeCategory's doc comment).
	private static let defaultCategoryBackgrounds: [String: String] = [
		"Gen": "#9ccfd8",
		"F/M": "#3e8fb0",
		"F/F": "#ebbcba",
		"M/M": "#eb6f92",
		// Source uses a conic gradient across all four hues for Multi; a flat
		// representative lavender stands in since UIKit pills can't do
		// gradients cleanly.
		"Multi": "#c4a7e7"
		// "Other" and anything unrecognized fall through to neutralBackground.
	]

	/// Warnings are free text pulled from AO3's own markup, not a fixed enum
	/// anywhere in this app -- AO3 constrains this in practice to ~6
	/// canonical strings, but nothing enforces that client-side, so this is
	/// a literal-string lookup with a neutral fallback for anything else.
	private static let defaultWarningBackgrounds: [String: String] = [
		"Creator Chose Not To Use Archive Warnings": "#9ccfd8",
		"No Archive Warnings Apply": "#9ccfd8",
		"Graphic Depictions Of Violence": "#eb6f92",
		"Major Character Death": "#eb6f92",
		"Rape/Non-Con": "#eb6f92",
		"Underage": "#eb6f92"
	]

	/// Severity-coded rather than aesthetic: ratings and warnings read as a
	/// calm -> caution -> serious traffic-light scale. Categories aren't
	/// severity-bearing, so they get their own cool-toned set instead of
	/// competing with the rating/warning signal.
	private static let semanticRatingBackgrounds: [String: String] = [
		"General Audiences": "#6fa971",
		"Teen And Up Audiences": "#d9a941",
		"Mature": "#d97f3f",
		"Explicit": "#c0483f"
	]

	private static let semanticCategoryBackgrounds: [String: String] = [
		"Gen": "#6d8ba7",
		"F/M": "#4d8f8b",
		"F/F": "#a8618f",
		"M/M": "#6a6db0",
		"Multi": "#8d75b3"
	]

	private static let semanticWarningBackgrounds: [String: String] = [
		"Creator Chose Not To Use Archive Warnings": "#6fa971",
		"No Archive Warnings Apply": "#6fa971",
		"Graphic Depictions Of Violence": "#c0483f",
		"Major Character Death": "#c0483f",
		"Rape/Non-Con": "#c0483f",
		"Underage": "#c0483f"
	]

	/// `.transparent` palette: no fill (`.clear`), text color comes
	/// straight from a hue table instead of being derived from a
	/// background via `textColor(against:)`. Reuses `.semantic`'s hues
	/// rather than curating a fifth hand-picked table -- they were already
	/// chosen with `textColor(against:)`'s contrast formula in mind
	/// (see semanticRatingBackgrounds' doc comment above) and read fine
	/// as flat foreground colors against both light and dark timeline
	/// backgrounds.
	private static let transparentRatingText: [String: String] = semanticRatingBackgrounds
	private static let transparentCategoryText: [String: String] = semanticCategoryBackgrounds
	private static let transparentWarningText: [String: String] = semanticWarningBackgrounds

	/// Shared across every non-monochrome palette -- this is the "we don't
	/// recognize this string" catch-all, not a palette-flavor choice, so it
	/// isn't duplicated per palette.
	private static let neutralBackgroundHex = "#8E8E93" // system gray, appearance-neutral fallback

	/// `.accent` palette: unlike every other case's fixed hex tables above,
	/// these are computed per-call from whatever AccentColor is currently
	/// selected, so badges recolor automatically when the person changes
	/// their accent choice -- no separate badge-specific setting to keep in
	/// sync. Ratings/categories/warnings each get a fixed hue-rotation
	/// offset away from the accent's primary hue, rather than an
	/// independently curated hex per (accentColor case x badge value) --
	/// that combinatorial table is exactly what a formula avoids having to
	/// hand-maintain.
	private static let accentRatingHueOffsets: [Double] = [0.0, 0.08, 0.15, 0.5] // General/Teen/Mature/Explicit -- same 4-value severity ramp shape as semanticRatingBackgrounds, but relative to the live accent hue instead of a fixed anchor
	private static let accentCategoryHueOffsets: [Double] = [0.0, 0.12, 0.25, 0.4, 0.55] // Gen/F-M/F-F/M-M/Multi
	private static let accentWarningHueOffsets: [Double] = [0.0, 0.0, 0.5, 0.5, 0.5, 0.5] // matches defaultWarningBackgrounds' calm/calm/serious x4 shape

	/// Rotates `accentColor`'s primary hue by each offset in
	/// `hueOffsets`, keeping saturation/brightness fixed, and returns the
	/// resulting hex strings in the same order. `AccentColor.default` has
	/// no `primaryHex`; anchored to rosePine's primary hue as `.default`'s
	/// accent-derived base in that case, since `.accent` badges still need
	/// *some* color to derive from even when the person hasn't chosen a
	/// non-default AccentColor.
	private static func accentDerivedBackgrounds(from accentColor: AccentColor, hueOffsets: [Double]) -> [String] {
		let baseHex = accentColor.primaryHex ?? "#3e8fb0"
		guard let base = UIColor(cssHex: baseHex) else { return hueOffsets.map { _ in neutralBackgroundHex } }
		var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
		base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
		return hueOffsets.map { offset in
			let newHue = (hue + CGFloat(offset)).truncatingRemainder(dividingBy: 1.0)
			let color = UIColor(hue: newHue < 0 ? newHue + 1.0 : newHue, saturation: saturation, brightness: brightness, alpha: 1.0)
			return color.cssHexString
		}
	}

	private static func accentDerivedRatingBackgrounds(from accentColor: AccentColor) -> [String: String] {
		let hexes = accentDerivedBackgrounds(from: accentColor, hueOffsets: accentRatingHueOffsets)
		return [
			"General Audiences": hexes[0],
			"Teen And Up Audiences": hexes[1],
			"Mature": hexes[2],
			"Explicit": hexes[3]
		]
	}

	private static func accentDerivedCategoryBackgrounds(from accentColor: AccentColor) -> [String: String] {
		let hexes = accentDerivedBackgrounds(from: accentColor, hueOffsets: accentCategoryHueOffsets)
		return [
			"Gen": hexes[0],
			"F/M": hexes[1],
			"F/F": hexes[2],
			"M/M": hexes[3],
			"Multi": hexes[4]
		]
	}

	private static func accentDerivedWarningBackgrounds(from accentColor: AccentColor) -> [String: String] {
		let hexes = accentDerivedBackgrounds(from: accentColor, hueOffsets: accentWarningHueOffsets)
		return [
			"Creator Chose Not To Use Archive Warnings": hexes[0],
			"No Archive Warnings Apply": hexes[1],
			"Graphic Depictions Of Violence": hexes[2],
			"Major Character Death": hexes[3],
			"Rape/Non-Con": hexes[4],
			"Underage": hexes[5]
		]
	}

	/// Background/text color pair for a badge, per `BadgeColorPalette`.
	/// `.monochrome` (or `.fandom`/unmatched category) returns the same
	/// `.tertiarySystemFill`/`.secondaryLabel` pair `.badges` mode has
	/// always used, so opting out is a zero-behavior-change no-op.
	static func colors(for text: String, category: BadgeCategory?, palette: BadgeColorPalette) -> (background: UIColor, text: UIColor) {
		guard palette != .monochrome, let category, category != .fandom else {
			return (.tertiarySystemFill, .secondaryLabel)
		}

		if palette == .transparent {
			let textHex: String
			switch category {
			case .rating:
				textHex = transparentRatingText[text] ?? neutralBackgroundHex
			case .category:
				textHex = transparentCategoryText[text] ?? neutralBackgroundHex
			case .warning:
				textHex = transparentWarningText[text] ?? neutralBackgroundHex
			case .fandom:
				textHex = neutralBackgroundHex // unreachable, guarded above
			}
			let textColor = UIColor(cssHex: textHex) ?? .secondaryLabel
			return (.clear, textColor)
		}

		let ratingBackgrounds: [String: String]
		let categoryBackgrounds: [String: String]
		let warningBackgrounds: [String: String]
		switch palette {
		case .default:
			ratingBackgrounds = defaultRatingBackgrounds
			categoryBackgrounds = defaultCategoryBackgrounds
			warningBackgrounds = defaultWarningBackgrounds
		case .semantic:
			ratingBackgrounds = semanticRatingBackgrounds
			categoryBackgrounds = semanticCategoryBackgrounds
			warningBackgrounds = semanticWarningBackgrounds
		case .accent:
			let accentColor = AppDefaults.shared.accentColor
			ratingBackgrounds = accentDerivedRatingBackgrounds(from: accentColor)
			categoryBackgrounds = accentDerivedCategoryBackgrounds(from: accentColor)
			warningBackgrounds = accentDerivedWarningBackgrounds(from: accentColor)
		case .monochrome, .transparent:
			// Handled by the early guard and the `.transparent` branch
			// above respectively -- unreachable here.
			preconditionFailure("\(palette) should have returned earlier")
		}

		let hex: String
		switch category {
		case .rating:
			hex = ratingBackgrounds[text] ?? neutralBackgroundHex
		case .category:
			hex = categoryBackgrounds[text] ?? neutralBackgroundHex
		case .warning:
			hex = warningBackgrounds[text] ?? neutralBackgroundHex
		case .fandom:
			hex = neutralBackgroundHex // unreachable, guarded above
		}

		guard let background = UIColor(cssHex: hex) else {
			return (.tertiarySystemFill, .secondaryLabel)
		}
		return (background, textColor(against: background))
	}

	/// Simple relative-luminance contrast check (same 0.299/0.587/0.114
	/// weighting CGImage+RSCore's icon-luminance code already uses
	/// elsewhere in this app) -- dark text on the light/pastel backgrounds,
	/// light text on the saturated ones. Every `.semantic` hex above was
	/// chosen with this formula in mind.
	private static func textColor(against background: UIColor) -> UIColor {
		var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
		background.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
		return luminance > 0.6 ? .black : .white
	}
}
