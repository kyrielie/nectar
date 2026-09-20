//
//  ArticleThemeOverflowSafetyTests.swift
//  NetNewsWire-iOSTests
//
//  Regression coverage for the "some books can be scrolled horizontally"
//  bug: some fic art (banners, manips) renders wider than its container
//  and, with nothing to clip it, the whole article page becomes
//  horizontally scrollable. Two independent layers are meant to prevent
//  this -- see docs/theme-system.md and the fix that added them:
//
//  1. core.css's `html, body { overflow-x: hidden }` -- the single
//     structural backstop, since core.css is prepended to every theme
//     (ArticleTheme.init(url:isAppTheme:) always prepends it; see
//     Shared/ArticleStyles/ArticleTheme.swift).
//  2. Every shipped theme's own `img, figure, video, div, object {
//     max-width: 100% }`-equivalent rule, which is what makes oversized
//     content actually *fit* rather than just get clipped. Most shipped
//     themes get this for free from buildscripts/theme-generation/
//     generate_ported_themes.py; the hand-written ones that predate the
//     generator (Aldine, Deco Line, Kelmscott, Kennerley, Marigold Press,
//     Rosarivo) needed it added directly to their stylesheet.css.
//
//  This suite guards (1) directly and (2) as a coverage check across every
//  bundled theme, so a newly hand-written theme that forgets the rule
//  fails the build instead of shipping a silent regression.
//

import Testing
import Foundation
@testable import Nectar

@Suite struct ArticleThemeOverflowSafetyTests {

	@Test func coreCSSHasHorizontalOverflowBackstop() throws {
		let coreCSS = try Self.readRepoFile("Shared/Article Rendering/core.css")
		#expect(coreCSS.contains("overflow-x: hidden"),
				"core.css must clip horizontal overflow at the html/body level -- this is the one place a fix here covers every theme")
	}

	/// Every bundled theme must constrain img/figure/video/object width itself --
	/// core.css's overflow-x: hidden (above) only clips content that still overflows
	/// despite this, it doesn't make oversized images fit their column.
	///
	/// Covers both Themes/ (app-embedded) and gallery-themes/ (gallery-only) --
	/// splitting the 33 themes across the two directories must not narrow this
	/// suite's real coverage down to just the themes the app ships today.
	@Test func everyBundledThemeConstrainsMediaWidth() throws {
		let themeDirectories = Self.repoThemeDirectories()
		var themeBundleNames: [(name: String, directory: URL)] = []
		for themesDirectory in themeDirectories {
			let contents = try FileManager.default.contentsOfDirectory(atPath: themesDirectory.path)
			themeBundleNames += contents.filter { $0.hasSuffix(".nnwtheme") }.map { ($0, themesDirectory) }
		}
		#expect(!themeBundleNames.isEmpty, "Expected to find .nnwtheme bundles under \(themeDirectories.map(\.path))")

		for (bundleName, themesDirectory) in themeBundleNames {
			let stylesheetURL = themesDirectory.appendingPathComponent(bundleName).appendingPathComponent("stylesheet.css")
			guard let css = try? String(contentsOf: stylesheetURL, encoding: .utf8) else { continue }

			let hasImgRule = css.range(of: #"img\s*,[^{]*\{[^}]*max-width\s*:\s*100%"#, options: .regularExpression) != nil
				|| css.range(of: #"\bimg\s*\{[^}]*max-width\s*:\s*100%"#, options: .regularExpression) != nil
			#expect(hasImgRule, "\(bundleName) has no img max-width: 100% rule -- oversized fic art will overflow its column")
		}
	}

	private static func readRepoFile(_ relativePath: String) throws -> String {
		var url = URL(fileURLWithPath: #filePath)
		while url.pathComponents.count > 1 {
			url.deleteLastPathComponent()
			let candidate = url.appendingPathComponent(relativePath)
			if FileManager.default.fileExists(atPath: candidate.path) {
				return try String(contentsOf: candidate, encoding: .utf8)
			}
		}
		fatalError("Could not locate \(relativePath) by walking up from \(#filePath)")
	}

	/// Both theme directories, resolved the same walk-up-to-repo-root way --
	/// gallery-themes/ holds the themes moved out of the app bundle (see
	/// gallery/build.py's BUNDLED set and docs/nnwtheme-format.md), so a theme's
	/// current folder is which directory ships it, not whether it exists at all.
	private static func repoThemeDirectories() -> [URL] {
		var url = URL(fileURLWithPath: #filePath)
		while url.pathComponents.count > 1 {
			url.deleteLastPathComponent()
			let themes = url.appendingPathComponent("Themes")
			if FileManager.default.fileExists(atPath: themes.path) {
				let galleryThemes = url.appendingPathComponent("gallery-themes")
				return [themes, galleryThemes].filter { FileManager.default.fileExists(atPath: $0.path) }
			}
		}
		fatalError("Could not locate repo Themes/ directory by walking up from \(#filePath)")
	}
}
