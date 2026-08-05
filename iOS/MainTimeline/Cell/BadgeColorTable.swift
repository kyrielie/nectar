//
//  BadgeColorTable.swift
//  NetNewsWire-iOS
//
//  Personalization & Theming plan, item 2 ("Toggleable colored badges").
//  Literal-string lookup tables for rating/category/warning pill tinting
//  under BadgeColorMode.colored -- fandom pills stay neutral in both modes
//  (see BadgeCategory's doc comment in MainTimelineCellData.swift).
//
//  Colors here are built directly from the plan's hex values via
//  UIColor(cssHex:) (ArticleThemeColorExtractor.swift) rather than as
//  Assets.xcassets colorset entries, the way primaryAccentColor/etc. are --
//  the exported source tree this was built against has no Assets.xcassets
//  at all (flagged as an open item in the plan itself), so the exact path
//  to add colorset folders under iOS/Shared couldn't be confirmed. Same
//  visual result, light/dark-adaptive; migrating these to real colorset
//  entries later is a mechanical follow-up once that path is confirmed,
//  not a behavior change.
//

import UIKit

enum BadgeColorTable {

	/// Ratings (5): Not Rated, General Audiences, Teen And Up Audiences,
	/// Mature, Explicit -- AO3's fixed rating vocabulary.
	private static let ratingBackgrounds: [String: String] = [
		"General Audiences": "#9ccfd8",
		"Teen And Up Audiences": "#3e8fb0",
		"Mature": "#ebbcba",
		"Explicit": "#eb6f92"
		// "Not Rated" and anything unrecognized fall through to neutralBackground.
	]

	/// Categories (6): F/F, F/M, Gen, M/M, Multi, Other -- AO3's fixed
	/// relationship-category vocabulary (article.categories, not
	/// article.relationships -- see BadgeCategory's doc comment).
	private static let categoryBackgrounds: [String: String] = [
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
	private static let warningBackgrounds: [String: String] = [
		"Creator Chose Not To Use Archive Warnings": "#9ccfd8",
		"No Archive Warnings Apply": "#9ccfd8",
		"Graphic Depictions Of Violence": "#eb6f92",
		"Major Character Death": "#eb6f92",
		"Rape/Non-Con": "#eb6f92",
		"Underage": "#eb6f92"
	]

	private static let neutralBackgroundHex = "#8E8E93" // system gray, appearance-neutral fallback

	/// Background/text color pair for a badge, per `BadgeColorMode`.
	/// `.neutral` (or `.fandom`/unmatched text) returns the same
	/// `.tertiarySystemFill`/`.secondaryLabel` pair `.badges` mode has
	/// always used, so opting out is a zero-behavior-change no-op.
	static func colors(for text: String, category: BadgeCategory?, mode: BadgeColorMode) -> (background: UIColor, text: UIColor) {
		guard mode == .colored, let category, category != .fandom else {
			return (.tertiarySystemFill, .secondaryLabel)
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
	/// elsewhere in this app) -- dark text on the plan's light/pastel
	/// backgrounds, light text on the few saturated ones.
	private static func textColor(against background: UIColor) -> UIColor {
		var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
		background.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
		return luminance > 0.6 ? .black : .white
	}
}
