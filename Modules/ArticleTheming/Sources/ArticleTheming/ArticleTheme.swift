//
//  ArticleTheme.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/26/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import CryptoKit

public struct ArticleTheme: Equatable, Sendable {

	public static let defaultTheme = ArticleTheme()
	public static let nnwThemeSuffix = ".nnwtheme"

	/// Display name of the built-in fallback theme. It is the same design as the bundled
	/// "System" theme, so it carries that name; the persisted sentinel stays
	/// `ArticleThemesManager.defaultThemeName` ("Default").
	private static let defaultThemeName = NSLocalizedString("System", comment: "Name of the built-in default article theme")
	private static let unknownValue = NSLocalizedString("Unknown", comment: "Unknown Value")

	public let url: URL?
	public let template: String?
	public let importCSS: String?
	public let css: String?
	public let isAppTheme: Bool

	/// Identifies this theme's measurable content for the color cache: SHA-256 over the
	/// raw `stylesheet.css`, raw `template.html` and the probe version. Excludes `core.css`
	/// (the cache tracks that separately) and identity fields (`ThemeIdentifier`, `Version`,
	/// bundle name), because only content can change colors and authors forget to bump `Version`.
	public let colorCacheKey: String

	/// The theme's own CSS after `@import` extraction and before `core.css` is prepended.
	/// nil when the bundle has no `stylesheet.css`.
	public let ownStylesheet: String?

	public var name: String {
		guard let url else { return Self.defaultThemeName }
		return Self.themeNameForPath(url.path)
	}

	public var creatorHomePage: String {
		return Self.nonEmpty(info?.creatorHomePage) ?? Self.unknownValue
	}

	public var creatorName: String {
		return Self.nonEmpty(info?.creatorName) ?? Self.unknownValue
	}

	public var version: String {
		return String(describing: info?.version ?? 0)
	}

	/// Purely presentational grouping for the theme gallery. nil for the large
	/// majority of themes, which aren't part of a multi-variant family.
	public var family: String? {
		info?.family
	}

	/// This bundle's variant label within `family`. Meaningless when `family` is nil.
	public var familyVariant: String? {
		info?.familyVariant
	}

	private let info: ArticleThemePlist?

	public init() {
		self.url = nil
		self.info = ArticleThemePlist(name: "Article Theme", themeIdentifier: "com.ranchero.netnewswire.theme.article", creatorHomePage: "https://netnewswire.com/", creatorName: "Ranchero Software", version: 1, family: nil, familyVariant: nil)

		let corePath = Bundle.main.path(forResource: "core", ofType: "css")!
		let stylesheetPath = Bundle.main.path(forResource: "stylesheet", ofType: "css")!
		let rawStylesheet = Self.stringAtPath(stylesheetPath)!
		let extraction = CSSImportExtractor.extract(from: rawStylesheet)
		self.importCSS = extraction.importCSS.nilIfEmpty
		self.css = Self.stringAtPath(corePath)! + "\n" + extraction.remainingCSS
		self.ownStylesheet = extraction.remainingCSS

		let templatePath = Bundle.main.path(forResource: "template", ofType: "html")!
		let rawTemplate = Self.stringAtPath(templatePath)!
		self.template = rawTemplate
		self.colorCacheKey = Self.cacheKey(stylesheet: rawStylesheet, template: rawTemplate, probeVersion: ArticleThemeColorProbe.version)

		self.isAppTheme = true
	}

	public init(url: URL, isAppTheme: Bool) throws {
		_ = url.startAccessingSecurityScopedResource()
		defer {
			url.stopAccessingSecurityScopedResource()
		}

		self.url = url

		let coreURL = Bundle.main.url(forResource: "core", withExtension: "css")!
		let styleSheetURL = url.appendingPathComponent("stylesheet.css")
		let rawStylesheet = Self.stringAtPath(styleSheetURL.path)
		if let stylesheetCSS = rawStylesheet {
			let extraction = CSSImportExtractor.extract(from: stylesheetCSS)
			self.importCSS = extraction.importCSS.nilIfEmpty
			self.css = Self.stringAtPath(coreURL.path)! + "\n" + extraction.remainingCSS
			self.ownStylesheet = extraction.remainingCSS
		} else {
			self.importCSS = nil
			self.css = nil
			self.ownStylesheet = nil
		}

		let templateURL = url.appendingPathComponent("template.html")
		let rawTemplate = Self.stringAtPath(templateURL.path)
		self.template = rawTemplate
		self.colorCacheKey = Self.cacheKey(stylesheet: rawStylesheet, template: rawTemplate, probeVersion: ArticleThemeColorProbe.version)

		self.isAppTheme = isAppTheme

		// Permissive: a missing, unreadable or odd Info.plist never blocks a theme. The name
		// comes from the folder, and the creator fields read as "Unknown". Upstream throws
		// here, which hid the theme from the list entirely.
		let infoURL = url.appendingPathComponent("Info.plist")
		self.info = (try? Data(contentsOf: infoURL)).flatMap { ArticleThemePlist.lenient(from: $0) }
	}

	/// nil for nil, empty and whitespace-only strings.
	private static func nonEmpty(_ string: String?) -> String? {
		guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
			return nil
		}
		return trimmed
	}

	/// SHA-256 (lowercase hex) over length-prefixed stylesheet, template and probe version,
	/// so no two (stylesheet, template) splits of the same bytes collide. A missing file
	/// hashes like an empty one.
	static func cacheKey(stylesheet: String?, template: String?, probeVersion: Int) -> String {
		var hasher = SHA256()
		func feed(_ data: Data) {
			var length = UInt64(data.count).bigEndian
			withUnsafeBytes(of: &length) { hasher.update(bufferPointer: $0) }
			hasher.update(data: data)
		}
		feed(Data((stylesheet ?? "").utf8))
		feed(Data((template ?? "").utf8))
		var version = UInt64(probeVersion).bigEndian
		withUnsafeBytes(of: &version) { hasher.update(bufferPointer: $0) }
		return hasher.finalize().map { String(format: "%02x", $0) }.joined()
	}

	static func stringAtPath(_ f: String) -> String? {
		if !FileManager.default.fileExists(atPath: f) {
			return nil
		}

		var encoding = String.Encoding.utf8
		if let s = try? String(contentsOfFile: f, usedEncoding: &encoding) {
			return s
		}
		return nil
	}

	static func filenameWithThemeSuffixRemoved(_ filename: String) -> String {
		return filename.stripping(suffix: Self.nnwThemeSuffix)
	}

	static func themeNameForPath(_ f: String) -> String {
		let filename = (f as NSString).lastPathComponent
		return filenameWithThemeSuffixRemoved(filename)
	}

	static func pathIsPathForThemeName(_ themeName: String, path: String) -> Bool {
		let filename = (path as NSString).lastPathComponent
		return filenameWithThemeSuffixRemoved(filename) == themeName
	}
}

private extension String {
	var nilIfEmpty: String? {
		isEmpty ? nil : self
	}
}
