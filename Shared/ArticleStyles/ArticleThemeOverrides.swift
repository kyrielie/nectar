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

	/// Targets `.articleBody` prose specifically. Named `serifFontFamilyName` (rather
	/// than the original single `fontFamilyName`) because the override now has two
	/// independent font roles -- see `sansFontFamilyName` below for why.
	var serifFontFamilyName: String?

	/// Targets UI chrome text (feedlink/byline/dateline/footer), not the fic prose.
	/// Split out from the original single font override, whose `body, .articleBody`
	/// selector reached chrome incidentally: none of the 30+ bundled themes mark their
	/// own chrome-text rules `!important`, so the old override always won there too,
	/// by accident rather than by design. Making the two roles explicit means a person
	/// can now choose them independently, which the old single property couldn't do at
	/// all -- this is new capability, not just a rename.
	var sansFontFamilyName: String?

	var fontSize: Double?
	var lineHeight: Double?
	var paragraphSpacing: Double?  // em
	var paragraphIndent: Double?   // em

	/// px. Left/right inset on `body` (see `cssOverrideBlock`'s comment on the
	/// corrected selector -- `.articleContent`/`.barContent` don't exist in the
	/// default template; only `body`'s own iOS-only padding rule does).
	var marginHorizontal: Double?
	/// px. Top inset on `#bodyContainer`.
	var marginTop: Double?

	var justifyText: Bool?
	var hyphenate: Bool?

	var textColorHex: String?
	var textColorDarkHex: String?
	var backgroundColorHex: String?
	var backgroundColorDarkHex: String?
	var linkColorHex: String?
	var linkColorDarkHex: String?

	init(serifFontFamilyName: String? = nil, sansFontFamilyName: String? = nil, fontSize: Double? = nil, lineHeight: Double? = nil, paragraphSpacing: Double? = nil, paragraphIndent: Double? = nil, marginHorizontal: Double? = nil, marginTop: Double? = nil, justifyText: Bool? = nil, hyphenate: Bool? = nil, textColorHex: String? = nil, textColorDarkHex: String? = nil, backgroundColorHex: String? = nil, backgroundColorDarkHex: String? = nil, linkColorHex: String? = nil, linkColorDarkHex: String? = nil) {
		self.serifFontFamilyName = serifFontFamilyName
		self.sansFontFamilyName = sansFontFamilyName
		self.fontSize = fontSize
		self.lineHeight = lineHeight
		self.paragraphSpacing = paragraphSpacing
		self.paragraphIndent = paragraphIndent
		self.marginHorizontal = marginHorizontal
		self.marginTop = marginTop
		self.justifyText = justifyText
		self.hyphenate = hyphenate
		self.textColorHex = textColorHex
		self.textColorDarkHex = textColorDarkHex
		self.backgroundColorHex = backgroundColorHex
		self.backgroundColorDarkHex = backgroundColorDarkHex
		self.linkColorHex = linkColorHex
		self.linkColorDarkHex = linkColorDarkHex
	}

	/// `fontFamilyName` was the pre-existing single property (targeted `body,
	/// .articleBody`, reaching chrome incidentally). Decoding old persisted JSON that
	/// still has this key maps it onto the new `serifFontFamilyName` -- prose is what
	/// people were actually adjusting when they set it, since chrome's font mostly
	/// wasn't independently visible before this change existed to separate them.
	private enum CodingKeys: String, CodingKey {
		case serifFontFamilyName = "fontFamilyName"
		case sansFontFamilyName
		case fontSize
		case lineHeight
		case paragraphSpacing
		case paragraphIndent
		case marginHorizontal
		case marginTop
		case justifyText
		case hyphenate
		case textColorHex
		case textColorDarkHex
		case backgroundColorHex
		case backgroundColorDarkHex
		case linkColorHex
		case linkColorDarkHex
	}

	var isEmpty: Bool {
		serifFontFamilyName == nil && sansFontFamilyName == nil
			&& fontSize == nil && lineHeight == nil && paragraphSpacing == nil && paragraphIndent == nil
			&& marginHorizontal == nil && marginTop == nil
			&& justifyText == nil && hyphenate == nil
			&& textColorHex == nil && textColorDarkHex == nil
			&& backgroundColorHex == nil && backgroundColorDarkHex == nil
			&& linkColorHex == nil && linkColorDarkHex == nil
	}

	/// Reasonable bounds for the Settings sliders. Below/above these the reader view
	/// either becomes unreadable or the layout breaks down (long lines, clipped chrome).
	static let fontSizeRange: ClosedRange<Double> = 12...32
	static let lineHeightRange: ClosedRange<Double> = 1.0...2.2
	static let paragraphSpacingRange: ClosedRange<Double> = 0...3.0
	static let paragraphIndentRange: ClosedRange<Double> = 0...3.0
	static let marginHorizontalRange: ClosedRange<Double> = 0...80
	static let marginTopRange: ClosedRange<Double> = 0...80

	/// Hand-maintained allowlist of chrome-text selectors, because class names for
	/// chrome aren't standardized across the bundled themes: the default theme uses
	/// `.headerContainer`/`.header`/`.feedlink`/`.articleDateline`/
	/// `.articleDatelineTitle`, Vintage Letter Green uses
	/// `.letter-header`/`.letter-byline`/`.letter-source`/`.letter-dateline`. Verified
	/// directly against `Shared/Article Rendering/template.html` and
	/// `Themes/Vintage Letter Green.nnwtheme/template.html` -- an earlier, unverified
	/// draft of this allowlist included `.headerBar`/`.datelineBar`/`.masthead`/
	/// `.editionLine`/`#nnwFooter`/`.footer`, none of which exist in the default
	/// template (the first two are real only inside some hand-written themes' own
	/// bundles; the default template has no footer element at all). This pass scopes
	/// the chrome-font override to the default theme plus the one other bundled theme
	/// with genuinely custom chrome class names; it is not a general mechanism for
	/// every theme's own bespoke chrome, which is the known fragile part of this
	/// design -- a future retrofit of all bundled themes to a shared `--font-main`/
	/// `--font-body` CSS variable convention would remove the need for an allowlist
	/// entirely, but no such convention currently exists across themes (confirmed:
	/// Hyperlegible hardcodes its font per-selector with no variable at all;
	/// Biblioteca uses its own `--font-sans`/`--font-serif`/`--font-mono` names, not
	/// shared with any other theme) -- that retrofit is separate, larger scope.
	private static let chromeSelectors = """
	.headerContainer, .header, .feedlink, .articleDateline, .articleDatelineTitle, \
	.letter-header, .letter-byline, .letter-source, .letter-dateline
	"""

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
		if let serifFontFamilyName {
			bodyDeclarations.append("font-family: \"\(serifFontFamilyName)\" !important;")
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

		var chromeDeclarations = [String]()
		if let sansFontFamilyName {
			chromeDeclarations.append("font-family: \"\(sansFontFamilyName)\" !important;")
		}
		if !chromeDeclarations.isEmpty {
			css += "\(Self.chromeSelectors) {\n\t\(chromeDeclarations.joined(separator: "\n\t"))\n}\n"
		}

		var paragraphDeclarations = [String]()
		if let paragraphSpacing {
			paragraphDeclarations.append("margin-bottom: \(paragraphSpacing)em !important;")
		}
		if let paragraphIndent {
			paragraphDeclarations.append("text-indent: \(paragraphIndent)em !important;")
		}
		if !paragraphDeclarations.isEmpty {
			css += ".articleBody p {\n\t\(paragraphDeclarations.joined(separator: "\n\t"))\n}\n"
		}

		var articleBodyDeclarations = [String]()
		if justifyText == true {
			articleBodyDeclarations.append("text-align: justify !important;")
		}
		if hyphenate == true {
			articleBodyDeclarations.append("hyphens: auto !important;")
			articleBodyDeclarations.append("-webkit-hyphens: auto !important;")
		} else if hyphenate == false {
			// Explicit off beats stylesheet.css's iOS-only @supports block, which
			// hardcodes -webkit-hyphens: auto unconditionally for the default theme
			// (see Shared/Article Rendering/stylesheet.css) -- an override the person
			// never touched shouldn't silently re-enable hyphenation for them.
			articleBodyDeclarations.append("hyphens: none !important;")
			articleBodyDeclarations.append("-webkit-hyphens: none !important;")
		}
		if !articleBodyDeclarations.isEmpty {
			css += ".articleBody {\n\t\(articleBodyDeclarations.joined(separator: "\n\t"))\n}\n"
		}

		if let linkColorHex {
			css += "a, a:link, a:visited, .articleBody a, .articleBody a:link, .articleBody a:visited {\n\tcolor: \(linkColorHex) !important;\n}\n"
		}

		// Horizontal/top margin overrides. .articleContent/.barContent don't exist in
		// the default template.html (grep-confirmed, zero matches repo-wide) -- the
		// real horizontal inset on the default theme is body's own iOS-only padding
		// rule (Shared/Article Rendering/stylesheet.css, inside the
		// @supports (-webkit-touch-callout: none) block). marginBottom is
		// deliberately not implemented in this pass: no footer element exists in the
		// default template.html at all, so there's nothing correct to target without
		// inventing a selector the same way the margin properties themselves were
		// originally invented against.
		if let marginHorizontal {
			css += "body {\n\tpadding-left: \(marginHorizontal)px !important; padding-right: \(marginHorizontal)px !important;\n}\n"
		}
		if let marginTop {
			css += "#bodyContainer {\n\tpadding-top: \(marginTop)px !important;\n}\n"
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
