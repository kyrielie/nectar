//
//  ArticleThemeColorExtractor.swift
//  NetNewsWire
//
//  Copyright © 2026 Ranchero Software, LLC. All rights reserved.
//

import UIKit

/// Extracts the effective text/background/link colors a theme's own stylesheet declares,
/// so overrides and chrome (webview background, notch fill) can default to what the
/// theme actually looks like instead of a generic system color.
enum ArticleThemeColorExtractor {

	struct ThemeColors {
		var textColor: UIColor
		var textColorDark: UIColor
		var backgroundColor: UIColor
		var backgroundColorDark: UIColor
		var linkColor: UIColor
		var linkColorDark: UIColor
	}

	/// Falls back to black-on-white (light) / white-on-black (dark) per selector,
	/// independently, when a given property isn't found -- never fails outright.
	static func colors(for theme: ArticleTheme) -> ThemeColors {
		let css = theme.css ?? ""
		let darkBlock = darkMediaBlock(in: css)

		let lightText = color(property: "color", selectors: ["body", ".articleBody"], in: css)
		let lightBackground = color(property: "background-color", selectors: ["body", ".articleBody"], in: css)
		let lightLink = color(property: "color", selectors: ["a", ".articleBody a"], in: css)

		let darkText = darkBlock.flatMap { color(property: "color", selectors: ["body", ".articleBody"], in: $0) }
		let darkBackground = darkBlock.flatMap { color(property: "background-color", selectors: ["body", ".articleBody"], in: $0) }
		let darkLink = darkBlock.flatMap { color(property: "color", selectors: ["a", ".articleBody a"], in: $0) }

		// Light-mode values: theme's own declaration, else the generic black-on-white
		// fallback (link falls back to text color rather than an arbitrary blue, since
		// most themes don't style links distinctly).
		let textColor = lightText ?? .black
		let backgroundColor = lightBackground ?? .white
		let linkColor = lightLink ?? textColor

		// Dark-mode values: theme's own dark declaration, else the light value (mirrors
		// ArticleThemeOverrides's own "dark ?? light" fallback semantics), else -- only
		// when there was no light-mode declaration either -- the generic dark fallback.
		let textColorDark = darkText ?? lightText ?? .white
		let backgroundColorDark = darkBackground ?? lightBackground ?? .black
		let linkColorDark = darkLink ?? lightLink ?? textColorDark

		return ThemeColors(
			textColor: textColor,
			textColorDark: textColorDark,
			backgroundColor: backgroundColor,
			backgroundColorDark: backgroundColorDark,
			linkColor: linkColor,
			linkColorDark: linkColorDark
		)
	}

	// MARK: - CSS scanning

	/// Finds the first top-level `@media (prefers-color-scheme: dark) { ... }` block
	/// and returns its inner contents -- exactly the shape
	/// `ArticleThemeOverrides.cssOverrideBlock` itself emits, and the pattern themes
	/// are expected to follow.
	private static func darkMediaBlock(in css: String) -> String? {
		guard let mediaRange = css.range(of: #"@media\s*\(\s*prefers-color-scheme:\s*dark\s*\)\s*\{"#, options: .regularExpression) else {
			return nil
		}

		guard let openBraceIndex = css[mediaRange].lastIndex(of: "{") else { return nil }
		var depth = 1
		var index = css.index(after: openBraceIndex)
		let contentStart = index

		while index < css.endIndex {
			let char = css[index]
			if char == "{" {
				depth += 1
			} else if char == "}" {
				depth -= 1
				if depth == 0 {
					return String(css[contentStart..<index])
				}
			}
			index = css.index(after: index)
		}

		return nil
	}

	/// Scans `block` for `selector { ... property: value ... }` rules across the given
	/// selectors, taking the last matching declaration across all matching rules (CSS
	/// cascade -- later rules win when specificity ties, and theme stylesheets are
	/// simple enough that this approximation is correct in practice).
	private static func color(property: String, selectors: [String], in block: String) -> UIColor? {
		var lastMatch: UIColor?

		for selector in selectors {
			let escapedSelector = NSRegularExpression.escapedPattern(for: selector)
			let pattern = "(?:^|[,{}\\s])\(escapedSelector)\\s*\\{([^}]*)\\}"
			guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

			let nsBlock = block as NSString
			let matches = regex.matches(in: block, range: NSRange(location: 0, length: nsBlock.length))

			for match in matches {
				guard match.numberOfRanges > 1 else { continue }
				let body = nsBlock.substring(with: match.range(at: 1))
				if let value = lastDeclaredValue(for: property, in: body), let uiColor = UIColor(cssColorValue: value) {
					lastMatch = uiColor
				}
			}
		}

		return lastMatch
	}

	/// Takes the last `property: value;` declaration in `body` (CSS cascade: later
	/// declarations win when specificity ties).
	private static func lastDeclaredValue(for property: String, in body: String) -> String? {
		let escapedProperty = NSRegularExpression.escapedPattern(for: property)
		let pattern = "(?:^|[;{\\s])\(escapedProperty)\\s*:\\s*([^;}!]+)"
		guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

		let nsBody = body as NSString
		let matches = regex.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
		guard let last = matches.last, last.numberOfRanges > 1 else { return nil }

		return nsBody.substring(with: last.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

private extension UIColor {

	/// Parses a CSS color value: `#RGB`, `#RRGGBB`, or `rgb()`/`rgba()`. Named CSS
	/// colors (e.g. `red`) are intentionally not supported -- theme stylesheets in
	/// this app consistently use hex/rgb values, not keywords.
	convenience init?(cssColorValue value: String) {
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

		if trimmed.hasPrefix("#") {
			self.init(cssHex: trimmed)
			return
		}

		if trimmed.lowercased().hasPrefix("rgb") {
			guard let openParen = trimmed.firstIndex(of: "("), let closeParen = trimmed.lastIndex(of: ")") else { return nil }
			let inner = trimmed[trimmed.index(after: openParen)..<closeParen]
			let components = inner.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
			guard components.count >= 3 else { return nil }
			self.init(red: components[0] / 255.0, green: components[1] / 255.0, blue: components[2] / 255.0, alpha: components.count > 3 ? components[3] : 1.0)
			return
		}

		return nil
	}
}

// MARK: - Color <-> hex

/// Shared with `ArticleThemeListView`'s color pickers, which also need hex parsing for
/// round-tripping `Color` <-> hex string -- kept internal (not private) so both call
/// sites can use it.
extension UIColor {

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
}
