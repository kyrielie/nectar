//
//  ArticleThemeOverridesView.swift
//  NetNewsWire-iOS
//
//  Created for Settings → Articles → Font & Color Overrides.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import SwiftUI

struct ArticleThemeOverridesView: View {

	private static let defaultFontLabel = NSLocalizedString("Theme Default", comment: "Theme Default font/color")

	@State private var useCustomFont: Bool
	@State private var fontFamilyName: String

	@State private var useCustomFontSize: Bool
	@State private var fontSize: Double

	@State private var useCustomLineHeight: Bool
	@State private var lineHeight: Double

	@State private var useCustomTextColor: Bool
	@State private var textColor: Color

	@State private var useCustomBackgroundColor: Bool
	@State private var backgroundColor: Color

	@State private var useCustomLinkColor: Bool
	@State private var linkColor: Color

	/// Sorted, de-duplicated list of installed font family names, standing in for
	/// "every font the reader view's WKWebView could plausibly render." System UI
	/// faces that don't actually work as CSS font-family names are unlikely to appear
	/// here since UIFont.familyNames only lists names WebKit's font matching also
	/// understands.
	private let availableFontFamilies = UIFont.familyNames.sorted()

	init() {
		let overrides = AppDefaults.shared.articleThemeOverrides

		_useCustomFont = State(initialValue: overrides.fontFamilyName != nil)
		_fontFamilyName = State(initialValue: overrides.fontFamilyName ?? UIFont.familyNames.sorted().first ?? "Helvetica")

		_useCustomFontSize = State(initialValue: overrides.fontSize != nil)
		_fontSize = State(initialValue: overrides.fontSize ?? UIFont.preferredFont(forTextStyle: .body).pointSize)

		_useCustomLineHeight = State(initialValue: overrides.lineHeight != nil)
		_lineHeight = State(initialValue: overrides.lineHeight ?? 1.4)

		_useCustomTextColor = State(initialValue: overrides.textColorHex != nil)
		_textColor = State(initialValue: Color(hex: overrides.textColorHex) ?? .primary)

		_useCustomBackgroundColor = State(initialValue: overrides.backgroundColorHex != nil)
		_backgroundColor = State(initialValue: Color(hex: overrides.backgroundColorHex) ?? Color(UIColor.systemBackground))

		_useCustomLinkColor = State(initialValue: overrides.linkColorHex != nil)
		_linkColor = State(initialValue: Color(hex: overrides.linkColorHex) ?? .accentColor)
	}

	var body: some View {
		Form {
			previewSection
			fontSection
			fontSizeSection
			lineHeightSection
			colorsSection
			resetSection
		}
		.navigationTitle(Text("Font & Color Overrides", comment: "Font & Color Overrides navigation title"))
		.navigationBarTitleDisplayMode(.inline)
		.onChange(of: useCustomFont) { _, _ in save() }
		.onChange(of: fontFamilyName) { _, _ in save() }
		.onChange(of: useCustomFontSize) { _, _ in save() }
		.onChange(of: fontSize) { _, _ in save() }
		.onChange(of: useCustomLineHeight) { _, _ in save() }
		.onChange(of: lineHeight) { _, _ in save() }
		.onChange(of: useCustomTextColor) { _, _ in save() }
		.onChange(of: textColor) { _, _ in save() }
		.onChange(of: useCustomBackgroundColor) { _, _ in save() }
		.onChange(of: backgroundColor) { _, _ in save() }
		.onChange(of: useCustomLinkColor) { _, _ in save() }
		.onChange(of: linkColor) { _, _ in save() }
	}

	// MARK: - Sections

	/// Split out of `body` (along with the other `...Section` properties below):
	/// a single `Form` closure containing every section, toggle, picker, and
	/// conditional inline was too large an expression for the type checker to
	/// solve within its per-expression time limit ("Getter for property 'body'
	/// took Xms to type-check"). Giving each section its own explicitly-typed
	/// `some View` property lets the compiler solve each in isolation instead of
	/// all at once.
	@ViewBuilder
	private var previewSection: some View {
		Section {
			preview
				.listRowInsets(EdgeInsets())
				.padding()
				.background(backgroundColor)
		} header: {
			Text("Preview", comment: "Preview section header")
		}
	}

	@ViewBuilder
	private var fontSection: some View {
		Section {
			Toggle(isOn: $useCustomFont) {
				Text("Custom Font", comment: "Custom Font toggle")
			}
			if useCustomFont {
				Picker(selection: $fontFamilyName) {
					ForEach(availableFontFamilies, id: \.self) { familyName in
						Text(familyName).tag(familyName)
					}
				} label: {
					Text("Font", comment: "Font picker label")
				}
			}
		}
	}

	@ViewBuilder
	private var fontSizeSection: some View {
		Section {
			Toggle(isOn: $useCustomFontSize) {
				Text("Custom Font Size", comment: "Custom Font Size toggle")
			}
			if useCustomFontSize {
				fontSizeRow
			}
		}
	}

	private var fontSizeRow: some View {
		HStack {
			Slider(value: $fontSize, in: ArticleThemeOverrides.fontSizeRange, step: 1)
			Text(fontSize, format: .number.precision(.fractionLength(0)))
				.monospacedDigit()
				.frame(width: 32, alignment: .trailing)
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private var lineHeightSection: some View {
		Section {
			Toggle(isOn: $useCustomLineHeight) {
				Text("Custom Line Height", comment: "Custom Line Height toggle")
			}
			if useCustomLineHeight {
				lineHeightRow
			}
		}
	}

	private var lineHeightRow: some View {
		HStack {
			Slider(value: $lineHeight, in: ArticleThemeOverrides.lineHeightRange, step: 0.1)
			Text(lineHeight, format: .number.precision(.fractionLength(1)))
				.monospacedDigit()
				.frame(width: 32, alignment: .trailing)
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private var colorsSection: some View {
		Section {
			Toggle(isOn: $useCustomTextColor) {
				Text("Custom Text Color", comment: "Custom Text Color toggle")
			}
			if useCustomTextColor {
				ColorPicker(selection: $textColor, supportsOpacity: false) {
					Text("Text Color", comment: "Text Color picker label")
				}
			}

			Toggle(isOn: $useCustomBackgroundColor) {
				Text("Custom Background Color", comment: "Custom Background Color toggle")
			}
			if useCustomBackgroundColor {
				ColorPicker(selection: $backgroundColor, supportsOpacity: false) {
					Text("Background Color", comment: "Background Color picker label")
				}
			}

			Toggle(isOn: $useCustomLinkColor) {
				Text("Custom Link Color", comment: "Custom Link Color toggle")
			}
			if useCustomLinkColor {
				ColorPicker(selection: $linkColor, supportsOpacity: false) {
					Text("Link Color", comment: "Link Color picker label")
				}
			}
		} header: {
			Text("Colors", comment: "Colors section header")
		}
	}

	@ViewBuilder
	private var resetSection: some View {
		Section {
			Button(role: .destructive) {
				resetToThemeDefaults()
			} label: {
				Text("Reset to Theme Default", comment: "Reset to Theme Default button")
			}
		}
	}

	private var preview: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("The Sample Chapter Title")
				.font(.headline)
				.foregroundStyle(useCustomTextColor ? textColor : .primary)
			Text("This is a preview of how article text will look with your chosen font, size, line height, and colors. The quick brown fox jumps over the lazy dog.")
				.font(useCustomFont ? .custom(fontFamilyName, size: useCustomFontSize ? fontSize : UIFont.preferredFont(forTextStyle: .body).pointSize) : .system(size: useCustomFontSize ? fontSize : UIFont.preferredFont(forTextStyle: .body).pointSize))
				.lineSpacing(previewLineSpacing)
				.foregroundStyle(useCustomTextColor ? textColor : .primary)
			Text("A link looks like this.")
				.foregroundStyle(useCustomLinkColor ? linkColor : .accentColor)
				.underline()
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	/// SwiftUI's lineSpacing is *extra* space added between lines, not the CSS
	/// line-height multiplier the override actually stores, so this converts one to
	/// the other using the same base point size the preview text is rendered at.
	private var previewLineSpacing: CGFloat {
		guard useCustomLineHeight else { return 0 }
		let baseSize = useCustomFontSize ? fontSize : UIFont.preferredFont(forTextStyle: .body).pointSize
		return CGFloat((lineHeight - 1.0) * baseSize)
	}

	private func save() {
		AppDefaults.shared.articleThemeOverrides = ArticleThemeOverrides(
			fontFamilyName: useCustomFont ? fontFamilyName : nil,
			fontSize: useCustomFontSize ? fontSize : nil,
			lineHeight: useCustomLineHeight ? lineHeight : nil,
			textColorHex: useCustomTextColor ? textColor.hexString : nil,
			backgroundColorHex: useCustomBackgroundColor ? backgroundColor.hexString : nil,
			linkColorHex: useCustomLinkColor ? linkColor.hexString : nil
		)
	}

	private func resetToThemeDefaults() {
		useCustomFont = false
		useCustomFontSize = false
		useCustomLineHeight = false
		useCustomTextColor = false
		useCustomBackgroundColor = false
		useCustomLinkColor = false
		fontSize = UIFont.preferredFont(forTextStyle: .body).pointSize
		lineHeight = 1.4
		textColor = .primary
		backgroundColor = Color(UIColor.systemBackground)
		linkColor = .accentColor
		save()
	}
}

// MARK: - Color <-> hex

private extension Color {

	init?(hex: String?) {
		guard let hex, let uiColor = UIColor(cssHex: hex) else { return nil }
		self.init(uiColor: uiColor)
	}

	/// Round-tripped through UIColor's sRGB components rather than done directly in
	/// SwiftUI, since Color has no public component accessors on every OS version this
	/// app supports.
	var hexString: String {
		UIColor(self).cssHexString
	}
}

private extension UIColor {

	convenience init?(cssHex: String) {
		var hex = cssHex.trimmingCharacters(in: .whitespacesAndNewlines)
		if hex.hasPrefix("#") {
			hex.removeFirst()
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

#Preview {
	NavigationStack {
		ArticleThemeOverridesView()
	}
}
