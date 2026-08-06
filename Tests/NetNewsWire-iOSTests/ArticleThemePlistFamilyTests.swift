//
//  ArticleThemePlistFamilyTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for ArticleThemePlist's Family/FamilyVariant fields
//  (theme-settings-implementation-plan.md §7.3): confirms the two new
//  optional keys decode correctly when present, and confirms every
//  existing Info.plist with no Family/FamilyVariant keys keeps decoding
//  cleanly with nil -- no migration needed for the 28+ themes that aren't
//  part of a family.
//

import Testing
import Foundation
@testable import Nectar

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

	/// Every actually-shipped Info.plist in Themes/ must still decode -- catches any
	/// future accidental key removal or a malformed hand-edit of the plist XML.
	@Test func decodesEveryBundledThemeInfoPlist() throws {
		let themesDirectory = Self.repoThemesDirectory()
		let contents = try FileManager.default.contentsOfDirectory(atPath: themesDirectory.path)
		let themeBundleNames = contents.filter { $0.hasSuffix(".nnwtheme") }
		#expect(!themeBundleNames.isEmpty, "Expected to find .nnwtheme bundles under \(themesDirectory.path)")

		for bundleName in themeBundleNames {
			let plistURL = themesDirectory.appendingPathComponent(bundleName).appendingPathComponent("Info.plist")
			let data = try Data(contentsOf: plistURL)
			_ = try PropertyListDecoder().decode(ArticleThemePlist.self, from: data)
		}
	}

	/// Walks up from this test file's own path to find the repo root's Themes/
	/// directory, rather than relying on Bundle.main (which inside a test target is
	/// the test runner's bundle, not the app's, and doesn't have Themes/ copied in).
	private static func repoThemesDirectory() -> URL {
		var url = URL(fileURLWithPath: #filePath)
		while url.pathComponents.count > 1 {
			url.deleteLastPathComponent()
			let candidate = url.appendingPathComponent("Themes")
			if FileManager.default.fileExists(atPath: candidate.path) {
				return candidate
			}
		}
		fatalError("Could not locate repo Themes/ directory by walking up from \(#filePath)")
	}
}
