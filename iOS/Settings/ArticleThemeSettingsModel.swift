//
//  ArticleThemeSettingsModel.swift
//  NetNewsWire-iOS
//
//  Observable state behind `ArticleThemeListView`: owns article theme override
//  editing state, persists changes to `AppDefaults.shared.articleThemeOverrides`,
//  and observes `ArticleThemesManager` theme-name/selection notifications.
//

import Foundation
import SwiftUI
import UIKit
import ArticleTheming
import HexColor

@MainActor final class ArticleThemeSettingsModel: ObservableObject {

	static let availableFonts = ArticleThemeOverrides.FontChoice.all

	private static let lastSerifFontFamilyNameDefaultsKey = "ArticleThemeListView.lastSerifFontFamilyName"
	private static let lastSansFontFamilyNameDefaultsKey = "ArticleThemeListView.lastSansFontFamilyName"

	@Published private(set) var currentTheme: ArticleTheme
	@Published private(set) var hasDarkModeVariant: Bool

	@Published var useCustomSerifFont: Bool { didSet { saveIfNeeded() } }
	@Published var serifFontFamilyName: String { didSet { saveIfNeeded() } }

	@Published var useCustomSansFont: Bool { didSet { saveIfNeeded() } }
	@Published var sansFontFamilyName: String { didSet { saveIfNeeded() } }

	@Published var useCustomFontSize: Bool { didSet { saveIfNeeded() } }
	@Published var fontSize: Double { didSet { saveIfNeeded() } }

	@Published var useCustomLineHeight: Bool { didSet { saveIfNeeded() } }
	@Published var lineHeight: Double { didSet { saveIfNeeded() } }

	@Published var useCustomParagraphSpacing: Bool { didSet { saveIfNeeded() } }
	@Published var paragraphSpacing: Double { didSet { saveIfNeeded() } }

	@Published var useCustomParagraphIndent: Bool { didSet { saveIfNeeded() } }
	@Published var paragraphIndent: Double { didSet { saveIfNeeded() } }

	@Published var useCustomMargins: Bool { didSet { saveIfNeeded() } }
	@Published var marginHorizontal: Double { didSet { saveIfNeeded() } }
	@Published var marginTop: Double { didSet { saveIfNeeded() } }

	@Published var useCustomJustifyText: Bool { didSet { saveIfNeeded() } }
	@Published var justifyText: Bool { didSet { saveIfNeeded() } }

	@Published var useCustomHyphenate: Bool { didSet { saveIfNeeded() } }
	@Published var hyphenate: Bool { didSet { saveIfNeeded() } }

	@Published var hideAuthorStyle: Bool { didSet { saveIfNeeded() } }

	@Published var useCustomTextColor: Bool { didSet { saveIfNeeded() } }
	@Published var textColor: Color { didSet { saveIfNeeded() } }
	@Published var textColorDark: Color { didSet { saveIfNeeded() } }

	@Published var useCustomBackgroundColor: Bool { didSet { saveIfNeeded() } }
	@Published var backgroundColor: Color { didSet { saveIfNeeded() } }
	@Published var backgroundColorDark: Color { didSet { saveIfNeeded() } }

	@Published var useCustomLinkColor: Bool { didSet { saveIfNeeded() } }
	@Published var linkColor: Color { didSet { saveIfNeeded() } }
	@Published var linkColorDark: Color { didSet { saveIfNeeded() } }

	private var isBatchUpdating = false
	nonisolated(unsafe) private var observers = [NSObjectProtocol]()

	init(notificationCenter: NotificationCenter = .default) {
		let overrides = AppDefaults.shared.articleThemeOverrides
		let theme = ArticleThemesManager.shared.currentTheme
		let themeColors = ArticleThemeColorStore.colors(for: theme)

		let storedSerif = ArticleThemeOverrides.FontChoice.choice(forStoredName: overrides.serifFontFamilyName)?.id
		let storedSans = ArticleThemeOverrides.FontChoice.choice(forStoredName: overrides.sansFontFamilyName)?.id
		let lastSerif = ArticleThemeOverrides.FontChoice.choice(forStoredName: UserDefaults.standard.string(forKey: Self.lastSerifFontFamilyNameDefaultsKey))?.id
		let lastSans = ArticleThemeOverrides.FontChoice.choice(forStoredName: UserDefaults.standard.string(forKey: Self.lastSansFontFamilyNameDefaultsKey))?.id

		self.currentTheme = theme
		self.hasDarkModeVariant = themeColors.hasDarkModeVariant

		self.useCustomSerifFont = storedSerif != nil
		self.serifFontFamilyName = storedSerif ?? lastSerif ?? Self.availableFonts.first!.id

		self.useCustomSansFont = storedSans != nil
		self.sansFontFamilyName = storedSans ?? lastSans ?? Self.availableFonts.first!.id

		self.useCustomFontSize = overrides.fontSize != nil
		self.fontSize = overrides.fontSize ?? UIFont.preferredFont(forTextStyle: .body).pointSize

		self.useCustomLineHeight = overrides.lineHeight != nil
		self.lineHeight = overrides.lineHeight ?? 1.4

		self.useCustomParagraphSpacing = overrides.paragraphSpacing != nil
		self.paragraphSpacing = overrides.paragraphSpacing ?? 1.0

		self.useCustomParagraphIndent = overrides.paragraphIndent != nil
		self.paragraphIndent = overrides.paragraphIndent ?? 0.0

		self.useCustomMargins = overrides.marginHorizontal != nil || overrides.marginTop != nil
		self.marginHorizontal = overrides.marginHorizontal ?? 20
		self.marginTop = overrides.marginTop ?? 0

		self.useCustomJustifyText = overrides.justifyText != nil
		self.justifyText = overrides.justifyText ?? false

		self.useCustomHyphenate = overrides.hyphenate != nil
		self.hyphenate = overrides.hyphenate ?? false

		self.hideAuthorStyle = overrides.hideAuthorStyle ?? false

		self.useCustomTextColor = overrides.textColorHex != nil
		self.textColor = Color(cssHex: overrides.textColorHex) ?? Color(themeColors.textColor)
		self.textColorDark = Color(cssHex: overrides.textColorDarkHex ?? overrides.textColorHex) ?? Color(themeColors.textColorDark)

		self.useCustomBackgroundColor = overrides.backgroundColorHex != nil
		self.backgroundColor = Color(cssHex: overrides.backgroundColorHex) ?? Color(themeColors.backgroundColor)
		self.backgroundColorDark = Color(cssHex: overrides.backgroundColorDarkHex ?? overrides.backgroundColorHex) ?? Color(themeColors.backgroundColorDark)

		self.useCustomLinkColor = overrides.linkColorHex != nil
		self.linkColor = Color(cssHex: overrides.linkColorHex) ?? Color(themeColors.linkColor)
		self.linkColorDark = Color(cssHex: overrides.linkColorDarkHex ?? overrides.linkColorHex) ?? Color(themeColors.linkColorDark)

		let names: [Notification.Name] = [.ArticleThemeNamesDidChangeNotification, .CurrentArticleThemeDidChangeNotification]
		observers = names.map { name in
			notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated {
					self?.refreshThemeMetadata()
				}
			}
		}
	}

	deinit {
		for observer in observers {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	var themeAppearanceDescription: String {
		if hasDarkModeVariant {
			let format = NSLocalizedString("“%@” has separate light and dark mode colors and follows your system appearance setting.", comment: "Theme appearance footer, light+dark theme")
			return NSString.localizedStringWithFormat(format as NSString, currentTheme.name) as String
		} else {
			let format = NSLocalizedString("“%@” uses a single color palette in both light and dark mode.", comment: "Theme appearance footer, single-palette theme")
			return NSString.localizedStringWithFormat(format as NSString, currentTheme.name) as String
		}
	}

	var liveOverrides: ArticleThemeOverrides {
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
			hideAuthorStyle: hideAuthorStyle ? true : nil,
			textColorHex: useCustomTextColor ? textColor.cssHexString : nil,
			textColorDarkHex: useCustomTextColor ? textColorDark.cssHexString : nil,
			backgroundColorHex: useCustomBackgroundColor ? backgroundColor.cssHexString : nil,
			backgroundColorDarkHex: useCustomBackgroundColor ? backgroundColorDark.cssHexString : nil,
			linkColorHex: useCustomLinkColor ? linkColor.cssHexString : nil,
			linkColorDarkHex: useCustomLinkColor ? linkColorDark.cssHexString : nil
		)
	}

	var previewCSS: String {
		let themeCSS = currentTheme.css ?? ""
		let overrideCSS = liveOverrides.cssOverrideBlock(themeCSS: themeCSS)
		guard !overrideCSS.isEmpty else { return themeCSS }
		return themeCSS + "\n" + overrideCSS
	}

	func resetToThemeDefaults() {
		let themeColors = ArticleThemeColorStore.colors(for: currentTheme)

		isBatchUpdating = true
		defer {
			isBatchUpdating = false
			save()
		}

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
		hideAuthorStyle = false
		textColor = Color(themeColors.textColor)
		textColorDark = Color(themeColors.textColorDark)
		backgroundColor = Color(themeColors.backgroundColor)
		backgroundColorDark = Color(themeColors.backgroundColorDark)
		linkColor = Color(themeColors.linkColor)
		linkColorDark = Color(themeColors.linkColorDark)
	}

	func deleteCurrentTheme() {
		ArticleThemesManager.shared.deleteTheme(themeName: currentTheme.name)
	}

	func importTheme(url: URL) {
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

	private func refreshThemeMetadata() {
		let theme = ArticleThemesManager.shared.currentTheme
		currentTheme = theme
		hasDarkModeVariant = ArticleThemeColorStore.colors(for: theme).hasDarkModeVariant
	}

	private func saveIfNeeded() {
		guard !isBatchUpdating else { return }
		save()
	}

	private func save() {
		AppDefaults.shared.articleThemeOverrides = liveOverrides
		UserDefaults.standard.set(serifFontFamilyName, forKey: Self.lastSerifFontFamilyNameDefaultsKey)
		UserDefaults.standard.set(sansFontFamilyName, forKey: Self.lastSansFontFamilyNameDefaultsKey)
	}
}

private extension Color {
	init?(cssHex: String?) {
		guard let cssHex, let uiColor = UIColor(cssHex: cssHex) else { return nil }
		self.init(uiColor: uiColor)
	}

	var cssHexString: String {
		UIColor(self).cssHexString
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
