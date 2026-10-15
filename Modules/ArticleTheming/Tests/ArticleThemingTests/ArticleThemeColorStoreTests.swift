//
//  ArticleThemeColorStoreTests.swift
//  ArticleThemingTests
//
//  Pure store logic that needs neither a web view nor `Bundle.main`: cache key
//  hashing, the dark-block check, lookup order, the persisted file, failure
//  handling and staleness. Tests that need a real `ArticleTheme` live in the
//  app's ArticleThemeColorStoreAppTests.
//

import Testing
import Foundation
import UIKit
import WebKit
@testable import ArticleTheming

struct ArticleThemeColorStoreTests {

	// MARK: Helpers

	private func measurement(page: String) -> ArticleThemeColorMeasurement {
		ArticleThemeColorMeasurement(pageLight: page, pageDark: "#000000", inkLight: "#111111", inkDark: "#EEEEEE",
									 linkLight: "#0000CC", linkDark: "#99CCFF",
									 pageWasPaintedLight: true, pageWasPaintedDark: true, hasDarkModeVariant: true)
	}

	private func tempFile() -> URL {
		FileManager.default.temporaryDirectory.appendingPathComponent("ThemeColors-\(UUID().uuidString).json")
	}

	private func writeEnvelope(_ envelope: ThemeColorCacheEnvelope, to url: URL) throws {
		try JSONEncoder().encode(envelope).write(to: url)
	}

	@MainActor private func environment(coreHash: String) -> ArticleThemeProbeEnvironment {
		ArticleThemeProbeEnvironment(pageHTML: "", styleSubstitutions: [:], lang: "en", coreCSSHash: coreHash,
									 makePagePreferences: { WKWebpagePreferences() })
	}

	private func waitForFile(_ url: URL) async -> Data? {
		for _ in 0..<40 {
			if let data = try? Data(contentsOf: url) {
				return data
			}
			try? await Task.sleep(for: .milliseconds(50))
		}
		return nil
	}

	// MARK: Cache key

	@Test func keyIsStableForSameContent() {
		#expect(ArticleTheme.cacheKey(stylesheet: "a{}", template: "<p>", probeVersion: 1)
				== ArticleTheme.cacheKey(stylesheet: "a{}", template: "<p>", probeVersion: 1))
	}

	@Test func keyChangesWithStylesheetTemplateOrProbeVersion() {
		let base = ArticleTheme.cacheKey(stylesheet: "a{}", template: "<p>", probeVersion: 1)
		#expect(base != ArticleTheme.cacheKey(stylesheet: "a{color:red}", template: "<p>", probeVersion: 1))
		#expect(base != ArticleTheme.cacheKey(stylesheet: "a{}", template: "<div>", probeVersion: 1))
		#expect(base != ArticleTheme.cacheKey(stylesheet: "a{}", template: "<p>", probeVersion: 2))
	}

	@Test func keyLengthPrefixPreventsBoundaryCollisions() {
		#expect(ArticleTheme.cacheKey(stylesheet: "ab", template: "c", probeVersion: 1)
				!= ArticleTheme.cacheKey(stylesheet: "a", template: "bc", probeVersion: 1))
	}

	@Test func missingFilesHashLikeEmptyOnes() {
		#expect(ArticleTheme.cacheKey(stylesheet: nil, template: nil, probeVersion: 1)
				== ArticleTheme.cacheKey(stylesheet: "", template: "", probeVersion: 1))
	}

	// MARK: Dark block

	@Test func declaresDarkBlockSeesARealBlock() {
		#expect(ArticleThemeColorExtractor.declaresDarkBlock("a{} @media (prefers-color-scheme: dark) { a{color:#fff} }"))
	}

	@Test func declaresDarkBlockIgnoresNilCommentsAndSupports() {
		#expect(!ArticleThemeColorExtractor.declaresDarkBlock(nil))
		#expect(!ArticleThemeColorExtractor.declaresDarkBlock("a{color:#000}"))
		#expect(!ArticleThemeColorExtractor.declaresDarkBlock("/* @media (prefers-color-scheme: dark) { a{} } */ a{}"))
		#expect(!ArticleThemeColorExtractor.declaresDarkBlock("@supports (color: red) { @media (prefers-color-scheme: dark) { a{} } }"))
	}

	// MARK: Lookup order

	@Test func lookupPrefersMemoryThenDiskThenBundled() throws {
		let file = tempFile()
		defer { try? FileManager.default.removeItem(at: file) }
		try writeEnvelope(ThemeColorCacheEnvelope(probeVersion: ArticleThemeColorProbe.version, coreCSSHash: "h",
												  entries: ["both": measurement(page: "#D00001"), "disk": measurement(page: "#D00002")]),
						  to: file)
		let bundled = [
			"both": measurement(page: "#B00001"),
			"disk": measurement(page: "#B00002"),
			"bundledOnly": measurement(page: "#B00003")
		]
		let core = ThemeColorStoreCore(fileURL: file, bundledLoader: { bundled })

		#expect(core.measurement(forKey: "both")?.pageLight == "#D00001")
		#expect(core.measurement(forKey: "bundledOnly")?.pageLight == "#B00003")
		#expect(core.measurement(forKey: "absent") == nil)

		core.store(measurement(page: "#A00001"), forKey: "both")
		#expect(core.measurement(forKey: "both")?.pageLight == "#A00001")
	}

	// MARK: Disk

	@Test func corruptFileIsIgnored() throws {
		let file = tempFile()
		defer { try? FileManager.default.removeItem(at: file) }
		try Data("not json {".utf8).write(to: file)
		let core = ThemeColorStoreCore(fileURL: file, bundledLoader: { ["k": self.measurement(page: "#B00001")] })
		#expect(core.measurement(forKey: "k")?.pageLight == "#B00001")
		#expect(!core.isPersistedCacheStale())
	}

	@Test func successIsPersistedAsAnEnvelope() async throws {
		let file = tempFile()
		defer { try? FileManager.default.removeItem(at: file) }
		let core = ThemeColorStoreCore(fileURL: file, bundledLoader: nil)
		core.store(measurement(page: "#123456"), forKey: "k")
		let data = try #require(await waitForFile(file))
		let envelope = try JSONDecoder().decode(ThemeColorCacheEnvelope.self, from: data)
		#expect(envelope.probeVersion == ArticleThemeColorProbe.version)
		#expect(envelope.entries["k"]?.pageLight == "#123456")
	}

	@Test func failureIsNotPersistedAndIsCounted() async throws {
		let file = tempFile()
		defer { try? FileManager.default.removeItem(at: file) }
		let core = ThemeColorStoreCore(fileURL: file, bundledLoader: nil)
		core.recordFailure(forKey: "k")
		core.recordFailure(forKey: "k")
		#expect(core.attempts(forKey: "k") == 2)
		#expect(core.measurement(forKey: "k") == nil)
		try await Task.sleep(for: .milliseconds(200))
		#expect(!FileManager.default.fileExists(atPath: file.path))
	}

	// MARK: Staleness

	@MainActor @Test func versionOrCoreHashMismatchIsStale() throws {
		let file = tempFile()
		defer { try? FileManager.default.removeItem(at: file) }
		try writeEnvelope(ThemeColorCacheEnvelope(probeVersion: ArticleThemeColorProbe.version, coreCSSHash: "old", entries: [:]), to: file)

		let hashChanged = ThemeColorStoreCore(fileURL: file, bundledLoader: nil)
		hashChanged.setEnvironment(environment(coreHash: "new"))
		#expect(hashChanged.isPersistedCacheStale())

		let same = ThemeColorStoreCore(fileURL: file, bundledLoader: nil)
		same.setEnvironment(environment(coreHash: "old"))
		#expect(!same.isPersistedCacheStale())

		try writeEnvelope(ThemeColorCacheEnvelope(probeVersion: ArticleThemeColorProbe.version + 1, coreCSSHash: "old", entries: [:]), to: file)
		let versionChanged = ThemeColorStoreCore(fileURL: file, bundledLoader: nil)
		versionChanged.setEnvironment(environment(coreHash: "old"))
		#expect(versionChanged.isPersistedCacheStale())
	}

	@MainActor @Test func noFileOrNoEnvironmentIsNotStale() {
		let missing = ThemeColorStoreCore(fileURL: tempFile(), bundledLoader: nil)
		missing.setEnvironment(environment(coreHash: "x"))
		#expect(!missing.isPersistedCacheStale())
	}

	@Test func storingIntoAStaleFileKeepsItStale() async throws {
		let file = tempFile()
		defer { try? FileManager.default.removeItem(at: file) }
		try writeEnvelope(ThemeColorCacheEnvelope(probeVersion: 0, coreCSSHash: "old", entries: [:]), to: file)
		let core = ThemeColorStoreCore(fileURL: file, bundledLoader: nil)
		core.store(measurement(page: "#123456"), forKey: "k")
		try await Task.sleep(for: .milliseconds(300))
		let envelope = try JSONDecoder().decode(ThemeColorCacheEnvelope.self, from: Data(contentsOf: file))
		#expect(envelope.probeVersion == 0)
		#expect(envelope.coreCSSHash == "old")
	}

	// MARK: Bundled table and conversion

	@Test func bundledTableIsKeyedByCacheKey() throws {
		let table = ThemeColorBundledTable(probeVersion: 1, coreCSSHash: "h",
										   themes: ["Sepia": .init(key: "abc", measurement: measurement(page: "#F4ECD8"))])
		let map = ThemeColorStoreCore.bundledMeasurements(from: try JSONEncoder().encode(table))
		#expect(map["abc"]?.pageLight == "#F4ECD8")
		#expect(ThemeColorStoreCore.bundledMeasurements(from: Data("junk".utf8)).isEmpty)
	}

	@Test func bundledTableGeneratedAgainstAnotherCoreCSSIsNotTrusted() async {
		let bundled = ["k": measurement(page: "#B00001")]
		let core = ThemeColorStoreCore(fileURL: nil, bundledLoader: { bundled }, bundledCoreCSSHashLoader: { "table-hash" })

		// No environment yet, so the hash cannot be compared and the table is used.
		#expect(core.measurement(forKey: "k")?.pageLight == "#B00001")

		core.setEnvironment(await environment(coreHash: "different-hash"))
		#expect(core.measurement(forKey: "k") == nil)

		core.setEnvironment(await environment(coreHash: "table-hash"))
		#expect(core.measurement(forKey: "k")?.pageLight == "#B00001")
	}

	@Test func bundledCoreCSSHashIsReadFromTheTable() throws {
		let table = ThemeColorBundledTable(probeVersion: 1, coreCSSHash: "h", themes: [:])
		#expect(ThemeColorStoreCore.bundledCoreCSSHash(from: try JSONEncoder().encode(table)) == "h")
		#expect(ThemeColorStoreCore.bundledCoreCSSHash(from: Data("junk".utf8)) == nil)
	}

	@Test func writesLandInTheOrderTheyWereRequested() async throws {
		let file = tempFile()
		defer { try? FileManager.default.removeItem(at: file) }
		let core = ThemeColorStoreCore(fileURL: file, bundledLoader: nil)
		for index in 0..<25 {
			core.store(measurement(page: String(format: "#%06X", index)), forKey: "k\(index)")
		}
		// The last write holds every entry, so none of the earlier snapshots overwrote it.
		var count = 0
		for _ in 0..<60 {
			if let data = try? Data(contentsOf: file), let envelope = try? JSONDecoder().decode(ThemeColorCacheEnvelope.self, from: data) {
				count = envelope.entries.count
				if count == 25 { break }
			}
			try await Task.sleep(nanoseconds: 50_000_000)
		}
		#expect(count == 25)
	}

	@Test func measurementConvertsToThemeColors() throws {
		let colors = try #require(ArticleThemeColorStore.themeColors(from: measurement(page: "#FFFFFF")))
		#expect(colors.hasDarkModeVariant)
		#expect(colors.backgroundColor.cssHexStringForTest == "#FFFFFF")
		var bad = measurement(page: "#FFFFFF")
		bad.inkLight = "nope"
		#expect(ArticleThemeColorStore.themeColors(from: bad) == nil)
	}
}

private extension UIColor {
	var cssHexStringForTest: String {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		getRed(&r, green: &g, blue: &b, alpha: &a)
		return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
	}
}
