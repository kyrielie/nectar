//
//  ThemeColorTableTests.swift
//  NetNewsWire-iOSTests
//
//  The bundled color table: `iOS/Resources/ThemeColorTable.json`, the
//  cold-start color source for every theme that ships in the app (each
//  `Themes/*.nnwtheme` plus the Default theme).
//
//  - `ThemeColorTableGeneratorTests` writes the file. It does nothing unless
//    REGENERATE_THEME_COLOR_TABLE=1 is set (see docs/theme-testing.md).
//  - `ThemeColorTableGuardTests` always runs and fails when the shipped table no
//    longer matches the shipped themes, probe version or `core.css`.
//
//  Both need a simulator `WKWebView` and `Bundle.main` resources, so they live in
//  the app test target. Written without being run in Xcode.
//

import Testing
import Foundation
import UIKit
@testable import Nectar
@testable import ArticleTheming

// MARK: - Shared

enum ThemeColorTableSupport {

	static let tableFileName = "ThemeColorTable"
	static let regenerateVariable = "REGENERATE_THEME_COLOR_TABLE"

	static var shouldRegenerate: Bool {
		ProcessInfo.processInfo.environment[regenerateVariable] == "1"
	}

	static func repoURL(_ relativePath: String) throws -> URL {
		var url = URL(fileURLWithPath: #filePath)
		while url.pathComponents.count > 1 {
			url.deleteLastPathComponent()
			let candidate = url.appendingPathComponent(relativePath)
			if FileManager.default.fileExists(atPath: candidate.path) {
				return candidate
			}
		}
		throw CocoaError(.fileNoSuchFile)
	}

	/// Table key for a bundled theme: its bundle name without the suffix.
	static func key(forBundlePath path: String) -> String {
		ArticleTheme.themeNameForPath(path)
	}

	/// The themes that ship in the app, from the repo checkout: `Themes/*.nnwtheme` and Default.
	@MainActor static func repoBundledThemes() throws -> [(name: String, theme: ArticleTheme)] {
		let directory = try repoURL("Themes")
		let bundles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
			.filter { $0.hasSuffix(ArticleTheme.nnwThemeSuffix) }
			.sorted()
		var result = [(name: String, theme: ArticleTheme)]()
		for bundle in bundles {
			let url = directory.appendingPathComponent(bundle)
			result.append((key(forBundlePath: bundle), try ArticleTheme(url: url, isAppTheme: true)))
		}
		result.append((ArticleThemesManager.defaultThemeName, ArticleTheme.defaultTheme))
		return result
	}

	/// The themes that ship in the app, from `Bundle.main`: what the running app will really load.
	@MainActor static func mainBundleThemes() throws -> [(name: String, theme: ArticleTheme)] {
		let paths = Bundle.main.paths(forResourcesOfType: "nnwtheme", inDirectory: "Themes").sorted()
		var result = [(name: String, theme: ArticleTheme)]()
		for path in paths {
			result.append((key(forBundlePath: path), try ArticleTheme(url: URL(fileURLWithPath: path), isAppTheme: true)))
		}
		result.append((ArticleThemesManager.defaultThemeName, ArticleTheme.defaultTheme))
		return result
	}

	static func mainBundleTable() throws -> ThemeColorBundledTable {
		let url = try #require(Bundle.main.url(forResource: tableFileName, withExtension: "json"),
							   "ThemeColorTable.json is not in the app bundle. \(regenerateAdvice)")
		return try JSONDecoder().decode(ThemeColorBundledTable.self, from: Data(contentsOf: url))
	}

	static let regenerateAdvice = """
		Regenerate it with TEST_RUNNER_REGENERATE_THEME_COLOR_TABLE=1 and the ThemeColorTableGeneratorTests suite \
		(docs/theme-testing.md), and commit the result. Bump ArticleThemeColorProbe.version only if the probe's own logic changed.
		"""
}

// MARK: - Generator

@MainActor @Suite(.serialized) struct ThemeColorTableGeneratorTests {

	/// Measures every bundled theme and rewrites `iOS/Resources/ThemeColorTable.json`.
	/// A theme that fails the sanity check fails the test and nothing is written.
	@Test(.enabled(if: ThemeColorTableSupport.shouldRegenerate,
				   "Set REGENERATE_THEME_COLOR_TABLE=1 to rewrite iOS/Resources/ThemeColorTable.json"))
	func regenerateTable() async throws {
		let environment = ArticleThemeProbeEnvironment.reader()
		var themes = [String: ThemeColorBundledTable.Entry]()
		var failures = [String]()
		for (name, theme) in try ThemeColorTableSupport.repoBundledThemes() {
			guard let measurement = await ArticleThemeColorProbe.measure(theme, environment: environment) else {
				failures.append(name)
				continue
			}
			themes[name] = ThemeColorBundledTable.Entry(key: theme.colorCacheKey, measurement: measurement)
		}
		#expect(failures.isEmpty, "Failed the probe sanity check, so the table was not written: \(failures.joined(separator: ", "))")
		guard failures.isEmpty else {
			return
		}

		let table = ThemeColorBundledTable(probeVersion: ArticleThemeColorProbe.version,
										   coreCSSHash: environment.coreCSSHash,
										   themes: themes)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		var data = try encoder.encode(table)
		data.append(Data("\n".utf8))

		let resources = try ThemeColorTableSupport.repoURL("iOS/Resources")
		let destination = resources.appendingPathComponent("\(ThemeColorTableSupport.tableFileName).json")
		try data.write(to: destination, options: .atomic)
		print("Wrote \(themes.count) themes to \(destination.path)")
	}
}

// MARK: - Guard

@MainActor @Suite(.serialized) struct ThemeColorTableGuardTests {

	@Test func tableIsBundledAndDecodes() throws {
		let table = try ThemeColorTableSupport.mainBundleTable()
		#expect(!table.themes.isEmpty)
	}

	@Test func tableHeaderMatchesTheProbeAndCoreCSS() throws {
		let table = try ThemeColorTableSupport.mainBundleTable()
		#expect(table.probeVersion == ArticleThemeColorProbe.version,
				"Table probeVersion \(table.probeVersion) != ArticleThemeColorProbe.version \(ArticleThemeColorProbe.version). \(ThemeColorTableSupport.regenerateAdvice)")
		#expect(table.coreCSSHash == ArticleThemeProbeEnvironment.bundledCoreCSSHash(),
				"core.css changed since the table was generated. \(ThemeColorTableSupport.regenerateAdvice)")
	}

	@Test func everyBundledThemeHasAMatchingEntry() throws {
		let table = try ThemeColorTableSupport.mainBundleTable()
		let themes = try ThemeColorTableSupport.mainBundleThemes()
		#expect(!themes.isEmpty)

		var missing = [String]()
		var stale = [String]()
		for (name, theme) in themes {
			guard let entry = table.themes[name] else {
				missing.append(name)
				continue
			}
			if entry.key != theme.colorCacheKey {
				stale.append(name)
			}
		}
		let extra = Set(table.themes.keys).subtracting(themes.map(\.name)).sorted()
		#expect(missing.isEmpty, "No table entry for: \(missing.joined(separator: ", ")). \(ThemeColorTableSupport.regenerateAdvice)")
		#expect(stale.isEmpty, "Stylesheet or template changed since the table was generated for: \(stale.joined(separator: ", ")). \(ThemeColorTableSupport.regenerateAdvice)")
		#expect(extra.isEmpty, "Table entries for themes that no longer ship: \(extra.joined(separator: ", ")). \(ThemeColorTableSupport.regenerateAdvice)")
	}

	@Test func everyEntryConvertsToColors() throws {
		let table = try ThemeColorTableSupport.mainBundleTable()
		for (name, entry) in table.themes {
			#expect(ArticleThemeColorStore.themeColors(from: entry.measurement) != nil, "Unparsable color in the table entry for \(name)")
		}
	}

	/// The store's loader reads the same file the guard reads, keyed by cache key. Two table
	/// entries can share a key (the System bundle's stylesheet and template are byte-identical
	/// to the Default theme's), and the loader keeps one measurement per key, so compare
	/// against the distinct keys, not the entry count.
	@Test func storeLoaderReadsTheBundledTable() throws {
		let table = try ThemeColorTableSupport.mainBundleTable()
		let loaded = ThemeColorStoreCore.loadBundledFromMainBundle()
		#expect(loaded.count == Set(table.themes.values.map(\.key)).count)
		for entry in table.themes.values {
			#expect(loaded[entry.key] == entry.measurement)
		}
	}
}
