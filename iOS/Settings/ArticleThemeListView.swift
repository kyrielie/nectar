//
//  ArticleThemeListView.swift
//  NetNewsWire-iOS
//
//  Created for Settings → Theme.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import RSCore

extension UTType {
	static var netNewsWireTheme: UTType { UTType(importedAs: "com.ranchero.netnewswire.theme") }
}

/// Replaces the former pair of screens (a UIKit theme-picker list that pushed to a
/// separate SwiftUI overrides screen) with a single scrolling list: picking a theme
/// and adjusting its font/color overrides now happen in the same place, with one
/// shared live preview reflecting both.
struct ArticleThemeListView: View {

	@Environment(\.dismiss) private var dismiss

	@State private var isImporterPresented = false
	@State private var themeNamesRefreshToken = false
	@State private var themeToDelete: String?
	@State private var isDeleteAlertPresented = false

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

	/// The font choices mirror Apple Books' own "Themes & Settings" font menu, not
	/// every UIFont family name reported by the system: matching Books' menu exactly
	/// is the point, not enumerating whatever happens to be installed. A few of
	/// these (Canela, Proxima Nova, Publico) are fonts Apple licenses exclusively
	/// for Books and aren't exposed to third-party apps as system fonts, so WebKit
	/// will silently fall back to its default serif/sans-serif for those -- they're
	/// kept in the list anyway to match Books' menu, and the live preview below
	/// makes that fallback immediately visible rather than surprising in the
	/// rendered article.
	private static let availableFonts: [(displayName: String, cssFontFamily: String)] = [
		("Athelas", "Athelas"),
		("Avenir Next", "Avenir Next"),
		("Canela", "Canela"),
		("Charter", "Charter"),
		("Georgia", "Georgia"),
		("Iowan", "Iowan Old Style"),
		("Palatino", "Palatino"),
		("Proxima Nova", "Proxima Nova"),
		("Publico", "Publico"),
		("San Francisco", "-apple-system"),
		("New York", "New York"),
		("Seravek", "Seravek"),
		("Times New Roman", "Times New Roman")
	]

	init() {
		let overrides = AppDefaults.shared.articleThemeOverrides

		_useCustomFont = State(initialValue: overrides.fontFamilyName != nil)
		_fontFamilyName = State(initialValue: overrides.fontFamilyName ?? Self.availableFonts.first!.cssFontFamily)

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
			themesSection
			previewSection
			fontSection
			fontSizeSection
			lineHeightSection
			colorsSection
			resetSection
		}
		.navigationTitle(Text("Theme", comment: "Theme navigation title"))
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					isImporterPresented = true
				} label: {
					Image(systemName: "plus")
				}
				.accessibilityLabel(Text("Import Theme", comment: "Import Theme"))
			}
		}
		.fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [UTType.netNewsWireTheme]) { result in
			guard case .success(let url) = result else { return }
			importTheme(url: url)
		}
		.alert(Text("Delete Theme?", comment: "Delete Theme"), isPresented: $isDeleteAlertPresented, presenting: themeToDelete) { themeName in
			Button(role: .cancel) { } label: {
				Text("Cancel", comment: "Cancel button")
			}
			Button(role: .destructive) {
				ArticleThemesManager.shared.deleteTheme(themeName: themeName)
			} label: {
				Text("Delete", comment: "Delete button")
			}
		} message: { themeName in
			let localizedMessageText = NSLocalizedString("Are you sure you want to delete the theme “%@”?.", comment: "Delete Theme Message")
			Text(NSString.localizedStringWithFormat(localizedMessageText as NSString, themeName) as String)
		}
		.onReceive(NotificationCenter.default.publisher(for: .ArticleThemeNamesDidChangeNotification)) { _ in
			themeNamesRefreshToken.toggle()
		}
		.onChange(of: snapshot) { _, _ in save() }
	}

	/// Chaining a dozen separate `.onChange` modifiers onto `body` (one per
	/// @State property) was itself a significant chunk of what made `body` too
	/// slow to type-check, on top of the Form contents -- each modifier adds
	/// another generic `ModifiedContent` layer the compiler has to solve for in
	/// the same expression. Bundling every tracked field into one Equatable
	/// value and reacting to that with a single `.onChange` collapses all
	/// twelve into one, and is behaviorally identical: `save()` still runs
	/// whenever any of them changes.
	private struct FormSnapshot: Equatable {
		var useCustomFont: Bool
		var fontFamilyName: String
		var useCustomFontSize: Bool
		var fontSize: Double
		var useCustomLineHeight: Bool
		var lineHeight: Double
		var useCustomTextColor: Bool
		var textColor: Color
		var useCustomBackgroundColor: Bool
		var backgroundColor: Color
		var useCustomLinkColor: Bool
		var linkColor: Color
	}

	private var snapshot: FormSnapshot {
		FormSnapshot(
			useCustomFont: useCustomFont,
			fontFamilyName: fontFamilyName,
			useCustomFontSize: useCustomFontSize,
			fontSize: fontSize,
			useCustomLineHeight: useCustomLineHeight,
			lineHeight: lineHeight,
			useCustomTextColor: useCustomTextColor,
			textColor: textColor,
			useCustomBackgroundColor: useCustomBackgroundColor,
			backgroundColor: backgroundColor,
			useCustomLinkColor: useCustomLinkColor,
			linkColor: linkColor
		)
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
	private var themesSection: some View {
		// Reading themeNamesRefreshToken here (even though it isn't otherwise used)
		// forces this section to be re-evaluated when the notification observer
		// above flips it, since ArticleThemesManager itself isn't ObservableObject.
		let _ = themeNamesRefreshToken

		Section {
			ForEach(themeNames, id: \.self) { themeName in
				themeRow(themeName)
			}
		}
	}

	private var themeNames: [String] {
		[ArticleTheme.defaultTheme.name] + ArticleThemesManager.shared.themeNames
	}

	@ViewBuilder
	private func themeRow(_ themeName: String) -> some View {
		let isCurrent = themeName == ArticleThemesManager.shared.currentTheme.name
		let isAppTheme = ArticleThemesManager.shared.articleThemeWithThemeName(themeName)?.isAppTheme ?? true

		Button {
			ArticleThemesManager.shared.currentThemeName = themeName
		} label: {
			HStack {
				Text(themeName)
					.foregroundStyle(.primary)
				Spacer()
				if isCurrent {
					Image(systemName: "checkmark")
						.foregroundStyle(.tint)
				}
			}
		}
		.swipeActions(edge: .trailing) {
			if !isAppTheme {
				Button(role: .destructive) {
					themeToDelete = themeName
					isDeleteAlertPresented = true
				} label: {
					Label {
						Text("Delete", comment: "Delete button")
					} icon: {
						Image(systemName: "trash")
					}
				}
			}
		}
	}

	@ViewBuilder
	private var previewSection: some View {
		Section {
			ArticleThemePreviewWebView(css: previewCSS)
				.frame(height: 220)
				.listRowInsets(EdgeInsets())
		} header: {
			Text("Preview", comment: "Preview section header")
		} footer: {
			Text("Preview reflects the current theme (\(ArticleThemesManager.shared.currentTheme.name)) with your overrides applied on top.", comment: "Preview footer explaining theme + override layering")
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
					ForEach(Self.availableFonts, id: \.cssFontFamily) { font in
						Text(font.displayName).tag(font.cssFontFamily)
					}
				} label: {
					Text("Font", comment: "Font picker label")
				}
			}
		} header: {
			Text("Font", comment: "Font section header")
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
		} header: {
			Text("Font Size", comment: "Font Size section header")
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
		} header: {
			Text("Line Height", comment: "Line Height section header")
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

	/// The override values implied by the current (possibly unsaved) toggle/slider/
	/// picker state -- used to drive the live preview immediately as the person
	/// adjusts controls, and also what actually gets persisted in `save()`.
	private var liveOverrides: ArticleThemeOverrides {
		ArticleThemeOverrides(
			fontFamilyName: useCustomFont ? fontFamilyName : nil,
			fontSize: useCustomFontSize ? fontSize : nil,
			lineHeight: useCustomLineHeight ? lineHeight : nil,
			textColorHex: useCustomTextColor ? textColor.hexString : nil,
			backgroundColorHex: useCustomBackgroundColor ? backgroundColor.hexString : nil,
			linkColorHex: useCustomLinkColor ? linkColor.hexString : nil
		)
	}

	/// The current theme's own CSS, with the live overrides appended on top --
	/// exactly what ArticleRenderer.styleString() does for real articles, so the
	/// preview shown here is the actual rendering a real article would get, not an
	/// approximation of it.
	private var previewCSS: String {
		let themeCSS = ArticleThemesManager.shared.currentTheme.css ?? ""
		let overrideCSS = liveOverrides.cssOverrideBlock
		guard !overrideCSS.isEmpty else { return themeCSS }
		return themeCSS + "\n" + overrideCSS
	}

	private func save() {
		AppDefaults.shared.articleThemeOverrides = liveOverrides
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

	// MARK: - Import

	private func importTheme(url: URL) {
		guard let controller = UIApplication.shared.firstKeyWindow?.topViewController else { return }

		if url.startAccessingSecurityScopedResource() {
			defer {
				url.stopAccessingSecurityScopedResource()
			}

			do {
				try ArticleThemeImporter.importTheme(controller: controller, url: url)
			} catch {
				NotificationCenter.default.post(name: .didFailToImportThemeWithError, object: nil, userInfo: ["error": error])
			}
		}
	}
}

private extension UIApplication {
	var firstKeyWindow: UIWindow? {
		connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap { $0.windows }
			.first { $0.isKeyWindow }
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
		ArticleThemeListView()
	}
}
