//
//  ArticleThemePlistFamilyTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for ArticleThemePlist's Family/FamilyVariant fields
//  (see docs/nnwtheme-format.md): confirms the two new
//  optional keys decode correctly when present, and confirms every
//  existing Info.plist with no Family/FamilyVariant keys keeps decoding
//  cleanly with nil -- no migration needed for the 28+ themes that aren't
//  part of a family.
//

import Testing
import Foundation
@testable import Nectar
@testable import ArticleTheming

@Suite struct ArticleThemePlistFamilyTests {

	private static func plistData(name: String, themeIdentifier: String, extraKeysXML: String = "") -> Data {
		let xml = """
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
			<key>Name</key>
			<string>\(name)</string>
			<key>ThemeIdentifier</key>
			<string>\(themeIdentifier)</string>
			<key>CreatorHomePage</key>
			<string>https://example.com/</string>
			<key>CreatorName</key>
			<string>Test Creator</string>
			<key>Version</key>
			<integer>1</integer>
			\(extraKeysXML)
		</dict>
		</plist>
		"""
		return Data(xml.utf8)
	}

	@Test func decodesFamilyFieldsWhenPresent() throws {
		let data = Self.plistData(
			name: "Dracula",
			themeIdentifier: "com.nectar.themes.dracula",
			extraKeysXML: """
			<key>Family</key>
			<string>Dracula</string>
			<key>FamilyVariant</key>
			<string>Purple</string>
			"""
		)
		let decoded = try PropertyListDecoder().decode(ArticleThemePlist.self, from: data)
		#expect(decoded.family == "Dracula")
		#expect(decoded.familyVariant == "Purple")
	}

	/// The 28+ themes with no Family key must keep decoding cleanly -- the same
	/// no-migration-needed guarantee AppDefaults.shared.articleThemeOverrides relies
	/// on for its own optional fields, applied here to Info.plist instead.
	@Test func decodesWithoutFamilyFieldsPresent() throws {
		let data = Self.plistData(name: "Sepia", themeIdentifier: "com.netnewswire.themes.sepia")
		let decoded = try PropertyListDecoder().decode(ArticleThemePlist.self, from: data)
		#expect(decoded.family == nil)
		#expect(decoded.familyVariant == nil)
	}

	/// Every actually-shipped Info.plist, in Themes/ (app-embedded) or
	/// gallery-themes/ (gallery-only), must still decode -- catches any future
	/// accidental key removal or a malformed hand-edit of the plist XML. Checking
	/// both directories keeps this at full 33-theme coverage regardless of which
	/// folder a given theme currently ships from.
	@Test func decodesEveryBundledThemeInfoPlist() throws {
		let themeDirectories = Self.repoThemeDirectories()
		var themeBundleNames: [(name: String, directory: URL)] = []
		for themesDirectory in themeDirectories {
			let contents = try FileManager.default.contentsOfDirectory(atPath: themesDirectory.path)
			themeBundleNames += contents.filter { $0.hasSuffix(".nnwtheme") }.map { ($0, themesDirectory) }
		}
		#expect(!themeBundleNames.isEmpty, "Expected to find .nnwtheme bundles under \(themeDirectories.map(\.path))")

		for (bundleName, themesDirectory) in themeBundleNames {
			let plistURL = themesDirectory.appendingPathComponent(bundleName).appendingPathComponent("Info.plist")
			let data = try Data(contentsOf: plistURL)
			_ = try PropertyListDecoder().decode(ArticleThemePlist.self, from: data)
		}
	}

	/// Walks up from this test file's own path to find the repo root, then returns
	/// whichever of Themes/ (app-embedded) and gallery-themes/ (gallery-only)
	/// actually exist there, rather than relying on Bundle.main (which inside a
	/// test target is the test runner's bundle, not the app's, and doesn't have
	/// either directory copied in).
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
