//
//  ArticleThemesManager.sqift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/26/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import UIKit
import os
import RSCore

public extension Notification.Name {
	static let ArticleThemeNamesDidChangeNotification = Notification.Name("ArticleThemeNamesDidChangeNotification")
	static let CurrentArticleThemeDidChangeNotification = Notification.Name("CurrentArticleThemeDidChangeNotification")
}

/// The persisted-state seam `ArticleThemesManager` needs from the app target.
/// `AppDefaults` (app-target-only -- see Modularization Stage 0b) conforms to
/// this; nothing else about AppDefaults is exposed to this package.
public protocol ArticleThemeNameStoring: AnyObject {
	var currentThemeName: String? { get set }
}

/// Fallback storage so an accidental early touch of `ArticleThemesManager`
/// (e.g. from this package's own tests, before the app target has injected
/// its real storage) doesn't crash. The real app always overwrites
/// `ArticleThemesManager.nameStorage` with `AppDefaults.shared` before
/// `start()` is called -- see `AppDelegate.swift`.
private final class InMemoryThemeNameStorage: ArticleThemeNameStoring, @unchecked Sendable {
	var currentThemeName: String?
}

public final class ArticleThemesManager: NSObject, NSFilePresenter, Sendable {
	public static let shared = ArticleThemesManager()

	/// Set once, before `start()` is called -- see `AppDelegate.swift`. Defaults
	/// to an in-memory fallback; the real app always overwrites this with
	/// `AppDefaults.shared` before `start()`.
	nonisolated(unsafe) public static var nameStorage: ArticleThemeNameStoring = InMemoryThemeNameStorage()

	public static let defaultThemeName = "Default"

	public let folderPath: String

	public let presentedItemOperationQueue = OperationQueue.main // NSFilePresenter
	public let presentedItemURL: URL? // NSFilePresenter

	public var currentThemeName: String {
		get {
			Self.nameStorage.currentThemeName ?? Self.defaultThemeName
		}
		set {
			if newValue != currentThemeName {
				Self.nameStorage.currentThemeName = newValue
				updateThemeNames()
				updateCurrentTheme()
			}
		}
	}

	public var currentTheme: ArticleTheme {
		get {
			state.withLock { $0.currentTheme }
		}
		set {
			state.withLock { $0.currentTheme = newValue }
			NotificationCenter.default.postOnMainThread(name: .CurrentArticleThemeDidChangeNotification, object: self)
		}
	}

	public var themeNames: [String] {
		get {
			state.withLock { $0.themeNames }
		}
		set {
			state.withLock { $0.themeNames = newValue }
			NotificationCenter.default.postOnMainThread(name: .ArticleThemeNamesDidChangeNotification, object: self)
		}
	}

	private struct State {
		var currentTheme = ArticleTheme.defaultTheme
		var themeNames = [ArticleThemesManager.defaultThemeName]
		/// The most recent gate or correction task (see `assignOrMeasure`). Kept so tests can await it.
		var settleTask: Task<Void, Never>?
		/// In-flight prewarms by theme name, so repeated file-presenter callbacks start nothing new.
		var prewarmTasks = [String: Task<Void, Never>]()
	}
	private let state = OSAllocatedUnfairLock(initialState: State())

	@MainActor private var didStart = false

	override init() {
		let folderPath = Platform.dataSubfolder(forApplication: nil, folderName: "Themes")!
		self.folderPath = folderPath
		self.presentedItemURL = URL(fileURLWithPath: folderPath)

		super.init()

		do {
			try FileManager.default.createDirectory(atPath: folderPath, withIntermediateDirectories: true, attributes: nil)
		} catch {
			assertionFailure("Could not create folder for Themes.")
			abort()
		}
	}

	@MainActor public func start() {
		guard !didStart else {
			assertionFailure("ArticlesThemesManager.start called when already started.")
			return
		}
		// Fails loudly in debug builds if nameStorage was never injected --
		// silently falling back to the in-memory default would mean a
		// person's saved theme choice stops loading, with no crash to flag
		// it. See AppDelegate.swift's ordering requirement above nameStorage.
		assert(!(Self.nameStorage is InMemoryThemeNameStorage), "ArticleThemesManager.nameStorage must be injected (see AppDelegate.swift) before start() is called.")
		didStart = true

		updateThemeNames()
		updateCurrentTheme(isStart: true)
		measureCurrentThemeAndCorrect()
		remeasureInstalledThemesIfStale()

		NSFileCoordinator.addFilePresenter(self)
	}

	public func presentedSubitemDidChange(at url: URL) {
		updateThemeNames()
		updateCurrentTheme()
		if let themeName = Self.themeName(forChangedURL: url) {
			prewarmTheme(named: themeName)
		}
	}

	// MARK: API

	public func themeExists(filename: String) -> Bool {
		let filenameLastPathComponent = (filename as NSString).lastPathComponent
		let toFilename = (folderPath as NSString).appendingPathComponent(filenameLastPathComponent)
		return FileManager.default.fileExists(atPath: toFilename)
	}

	public func importTheme(filename: String) throws {
		// Validate before touching the installed copy, so a rejected bundle
		// can never replace or delete an existing theme.
		let source = URL(fileURLWithPath: filename)
		try ArticleThemeBundleValidator.validate(directory: source)

		let filenameLastPathComponent = (filename as NSString).lastPathComponent
		let toFilename = (folderPath as NSString).appendingPathComponent(filenameLastPathComponent)

		// Build the clean copy (kept files only) outside the Themes folder first, so a
		// failure while copying also leaves the installed theme alone.
		let fileManager = FileManager.default
		let staging = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		defer { try? fileManager.removeItem(at: staging) }
		let staged = staging.appendingPathComponent(filenameLastPathComponent, isDirectory: true)
		try ArticleThemeBundleValidator.copyInstallableFiles(from: source, to: staged)

		if fileManager.fileExists(atPath: toFilename) {
			try fileManager.removeItem(atPath: toFilename)
		}

		try fileManager.copyItem(at: staged, to: URL(fileURLWithPath: toFilename))

		prewarmTheme(named: ArticleTheme.themeNameForPath(filename))
	}

	/// A silent lookup: returns nil for a theme name that can't be resolved or
	/// whose package fails to load, without reporting anything. Used for display
	/// purposes (e.g. the theme picker's row labels), which may re-evaluate this
	/// for every theme on every SwiftUI re-render -- posting a failure
	/// notification from here would show a duplicate "couldn't be opened" alert
	/// per broken theme per render, rather than only on an actual import attempt.
	/// Callers that perform a user-initiated import already report their own
	/// failures at the call site.
	func articleThemeWithThemeName(_ themeName: String) -> ArticleTheme? {
		if themeName == Self.defaultThemeName {
			return ArticleTheme.defaultTheme
		}

		let url: URL
		let isAppTheme: Bool
		if let appThemeURL = Bundle.main.url(forResource: themeName, withExtension: ArticleTheme.nnwThemeSuffix, subdirectory: "Themes") {
			url = appThemeURL
			isAppTheme = true
		} else if let installedPath = pathForThemeName(themeName, folder: folderPath) {
			url = URL(fileURLWithPath: installedPath)
			isAppTheme = false
		} else {
			return nil
		}

		return try? ArticleTheme(url: url, isAppTheme: isAppTheme)
	}

	public func deleteTheme(themeName: String) {
		if let filename = pathForThemeName(themeName, folder: folderPath) {
			try? FileManager.default.removeItem(atPath: filename)
		}
	}
}

// MARK: - Private

extension ArticleThemesManager {

	func updateThemeNames() {
		let appThemeFilenames = Bundle.main.paths(forResourcesOfType: ArticleTheme.nnwThemeSuffix, inDirectory: "Themes")
		let appThemeNames = Set(appThemeFilenames.map { ArticleTheme.themeNameForPath($0) })

		let installedThemeNames = Set(allThemePaths(folderPath).map { ArticleTheme.themeNameForPath($0) })

		let allThemeNames = appThemeNames.union(installedThemeNames)

		let sortedThemeNames = allThemeNames.sorted(by: { $0.compare($1, options: .caseInsensitive) == .orderedAscending })
		if sortedThemeNames != themeNames {
			themeNames = sortedThemeNames
		}
	}

	func defaultArticleTheme() -> ArticleTheme {
		articleThemeWithThemeName(Self.defaultThemeName)!
	}

	/// Resolves the stored theme name to a theme and hands it to the gate.
	/// `isStart` is true only for the launch-time resolution of the stored theme.
	func updateCurrentTheme(isStart: Bool = false) {
		var themeName = currentThemeName
		if !themeNames.contains(themeName) {
			themeName = Self.defaultThemeName
			currentThemeName = Self.defaultThemeName
		}

		var articleTheme = articleThemeWithThemeName(themeName)
		if articleTheme == nil {
			articleTheme = defaultArticleTheme()
			currentThemeName = Self.defaultThemeName
		}

		if let articleTheme = articleTheme, articleTheme != currentTheme {
			assignOrMeasure(articleTheme, named: themeName, isStart: isStart)
		}
	}

	// MARK: Gate (D12)

	/// Native colors are derived from the theme, so a theme with no measurement would paint
	/// scanner colors first and visibly correct itself. The gate avoids that where it can:
	/// - measured theme (or the probe is disabled): assign synchronously;
	/// - the stored theme at launch: assign synchronously with scanner colors, then measure
	///   in the background (see `measureCurrentThemeAndCorrect`);
	/// - anything else: measure first, assign afterwards, and drop the result if the
	///   selection changed meanwhile.
	private func assignOrMeasure(_ theme: ArticleTheme, named themeName: String, isStart: Bool) {
		if isStart || !ArticleThemeColorProbe.isEnabled || ArticleThemeColorStore.hasMeasurement(for: theme) {
			currentTheme = theme
			return
		}
		let task = Task { @MainActor in
			await ArticleThemeColorStore.ensureMeasured(theme)
			// Stale: the person picked something else (or the theme was removed) while measuring.
			guard self.currentThemeName == themeName, theme != self.currentTheme else {
				return
			}
			self.currentTheme = theme
		}
		state.withLock { $0.settleTask = task }
	}

	/// For a current theme that was assigned without a measurement: measure it in the
	/// background and, if its colors differ from the scanner colors already on screen,
	/// repost the current-theme notification once so every native surface updates.
	func measureCurrentThemeAndCorrect() {
		let theme = currentTheme
		guard ArticleThemeColorProbe.isEnabled, !ArticleThemeColorStore.hasMeasurement(for: theme) else {
			return
		}
		let task = Task { @MainActor in
			guard !ArticleThemeColorStore.hasMeasurement(for: theme) else {
				return
			}
			let before = ArticleThemeColorStore.colors(for: theme)
			await ArticleThemeColorStore.ensureMeasured(theme)
			guard self.currentTheme.colorCacheKey == theme.colorCacheKey,
				  ArticleThemeColorStore.hasMeasurement(for: theme) else {
				return
			}
			if !Self.sameColors(before, ArticleThemeColorStore.colors(for: theme)) {
				NotificationCenter.default.postOnMainThread(name: .CurrentArticleThemeDidChangeNotification, object: self)
			}
		}
		state.withLock { $0.settleTask = task }
	}

	/// D9: when the persisted cache predates the current probe version or `core.css`,
	/// re-measure the installed themes at utility priority. Entries stay in use meanwhile.
	func remeasureInstalledThemesIfStale() {
		guard ArticleThemeColorProbe.isEnabled, ArticleThemeColorStore.core.isPersistedCacheStale() else {
			return
		}
		Task(priority: .utility) { @MainActor in
			let themes = self.themeNames.compactMap { self.articleThemeWithThemeName($0) }
			let changed = await ArticleThemeColorStore.remeasureIfStale(themes)
			if changed.contains(self.currentTheme.colorCacheKey) {
				NotificationCenter.default.postOnMainThread(name: .CurrentArticleThemeDidChangeNotification, object: self)
			}
		}
	}

	// MARK: Prewarm

	/// Measures a newly installed or changed theme ahead of selection. Coalesced by theme
	/// name here and by cache key in the store, so repeated callbacks do nothing.
	func prewarmTheme(named themeName: String) {
		guard ArticleThemeColorProbe.isEnabled else {
			return
		}
		state.withLock { s in
			guard s.prewarmTasks[themeName] == nil else {
				return
			}
			s.prewarmTasks[themeName] = Task { @MainActor in
				if let theme = self.articleThemeWithThemeName(themeName),
				   !ArticleThemeColorStore.hasMeasurement(for: theme) {
					await ArticleThemeColorStore.ensureMeasured(theme)
				}
				self.state.withLock { $0.prewarmTasks[themeName] = nil }
			}
		}
	}

	/// The theme a changed file-presenter URL belongs to: the first `.nnwtheme` path component.
	static func themeName(forChangedURL url: URL) -> String? {
		for component in url.pathComponents where component.hasSuffix(ArticleTheme.nnwThemeSuffix) {
			return ArticleTheme.themeNameForPath(component)
		}
		return nil
	}

	/// Whether two color sets agree to within less than one 8-bit step per channel.
	private static func sameColors(_ a: ArticleThemeColorExtractor.ThemeColors, _ b: ArticleThemeColorExtractor.ThemeColors) -> Bool {
		func close(_ x: UIColor, _ y: UIColor) -> Bool {
			var xr: CGFloat = 0, xg: CGFloat = 0, xb: CGFloat = 0, xa: CGFloat = 0
			var yr: CGFloat = 0, yg: CGFloat = 0, yb: CGFloat = 0, ya: CGFloat = 0
			x.getRed(&xr, green: &xg, blue: &xb, alpha: &xa)
			y.getRed(&yr, green: &yg, blue: &yb, alpha: &ya)
			let step = 1.0 / 255.0
			return abs(xr - yr) < step && abs(xg - yg) < step && abs(xb - yb) < step
		}
		return close(a.backgroundColor, b.backgroundColor) && close(a.backgroundColorDark, b.backgroundColorDark)
			&& close(a.textColor, b.textColor) && close(a.textColorDark, b.textColorDark)
			&& close(a.linkColor, b.linkColor) && close(a.linkColorDark, b.linkColorDark)
	}

	/// Test hooks.
	var settleTaskForTesting: Task<Void, Never>? {
		state.withLock { $0.settleTask }
	}

	var prewarmTasksForTesting: [Task<Void, Never>] {
		state.withLock { Array($0.prewarmTasks.values) }
	}

	func allThemePaths(_ folder: String) -> [String] {
		let filepaths = FileManager.default.filePaths(inFolder: folder)
		return filepaths?.filter { $0.hasSuffix(ArticleTheme.nnwThemeSuffix) } ?? []
	}

	func pathForThemeName(_ themeName: String, folder: String) -> String? {
		for onePath in allThemePaths(folder) {
			if ArticleTheme.pathIsPathForThemeName(themeName, path: onePath) {
				return onePath
			}
		}
		return nil
	}

}
