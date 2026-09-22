//
//  ArticleThemesManager.sqift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/26/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import Foundation
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
		updateCurrentTheme()

		NSFileCoordinator.addFilePresenter(self)
	}

	public func presentedSubitemDidChange(at url: URL) {
		updateThemeNames()
		updateCurrentTheme()
	}

	// MARK: API

	public func themeExists(filename: String) -> Bool {
		let filenameLastPathComponent = (filename as NSString).lastPathComponent
		let toFilename = (folderPath as NSString).appendingPathComponent(filenameLastPathComponent)
		return FileManager.default.fileExists(atPath: toFilename)
	}

	public func importTheme(filename: String) throws {
		let filenameLastPathComponent = (filename as NSString).lastPathComponent
		let toFilename = (folderPath as NSString).appendingPathComponent(filenameLastPathComponent)

		if FileManager.default.fileExists(atPath: toFilename) {
			try FileManager.default.removeItem(atPath: toFilename)
		}

		try FileManager.default.copyItem(atPath: filename, toPath: toFilename)
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

private extension ArticleThemesManager {

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

	func updateCurrentTheme() {
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
			currentTheme = articleTheme
		}
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
