//
//  ArticleTheme.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/26/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import Foundation

struct ArticleTheme: Equatable, Sendable {

	static let defaultTheme = ArticleTheme()
	static let nnwThemeSuffix = ".nnwtheme"

	private static let defaultThemeName = NSLocalizedString("Default", comment: "Default")
	private static let unknownValue = NSLocalizedString("Unknown", comment: "Unknown Value")

	let url: URL?
	let template: String?
	let importCSS: String?
	let css: String?
	let isAppTheme: Bool

	var name: String {
		guard let url else { return Self.defaultThemeName }
		return Self.themeNameForPath(url.path)
	}

	var creatorHomePage: String {
		return info?.creatorHomePage ?? Self.unknownValue
	}

	var creatorName: String {
		return info?.creatorName ?? Self.unknownValue
	}

	var version: String {
		return String(describing: info?.version ?? 0)
	}

	/// Purely presentational grouping for the theme gallery. nil for the large
	/// majority of themes, which aren't part of a multi-variant family.
	var family: String? {
		info?.family
	}

	/// This bundle's variant label within `family`. Meaningless when `family` is nil.
	var familyVariant: String? {
		info?.familyVariant
	}

	private let info: ArticleThemePlist?

	init() {
		self.url = nil
		self.info = ArticleThemePlist(name: "Article Theme", themeIdentifier: "com.ranchero.netnewswire.theme.article", creatorHomePage: "https://netnewswire.com/", creatorName: "Ranchero Software", version: 1, family: nil, familyVariant: nil)

		let corePath = Bundle.main.path(forResource: "core", ofType: "css")!
		let stylesheetPath = Bundle.main.path(forResource: "stylesheet", ofType: "css")!
		let extraction = CSSImportExtractor.extract(from: Self.stringAtPath(stylesheetPath)!)
		self.importCSS = extraction.importCSS.nilIfEmpty
		self.css = Self.stringAtPath(corePath)! + "\n" + extraction.remainingCSS

		let templatePath = Bundle.main.path(forResource: "template", ofType: "html")!
		self.template = Self.stringAtPath(templatePath)!

		self.isAppTheme = true
	}

	init(url: URL, isAppTheme: Bool) throws {
		_ = url.startAccessingSecurityScopedResource()
		defer {
			url.stopAccessingSecurityScopedResource()
		}

		self.url = url

		let coreURL = Bundle.main.url(forResource: "core", withExtension: "css")!
		let styleSheetURL = url.appendingPathComponent("stylesheet.css")
		if let stylesheetCSS = Self.stringAtPath(styleSheetURL.path) {
			let extraction = CSSImportExtractor.extract(from: stylesheetCSS)
			self.importCSS = extraction.importCSS.nilIfEmpty
			self.css = Self.stringAtPath(coreURL.path)! + "\n" + extraction.remainingCSS
		} else {
			self.importCSS = nil
			self.css = nil
		}

		let templateURL = url.appendingPathComponent("template.html")
		self.template = Self.stringAtPath(templateURL.path)

		self.isAppTheme = isAppTheme

		let infoURL = url.appendingPathComponent("Info.plist")
		let data = try Data(contentsOf: infoURL)
		self.info = try PropertyListDecoder().decode(ArticleThemePlist.self, from: data)
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
