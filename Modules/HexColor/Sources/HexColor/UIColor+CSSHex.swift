//
//  UIColor+CSSHex.swift
//  HexColor
//
//  Copyright © 2026 Ranchero Software, LLC. All rights reserved.
//
//  Extracted from Shared/ArticleStyles/ArticleThemeColorExtractor.swift
//  (Modularization Stage 0a). Used across the Accent Color / Surface
//  Palette / Badge Color / Highlight Palette systems, and by
//  ArticleTheming's own CSS-value parser (Stage 0b) -- see
//  docs/module-layout.md for the current package list.
//

import UIKit

public extension UIColor {

	convenience init?(cssHex: String) {
		var hex = cssHex.trimmingCharacters(in: .whitespacesAndNewlines)
		if hex.hasPrefix("#") {
			hex.removeFirst()
		}
		if hex.count == 3 {
			hex = hex.map { "\($0)\($0)" }.joined()
		}
		guard hex.count == 6, let rgbValue = UInt32(hex, radix: 16) else { return nil }
		let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
		let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
		let blue = CGFloat(rgbValue & 0x0000FF) / 255.0
		self.init(red: red, green: green, blue: blue, alpha: 1.0)
	}

	var cssHexString: String {
		var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
		getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
	}

	/// WCAG 2.x relative-luminance contrast ratio against another color,
	/// per https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio -- (L1+0.05)/(L2+0.05)
	/// with L1 the lighter of the two relative luminances. Used by
	/// HighlightPaletteHexSetTests to guard every HighlightPalette dark-mode
	/// HexSet against the bug that motivated dark-mode-tuning them in the
	/// first place: white article text on a highlight background that's
	/// still a light-mode-style pastel is nearly unreadable. Order of the
	/// two colors doesn't matter -- the ratio is symmetric by construction.
	func contrastRatio(against other: UIColor) -> CGFloat {
		func relativeLuminance(_ color: UIColor) -> CGFloat {
			var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
			color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
			func linearize(_ component: CGFloat) -> CGFloat {
				component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
			}
			return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
		}
		let l1 = relativeLuminance(self)
		let l2 = relativeLuminance(other)
		let lighter = max(l1, l2)
		let darker = min(l1, l2)
		return (lighter + 0.05) / (darker + 0.05)
	}
}
