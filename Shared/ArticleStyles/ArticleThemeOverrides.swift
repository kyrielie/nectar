//
//  ArticleThemeOverrides.swift
//  NetNewsWire
//
//  Created for Settings → Articles → Theme → Font & Color Overrides.
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
///
/// Each color has an independent dark-mode variant (`*DarkHex`). When a dark variant
/// isn't set, the light value is used for both, so existing single-color preferences
/// keep behaving exactly as before rather than silently losing their color in dark
/// mode. Font family/size/line height have no dark variant -- they're not
/// appearance-dependent.
struct ArticleThemeOverrides: Codable, Equatable, Sendable {

	var fontFamilyName: String?
	var fontSize: Double?
	var lineHeight: Double?
	var textColorHex: String?
	var textColorDarkHex: String?
	var backgroundColorHex: String?
	var backgroundColorDarkHex: String?
	var linkColorHex: String?
	var linkColorDarkHex: String?

	init(fontFamilyName: String? = nil, fontSize: Double? = nil, lineHeight: Double? = nil, textColorHex: String? = nil, textColorDarkHex: String? = nil, backgroundColorHex: String? = nil, backgroundColorDarkHex: String? = nil, linkColorHex: String? = nil, linkColorDarkHex: String? = nil) {
		self.fontFamilyName = fontFamilyName
		self.fontSize = fontSize
		self.lineHeight = lineHeight
		self.textColorHex = textColorHex
		self.textColorDarkHex = textColorDarkHex
		self.backgroundColorHex = backgroundColorHex
		self.backgroundColorDarkHex = backgroundColorDarkHex
		self.linkColorHex = linkColorHex
		self.linkColorDarkHex = linkColorDarkHex
	}

	var isEmpty: Bool {
		fontFamilyName == nil && fontSize == nil && lineHeight == nil
			&& textColorHex == nil && textColorDarkHex == nil
			&& backgroundColorHex == nil && backgroundColorDarkHex == nil
			&& linkColorHex == nil && linkColorDarkHex == nil
	}

	/// Reasonable bounds for the Settings sliders. Below/above these the reader view
	/// either becomes unreadable or the layout breaks down (long lines, clipped chrome).
	static let fontSizeRange: ClosedRange<Double> = 12...32
	static let lineHeightRange: ClosedRange<Double> = 1.0...2.2

	/// CSS appended after the current theme's own stylesheet. `!important` is required
	/// here, not just convenient: this has to win regardless of the specificity or
	/// declaration order any given theme -- including third-party imported .nnwtheme
	/// files this code has never seen -- happens to use for `body`/`a` rules.
	///
	/// Every included theme's stylesheet.css declares its own `line-height` directly
	/// on `.articleBody` (the actual content wrapper div every theme renders text
	/// into -- see Themes/*/template.html), and only `line-height`, not
	/// font-family/size/color. A directly-declared property on an element always wins
	/// over an inherited one regardless of `!important` (inheritance only applies when
	/// nothing more specific targets the element at all), so a body-only override is
	/// silently shadowed for line-height specifically while font/size/color still work.
	/// `.articleBody` is targeted alongside `body` (and `.articleBody a` alongside `a`)
	/// so this can't be shadowed by any current or future theme's own rules.
	///
	/// Dark-mode color variants are emitted as a `@media (prefers-color-scheme: dark)`
	/// block layered after the light-mode rules, so they react live to system
	/// appearance changes without any Swift-side trait-collection plumbing.
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
			css += "body, .articleBody {\n\t\(bodyDeclarations.joined(separator: "\n\t"))\n}\n"
		}
		if let linkColorHex {
			css += "a, a:link, a:visited, .articleBody a, .articleBody a:link, .articleBody a:visited {\n\tcolor: \(linkColorHex) !important;\n}\n"
		}

		var darkDeclarations = [String]()
		if let dark = textColorDarkHex ?? textColorHex {
			darkDeclarations.append("color: \(dark) !important;")
		}
		if let dark = backgroundColorDarkHex ?? backgroundColorHex {
			darkDeclarations.append("background-color: \(dark) !important;")
		}
		var darkCSS = ""
		if !darkDeclarations.isEmpty {
			darkCSS += "body, .articleBody {\n\t\(darkDeclarations.joined(separator: "\n\t"))\n}\n"
		}
		if let dark = linkColorDarkHex ?? linkColorHex {
			darkCSS += "a, a:link, a:visited, .articleBody a, .articleBody a:link, .articleBody a:visited {\n\tcolor: \(dark) !important;\n}\n"
		}
		if !darkCSS.isEmpty {
			css += "@media (prefers-color-scheme: dark) {\n\(darkCSS)}\n"
		}

		return css
	}
}
