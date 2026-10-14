//
//  ArticleThemeColorStoreAppTests.swift
//  NetNewsWire-iOSTests
//
//  The store tests that need a real `ArticleTheme` (and so `Bundle.main`'s
//  `core.css`): cache key from real bundles, the scanner fallback's
//  `hasDarkModeVariant`, and `ensureMeasured` / `remeasureIfStale` with an
//  injected measurer. Pure logic is in the package's ArticleThemeColorStoreTests.
//  Written without being run in Xcode.
//

import Testing
import Foundation
import UIKit
import WebKit
@testable import Nectar
@testable import ArticleTheming

/// `ArticleThemeColorStore` is process-global (`core`, `measurer`). Swift Testing runs suites in
/// parallel and `.serialized` only orders tests inside one suite, so two suites that swap the store
/// (this one and `ArticleThemesManagerGateTests`) overwrote each other's `measurer` and counters.
/// Every test that swaps the shared store holds this lock for its whole body. `release()` is
/// synchronous so it can run from a `defer`.
final class ThemeColorStoreTestLock: @unchecked Sendable {
	static let shared = ThemeColorStoreTestLock()

	private let mutex = NSLock()
	private var isHeld = false
	private var waiters = [CheckedContinuation<Void, Never>]()

	func acquire() async {
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			mutex.lock()
			if isHeld {
				waiters.append(continuation)
				mutex.unlock()
			} else {
				isHeld = true
				mutex.unlock()
				continuation.resume()
			}
		}
	}

	func release() {
		mutex.lock()
		if waiters.isEmpty {
			isHeld = false
			mutex.unlock()
		} else {
			let next = waiters.removeFirst()
			mutex.unlock()
			next.resume()
		}
	}
}

@MainActor @Suite(.serialized) struct ArticleThemeColorStoreAppTests {

	// MARK: Helpers

	private static func fixtureURL(_ name: String) throws -> URL {
		var url = URL(fileURLWithPath: #filePath)
		while url.pathComponents.count > 1 {
			url.deleteLastPathComponent()
			let candidate = url.appendingPathComponent("Tests/NetNewsWire-iOSTests/Fixtures/ThemeColorProbe/\(name).nnwtheme")
			if FileManager.default.fileExists(atPath: candidate.path) {
				return candidate
			}
		}
		throw CocoaError(.fileNoSuchFile)
	}

	private static func theme(_ name: String) throws -> ArticleTheme {
		try ArticleTheme(url: try fixtureURL(name), isAppTheme: false)
	}

	private static func measurement(page: String) -> ArticleThemeColorMeasurement {
		ArticleThemeColorMeasurement(pageLight: page, pageDark: "#000000", inkLight: "#111111", inkDark: "#EEEEEE",
									 linkLight: "#0000CC", linkDark: "#99CCFF",
									 pageWasPaintedLight: true, pageWasPaintedDark: true, hasDarkModeVariant: true)
	}

	private final class Counter: @unchecked Sendable {
		var value = 0
	}

	/// Resets the shared store to a temp file, runs `body`, then restores the real measurer.
	private static func withIsolatedStore(file: URL? = nil, _ body: () async throws -> Void) async rethrows {
		await ThemeColorStoreTestLock.shared.acquire()
		defer { ThemeColorStoreTestLock.shared.release() }
		let original = ArticleThemeColorStore.measurer
		let url = file ?? FileManager.default.temporaryDirectory.appendingPathComponent("ThemeColors-\(UUID().uuidString).json")
		ArticleThemeColorStore.core.resetForTesting(fileURL: url, bundledLoader: nil)
		defer {
			ArticleThemeColorStore.measurer = original
			ArticleThemeColorStore.core.resetForTesting(fileURL: nil, bundledLoader: nil)
			try? FileManager.default.removeItem(at: url)
		}
		try await body()
	}

	// MARK: Cache key and own stylesheet

	@Test func keyTracksContentNotIdentityOrCore() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent("probe-key-\(UUID().uuidString).nnwtheme")
		defer { try? FileManager.default.removeItem(at: directory) }
		try FileManager.default.copyItem(at: try Self.fixtureURL("LightOnly"), to: directory)
		let original = try ArticleTheme(url: directory, isAppTheme: false)

		// Bumping Version in Info.plist does not change the key.
		let plistURL = directory.appendingPathComponent("Info.plist")
		let plist = try String(contentsOf: plistURL, encoding: .utf8).replacingOccurrences(of: "<integer>1</integer>", with: "<integer>2</integer>")
		try plist.write(to: plistURL, atomically: true, encoding: .utf8)
		#expect(try ArticleTheme(url: directory, isAppTheme: false).colorCacheKey == original.colorCacheKey)

		// Changing the stylesheet does.
		let cssURL = directory.appendingPathComponent("stylesheet.css")
		try (try String(contentsOf: cssURL, encoding: .utf8) + "\na { color: red; }\n").write(to: cssURL, atomically: true, encoding: .utf8)
		#expect(try ArticleTheme(url: directory, isAppTheme: false).colorCacheKey != original.colorCacheKey)
	}

	@Test func ownStylesheetExcludesCoreCSS() throws {
		let theme = try Self.theme("LightOnly")
		let own = try #require(theme.ownStylesheet)
		#expect(own.contains("#f5f5f5"))
		#expect(!own.contains("scrollbar-gutter"))
		#expect(try #require(theme.css).contains("scrollbar-gutter"))
	}

	// MARK: Scanner fallback (D13)

	@Test func scannerFallbackReadsDarkVariantFromTheOwnStylesheet() async throws {
		await Self.withIsolatedStore {
			// core.css has a dark block, so the composed CSS always did; the theme's own CSS decides now.
			#expect(ArticleThemeColorStore.colors(for: try! Self.theme("LightOnly")).hasDarkModeVariant == false)
			#expect(ArticleThemeColorStore.colors(for: try! Self.theme("StarterStyle")).hasDarkModeVariant == true)
		}
	}

	// MARK: The seam (WP5)

	private static func hex(_ color: UIColor) -> String {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		color.getRed(&r, green: &g, blue: &b, alpha: &a)
		return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
	}

	@Test func resolvedColorsMatchTheScannerWhileTheStoreIsEmpty() async throws {
		let theme = try Self.theme("StarterStyle")
		await Self.withIsolatedStore {
			let scanner = ArticleThemeColorExtractor.colors(for: theme)
			let light = ArticleResolvedColors.resolved(theme: theme, isDark: false, overrideBackgroundColorHex: nil, overrideBackgroundColorDarkHex: nil)
			let dark = ArticleResolvedColors.resolved(theme: theme, isDark: true, overrideBackgroundColorHex: nil, overrideBackgroundColorDarkHex: nil)
			#expect(Self.hex(light.background) == Self.hex(scanner.backgroundColor))
			#expect(Self.hex(light.text) == Self.hex(scanner.textColor))
			#expect(Self.hex(dark.background) == Self.hex(scanner.backgroundColorDark))
			#expect(Self.hex(dark.text) == Self.hex(scanner.textColorDark))
		}
	}

	@Test func resolvedColorsReadTheStoreAndOverridesStillWin() async throws {
		let theme = try Self.theme("LightOnly")
		await Self.withIsolatedStore {
			ArticleThemeColorStore.measurer = { _ in Self.measurement(page: "#ABCDEF") }
			await ArticleThemeColorStore.ensureMeasured(theme)

			let light = ArticleResolvedColors.resolved(theme: theme, isDark: false, overrideBackgroundColorHex: nil, overrideBackgroundColorDarkHex: nil)
			#expect(Self.hex(light.background) == "#ABCDEF")
			#expect(Self.hex(light.text) == "#111111")

			let dark = ArticleResolvedColors.resolved(theme: theme, isDark: true, overrideBackgroundColorHex: nil, overrideBackgroundColorDarkHex: nil)
			#expect(Self.hex(dark.background) == "#000000")
			#expect(Self.hex(dark.text) == "#EEEEEE")

			let overridden = ArticleResolvedColors.resolved(theme: theme, isDark: false, overrideBackgroundColorHex: "#102030", overrideBackgroundColorDarkHex: nil)
			#expect(Self.hex(overridden.background) == "#102030")
			#expect(Self.hex(overridden.text) == "#111111")
		}
	}

	// MARK: ensureMeasured

	@Test func measuredThemeUsesMeasuredColorsAndIsRemembered() async throws {
		let theme = try Self.theme("LightOnly")
		await Self.withIsolatedStore {
			#expect(!ArticleThemeColorStore.hasMeasurement(for: theme))
			ArticleThemeColorStore.measurer = { _ in Self.measurement(page: "#ABCDEF") }
			await ArticleThemeColorStore.ensureMeasured(theme)
			#expect(ArticleThemeColorStore.hasMeasurement(for: theme))
			let colors = ArticleThemeColorStore.colors(for: theme)
			var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
			colors.backgroundColor.getRed(&r, green: &g, blue: &b, alpha: &a)
			#expect(Int((r * 255).rounded()) == 0xAB)
			#expect(colors.hasDarkModeVariant)
		}
	}

	@Test func measuredThemeIsNotMeasuredAgain() async throws {
		let theme = try Self.theme("LightOnly")
		let calls = Counter()
		await Self.withIsolatedStore {
			ArticleThemeColorStore.measurer = { _ in calls.value += 1; return Self.measurement(page: "#ABCDEF") }
			await ArticleThemeColorStore.ensureMeasured(theme)
			await ArticleThemeColorStore.ensureMeasured(theme)
			#expect(calls.value == 1)
		}
	}

	@Test func failureIsRetriedAtMostOncePerLaunchAndNeverStored() async throws {
		let theme = try Self.theme("LightOnly")
		let calls = Counter()
		await Self.withIsolatedStore {
			ArticleThemeColorStore.measurer = { _ in calls.value += 1; return nil }
			for _ in 0..<4 {
				await ArticleThemeColorStore.ensureMeasured(theme)
			}
			#expect(calls.value == ArticleThemeColorStore.maximumAttempts)
			#expect(!ArticleThemeColorStore.hasMeasurement(for: theme))
		}
	}

	@Test func concurrentCallersShareOneMeasurement() async throws {
		let theme = try Self.theme("LightOnly")
		let calls = Counter()
		await Self.withIsolatedStore {
			ArticleThemeColorStore.measurer = { _ in
				calls.value += 1
				try? await Task.sleep(for: .milliseconds(150))
				return Self.measurement(page: "#ABCDEF")
			}
			async let first: Void = ArticleThemeColorStore.ensureMeasured(theme)
			async let second: Void = ArticleThemeColorStore.ensureMeasured(theme)
			_ = await (first, second)
			#expect(calls.value == 1)
			#expect(ArticleThemeColorStore.hasMeasurement(for: theme))
		}
	}

	// MARK: remeasureIfStale (D9)

	@Test func staleCacheIsRemeasuredReplacedAndReported() async throws {
		let theme = try Self.theme("LightOnly")
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("ThemeColors-\(UUID().uuidString).json")
		let stale = ThemeColorCacheEnvelope(probeVersion: ArticleThemeColorProbe.version, coreCSSHash: "old",
											entries: [theme.colorCacheKey: Self.measurement(page: "#111111"), "gone": Self.measurement(page: "#222222")])
		try JSONEncoder().encode(stale).write(to: file)
		await Self.withIsolatedStore(file: file) {
			ArticleThemeColorStore.configure(ArticleThemeProbeEnvironment(
				pageHTML: "", styleSubstitutions: [:], lang: "en", coreCSSHash: "new",
				makePagePreferences: { WKWebpagePreferences() }))
			// Entries stay in use until the re-measure finishes.
			#expect(ArticleThemeColorStore.core.measurement(forKey: theme.colorCacheKey)?.pageLight == "#111111")
			ArticleThemeColorStore.measurer = { _ in Self.measurement(page: "#333333") }
			let changed = await ArticleThemeColorStore.remeasureIfStale([theme])
			#expect(changed == [theme.colorCacheKey])
			#expect(ArticleThemeColorStore.core.measurement(forKey: theme.colorCacheKey)?.pageLight == "#333333")
			#expect(ArticleThemeColorStore.core.measurement(forKey: "gone") == nil)
			#expect(!ArticleThemeColorStore.core.isPersistedCacheStale())
		}
	}

	@Test func freshCacheIsNotRemeasured() async throws {
		let theme = try Self.theme("LightOnly")
		let calls = Counter()
		await Self.withIsolatedStore {
			ArticleThemeColorStore.configure(ArticleThemeProbeEnvironment(
				pageHTML: "", styleSubstitutions: [:], lang: "en", coreCSSHash: "same",
				makePagePreferences: { WKWebpagePreferences() }))
			ArticleThemeColorStore.measurer = { _ in calls.value += 1; return Self.measurement(page: "#333333") }
			#expect(await ArticleThemeColorStore.remeasureIfStale([theme]).isEmpty)
			#expect(calls.value == 0)
		}
	}
}
