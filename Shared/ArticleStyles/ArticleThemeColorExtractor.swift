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
///
/// This is a small regex-based scanner, not a full CSS parser -- see the plan doc this
/// was built against. It understands the patterns actually used across the shipped
/// themes (Default, Appanoose, Biblioteca, Hyperlegible, NewsFax, Promenade, Sepia,
/// Tiqoe Dark, Verdana Revival):
///   - literal `#hex`/`rgb()`/`rgba()` colors
///   - a modest set of common named CSS colors
///   - `var(--custom-property)`, resolved against that theme's own `:root` declarations,
///     with light/dark scoped separately so a dark-mode redefinition of a variable
///     doesn't leak into the light-mode result (or vice versa)
/// It does not understand nested `@supports`/other conditional overrides beyond
/// stripping them out of consideration entirely (see `stripBraceBlocks`), CSS-4
/// system color keywords (`Canvas`, `CanvasText`, etc. -- these fall through to "not
/// found" like any other unparseable value), or selector specificity beyond
/// exact-selector matching.
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
		let rawCSS = theme.css ?? ""
		let css = stripComments(rawCSS)

		// @supports blocks carry platform-specific overrides (and, in at least one
		// shipped theme, a CSS-4 system-color override) that this scanner isn't
		// equipped to reason about correctly -- excluded entirely rather than risk
		// picking up something that doesn't reflect the common-case rendering.
		let cssWithoutSupports = stripBraceBlocks(css)

		let darkBlock = extractBraceBlock(in: cssWithoutSupports, openerPattern: #"@media\s*\(\s*prefers-color-scheme:\s*dark\s*\)\s*\{"#)
		let lightScanCSS: String
		if let darkBlock {
			lightScanCSS = cssWithoutSupports.replacingCharacters(in: darkBlock.fullRange, with: "")
		} else {
			lightScanCSS = cssWithoutSupports
		}

		let lightVars = cssCustomProperties(in: lightScanCSS)
		let darkVars = darkBlock.map { cssCustomProperties(in: $0.content) } ?? [:]

		func compute(property: String, selectors: [String]) -> (light: UIColor?, dark: UIColor?) {
			// The declaration that always applies (outside any dark media query) --
			// this is also what dark mode uses, UNLESS the theme also declares an
			// explicit override for the same selector/property inside its own dark
			// media block (rare -- most shipped themes vary a color only by
			// redefining the *variable* it references, not by re-declaring the
			// property itself).
			let unconditionalRaw = exactSelectorValue(property: property, selectors: selectors, in: lightScanCSS)
			let darkOverrideRaw = darkBlock.flatMap { exactSelectorValue(property: property, selectors: selectors, in: $0.content) }

			let light = resolvedColor(unconditionalRaw, localVars: lightVars, fallbackVars: [:])
			let darkRaw = darkOverrideRaw ?? unconditionalRaw
			let dark = resolvedColor(darkRaw, localVars: darkVars, fallbackVars: lightVars)

			return (light, dark)
		}

		let (lightTextFound, darkTextFound) = compute(property: "color", selectors: ["body", ".articleBody"])
		let (lightBackgroundFound, darkBackgroundFound) = compute(property: "background-color", selectors: ["body", ".articleBody"])
		let (lightLinkFound, darkLinkFound) = compute(property: "color", selectors: ["a", ".articleBody a"])

		// Light-mode values: theme's own declaration, else the generic black-on-white
		// fallback (link falls back to text color rather than an arbitrary blue, since
		// most themes don't style links distinctly).
		let textColor = lightTextFound ?? .black
		let backgroundColor = lightBackgroundFound ?? .white
		let linkColor = lightLinkFound ?? textColor

		// Dark-mode values: theme's own dark-scoped declaration, else the light value
		// (mirrors ArticleThemeOverrides's own "dark ?? light" fallback semantics --
		// correct for themes like Tiqoe Dark and Sepia that only ever declare one set
		// of colors and expect it to apply unconditionally), else -- only when there
		// was no light-mode declaration either -- the generic dark fallback.
		let textColorDark = darkTextFound ?? lightTextFound ?? .white
		let backgroundColorDark = darkBackgroundFound ?? lightBackgroundFound ?? .black
		let linkColorDark = darkLinkFound ?? lightLinkFound ?? textColorDark

		return ThemeColors(
			textColor: textColor,
			textColorDark: textColorDark,
			backgroundColor: backgroundColor,
			backgroundColorDark: backgroundColorDark,
			linkColor: linkColor,
			linkColorDark: linkColorDark
		)
	}

	// MARK: - CSS pre-processing

	private static func stripComments(_ css: String) -> String {
		css.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
	}

	/// Removes every top-level `@supports (...) { ... }` block (brace-matched) from
	/// `css`, leaving everything else in place.
	private static func stripBraceBlocks(_ css: String) -> String {
		var result = ""
		var searchStart = css.startIndex

		while searchStart < css.endIndex,
			  let openerRange = css.range(of: #"@supports\s*\([^)]*\)\s*\{"#, options: .regularExpression, range: searchStart..<css.endIndex) {
			result += css[searchStart..<openerRange.lowerBound]

			guard let openBraceIndex = css[openerRange].lastIndex(of: "{") else { break }
			var depth = 1
			var index = css.index(after: openBraceIndex)

			while index < css.endIndex, depth > 0 {
				if css[index] == "{" { depth += 1 } else if css[index] == "}" { depth -= 1 }
				index = css.index(after: index)
			}

			searchStart = index
		}

		result += css[searchStart..<css.endIndex]
		return result
	}

	private struct BraceBlock {
		let content: String
		let fullRange: Range<String.Index>
	}

	/// Finds the first block matching `openerPattern` (a regex ending in `\{`) and
	/// returns both its inner content and the full range (opener through closing
	/// brace) so the caller can excise it from the source string if needed.
	private static func extractBraceBlock(in css: String, openerPattern: String) -> BraceBlock? {
		guard let openerRange = css.range(of: openerPattern, options: .regularExpression) else { return nil }
		guard let openBraceIndex = css[openerRange].lastIndex(of: "{") else { return nil }

		var depth = 1
		var index = css.index(after: openBraceIndex)
		let contentStart = index

		while index < css.endIndex {
			if css[index] == "{" {
				depth += 1
			} else if css[index] == "}" {
				depth -= 1
				if depth == 0 {
					return BraceBlock(content: String(css[contentStart..<index]), fullRange: openerRange.lowerBound..<css.index(after: index))
				}
			}
			index = css.index(after: index)
		}

		return nil
	}

	// MARK: - Custom properties (CSS variables)

	/// Collects every `--name: value;` declaration in `block` into a name -> value
	/// map (later declarations win, matching the cascade for same-specificity rules).
	/// This intentionally doesn't track which `:root` (or other) rule each declaration
	/// came from -- callers are expected to pass in an already light/dark-scoped
	/// `block` (see `colors(for:)`, which excises the dark media block before calling
	/// this for the light scan, and passes only the dark block's own content for dark).
	private static func cssCustomProperties(in block: String) -> [String: String] {
		var result = [String: String]()
		guard let regex = try? NSRegularExpression(pattern: #"--([A-Za-z0-9_-]+)\s*:\s*([^;}]+);"#) else { return result }

		let nsBlock = block as NSString
		for match in regex.matches(in: block, range: NSRange(location: 0, length: nsBlock.length)) {
			guard match.numberOfRanges > 2 else { continue }
			let name = nsBlock.substring(with: match.range(at: 1))
			let value = nsBlock.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
			result[name] = value
		}

		return result
	}

	/// Resolves `var(--name)` / `var(--name, fallback)` against `localVars`, then
	/// `fallbackVars` (used when resolving a dark-mode value: check the dark block's
	/// own variables first, then fall back to the light-scoped ones for any variable
	/// the dark block didn't redefine), then the CSS fallback argument if present.
	/// Non-`var()` values pass through unchanged.
	private static func resolveVarReferences(_ value: String, localVars: [String: String], fallbackVars: [String: String]) -> String? {
		guard let regex = try? NSRegularExpression(pattern: #"^var\(\s*--([A-Za-z0-9_-]+)\s*(?:,\s*(.+))?\)$"#) else { return value }
		let nsValue = value as NSString
		guard let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: nsValue.length)), match.numberOfRanges > 1 else {
			return value
		}

		let name = nsValue.substring(with: match.range(at: 1))
		if let localValue = localVars[name] { return localValue }
		if let fallbackValue = fallbackVars[name] { return fallbackValue }
		if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
			return nsValue.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
		}
		return nil
	}

	private static func resolvedColor(_ rawValue: String?, localVars: [String: String], fallbackVars: [String: String]) -> UIColor? {
		guard let rawValue else { return nil }
		guard let resolved = resolveVarReferences(rawValue, localVars: localVars, fallbackVars: fallbackVars) else { return nil }
		return UIColor(cssColorValue: resolved)
	}

	// MARK: - Selector/property scanning

	/// Scans `block` for rules whose selector list contains an *exact* match (after
	/// whitespace normalization) for one of `selectors`, and returns the last such
	/// rule's declared value for `property`.
	///
	/// Exact matching (rather than substring/suffix matching) is deliberate: a naive
	/// "selector ends in ` a {`" check would also match `pre a {` or `code a {}`,
	/// silently picking up an unrelated link color from inside a code block.
	private static func exactSelectorValue(property: String, selectors: [String], in block: String) -> String? {
		let targets = Set(selectors)
		guard let regex = try? NSRegularExpression(pattern: #"([^{}]+)\{([^{}]*)\}"#) else { return nil }

		let nsBlock = block as NSString
		var lastMatch: String?

		for match in regex.matches(in: block, range: NSRange(location: 0, length: nsBlock.length)) {
			guard match.numberOfRanges > 2 else { continue }
			let selectorList = nsBlock.substring(with: match.range(at: 1))
			let ruleBody = nsBlock.substring(with: match.range(at: 2))

			let normalizedSelectors = selectorList
				.components(separatedBy: ",")
				.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }

			guard normalizedSelectors.contains(where: { targets.contains($0) }) else { continue }

			if let value = lastDeclaredValue(for: property, in: ruleBody) {
				lastMatch = value
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

	/// A modest set of named CSS colors actually seen in shipped themes (e.g.
	/// NewsFax's `color: white` / `color: cornflowerblue`), not the full CSS
	/// keyword table -- extend as new themes surface new names.
	static let cssNamedColors: [String: String] = [
		"white": "#FFFFFF", "black": "#000000",
		"red": "#FF0000", "green": "#008000", "blue": "#0000FF",
		"gray": "#808080", "grey": "#808080",
		"dimgray": "#696969", "dimgrey": "#696969",
		"lightgray": "#D3D3D3", "lightgrey": "#D3D3D3",
		"darkgray": "#A9A9A9", "darkgrey": "#A9A9A9",
		"silver": "#C0C0C0",
		"cornflowerblue": "#6495ED",
		"firebrick": "#B22222",
		"navy": "#000080",
		"teal": "#008080",
		"maroon": "#800000",
		"olive": "#808000",
		"orange": "#FFA500",
		"gold": "#FFD700",
	]

	/// Parses a CSS color value: `#RGB`/`#RRGGBB`, `rgb()`/`rgba()`, or one of the
	/// named colors above. CSS-4 system color keywords (`Canvas`, `CanvasText`,
	/// `AccentColor`, etc.) and anything else unrecognized deliberately return `nil`
	/// rather than guessing.
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

		if let hex = UIColor.cssNamedColors[trimmed.lowercased()] {
			self.init(cssHex: hex)
			return
		}

		return nil
	}
}

// MARK: - Color <-> hex

/// Shared with `ArticleThemeCustomizeView`'s color pickers, which also need hex parsing
/// for round-tripping `Color` <-> hex string -- kept internal (not private) so both call
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
