//
//  ArticleThemeColorProbeTests.swift
//  NetNewsWire-iOSTests
//
//  Acceptance tests for `ArticleThemeColorProbe` (WP3 of the theme color probe
//  plan). These render real themes in a simulator `WKWebView` through the
//  reader's `page.html` and the bundled `core.css`, so they live here rather
//  than in the package's own test target. Pure logic (compositing, sanity,
//  decoding) is in the package's `ArticleThemeColorProbeLogicTests`.
//
//  Written without being run in Xcode: the expectations below that depend on
//  WebKit behavior (computed `color` under `color-scheme: light dark`, the
//  hidden window flipping `prefers-color-scheme`) are the runtime facts the
//  plan's acceptance tests exist to settle.
//

import Testing
import Foundation
import UIKit
import WebKit
@testable import Nectar
@testable import ArticleTheming

/// Probe results by `ArticleTheme.colorCacheKey`, shared by the suites in this target so a theme
/// is loaded once per test process. `nil` (a rejected or failed measurement) is cached too.
/// Only for tests that call `measure(_:environment:)` with the reader environment.
@MainActor enum ThemeProbeMeasurementCache {
	private static var results = [String: ArticleThemeColorMeasurement?]()

	static func measure(_ theme: ArticleTheme) async -> ArticleThemeColorMeasurement? {
		if let hit = results[theme.colorCacheKey] {
			return hit
		}
		let measurement = await ArticleThemeColorProbe.measure(theme, environment: ArticleThemeProbeEnvironment.reader())
		results[theme.colorCacheKey] = .some(measurement)
		return measurement
	}
}

@MainActor @Suite(.serialized) struct ArticleThemeColorProbeTests {

	// MARK: Helpers

	private static func environment() -> ArticleThemeProbeEnvironment {
		ArticleThemeProbeEnvironment.reader()
	}

	private static func repoURL(_ relativePath: String) throws -> URL {
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

	private static func fixtureTheme(_ name: String) throws -> ArticleTheme {
		let directory = try repoURL("Tests/NetNewsWire-iOSTests/Fixtures/ThemeColorProbe")
		return try ArticleTheme(url: directory.appendingPathComponent("\(name).nnwtheme"), isAppTheme: false)
	}

	private static func bundles(in folder: String) throws -> [URL] {
		let directory = try repoURL(folder)
		return try FileManager.default.contentsOfDirectory(atPath: directory.path)
			.filter { $0.hasSuffix(".nnwtheme") }
			.sorted()
			.map { directory.appendingPathComponent($0) }
	}

	private static func measure(_ name: String) async throws -> ArticleThemeColorMeasurement? {
		await ArticleThemeColorProbe.measure(try fixtureTheme(name), environment: environment())
	}

	private static func expected(_ pageLight: String, _ inkLight: String, _ linkLight: String,
								 dark pageDark: String, _ inkDark: String, _ linkDark: String,
								 paintedLight: Bool = true, paintedDark: Bool = true,
								 darkVariant: Bool) -> ArticleThemeColorMeasurement {
		ArticleThemeColorMeasurement(pageLight: pageLight, pageDark: pageDark,
									 inkLight: inkLight, inkDark: inkDark,
									 linkLight: linkLight, linkDark: linkDark,
									 pageWasPaintedLight: paintedLight, pageWasPaintedDark: paintedDark,
									 hasDarkModeVariant: darkVariant)
	}

	private static func bytes(_ hex: String) -> (r: Int, g: Int, b: Int) {
		let value = Int(hex.dropFirst(), radix: 16) ?? 0
		return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
	}

	private static func bytes(_ color: UIColor) -> (r: Int, g: Int, b: Int) {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		color.getRed(&r, green: &g, blue: &b, alpha: &a)
		return (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
	}

	private static func luminance(_ hex: String) -> Double {
		let c = bytes(hex)
		return ThemeColorProbeLogic.relativeLuminance(.init(r: c.r, g: c.g, b: c.b))
	}

	// MARK: 1. Dark-flag assertion

	@Test func lightAndDarkPassesReportTheRequestedAppearance() async throws {
		let environment = Self.environment()
		let html = try ArticleThemeColorProbe.composeHTML(for: try Self.fixtureTheme("StarterStyle"), environment: environment)
		let light = await ArticleThemeColorProbe.runPass(html: html, dark: false, environment: environment)
		let dark = await ArticleThemeColorProbe.runPass(html: html, dark: true, environment: environment)
		#expect(light?.dark == false, "Light pass must report matchMedia dark == false")
		#expect(dark?.dark == true, """
			Dark pass must report matchMedia dark == true. If this fails with the hidden window, \
			change ArticleThemeColorProbe.useVisibleHostFallback to true (plan WP3 test 1); do not switch to evaluateJavaScript.
			""")
	}

	@Test func probePageHasNoColorSchemeMetaOrCSP() throws {
		let html = try ArticleThemeColorProbe.composeHTML(for: try Self.fixtureTheme("StarterStyle"), environment: Self.environment())
		#expect(!html.contains("name=\"color-scheme\""))
		#expect(!html.contains("Content-Security-Policy"))
	}

	// MARK: 2. Fixture matrix

	@Test func starterStyleReadsColorsDeclaredOnHtml() async throws {
		let m = try await Self.measure("StarterStyle")
		#expect(m == Self.expected("#FDF6E3", "#333333", "#0645AD", dark: "#1B1B1B", "#DDDDDD", "#8AB4F8", darkVariant: true))
	}

	@Test func shorthandBackgroundIsSeen() async throws {
		let m = try await Self.measure("ShorthandBackground")
		#expect(m == Self.expected("#EEEEEE", "#222222", "#0000CC", dark: "#202020", "#E8E8E8", "#99BBFF", darkVariant: true))
	}

	@Test func spaceSeparatedRGBAIsNormalized() async throws {
		let m = try await Self.measure("SpaceSeparatedRGBA")
		#expect(m == Self.expected("#FAF5EB", "#1E1E1E", "#0000C8", dark: "#141820", "#E6E6E6", "#8CB4FF", darkVariant: true))
	}

	@Test func oklchIsGamutMappedToSRGB() async throws {
		let m = try #require(try await Self.measure("OKLCH"))
		#expect(Self.luminance(m.pageLight) > 0.85)
		#expect(Self.luminance(m.inkLight) < 0.05)
		#expect(Self.luminance(m.pageDark) < 0.03)
		#expect(Self.luminance(m.inkDark) > 0.6)
		#expect(m.pageWasPaintedLight && m.pageWasPaintedDark)
		#expect(m.hasDarkModeVariant)
	}

	@Test func lightDarkFunctionResolvesPerAppearance() async throws {
		let m = try await Self.measure("LightDark")
		#expect(m == Self.expected("#FFFFF0", "#202020", "#0050A0", dark: "#101820", "#E0E0E0", "#80C0FF", darkVariant: true))
	}

	@Test func colorSchemeOnlyThemeIsUnpaintedButInkFollowsAppearance() async throws {
		let m = try #require(try await Self.measure("ColorSchemeOnly"))
		#expect(m.pageWasPaintedLight == false)
		#expect(m.pageWasPaintedDark == false)
		#expect(m.pageLight == "#FFFFFF")
		#expect(m.pageDark == "#000000")
		#expect(m.inkLight == "#000000")
		#expect(m.inkDark == "#FFFFFF")
		#expect(m.hasDarkModeVariant)
	}

	@Test func darkOnlyThemeIsTheSameInBothAppearances() async throws {
		let m = try await Self.measure("DarkOnly")
		#expect(m == Self.expected("#101010", "#EEEEEE", "#99CCFF", dark: "#101010", "#EEEEEE", "#99CCFF", darkVariant: false))
	}

	@Test func lightOnlyThemeIsTheSameInBothAppearances() async throws {
		let m = try await Self.measure("LightOnly")
		#expect(m == Self.expected("#F5F5F5", "#111111", "#0033CC", dark: "#F5F5F5", "#111111", "#0033CC", darkVariant: false))
	}

	@Test func gradientPageIsNotSampledAndFallsBackToLegacyPage() async throws {
		let m = try await Self.measure("GradientPage")
		#expect(m == Self.expected("#FFFFFF", "#111111", "#0000CC", dark: "#000000", "#EEEEEE", "#99CCFF",
								   paintedLight: false, paintedDark: false, darkVariant: true))
	}

	@Test func themeScriptDoesNotRun() async throws {
		let m = try #require(try await Self.measure("ScriptRecolors"))
		#expect(m.pageLight == "#FFFFFF", "Inline script recolored the page; content JavaScript must stay off")
		#expect(m.inkLight == "#111111")
		#expect(m.pageDark == "#101010")
	}

	// MARK: 3. Agreement with the legacy scanner

	@Test(.timeLimit(.minutes(5))) func probeAgreesWithScannerWhereScannerFoundAValue() async throws {
		var mismatches = [String]()
		var breaker = ConsecutiveNilBreaker()
		for url in try Self.bundles(in: "Themes") {
			let theme = try ArticleTheme(url: url, isAppTheme: false)
			let measured = await ThemeProbeMeasurementCache.measure(theme)
			breaker.record(isNil: measured == nil)
			guard let m = measured else {
				mismatches.append("\(theme.name): probe returned nil")
				if breaker.isTripped {
					mismatches.append("aborted after \(breaker.limit) consecutive nil results")
					break
				}
				continue
			}
			let scanner = ArticleThemeColorExtractor.colors(for: theme)
			// ThemeColors does not say whether a value was found, so a value equal to the
			// scanner's own fallback (white/black page, black/white ink) is skipped.
			func check(_ label: String, _ scanned: UIColor, fallback: UIColor, _ measured: String) {
				let s = Self.bytes(scanned)
				guard s != Self.bytes(fallback) else {
					return
				}
				let p = Self.bytes(measured)
				if abs(s.r - p.r) > 1 || abs(s.g - p.g) > 1 || abs(s.b - p.b) > 1 {
					mismatches.append("\(theme.name) \(label): scanner \(s) probe \(measured)")
				}
			}
			check("pageLight", scanner.backgroundColor, fallback: .white, m.pageLight)
			check("pageDark", scanner.backgroundColorDark, fallback: .black, m.pageDark)
			check("inkLight", scanner.textColor, fallback: .black, m.inkLight)
			check("inkDark", scanner.textColorDark, fallback: .white, m.inkDark)
		}
		#expect(mismatches.isEmpty, "Probe and scanner disagree: \(mismatches.joined(separator: "; "))")
	}

	// MARK: 4. Sanity floor
	// The all-themes sanity check is `ArticleThemeSmokeTests` (heavy, skipped by default in CI).

	@Test func inkEqualToPageIsRejected() async throws {
		#expect(try await Self.measure("InkEqualsPage") == nil)
	}
}
