//
//  ArticleThemeListView.swift
//  NetNewsWire-iOS
//
//  Created for Settings → Theme.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import ArticleTheming
import HexColor

extension UTType {
	static var netNewsWireTheme: UTType { UTType(importedAs: "com.ranchero.netnewswire.theme") }
}

struct ArticleThemeListView: View {

	@StateObject private var model = ArticleThemeSettingsModel()

	@State private var isDeleteCurrentThemeAlertPresented = false
	@State private var isResetAlertPresented = false
	@State private var previewColorScheme: ColorScheme = .light

	var body: some View {
		Form {
			ArticleThemeSelectionSection(
				model: model,
				onDeleteTap: { isDeleteCurrentThemeAlertPresented = true }
			)
			ArticleThemePreviewSection(
				model: model,
				previewColorScheme: $previewColorScheme
			)
			Section {
				NavigationLink {
					ArticleThemeOverridesView(model: model, isResetAlertPresented: $isResetAlertPresented)
				} label: {
					LabeledContent {
						Text(overrideSummaryText)
							.foregroundStyle(.secondary)
					} label: {
						Label(NSLocalizedString("Customize Theme", comment: "Customize Theme overrides row"), systemImage: "slider.horizontal.3")
					}
				}
			} footer: {
				Text("Override fonts, spacing, margins, creator styles, and colors for the active theme.", comment: "Customize Theme row footer")
			}

			if model.activeOverrideCount > 0 {
				Section {
					Button(role: .destructive) {
						isResetAlertPresented = true
					} label: {
						Text("Reset to Theme Default", comment: "Reset to Theme Default button")
					}
				}
			}
		}
		.surfacePaletteListBackground()
		.navigationTitle(Text("Theme", comment: "Theme navigation title"))
		.navigationBarTitleDisplayMode(.inline)
		.alert(Text("Delete Theme?", comment: "Delete Theme"), isPresented: $isDeleteCurrentThemeAlertPresented) {
			Button(role: .cancel) { } label: {
				Text("Cancel", comment: "Cancel button")
			}
			Button(role: .destructive) {
				model.deleteCurrentTheme()
			} label: {
				Text("Delete", comment: "Delete button")
			}
		} message: {
			let localizedMessageText = NSLocalizedString("Are you sure you want to delete the theme “%@”?.", comment: "Delete Theme Message")
			Text(NSString.localizedStringWithFormat(localizedMessageText as NSString, model.currentTheme.name) as String)
		}
		.alert(Text("Reset Theme Overrides?", comment: "Reset Theme Overrides"), isPresented: $isResetAlertPresented) {
			Button(role: .cancel) { } label: {
				Text("Cancel", comment: "Cancel button")
			}
			Button(role: .destructive) {
				model.resetToThemeDefaults()
			} label: {
				Text("Reset", comment: "Reset button")
			}
		} message: {
			Text("This will discard all custom font, layout, and color overrides.", comment: "Reset Theme Overrides message")
		}
	}

	private var overrideSummaryText: String {
		let count = model.activeOverrideCount
		if count == 0 {
			return NSLocalizedString("None", comment: "No theme overrides active")
		} else if count == 1 {
			return NSLocalizedString("1 Active", comment: "One theme override active")
		} else {
			let format = NSLocalizedString("%d Active", comment: "Multiple theme overrides active")
			return String(format: format, count)
		}
	}
}

private struct ArticleThemeOverridesView: View {
	@ObservedObject var model: ArticleThemeSettingsModel
	@Binding var isResetAlertPresented: Bool

	var body: some View {
		Form {
			ArticleThemeTypographySection(model: model)
			ArticleThemeColorsSection(model: model)
			if model.activeOverrideCount > 0 {
				Section {
					Button(role: .destructive) {
						isResetAlertPresented = true
					} label: {
						Text("Reset to Theme Default", comment: "Reset to Theme Default button")
					}
				}
			}
		}
		.navigationTitle(Text("Customize Theme", comment: "Customize Theme navigation title"))
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct ArticleThemeSelectionSection: View {
	@ObservedObject var model: ArticleThemeSettingsModel
	let onDeleteTap: () -> Void

	var body: some View {
		Section {
			NavigationLink {
				ArticleThemePickerView()
			} label: {
				LabeledContent {
					Text(model.currentTheme.name)
						.foregroundStyle(.secondary)
				} label: {
					Text("Theme", comment: "Theme picker label")
				}
			}

			if !model.currentTheme.isAppTheme {
				Button(role: .destructive, action: onDeleteTap) {
					Text("Delete This Theme", comment: "Delete current imported theme button")
				}
			}
		} footer: {
			Text(model.themeAppearanceDescription)
		}
	}
}

private struct ArticleThemePreviewSection: View {
	@ObservedObject var model: ArticleThemeSettingsModel
	@Binding var previewColorScheme: ColorScheme

	var body: some View {
		Section {
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
			.disabled(!model.hasDarkModeVariant)
			.foregroundStyle(model.hasDarkModeVariant ? .primary : .secondary)

			ArticleThemePreviewWebView(
				importCSS: model.currentTheme.importCSS,
				css: model.previewCSS,
				template: model.currentTheme.template,
				showFeedName: AppDefaults.shared.showFeedNameInReaderView,
				colorScheme: model.hasDarkModeVariant ? previewColorScheme : .light,
				overrideBackgroundColorHex: model.useCustomBackgroundColor ? UIColor(model.backgroundColor).cssHexString : nil,
				overrideBackgroundColorDarkHex: model.useCustomBackgroundColor ? UIColor(model.backgroundColorDark).cssHexString : nil
			)
			.frame(height: 320)
			.listRowInsets(EdgeInsets())
		} header: {
			Text("Preview", comment: "Preview section header")
		} footer: {
			Text("Reflects the current theme (\(model.currentTheme.name)) plus your overrides.", comment: "Preview footer explaining theme + override layering")
		}
	}
}

private struct ArticleThemeTypographySection: View {
	@ObservedObject var model: ArticleThemeSettingsModel

	var body: some View {
		Section {
			Toggle(isOn: $model.useCustomSerifFont) {
				Text("Custom Reading Font", comment: "Custom Reading Font toggle")
			}
			if model.useCustomSerifFont {
				Picker(selection: $model.serifFontFamilyName) {
					ForEach(ArticleThemeSettingsModel.availableFonts) { font in
						Text(font.displayName).tag(font.id)
					}
				} label: {
					Text("Reading Font", comment: "Reading Font picker label")
				}
			}

			Toggle(isOn: $model.useCustomSansFont) {
				Text("Custom Interface Font", comment: "Custom Interface Font toggle")
			}
			if model.useCustomSansFont {
				Picker(selection: $model.sansFontFamilyName) {
					ForEach(ArticleThemeSettingsModel.availableFonts) { font in
						Text(font.displayName).tag(font.id)
					}
				} label: {
					Text("Interface Font", comment: "Interface Font picker label")
				}
			}

			Toggle(isOn: $model.useCustomFontSize) {
				Text("Custom Font Size", comment: "Custom Font Size toggle")
			}
			if model.useCustomFontSize {
				OverrideSliderRow(value: $model.fontSize, range: ArticleThemeOverrides.fontSizeRange, step: 1, fractionLength: 0)
			}

			Toggle(isOn: $model.useCustomLineHeight) {
				Text("Custom Line Spacing", comment: "Custom Line Spacing toggle")
			}
			if model.useCustomLineHeight {
				OverrideSliderRow(value: $model.lineHeight, range: ArticleThemeOverrides.lineHeightRange, step: 0.1, fractionLength: 1)
			}

			Toggle(isOn: $model.useCustomParagraphSpacing) {
				Text("Custom Paragraph Spacing", comment: "Custom Paragraph Spacing toggle")
			}
			if model.useCustomParagraphSpacing {
				OverrideSliderRow(value: $model.paragraphSpacing, range: ArticleThemeOverrides.paragraphSpacingRange, step: 0.1, fractionLength: 1)
			}

			Toggle(isOn: $model.useCustomParagraphIndent) {
				Text("Custom Paragraph Indent", comment: "Custom Paragraph Indent toggle")
			}
			if model.useCustomParagraphIndent {
				OverrideSliderRow(value: $model.paragraphIndent, range: ArticleThemeOverrides.paragraphIndentRange, step: 0.1, fractionLength: 1)
			}

			Toggle(isOn: $model.useCustomMargins) {
				Text("Custom Page Margins", comment: "Custom Page Margins toggle")
			}
			if model.useCustomMargins {
				OverrideSliderRow(
					title: NSLocalizedString("Left & Right", comment: "Left & Right margin label"),
					value: $model.marginHorizontal,
					range: ArticleThemeOverrides.marginHorizontalRange,
					step: 1,
					fractionLength: 0
				)
				OverrideSliderRow(
					title: NSLocalizedString("Top", comment: "Top margin label"),
					value: $model.marginTop,
					range: ArticleThemeOverrides.marginTopRange,
					step: 1,
					fractionLength: 0
				)
			}

			Toggle(isOn: $model.useCustomJustifyText) {
				Text("Override Justification", comment: "Override Justification toggle")
			}
			if model.useCustomJustifyText {
				Toggle(isOn: $model.justifyText) {
					Text("Justify Text", comment: "Justify Text toggle")
				}
			}

			Toggle(isOn: $model.useCustomHyphenate) {
				Text("Override Hyphenation", comment: "Override Hyphenation toggle")
			}
			if model.useCustomHyphenate {
				Toggle(isOn: $model.hyphenate) {
					Text("Hyphenate", comment: "Hyphenate toggle")
				}
			}

			Toggle(isOn: $model.hideAuthorStyle) {
				Text("Hide Creator's Style", comment: "Hide Creator's Style toggle")
			}
		} header: {
			Text("Typography & Text Layout", comment: "Typography & Text Layout section header")
		} footer: {
			Text("Reading Font applies to the work text. Interface Font applies to the byline, dateline, and other chrome. Margin below 20px may run edge-to-edge. Hide Creator's Style suppresses custom author fonts, colors, and layout skins on AO3 works.", comment: "Typography and Layout section footer")
		}
	}
}

private struct OverrideSliderRow: View {
	var title: String?
	@Binding var value: Double
	let range: ClosedRange<Double>
	let step: Double
	let fractionLength: Int

	var body: some View {
		HStack {
			if let title {
				Text(title)
			}
			Slider(value: $value, in: range, step: step)
			Text(value, format: .number.precision(.fractionLength(fractionLength)))
				.monospacedDigit()
				.frame(width: 32, alignment: .trailing)
				.foregroundStyle(.secondary)
		}
	}
}

private struct ArticleThemeColorsSection: View {
	@ObservedObject var model: ArticleThemeSettingsModel

	var body: some View {
		Section {
			LightDarkColorOverrideGroup(
				toggleTitle: Text("Custom Text Color", comment: "Custom Text Color toggle"),
				lightTitle: Text("Text Color", comment: "Text Color (light) picker label"),
				darkTitle: Text("Text Color (Dark Mode)", comment: "Text Color (dark) picker label"),
				isEnabled: $model.useCustomTextColor,
				lightColor: $model.textColor,
				darkColor: $model.textColorDark
			)
			LightDarkColorOverrideGroup(
				toggleTitle: Text("Custom Background Color", comment: "Custom Background Color toggle"),
				lightTitle: Text("Background Color", comment: "Background Color (light) picker label"),
				darkTitle: Text("Background Color (Dark Mode)", comment: "Background Color (dark) picker label"),
				isEnabled: $model.useCustomBackgroundColor,
				lightColor: $model.backgroundColor,
				darkColor: $model.backgroundColorDark
			)
			LightDarkColorOverrideGroup(
				toggleTitle: Text("Custom Link Color", comment: "Custom Link Color toggle"),
				lightTitle: Text("Link Color", comment: "Link Color (light) picker label"),
				darkTitle: Text("Link Color (Dark Mode)", comment: "Link Color (dark) picker label"),
				isEnabled: $model.useCustomLinkColor,
				lightColor: $model.linkColor,
				darkColor: $model.linkColorDark
			)
		} header: {
			Text("Colors", comment: "Colors section header")
		} footer: {
			Text("Each color has a separate light and dark mode value.", comment: "Colors section footer explaining light/dark pairing")
		}
	}
}

private struct LightDarkColorOverrideGroup: View {
	let toggleTitle: Text
	let lightTitle: Text
	let darkTitle: Text
	@Binding var isEnabled: Bool
	@Binding var lightColor: Color
	@Binding var darkColor: Color

	var body: some View {
		Toggle(isOn: $isEnabled) {
			toggleTitle
		}
		if isEnabled {
			ColorPicker(selection: $lightColor, supportsOpacity: false) {
				Label {
					lightTitle
				} icon: {
					Image(systemName: "sun.max")
				}
			}
			ColorPicker(selection: $darkColor, supportsOpacity: false) {
				Label {
					darkTitle
				} icon: {
					Image(systemName: "moon")
				}
			}
		}
	}
}

#Preview {
	NavigationStack {
		ArticleThemeListView()
	}
}
