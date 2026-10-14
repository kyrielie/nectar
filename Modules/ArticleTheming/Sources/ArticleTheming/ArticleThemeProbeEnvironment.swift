//
//  ArticleThemeProbeEnvironment.swift
//  ArticleTheming
//
//  Everything the color probe needs from the app target, which this package
//  cannot see (`page.html`, the reader's webpage preferences, `core.css`).
//  The app builds one at launch and hands it to the color store.
//

import Foundation
import WebKit

public struct ArticleThemeProbeEnvironment: Sendable {
	/// `ArticleRenderer.page.html`.
	public var pageHTML: String
	/// The same values the reader gives a theme's stylesheet (font-size).
	public var styleSubstitutions: [String: String]
	/// The same expression the reader uses for `<html lang>`.
	public var lang: String
	/// SHA-256 of the bundled `core.css`, recorded in the persisted cache.
	public var coreCSSHash: String
	/// The reader's page preferences (content JavaScript off). A closure
	/// because `WKWebpagePreferences` is not `Sendable`.
	public var makePagePreferences: @MainActor @Sendable () -> WKWebpagePreferences

	public init(pageHTML: String,
				styleSubstitutions: [String: String],
				lang: String,
				coreCSSHash: String,
				makePagePreferences: @escaping @MainActor @Sendable () -> WKWebpagePreferences) {
		self.pageHTML = pageHTML
		self.styleSubstitutions = styleSubstitutions
		self.lang = lang
		self.coreCSSHash = coreCSSHash
		self.makePagePreferences = makePagePreferences
	}
}
