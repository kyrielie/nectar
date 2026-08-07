//
//  ArticleThemeListView.swift
//  NetNewsWire-iOS
//
//  Created for Settings → Theme.
//  Reverts the Gallery/Customize split (theme-settings-implementation-plan.md):
//  back to a single screen. Theme selection is a plain dropdown Picker instead
//  of a swatch-grid gallery -- no per-theme WKWebView or color-swatch preview
//  cells, just the theme's name plus a short light/dark-vs-single-palette tag
//  so that disclosure doesn't require opening each theme to find out. Font,
//  size, and color overrides for whichever theme is current still live here
//  too, with one shared live preview reflecting every change immediately.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import RSCore

extension UTType {
	static var netNewsWireTheme: UTType { UTType(importedAs: "com.ranchero.netnewswire.theme") }
}

struct ArticleThemeListView: View {

	@Environment(\.dismiss) private var dismiss

	@State private var isImporterPresented = false
	@State private var themeNamesRefreshToken = false
	@State private var isDeleteCurrentThemeAlertPresented = false

	/// Preview-only -- not part of `ArticleThemeOverrides`, doesn't get saved. Lets the
	/// preview show either appearance of a light+dark theme regardless of the device's
	/// actual current appearance. Fixed at `.light` for single-palette themes (the slider
	/// is disabled in that case; see `previewSection`), since toggling it would show the
	/// same colors either way and just be confusing to interact with.
	@State private var previewColorScheme: ColorScheme = .light

	@State private var useCustomSerifFont: Bool
	@State private var serifFontFamilyName: String

	@State private var useCustomSansFont: Bool
	@State private var sansFontFamilyName: String

	@State private var useCustomFontSize: Bool
	@State private var fontSize: Double

	@State private var useCustomLineHeight: Bool
	@State private var lineHeight: Double

	@State private var useCustomParagraphSpacing: Bool
	@State private var paragraphSpacing: Double
	@State private var useCustomParagraphIndent: Bool
	@State private var paragraphIndent: Double

	@State private var useCustomMargins: Bool
	@State private var marginHorizontal: Double
	@State private var marginTop: Double

	@State private var useCustomJustifyText: Bool
	@State private var justifyText: Bool
	@State private var useCustomHyphenate: Bool
	@State private var hyphenate: Bool

	@State private var useCustomTextColor: Bool
	@State private var textColor: Color
	@State private var textColorDark: Color

	@State private var useCustomBackgroundColor: Bool
	@State private var backgroundColor: Color
	@State private var backgroundColorDark: Color

	@State private var useCustomLinkColor: Bool
	@State private var linkColor: Color
	@State private var linkColorDark: Color

	/// The font choices mirror Apple Books' own "Themes & Settings" font menu, not
	/// every UIFont family name reported by the system: matching Books' menu exactly
	/// is the point, not enumerating whatever happens to be installed. A few of
	/// these (Canela, Proxima Nova, Publico) are fonts Apple licenses exclusively
	/// for Books and aren't exposed to third-party apps as system fonts, so WebKit
	/// will silently fall back to its default serif/sans-serif for those -- they're
	/// kept in the list anyway to match Books' menu, and the live preview below
	/// makes that fallback immediately visible rather than surprising in the
	/// rendered article. Reused for both the serif (prose) and sans (chrome)
	/// pickers -- Books' own font menu already spans both categories, so no second
	/// font list is needed.
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

	/// `ArticleThemeOverrides.serifFontFamilyName`/`sansFontFamilyName` are nil
	/// whenever their "Custom Font" toggle is off, since nil is exactly what tells
	/// `cssOverrideBlock` not to touch that property. That means the override itself
	/// can't also remember which font was last picked while the toggle is off --
	/// turning the toggle off and back on would otherwise always land back on the
	/// first font in the list. These keys store just that last choice, independent
	/// of whether it's currently applied.
	private static let lastSerifFontFamilyNameDefaultsKey = "ArticleThemeListView.lastSerifFontFamilyName"
	private static let lastSansFontFamilyNameDefaultsKey = "ArticleThemeListView.lastSansFontFamilyName"

	init() {
		let overrides = AppDefaults.shared.articleThemeOverrides
		let themeColors = ArticleThemeColorExtractor.colors(for: ArticleThemesManager.shared.currentTheme)
		let lastSerifFontFamilyName = UserDefaults.standard.string(forKey: Self.lastSerifFontFamilyNameDefaultsKey)
		let lastSansFontFamilyName = UserDefaults.standard.string(forKey: Self.lastSansFontFamilyNameDefaultsKey)

		_useCustomSerifFont = State(initialValue: overrides.serifFontFamilyName != nil)
		_serifFontFamilyName = State(initialValue: overrides.serifFontFamilyName ?? lastSerifFontFamilyName ?? Self.availableFonts.first!.cssFontFamily)

		_useCustomSansFont = State(initialValue: overrides.sansFontFamilyName != nil)
		_sansFontFamilyName = State(initialValue: overrides.sansFontFamilyName ?? lastSansFontFamilyName ?? Self.availableFonts.first!.cssFontFamily)

		_useCustomFontSize = State(initialValue: overrides.fontSize != nil)
		_fontSize = State(initialValue: overrides.fontSize ?? UIFont.preferredFont(forTextStyle: .body).pointSize)

		_useCustomLineHeight = State(initialValue: overrides.lineHeight != nil)
		_lineHeight = State(initialValue: overrides.lineHeight ?? 1.4)

		_useCustomParagraphSpacing = State(initialValue: overrides.paragraphSpacing != nil)
		_paragraphSpacing = State(initialValue: overrides.paragraphSpacing ?? 1.0)
		_useCustomParagraphIndent = State(initialValue: overrides.paragraphIndent != nil)
		_paragraphIndent = State(initialValue: overrides.paragraphIndent ?? 0.0)

		_useCustomMargins = State(initialValue: overrides.marginHorizontal != nil || overrides.marginTop != nil)
		_marginHorizontal = State(initialValue: overrides.marginHorizontal ?? 20)
		_marginTop = State(initialValue: overrides.marginTop ?? 0)

		// justifyText now follows the same useCustom-gated pattern as every other
		// override below: nil ("no override") and false ("override to not-justified")
		// are different things, since some themes justify text in their own stylesheet
		// and a person needs a way to force that off, not just decline to force it on.
		_useCustomJustifyText = State(initialValue: overrides.justifyText != nil)
		_justifyText = State(initialValue: overrides.justifyText ?? false)

		_useCustomHyphenate = State(initialValue: overrides.hyphenate != nil)
		_hyphenate = State(initialValue: overrides.hyphenate ?? false)

		// Seeded from the theme's own colors (not `.primary`/`.accentColor`/`systemBackground`)
		// so that turning a custom-color toggle on doesn't itself change anything visually --
		// the picker starts out showing exactly what's already on screen, and only actually
		// diverges from the theme once the person picks a different color.
		_useCustomTextColor = State(initialValue: overrides.textColorHex != nil)
		_textColor = State(initialValue: Color(hex: overrides.textColorHex) ?? Color(themeColors.textColor))
		_textColorDark = State(initialValue: Color(hex: overrides.textColorDarkHex ?? overrides.textColorHex) ?? Color(themeColors.textColorDark))

		_useCustomBackgroundColor = State(initialValue: overrides.backgroundColorHex != nil)
		_backgroundColor = State(initialValue: Color(hex: overrides.backgroundColorHex) ?? Color(themeColors.backgroundColor))
		_backgroundColorDark = State(initialValue: Color(hex: overrides.backgroundColorDarkHex ?? overrides.backgroundColorHex) ?? Color(themeColors.backgroundColorDark))

		_useCustomLinkColor = State(initialValue: overrides.linkColorHex != nil)
		_linkColor = State(initialValue: Color(hex: overrides.linkColorHex) ?? Color(themeColors.linkColor))
		_linkColorDark = State(initialValue: Color(hex: overrides.linkColorDarkHex ?? overrides.linkColorHex) ?? Color(themeColors.linkColorDark))
	}

	var body: some View {
		Form {
			themeSection
			previewSection
			fontSection
			fontSizeSection
			lineHeightSection
			paragraphSpacingSection
			paragraphIndentSection
			marginsSection
			justificationSection
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
		.alert(Text("Delete Theme?", comment: "Delete Theme"), isPresented: $isDeleteCurrentThemeAlertPresented) {
			Button(role: .cancel) { } label: {
				Text("Cancel", comment: "Cancel button")
			}
			Button(role: .destructive) {
				deleteCurrentTheme()
			} label: {
				Text("Delete", comment: "Delete button")
			}
		} message: {
			let localizedMessageText = NSLocalizedString("Are you sure you want to delete the theme “%@”?.", comment: "Delete Theme Message")
			Text(NSString.localizedStringWithFormat(localizedMessageText as NSString, ArticleThemesManager.shared.currentTheme.name) as String)
		}
		.onReceive(NotificationCenter.default.publisher(for: .ArticleThemeNamesDidChangeNotification)) { _ in
			themeNamesRefreshToken.toggle()
		}
		.onReceive(NotificationCenter.default.publisher(for: .CurrentArticleThemeDidChangeNotification)) { _ in
			themeNamesRefreshToken.toggle()
		}
		.onChange(of: snapshot) { _, _ in save() }
	}

	/// Chaining a dozen-plus separate `.onChange` modifiers onto `body` (one per
	/// @State property) was itself a significant chunk of what made `body` too
	/// slow to type-check, on top of the Form contents -- each modifier adds
	/// another generic `ModifiedContent` layer the compiler has to solve for in
	/// the same expression. Bundling every tracked field into one Equatable
	/// value and reacting to that with a single `.onChange` collapses all of
	/// them into one, and is behaviorally identical: `save()` still runs
	/// whenever any of them changes.
	private struct FormSnapshot: Equatable {
		var useCustomSerifFont: Bool
		var serifFontFamilyName: String
		var useCustomSansFont: Bool
		var sansFontFamilyName: String
		var useCustomFontSize: Bool
		var fontSize: Double
		var useCustomLineHeight: Bool
		var lineHeight: Double
		var useCustomParagraphSpacing: Bool
		var paragraphSpacing: Double
		var useCustomParagraphIndent: Bool
		var paragraphIndent: Double
		var useCustomMargins: Bool
		var marginHorizontal: Double
		var marginTop: Double
		var useCustomJustifyText: Bool
		var justifyText: Bool
		var useCustomHyphenate: Bool
		var hyphenate: Bool
		var useCustomTextColor: Bool
		var textColor: Color
		var textColorDark: Color
		var useCustomBackgroundColor: Bool
		var backgroundColor: Color
		var backgroundColorDark: Color
		var useCustomLinkColor: Bool
		var linkColor: Color
		var linkColorDark: Color
	}

	private var snapshot: FormSnapshot {
		FormSnapshot(
			useCustomSerifFont: useCustomSerifFont,
			serifFontFamilyName: serifFontFamilyName,
			useCustomSansFont: useCustomSansFont,
			sansFontFamilyName: sansFontFamilyName,
			useCustomFontSize: useCustomFontSize,
			fontSize: fontSize,
			useCustomLineHeight: useCustomLineHeight,
			lineHeight: lineHeight,
			useCustomParagraphSpacing: useCustomParagraphSpacing,
			paragraphSpacing: paragraphSpacing,
			useCustomParagraphIndent: useCustomParagraphIndent,
			paragraphIndent: paragraphIndent,
			useCustomMargins: useCustomMargins,
			marginHorizontal: marginHorizontal,
			marginTop: marginTop,
			useCustomJustifyText: useCustomJustifyText,
			justifyText: justifyText,
			useCustomHyphenate: useCustomHyphenate,
			hyphenate: hyphenate,
			useCustomTextColor: useCustomTextColor,
			textColor: textColor,
			textColorDark: textColorDark,
			useCustomBackgroundColor: useCustomBackgroundColor,
			backgroundColor: backgroundColor,
			backgroundColorDark: backgroundColorDark,
			useCustomLinkColor: useCustomLinkColor,
			linkColor: linkColor,
			linkColorDark: linkColorDark
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
	///
	/// A plain dropdown `Picker`, not the swatch-grid gallery this replaces --
	/// no per-theme `WKWebView` or color-swatch cell, just the theme's name.
	/// Whether a theme supports light/dark or is single-palette is left to the
	/// footer, which spells it out in full for whichever theme is currently
	/// selected, rather than being abbreviated into every row's label.
	@ViewBuilder
	private var themeSection: some View {
		// Reading themeNamesRefreshToken here (even though it isn't otherwise used)
		// forces this section to be re-evaluated when the notification observers
		// below flip it, since ArticleThemesManager itself isn't ObservableObject.
		// swiftlint:disable:next redundant_discardable_let
		let _ = themeNamesRefreshToken

		let currentTheme = ArticleThemesManager.shared.currentTheme

		Section {
			Picker(selection: themeNameBinding) {
				ForEach(themeNames, id: \.self) { themeName in
					Text(themeName).tag(themeName)
				}
			} label: {
				Text("Theme", comment: "Theme picker label")
			}

			if !currentTheme.isAppTheme {
				Button(role: .destructive) {
					isDeleteCurrentThemeAlertPresented = true
				} label: {
					Text("Delete This Theme", comment: "Delete current imported theme button")
				}
			}
		} footer: {
			Text(themeAppearanceDescription(for: currentTheme))
		}
	}

	private var themeNames: [String] {
		[ArticleTheme.defaultTheme.name] + ArticleThemesManager.shared.themeNames
	}

	private var themeNameBinding: Binding<String> {
		Binding(
			get: { ArticleThemesManager.shared.currentTheme.name },
			set: { ArticleThemesManager.shared.currentThemeName = $0 }
		)
	}

	private func themeAppearanceDescription(for theme: ArticleTheme) -> String {
		if ArticleThemeColorExtractor.colors(for: theme).hasDarkModeVariant {
			let format = NSLocalizedString("“%@” has separate light and dark mode colors and follows your system appearance setting.", comment: "Theme appearance footer, light+dark theme")
			return NSString.localizedStringWithFormat(format as NSString, theme.name) as String
		} else {
			let format = NSLocalizedString("“%@” uses a single color palette in both light and dark mode.", comment: "Theme appearance footer, single-palette theme")
			return NSString.localizedStringWithFormat(format as NSString, theme.name) as String
		}
	}

	private var currentThemeHasDarkModeVariant: Bool {
		ArticleThemeColorExtractor.colors(for: ArticleThemesManager.shared.currentTheme).hasDarkModeVariant
	}

	/// Disabled (and left off) for a single-palette theme, since that theme's CSS
	/// doesn't branch on `prefers-color-scheme` at all -- the toggle would flip but
	/// nothing in the preview below it would change, which is worse than not
	/// offering it.
	@ViewBuilder
	private var previewColorSchemeToggle: some View {
		Toggle(isOn: Binding(
			get: { previewColorScheme == .dark },
			set: { previewColorScheme = $0 ? .dark : .light }
		)) {
			Label {
				Text("Preview Dark Mode", comment: "Preview dark mode toggle label")
			} icon: {
				Image(systemName: previewColorScheme == .dark ? "moon" : "sun.max")
			}
		}
		.disabled(!currentThemeHasDarkModeVariant)
		.foregroundStyle(currentThemeHasDarkModeVariant ? .primary : .secondary)
	}

	@ViewBuilder
	private var previewSection: some View {
		Section {
			previewColorSchemeToggle
			ArticleThemePreviewWebView(
				importCSS: ArticleThemesManager.shared.currentTheme.importCSS,
				css: previewCSS,
				template: ArticleThemesManager.shared.currentTheme.template,
				showFeedName: AppDefaults.shared.showFeedNameInReaderView,
				colorScheme: currentThemeHasDarkModeVariant ? previewColorScheme : .light
			)
			.frame(height: 320)
			.listRowInsets(EdgeInsets())
		} header: {
			Text("Preview", comment: "Preview section header")
		} footer: {
			Text("Reflects the current theme (\(ArticleThemesManager.shared.currentTheme.name)) plus your overrides.", comment: "Preview footer explaining theme + override layering")
		}
	}

	@ViewBuilder
	private var fontSection: some View {
		Section {
			Toggle(isOn: $useCustomSerifFont) {
				Text("Custom Reading Font", comment: "Custom Reading Font toggle")
			}
			if useCustomSerifFont {
				Picker(selection: $serifFontFamilyName) {
					ForEach(Self.availableFonts, id: \.cssFontFamily) { font in
						Text(font.displayName).tag(font.cssFontFamily)
					}
				} label: {
					Text("Reading Font", comment: "Reading Font picker label")
				}
			}

			Toggle(isOn: $useCustomSansFont) {
				Text("Custom Interface Font", comment: "Custom Interface Font toggle")
			}
			if useCustomSansFont {
				Picker(selection: $sansFontFamilyName) {
					ForEach(Self.availableFonts, id: \.cssFontFamily) { font in
						Text(font.displayName).tag(font.cssFontFamily)
					}
				} label: {
					Text("Interface Font", comment: "Interface Font picker label")
				}
			}
		} header: {
			Text("Font", comment: "Font section header")
		} footer: {
			Text("Reading Font applies to the article text. Interface Font applies to the byline, dateline, and other chrome.", comment: "Font section footer explaining serif/sans split")
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

	private var paragraphSpacingRow: some View {
		HStack {
			Slider(value: $paragraphSpacing, in: ArticleThemeOverrides.paragraphSpacingRange, step: 0.1)
			Text(paragraphSpacing, format: .number.precision(.fractionLength(1)))
				.monospacedDigit()
				.frame(width: 32, alignment: .trailing)
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private var paragraphSpacingSection: some View {
		Section {
			Toggle(isOn: $useCustomParagraphSpacing) {
				Text("Custom Paragraph Spacing", comment: "Custom Paragraph Spacing toggle")
			}
			if useCustomParagraphSpacing {
				paragraphSpacingRow
			}
		} header: {
			Text("Paragraph Spacing", comment: "Paragraph Spacing section header")
		}
	}

	private var paragraphIndentRow: some View {
		HStack {
			Slider(value: $paragraphIndent, in: ArticleThemeOverrides.paragraphIndentRange, step: 0.1)
			Text(paragraphIndent, format: .number.precision(.fractionLength(1)))
				.monospacedDigit()
				.frame(width: 32, alignment: .trailing)
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private var paragraphIndentSection: some View {
		Section {
			Toggle(isOn: $useCustomParagraphIndent) {
				Text("Custom Paragraph Indent", comment: "Custom Paragraph Indent toggle")
			}
			if useCustomParagraphIndent {
				paragraphIndentRow
			}
		} header: {
			Text("Paragraph Indent", comment: "Paragraph Indent section header")
		}
	}

	private func marginRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
		HStack {
			Text(title)
			Slider(value: value, in: range, step: 1)
			Text(value.wrappedValue, format: .number.precision(.fractionLength(0)))
				.monospacedDigit()
				.frame(width: 32, alignment: .trailing)
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private var marginsSection: some View {
		Section {
			Toggle(isOn: $useCustomMargins) {
				Text("Custom Margins", comment: "Custom Margins toggle")
			}
			if useCustomMargins {
				marginRow(title: NSLocalizedString("Left & Right", comment: "Left & Right margin label"), value: $marginHorizontal, range: ArticleThemeOverrides.marginHorizontalRange)
				marginRow(title: NSLocalizedString("Top", comment: "Top margin label"), value: $marginTop, range: ArticleThemeOverrides.marginTopRange)
			}
		} header: {
			Text("Page Margins", comment: "Page Margins section header")
		} footer: {
			if useCustomMargins && marginHorizontal < 20 {
				Text("Below 20px, text can run edge-to-edge on some devices. Most themes treat 20px as the minimum comfortable margin.", comment: "Margin below recommended floor footer warning")
			}
		}
	}

	@ViewBuilder
	private var justificationSection: some View {
		Section {
			Toggle(isOn: $useCustomJustifyText) {
				Text("Override Justification", comment: "Override Justification toggle")
			}
			if useCustomJustifyText {
				Toggle(isOn: $justifyText) {
					Text("Justify Text", comment: "Justify Text toggle")
				}
			}
			Toggle(isOn: $useCustomHyphenate) {
				Text("Override Hyphenation", comment: "Override Hyphenation toggle")
			}
			if useCustomHyphenate {
				Toggle(isOn: $hyphenate) {
					Text("Hyphenate", comment: "Hyphenate toggle")
				}
			}
		} footer: {
			Text("Some themes justify text on their own. Turn on Override Justification to force it on or off regardless of the theme. Hyphenation works best paired with justified text on narrow screens.", comment: "Justification/hyphenation footer")
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
					Label {
						Text("Text Color", comment: "Text Color (light) picker label")
					} icon: {
						Image(systemName: "sun.max")
					}
				}
				ColorPicker(selection: $textColorDark, supportsOpacity: false) {
					Label {
						Text("Text Color (Dark Mode)", comment: "Text Color (dark) picker label")
					} icon: {
						Image(systemName: "moon")
					}
				}
			}

			Toggle(isOn: $useCustomBackgroundColor) {
				Text("Custom Background Color", comment: "Custom Background Color toggle")
			}
			if useCustomBackgroundColor {
				ColorPicker(selection: $backgroundColor, supportsOpacity: false) {
					Label {
						Text("Background Color", comment: "Background Color (light) picker label")
					} icon: {
						Image(systemName: "sun.max")
					}
				}
				ColorPicker(selection: $backgroundColorDark, supportsOpacity: false) {
					Label {
						Text("Background Color (Dark Mode)", comment: "Background Color (dark) picker label")
					} icon: {
						Image(systemName: "moon")
					}
				}
			}

			Toggle(isOn: $useCustomLinkColor) {
				Text("Custom Link Color", comment: "Custom Link Color toggle")
			}
			if useCustomLinkColor {
				ColorPicker(selection: $linkColor, supportsOpacity: false) {
					Label {
						Text("Link Color", comment: "Link Color (light) picker label")
					} icon: {
						Image(systemName: "sun.max")
					}
				}
				ColorPicker(selection: $linkColorDark, supportsOpacity: false) {
					Label {
						Text("Link Color (Dark Mode)", comment: "Link Color (dark) picker label")
					} icon: {
						Image(systemName: "moon")
					}
				}
			}
		} header: {
			Text("Colors", comment: "Colors section header")
		} footer: {
			Text("Each color has a separate light and dark mode value.", comment: "Colors section footer explaining light/dark pairing")
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
			serifFontFamilyName: useCustomSerifFont ? serifFontFamilyName : nil,
			sansFontFamilyName: useCustomSansFont ? sansFontFamilyName : nil,
			fontSize: useCustomFontSize ? fontSize : nil,
			lineHeight: useCustomLineHeight ? lineHeight : nil,
			paragraphSpacing: useCustomParagraphSpacing ? paragraphSpacing : nil,
			paragraphIndent: useCustomParagraphIndent ? paragraphIndent : nil,
			marginHorizontal: useCustomMargins ? marginHorizontal : nil,
			marginTop: useCustomMargins ? marginTop : nil,
			justifyText: useCustomJustifyText ? justifyText : nil,
			hyphenate: useCustomHyphenate ? hyphenate : nil,
			textColorHex: useCustomTextColor ? textColor.hexString : nil,
			textColorDarkHex: useCustomTextColor ? textColorDark.hexString : nil,
			backgroundColorHex: useCustomBackgroundColor ? backgroundColor.hexString : nil,
			backgroundColorDarkHex: useCustomBackgroundColor ? backgroundColorDark.hexString : nil,
			linkColorHex: useCustomLinkColor ? linkColor.hexString : nil,
			linkColorDarkHex: useCustomLinkColor ? linkColorDark.hexString : nil
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
		UserDefaults.standard.set(serifFontFamilyName, forKey: Self.lastSerifFontFamilyNameDefaultsKey)
		UserDefaults.standard.set(sansFontFamilyName, forKey: Self.lastSansFontFamilyNameDefaultsKey)
	}

	private func resetToThemeDefaults() {
		let themeColors = ArticleThemeColorExtractor.colors(for: ArticleThemesManager.shared.currentTheme)

		useCustomSerifFont = false
		useCustomSansFont = false
		useCustomFontSize = false
		useCustomLineHeight = false
		useCustomParagraphSpacing = false
		useCustomParagraphIndent = false
		useCustomMargins = false
		useCustomJustifyText = false
		useCustomHyphenate = false
		useCustomTextColor = false
		useCustomBackgroundColor = false
		useCustomLinkColor = false
		fontSize = UIFont.preferredFont(forTextStyle: .body).pointSize
		lineHeight = 1.4
		paragraphSpacing = 1.0
		paragraphIndent = 0.0
		marginHorizontal = 20
		marginTop = 0
		justifyText = false
		hyphenate = false
		textColor = Color(themeColors.textColor)
		textColorDark = Color(themeColors.textColorDark)
		backgroundColor = Color(themeColors.backgroundColor)
		backgroundColorDark = Color(themeColors.backgroundColorDark)
		linkColor = Color(themeColors.linkColor)
		linkColorDark = Color(themeColors.linkColorDark)
		save()
	}

	// MARK: - Import / delete

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

	private func deleteCurrentTheme() {
		let themeName = ArticleThemesManager.shared.currentTheme.name
		ArticleThemesManager.shared.deleteTheme(themeName: themeName)
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

// `UIColor(cssHex:)` / `cssHexString` live in ArticleThemeColorExtractor.swift,
// shared with this file's color pickers.

private extension UIApplication {
	var firstKeyWindow: UIWindow? {
		connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap { $0.windows }
			.first { $0.isKeyWindow }
	}
}

#Preview {
	NavigationStack {
		ArticleThemeListView()
	}
}
