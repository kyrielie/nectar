//
//  ArticleThemeColorStore.swift
//  ArticleTheming
//
//  Where measured theme colors live. `colors(for:)` is synchronous and never
//  blocks: session memory, then the persisted cache, then the bundled table,
//  then the legacy scanner. Measuring (`ensureMeasured`) is separate, async,
//  and coalesced per theme. See docs/article-color-pipeline.md.
//

import UIKit
import os
import HexColor
import RSCore

// MARK: - Public store

public enum ArticleThemeColorStore {

	/// Shared state. Immutable reference; all mutation happens under the core's lock.
	static let core = ThemeColorStoreCore()

	/// Test hook: how a theme gets measured. Defaults to the probe with the configured environment.
	@MainActor static var measurer: (ArticleTheme) async -> ArticleThemeColorMeasurement? = { theme in
		guard let environment = ArticleThemeColorStore.core.environment else {
			return nil
		}
		return await ArticleThemeColorProbe.measure(theme, environment: environment)
	}

	/// Maximum measurement attempts per theme per launch (one retry, D7).
	static let maximumAttempts = 2

	@MainActor private static var inFlight = [String: Task<Void, Never>]()

	public static func configure(_ environment: ArticleThemeProbeEnvironment) {
		core.setEnvironment(environment)
	}

	/// Never blocks. A measured theme gets its measured colors; any other theme gets the
	/// legacy scanner's, with `hasDarkModeVariant` taken from the theme's own stylesheet.
	public static func colors(for theme: ArticleTheme) -> ArticleThemeColorExtractor.ThemeColors {
		if ArticleThemeColorProbe.isEnabled,
		   let measurement = core.measurement(forKey: theme.colorCacheKey),
		   let colors = themeColors(from: measurement) {
			return colors
		}
		var colors = ArticleThemeColorExtractor.colors(for: theme)
		colors.hasDarkModeVariant = ArticleThemeColorExtractor.declaresDarkBlock(theme.ownStylesheet)
		return colors
	}

	public static func hasMeasurement(for theme: ArticleTheme) -> Bool {
		guard ArticleThemeColorProbe.isEnabled else {
			return false
		}
		return core.measurement(forKey: theme.colorCacheKey) != nil
	}

	/// Measures `theme` unless it already has a measurement or has used up its attempts.
	/// Concurrent callers for the same theme share one measurement. Successes are persisted;
	/// failures are remembered for the session only.
	@MainActor public static func ensureMeasured(_ theme: ArticleTheme) async {
		guard ArticleThemeColorProbe.isEnabled else {
			return
		}
		let key = theme.colorCacheKey
		if core.measurement(forKey: key) != nil {
			return
		}
		if let running = inFlight[key] {
			await running.value
			return
		}
		guard core.attempts(forKey: key) < maximumAttempts else {
			return
		}
		let task = Task { @MainActor in
			if let measurement = await measurer(theme) {
				core.store(measurement, forKey: key)
			} else {
				core.recordFailure(forKey: key)
			}
		}
		inFlight[key] = task
		await task.value
		inFlight[key] = nil
	}

	/// D9: when the persisted cache was written under a different probe version or `core.css`,
	/// re-measure the given installed themes one at a time and replace the cache with the
	/// results. Entries stay in use meanwhile (no flash). Returns the keys whose values changed,
	/// so the caller can repost the current-theme notification.
	@MainActor @discardableResult
	public static func remeasureIfStale(_ themes: [ArticleTheme]) async -> Set<String> {
		guard core.isPersistedCacheStale() else {
			return []
		}
		let task = Task(priority: .utility) { @MainActor () -> Set<String> in
			var fresh = [String: ArticleThemeColorMeasurement]()
			var changed = Set<String>()
			for theme in themes {
				let key = theme.colorCacheKey
				let previous = core.measurement(forKey: key)
				if let measurement = await measurer(theme) {
					fresh[key] = measurement
					if previous != measurement {
						changed.insert(key)
					}
				} else if let previous {
					fresh[key] = previous
				}
				await Task.yield()
			}
			core.replacePersistedEntries(with: fresh)
			return changed
		}
		return await task.value
	}

	// MARK: Conversion

	static func themeColors(from m: ArticleThemeColorMeasurement) -> ArticleThemeColorExtractor.ThemeColors? {
		guard let pageLight = UIColor(cssHex: m.pageLight), let pageDark = UIColor(cssHex: m.pageDark),
			  let inkLight = UIColor(cssHex: m.inkLight), let inkDark = UIColor(cssHex: m.inkDark),
			  let linkLight = UIColor(cssHex: m.linkLight), let linkDark = UIColor(cssHex: m.linkDark) else {
			return nil
		}
		return ArticleThemeColorExtractor.ThemeColors(
			textColor: inkLight, textColorDark: inkDark,
			backgroundColor: pageLight, backgroundColorDark: pageDark,
			linkColor: linkLight, linkColorDark: linkDark,
			hasDarkModeVariant: m.hasDarkModeVariant)
	}
}

// MARK: - Core (state, disk, bundled table)

/// The persisted file's shape.
struct ThemeColorCacheEnvelope: Codable, Equatable, Sendable {
	var probeVersion: Int
	var coreCSSHash: String
	var entries: [String: ArticleThemeColorMeasurement]
}

/// The bundled table's shape (`iOS/Resources/ThemeColorTable.json`, generated in WP7).
struct ThemeColorBundledTable: Codable, Equatable, Sendable {
	struct Entry: Codable, Equatable, Sendable {
		var key: String
		var measurement: ArticleThemeColorMeasurement
	}
	var probeVersion: Int
	var coreCSSHash: String
	var themes: [String: Entry]
}

final class ThemeColorStoreCore: Sendable {

	private struct State {
		var fileURL: URL?
		var environment: ArticleThemeProbeEnvironment?
		var memory = [String: ArticleThemeColorMeasurement]()
		var disk = [String: ArticleThemeColorMeasurement]()
		var diskLoaded = false
		var persistedProbeVersion: Int?
		var persistedCoreCSSHash: String?
		var bundled: [String: ArticleThemeColorMeasurement]?
		var bundledLoader: (@Sendable () -> [String: ArticleThemeColorMeasurement])?
		var attempts = [String: Int]()
	}

	private let state: OSAllocatedUnfairLock<State>

	init(fileURL: URL? = ThemeColorStoreCore.defaultFileURL(),
		 bundledLoader: (@Sendable () -> [String: ArticleThemeColorMeasurement])? = ThemeColorStoreCore.loadBundledFromMainBundle) {
		var initial = State()
		initial.fileURL = fileURL
		initial.bundledLoader = bundledLoader
		state = OSAllocatedUnfairLock(initialState: initial)
	}

	// MARK: Defaults

	static func defaultFileURL() -> URL? {
		guard let folder = Platform.dataSubfolder(forApplication: nil, folderName: "ThemeColorCache") else {
			return nil
		}
		return URL(fileURLWithPath: folder).appendingPathComponent("ThemeColors.json")
	}

	/// Reads `ThemeColorTable.json` from the main bundle, keyed by cache key. Empty if absent or unreadable.
	@Sendable static func loadBundledFromMainBundle() -> [String: ArticleThemeColorMeasurement] {
		guard let url = Bundle.main.url(forResource: "ThemeColorTable", withExtension: "json"),
			  let data = try? Data(contentsOf: url) else {
			return [:]
		}
		return bundledMeasurements(from: data)
	}

	static func bundledMeasurements(from data: Data) -> [String: ArticleThemeColorMeasurement] {
		guard let table = try? JSONDecoder().decode(ThemeColorBundledTable.self, from: data) else {
			return [:]
		}
		var result = [String: ArticleThemeColorMeasurement]()
		for entry in table.themes.values {
			result[entry.key] = entry.measurement
		}
		return result
	}

	// MARK: Configuration

	var environment: ArticleThemeProbeEnvironment? {
		state.withLock { $0.environment }
	}

	func setEnvironment(_ environment: ArticleThemeProbeEnvironment) {
		state.withLock { $0.environment = environment }
	}

	/// Resets everything and points the core at a new file and bundled loader. For tests.
	func resetForTesting(fileURL: URL?, bundledLoader: (@Sendable () -> [String: ArticleThemeColorMeasurement])?) {
		state.withLock {
			$0 = State()
			$0.fileURL = fileURL
			$0.bundledLoader = bundledLoader
		}
	}

	// MARK: Lookup (memory, disk, bundled)

	func measurement(forKey key: String) -> ArticleThemeColorMeasurement? {
		state.withLock { s in
			if let hit = s.memory[key] {
				return hit
			}
			Self.loadDiskIfNeeded(&s)
			if let hit = s.disk[key] {
				return hit
			}
			if s.bundled == nil {
				s.bundled = s.bundledLoader?() ?? [:]
			}
			return s.bundled?[key]
		}
	}

	// MARK: Writes

	/// Remembers a success in memory and persists it. The disk write runs on a detached
	/// utility task and captures only `Sendable` values.
	func store(_ measurement: ArticleThemeColorMeasurement, forKey key: String) {
		let pending: (URL, Data)? = state.withLock { s in
			Self.loadDiskIfNeeded(&s)
			s.memory[key] = measurement
			s.disk[key] = measurement
			s.attempts[key] = nil
			return Self.encodedEnvelope(&s)
		}
		Self.write(pending)
	}

	func recordFailure(forKey key: String) {
		state.withLock { $0.attempts[key, default: 0] += 1 }
	}

	func attempts(forKey key: String) -> Int {
		state.withLock { $0.attempts[key] ?? 0 }
	}

	// MARK: Staleness (D9)

	/// True when a persisted file exists and was written under a different probe version
	/// or `core.css` than the current ones. No file, or no configured environment: not stale.
	func isPersistedCacheStale() -> Bool {
		state.withLock { s in
			Self.loadDiskIfNeeded(&s)
			guard let version = s.persistedProbeVersion, let hash = s.persistedCoreCSSHash,
				  let environment = s.environment else {
				return false
			}
			return version != ArticleThemeColorProbe.version || hash != environment.coreCSSHash
		}
	}

	/// Replaces the persisted entries (and session memory for those keys) and stamps the
	/// file with the current probe version and `core.css` hash.
	func replacePersistedEntries(with entries: [String: ArticleThemeColorMeasurement]) {
		let pending: (URL, Data)? = state.withLock { s in
			Self.loadDiskIfNeeded(&s)
			s.disk = entries
			s.memory.merge(entries) { _, new in new }
			s.persistedProbeVersion = ArticleThemeColorProbe.version
			s.persistedCoreCSSHash = s.environment?.coreCSSHash ?? ""
			return Self.encodedEnvelope(&s)
		}
		Self.write(pending)
	}

	// MARK: Disk

	private static func loadDiskIfNeeded(_ s: inout State) {
		guard !s.diskLoaded else {
			return
		}
		s.diskLoaded = true
		guard let url = s.fileURL, let data = try? Data(contentsOf: url) else {
			return
		}
		// A corrupt file is discarded silently.
		guard let envelope = try? JSONDecoder().decode(ThemeColorCacheEnvelope.self, from: data) else {
			return
		}
		s.disk = envelope.entries
		s.persistedProbeVersion = envelope.probeVersion
		s.persistedCoreCSSHash = envelope.coreCSSHash
	}

	/// Encodes the file as it will be written. A file that already exists keeps its own
	/// probe version and `core.css` hash (so a stale file stays stale until it is re-measured);
	/// a new file is stamped with the current ones.
	private static func encodedEnvelope(_ s: inout State) -> (URL, Data)? {
		guard let url = s.fileURL else {
			return nil
		}
		if s.persistedProbeVersion == nil || s.persistedCoreCSSHash == nil {
			s.persistedProbeVersion = ArticleThemeColorProbe.version
			s.persistedCoreCSSHash = s.environment?.coreCSSHash ?? ""
		}
		let envelope = ThemeColorCacheEnvelope(probeVersion: s.persistedProbeVersion ?? ArticleThemeColorProbe.version,
											   coreCSSHash: s.persistedCoreCSSHash ?? "",
											   entries: s.disk)
		guard let data = try? JSONEncoder().encode(envelope) else {
			return nil
		}
		return (url, data)
	}

	private static func write(_ pending: (URL, Data)?) {
		guard let (url, data) = pending else {
			return
		}
		Task.detached(priority: .utility) {
			try? data.write(to: url, options: .atomic)
		}
	}
}
