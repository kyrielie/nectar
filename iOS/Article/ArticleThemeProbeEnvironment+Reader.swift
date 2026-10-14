//
//  ArticleThemeProbeEnvironment+Reader.swift
//  Nectar
//
//  Builds the theme color probe's environment from the reader's own pieces
//  (`page.html`, the style macro values, the reader's webpage preferences and
//  `core.css`), so the probe renders a theme the way the reader does. Lives in
//  the app target because the package cannot see any of these.
//

import Foundation
import CryptoKit
import ArticleTheming

extension ArticleThemeProbeEnvironment {

	/// The environment the app uses at launch and the probe tests use.
	@MainActor static func reader() -> ArticleThemeProbeEnvironment {
		ArticleThemeProbeEnvironment(
			pageHTML: ArticleRenderer.page.html,
			styleSubstitutions: ArticleRenderer.styleSubstitutions(),
			lang: ArticlePageComposer.defaultLang,
			coreCSSHash: bundledCoreCSSHash(),
			makePagePreferences: { WebViewConfiguration.makeReaderWebpagePreferences() })
	}

	/// Lowercase hex SHA-256 of the bundled `core.css`; empty if it cannot be read.
	static func bundledCoreCSSHash() -> String {
		guard let url = Bundle.main.url(forResource: "core", withExtension: "css"),
			  let data = try? Data(contentsOf: url) else {
			return ""
		}
		return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
	}
}
