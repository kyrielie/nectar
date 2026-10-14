//
//  ArticlePageComposer.swift
//  ArticleTheming
//
//  Builds the final HTML for a page the same way the reader does: the app's
//  `page.html` run through `MacroProcessor` with exactly six keys. Shared by
//  the reader's tests, the Settings preview and the theme color probe, so none
//  of them can drift from the reader's page skeleton.
//

import Foundation
import RSCore

public enum ArticlePageComposer {

	/// Device-locale language, the same expression the reader uses. `hyphens: auto`
	/// needs it to pick a WebKit hyphenation dictionary.
	public static var defaultLang: String {
		Locale.current.language.languageCode?.identifier ?? "en"
	}

	/// The `[[importStyle]]` value for a theme's extracted `@import` rules.
	/// Empty when the theme has none.
	public static func importStyle(importCSS: String?) -> String {
		guard let importCSS, !importCSS.isEmpty else {
			return ""
		}
		return """
		<style>
			\(importCSS)
		</style>
		"""
	}

	/// Renders `pageHTML` with the six keys `page.html` uses:
	/// `title`, `importStyle`, `style`, `baseURL`, `body`, `lang`.
	public static func compose(pageHTML: String,
							   title: String,
							   importStyle: String,
							   style: String,
							   baseURL: String,
							   body: String,
							   lang: String) throws -> String {
		let substitutions = [
			"title": title,
			"baseURL": baseURL,
			"importStyle": importStyle,
			"style": style,
			"body": body,
			"lang": lang
		]
		return try MacroProcessor.renderedText(withTemplate: pageHTML, substitutions: substitutions)
	}
}
