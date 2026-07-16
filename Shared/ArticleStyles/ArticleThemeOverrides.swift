//
//  ArticleThemeOverrides.swift
//  NetNewsWire
//
//  Created for Settings → Articles → Font & Color Overrides.
//  Copyright © 2026 Ranchero Software, LLC. All rights reserved.
//

import Foundation

/// User-chosen overrides for the reader view's typography and colors, layered on top
/// of whichever article theme (default or imported .nnwtheme) is currently active.
///
/// Every property is optional and independently nil-able: nil means "use whatever the
/// current theme specifies," so a person can override just the font size, say, while
/// leaving colors and line height alone. This intentionally mirrors how
/// AppDefaults.showFeedNameInReaderView / blockSwipesWhenBarsHidden already model a
/// single settings-driven toggle layered on top of theme-agnostic rendering -- see
/// ArticleRenderer.styleString(), which is where cssOverrideBlock gets appended.
struct ArticleThemeOverrides: Codable, Equatable, Sendable {

	var fontFamilyName: String?
	var fontSize: Double?
	var lineHeight: Double?
	var textColorHex: String?
	var backgroundColorHex: String?
	var linkColorHex: String?

	init(fontFamilyName: String? = nil, fontSize: Double? = nil, lineHeight: Double? = nil, textColorHex: String? = nil, backgroundColorHex: String? = nil, linkColorHex: String? = nil) {
		self.fontFamilyName = fontFamilyName
		self.fontSize = fontSize
		self.lineHeight = lineHeight
		self.textColorHex = textColorHex
		self.backgroundColorHex = backgroundColorHex
		self.linkColorHex = linkColorHex
	}

	var isEmpty: Bool {
		fontFamilyName == nil && fontSize == nil && lineHeight == nil && textColorHex == nil && backgroundColorHex == nil && linkColorHex == nil
	}

	/// Reasonable bounds for the Settings sliders. Below/above these the reader view
	/// either becomes unreadable or the layout breaks down (long lines, clipped chrome).
	static let fontSizeRange: ClosedRange<Double> = 12...32
	static let lineHeightRange: ClosedRange<Double> = 1.0...2.2

	/// CSS appended after the current theme's own stylesheet. `!important` is required
	/// here, not just convenient: this has to win regardless of the specificity or
	/// declaration order any given theme -- including third-party imported .nnwtheme
	/// files this code has never seen -- happens to use for `body`/`a` rules. Anchoring
	/// on `body` and `a` (rather than more specific selectors) is deliberate too, since
	/// those are the two selectors every theme's stylesheet.css is expected to style,
	/// per the theme format's own documentation.
	var cssOverrideBlock: String {
		guard !isEmpty else { return "" }

		var bodyDeclarations = [String]()
		if let fontFamilyName {
			bodyDeclarations.append("font-family: \"\(fontFamilyName)\" !important;")
		}
		if let fontSize {
			bodyDeclarations.append("font-size: \(fontSize)px !important;")
		}
		if let lineHeight {
			bodyDeclarations.append("line-height: \(lineHeight) !important;")
		}
		if let textColorHex {
			bodyDeclarations.append("color: \(textColorHex) !important;")
		}
		if let backgroundColorHex {
			bodyDeclarations.append("background-color: \(backgroundColorHex) !important;")
		}

		var css = ""
		if !bodyDeclarations.isEmpty {
			css += "body {\n\t\(bodyDeclarations.joined(separator: "\n\t"))\n}\n"
		}
		if let linkColorHex {
			css += "a, a:link, a:visited {\n\tcolor: \(linkColorHex) !important;\n}\n"
		}
		return css
	}
}
