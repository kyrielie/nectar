//
//  AppDefaults.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/22/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import UIKit
import os
import Account
import Articles
import Images

enum UserInterfaceColorPalette: Int, CustomStringConvertible, CaseIterable {
	case automatic = 0
	case light = 1
	case dark = 2

	var description: String {
		switch self {
		case .automatic:
			return NSLocalizedString("Automatic", comment: "Automatic")
		case .light:
			return NSLocalizedString("Light", comment: "Light")
		case .dark:
			return NSLocalizedString("Dark", comment: "Dark")
		}
	}
}

/// How the timeline card renders word count / completion / fandom / rating /
/// warnings. `.compact` is the default (today's single truncating line);
/// `.expanded` and `.badges` are alternative modes chosen via Settings →
/// Timeline Layout, independent of the number-of-lines slider, which continues
/// to govern the summary/description text.
enum TagDisplayMode: Int, CaseIterable, Sendable {
	/// Today's single truncating `metadataString`-style line.
	case compact = 1
	/// Word count / completion / fandom / rating / warnings, each on its own row.
	case expanded = 2
	/// Word count / completion stays on one line; fandom + rating + warnings
	/// wrap as small pill badges below it.
	case badges = 3

	var description: String {
		switch self {
		case .compact:
			return NSLocalizedString("Compact", comment: "Compact tag display mode")
		case .expanded:
			return NSLocalizedString("Expanded", comment: "Expanded tag display mode")
		case .badges:
			return NSLocalizedString("Badges", comment: "Badges tag display mode")
		}
	}
}

extension Notification.Name {
	public static let userInterfaceColorPaletteDidUpdate = Notification.Name("UserInterfaceColorPaletteDidUpdateNotification")
	public static let timelineIconSizeDidChange = Notification.Name("TimelineIconSizeDidChangeNotification")
	public static let timelineNumberOfLinesDidChange = Notification.Name("TimelineNumberOfLinesDidChangeNotification")
	public static let timelineTagDisplayModeDidChange = Notification.Name("TimelineTagDisplayModeDidChangeNotification")
	public static let articleThemeOverridesDidChange = Notification.Name("ArticleThemeOverridesDidChangeNotification")
}

final class AppDefaults: Sendable {
	static let shared = AppDefaults()
	static let defaultThemeName = "Default"
	fileprivate static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDefaults")

	private init() {}

	nonisolated(unsafe) static let store: UserDefaults = {
		let appIdentifierPrefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as! String
		let suiteName = "\(appIdentifierPrefix)group.\(Bundle.main.bundleIdentifier!)"
		return UserDefaults.init(suiteName: suiteName)!
	}()

	struct Key {
		static let userInterfaceColorPalette = "userInterfaceColorPalette"
		static let lastImageCacheFlushDate = "lastImageCacheFlushDate"
		static let firstRunDate = "firstRunDate"
		static let timelineGroupByFeed = "timelineGroupByFeed"
		static let refreshClearsReadArticles = "refreshClearsReadArticles"
		static let timelineNumberOfLines = "timelineNumberOfLines"
		static let timelineIconDimension = "timelineIconSize"
		static let timelineTagDisplayMode = "timelineTagDisplayMode"
		static let timelineSortDirection = "timelineSortDirection"
		static let timelineSortField = "timelineSortField"
		static let articleFullscreenAvailable = "articleFullscreenAvailable"
		static let articleFullscreenEnabled = "articleFullscreenEnabled"
		static let blockSwipesWhenBarsHidden = "blockSwipesWhenBarsHidden"
		static let showFeedNameInReaderView = "showFeedNameInReaderView"
		static let articleThemeOverrides = "articleThemeOverrides"
		static let confirmMarkAllAsRead = "confirmMarkAllAsRead"
		static let lastRefresh = "lastRefresh"
		static let addFeedAccountID = "addFeedAccountID"
		static let addFeedFolderName = "addFeedFolderName"
		static let addFolderAccountID = "addFolderAccountID"
		static let useSystemBrowser = "useSystemBrowser"
		static let currentThemeName = "currentThemeName"
		static let hideReadFeeds = "hideReadFeeds"
		static let articleWindowScrollY = "articleWindowScrollY"
		static let expandedContainers = "expandedContainers"
		static let smartFeedsHidingReadArticles = "smartFeedsHidingReadArticles"
		static let feedsHidingReadArticles = "feedsHidingReadArticles"
		static let foldersShowingReadArticles = "foldersShowingReadArticles"
		static let selectedSidebarItem = "selectedSidebarItem"
		static let selectedArticle = "selectedArticle"
		static let didMigrateLegacyStateRestorationInfo = "didMigrateLegacyStateRestorationInfo"
		static let splitViewPreferredDisplayMode = "splitViewPreferredDisplayMode"
	}

	let isDeveloperBuild: Bool = {
		if let dev = Bundle.main.object(forInfoDictionaryKey: "DeveloperEntitlements") as? String, dev == "-dev" {
			return true
		}
		return false
	}()

	let isFirstRun: Bool = {
		if AppDefaults.store.object(forKey: Key.firstRunDate) is Date {
			return false
		}
		firstRunDate = Date()
		return true
	}()

	static var userInterfaceColorPalette: UserInterfaceColorPalette {
		get {
			if let result = UserInterfaceColorPalette(rawValue: int(for: Key.userInterfaceColorPalette)) {
				return result
			}
			return .automatic
		}
		set {
			setInt(for: Key.userInterfaceColorPalette, newValue.rawValue)
			NotificationCenter.default.post(name: .userInterfaceColorPaletteDidUpdate, object: self)
		}
	}

	var addFeedAccountID: String? {
		get {
			return AppDefaults.string(for: Key.addFeedAccountID)
		}
		set {
			AppDefaults.setString(for: Key.addFeedAccountID, newValue)
		}
	}

	var addFeedFolderName: String? {
		get {
			return AppDefaults.string(for: Key.addFeedFolderName)
		}
		set {
			AppDefaults.setString(for: Key.addFeedFolderName, newValue)
		}
	}

	var addFolderAccountID: String? {
		get {
			return AppDefaults.string(for: Key.addFolderAccountID)
		}
		set {
			AppDefaults.setString(for: Key.addFolderAccountID, newValue)
		}
	}

	var useSystemBrowser: Bool {
		get {
			return UserDefaults.standard.bool(forKey: Key.useSystemBrowser)
		}
		set {
			UserDefaults.standard.setValue(newValue, forKey: Key.useSystemBrowser)
		}
	}

	var lastImageCacheFlushDate: Date? {
		get {
			return AppDefaults.date(for: Key.lastImageCacheFlushDate)
		}
		set {
			AppDefaults.setDate(for: Key.lastImageCacheFlushDate, newValue)
		}
	}

	var timelineGroupByFeed: Bool {
		get {
			return AppDefaults.bool(for: Key.timelineGroupByFeed)
		}
		set {
			AppDefaults.setBool(for: Key.timelineGroupByFeed, newValue)
		}
	}

	var refreshClearsReadArticles: Bool {
		get {
			return AppDefaults.bool(for: Key.refreshClearsReadArticles)
		}
		set {
			AppDefaults.setBool(for: Key.refreshClearsReadArticles, newValue)
		}
	}

	var timelineSortDirection: ComparisonResult {
		get {
			return AppDefaults.sortDirection(for: Key.timelineSortDirection)
		}
		set {
			AppDefaults.setSortDirection(for: Key.timelineSortDirection, newValue)
		}
	}

	var timelineSortField: ArticleSorter.SortField {
		get {
			let rawValue = AppDefaults.int(for: Key.timelineSortField)
			return ArticleSorter.SortField(rawValue: rawValue) ?? .date
		}
		set {
			AppDefaults.setInt(for: Key.timelineSortField, newValue.rawValue)
		}
	}

	var articleFullscreenAvailable: Bool {
		get {
			return AppDefaults.bool(for: Key.articleFullscreenAvailable)
		}
		set {
			AppDefaults.setBool(for: Key.articleFullscreenAvailable, newValue)
		}
	}

	var articleFullscreenEnabled: Bool {
		get {
			return articleFullscreenAvailable && AppDefaults.bool(for: Key.articleFullscreenEnabled)
		}
		set {
			AppDefaults.setBool(for: Key.articleFullscreenEnabled, newValue)
		}
	}

	var logicalArticleFullscreenEnabled: Bool {
		articleFullscreenAvailable && articleFullscreenEnabled
	}

	/// When true (default), hiding the article bars also blocks swiping to
	/// the next/previous article and swiping back, so a tap-to-hide doesn't
	/// get immediately undone by a swipe the user didn't intend as a "show
	/// bars again" gesture. Some people would rather keep swiping through a
	/// library uninterrupted with the bars out of the way, hence the toggle.
	var blockSwipesWhenBarsHidden: Bool {
		get {
			return AppDefaults.bool(for: Key.blockSwipesWhenBarsHidden)
		}
		set {
			AppDefaults.setBool(for: Key.blockSwipesWhenBarsHidden, newValue)
		}
	}

	/// Off by default: a book's feed name becomes ambiguous once smart-feed
	/// deduplication can surface it from more than one feed (see
	/// SmartFeedArticleGrouping), so the reader view hides it by default
	/// rather than showing only one of several feeds it happens to belong to.
	/// When turned on, ArticleRenderer shows the single feed name for
	/// articles opened from a real feed, or every feed a book appeared in
	/// (comma-separated) for articles opened from a smart feed where it was
	/// deduplicated across more than one.
	var showFeedNameInReaderView: Bool {
		get {
			return AppDefaults.bool(for: Key.showFeedNameInReaderView)
		}
		set {
			AppDefaults.setBool(for: Key.showFeedNameInReaderView, newValue)
		}
	}

	/// User overrides for font, size, line height, and colors in the reader view,
	/// layered on top of whichever theme (default or imported) is active. See
	/// ArticleThemeOverrides.cssOverrideBlock and ArticleRenderer.styleString().
	var articleThemeOverrides: ArticleThemeOverrides {
		get {
			guard let json = AppDefaults.string(for: Key.articleThemeOverrides),
				  let data = json.data(using: .utf8),
				  let decoded = try? JSONDecoder().decode(ArticleThemeOverrides.self, from: data) else {
				return ArticleThemeOverrides()
			}
			return decoded
		}
		set {
			if let data = try? JSONEncoder().encode(newValue), let json = String(data: data, encoding: .utf8) {
				AppDefaults.setString(for: Key.articleThemeOverrides, json)
			}
			NotificationCenter.default.post(name: .articleThemeOverridesDidChange, object: self)
		}
	}

	var confirmMarkAllAsRead: Bool {
		get {
			return AppDefaults.bool(for: Key.confirmMarkAllAsRead)
		}
		set {
			AppDefaults.setBool(for: Key.confirmMarkAllAsRead, newValue)
		}
	}

	var splitViewPreferredDisplayMode: Int {
		get {
			return AppDefaults.int(for: Key.splitViewPreferredDisplayMode)
		}
		set {
			AppDefaults.setInt(for: Key.splitViewPreferredDisplayMode, newValue)
		}
	}

	var lastRefresh: Date? {
		get {
			return AppDefaults.date(for: Key.lastRefresh)
		}
		set {
			AppDefaults.setDate(for: Key.lastRefresh, newValue)
		}
	}

	var timelineNumberOfLines: Int {
		get {
			return AppDefaults.int(for: Key.timelineNumberOfLines)
		}
		set {
			AppDefaults.setInt(for: Key.timelineNumberOfLines, newValue)
			NotificationCenter.default.post(name: .timelineNumberOfLinesDidChange, object: nil)
		}
	}

	var timelineIconSize: IconSize {
		get {
			let rawValue = AppDefaults.store.integer(forKey: Key.timelineIconDimension)
			return IconSize(rawValue: rawValue) ?? IconSize.medium
		}
		set {
			AppDefaults.store.set(newValue.rawValue, forKey: Key.timelineIconDimension)
			NotificationCenter.default.post(name: .timelineIconSizeDidChange, object: nil)
		}
	}

	var timelineTagDisplayMode: TagDisplayMode {
		get {
			let rawValue = AppDefaults.store.integer(forKey: Key.timelineTagDisplayMode)
			return TagDisplayMode(rawValue: rawValue) ?? .compact
		}
		set {
			AppDefaults.store.set(newValue.rawValue, forKey: Key.timelineTagDisplayMode)
			NotificationCenter.default.post(name: .timelineTagDisplayModeDidChange, object: nil)
		}
	}

	var currentThemeName: String? {
		get {
			return AppDefaults.string(for: Key.currentThemeName)
		}
		set {
			AppDefaults.setString(for: Key.currentThemeName, newValue)
		}
	}

	var hideReadFeeds: Bool {
		get {
			UserDefaults.standard.bool(forKey: Key.hideReadFeeds)
		}
		set {
			UserDefaults.standard.set(newValue, forKey: Key.hideReadFeeds)
		}
	}

	/// Write-only as of Phase A0 (nectar-plan-v3.md): WebViewController still writes this on
	/// every scroll change, but nothing reads it back to restore a position anymore -- it was a
	/// single value shared across every article, so using it to restore whichever article the
	/// user returns to on relaunch/Handoff meant restoring the *last-scrolled* article's offset
	/// onto a possibly different article. Per-article restoration now goes entirely through
	/// Account.fetchScrollPosition(forArticleID:). Left in place (rather than deleted outright)
	/// because StateRestorationInfo's shape/migration still carries it; worth removing properly
	/// in a follow-up once nothing depends on that shape.
	var articleWindowScrollY: Int {
		get {
			UserDefaults.standard.integer(forKey: Key.articleWindowScrollY)
		}
		set {
			UserDefaults.standard.set(newValue, forKey: Key.articleWindowScrollY)
		}
	}

	var expandedContainers: Set<ContainerIdentifier> {
		get {
			guard let rawIdentifiers = UserDefaults.standard.array(forKey: Key.expandedContainers) as? [[String: String]] else {
				return Set<ContainerIdentifier>()
			}
			let containerIdentifiers = rawIdentifiers.compactMap { ContainerIdentifier(userInfo: $0) }
			return Set(containerIdentifiers)
		}
		set {
			Self.logger.debug("AppDefaults: set expandedContainers: \(newValue)")
			let containerIdentifierUserInfos = newValue.compactMap { $0.userInfo }
			UserDefaults.standard.set(containerIdentifierUserInfos, forKey: Key.expandedContainers)
		}
	}

	var smartFeedsHidingReadArticles: Set<String> {
		get {
			let smartFeedIDs = UserDefaults.standard.array(forKey: Key.smartFeedsHidingReadArticles) as? [String] ?? []
			return Set(smartFeedIDs)
		}
		set {
			let array = Array(newValue)
			UserDefaults.standard.set(array, forKey: Key.smartFeedsHidingReadArticles)
		}
	}

	var feedsHidingReadArticles: [String: Set<String>] { // Account id: Set<feed.feedID>
		get {
			guard let d = UserDefaults.standard.dictionary(forKey: Key.feedsHidingReadArticles) as? [String: [String]] else {
				return [String: Set<String>]()
			}
			return d.mapValues { Set($0) }
		}
		set {
			let d = newValue.mapValues { Array($0) }
			UserDefaults.standard.set(d, forKey: Key.feedsHidingReadArticles)
		}
	}

	var foldersShowingReadArticles: [String: Set<String>] { // Account id: Set<folder.nameForDisplay>
		get {
			guard let d = UserDefaults.standard.dictionary(forKey: Key.foldersShowingReadArticles) as? [String: [String]] else {
				return [String: Set<String>]()
			}
			return d.mapValues { Set($0) }
		}
		set {
			let d = newValue.mapValues { Array($0) }
			UserDefaults.standard.set(d, forKey: Key.foldersShowingReadArticles)
		}
	}

	var selectedSidebarItem: SidebarItemIdentifier? {
		get {
			guard let userInfo = UserDefaults.standard.dictionary(forKey: Key.selectedSidebarItem) as? [String: String] else {
				return nil
			}
			return SidebarItemIdentifier(userInfo: userInfo)
		}
		set {
			guard let newValue else {
				UserDefaults.standard.removeObject(forKey: Key.selectedSidebarItem)
				return
			}
			UserDefaults.standard.set(newValue.userInfo, forKey: Key.selectedSidebarItem)
		}
	}

	var selectedArticle: ArticleSpecifier? {
		get {
			guard let d = UserDefaults.standard.dictionary(forKey: Key.selectedArticle) as? [String: String] else {
				return nil
			}
			return ArticleSpecifier(dictionary: d)
		}
		set {
			guard let newValue else {
				UserDefaults.standard.removeObject(forKey: Key.selectedArticle)
				return
			}
			UserDefaults.standard.set(newValue.dictionary, forKey: Key.selectedArticle)
		}
	}

	var didMigrateLegacyStateRestorationInfo: Bool {
		get {
			UserDefaults.standard.bool(forKey: Key.didMigrateLegacyStateRestorationInfo)
		}
		set {
			UserDefaults.standard.set(newValue, forKey: Key.didMigrateLegacyStateRestorationInfo)
		}
	}

	@MainActor static func registerDefaults() {
		let defaults: [String: Any] = [Key.userInterfaceColorPalette: UserInterfaceColorPalette.automatic.rawValue,
										Key.timelineGroupByFeed: false,
										Key.refreshClearsReadArticles: false,
										Key.timelineNumberOfLines: 2,
										Key.timelineIconDimension: IconSize.medium.rawValue,
										Key.timelineTagDisplayMode: TagDisplayMode.compact.rawValue,
										Key.timelineSortDirection: ComparisonResult.orderedDescending.rawValue,
								Key.timelineSortField: ArticleSorter.SortField.date.rawValue,
										Key.articleFullscreenAvailable: false,
										Key.articleFullscreenEnabled: false,
										Key.blockSwipesWhenBarsHidden: true,
										Key.showFeedNameInReaderView: false,
										Key.confirmMarkAllAsRead: true,
										Key.currentThemeName: Self.defaultThemeName,
									   Key.splitViewPreferredDisplayMode: UISplitViewController.DisplayMode.oneBesideSecondary.rawValue]
		AppDefaults.store.register(defaults: defaults)
	}
}

private extension AppDefaults {

	static var firstRunDate: Date? {
		get {
			return date(for: Key.firstRunDate)
		}
		set {
			setDate(for: Key.firstRunDate, newValue)
		}
	}

	static func string(for key: String) -> String? {
		return UserDefaults.standard.string(forKey: key)
	}

	static func setString(for key: String, _ value: String?) {
		UserDefaults.standard.set(value, forKey: key)
	}

	static func bool(for key: String) -> Bool {
		return AppDefaults.store.bool(forKey: key)
	}

	static func setBool(for key: String, _ flag: Bool) {
		AppDefaults.store.set(flag, forKey: key)
	}

	static func int(for key: String) -> Int {
		return AppDefaults.store.integer(forKey: key)
	}

	static func setInt(for key: String, _ x: Int) {
		AppDefaults.store.set(x, forKey: key)
	}

	static func date(for key: String) -> Date? {
		return AppDefaults.store.object(forKey: key) as? Date
	}

	static func setDate(for key: String, _ date: Date?) {
		AppDefaults.store.set(date, forKey: key)
	}

	static func sortDirection(for key: String) -> ComparisonResult {
		let rawInt = int(for: key)
		if rawInt == ComparisonResult.orderedAscending.rawValue {
			return .orderedAscending
		}
		return .orderedDescending
	}

	static func setSortDirection(for key: String, _ value: ComparisonResult) {
		if value == .orderedAscending {
			setInt(for: key, ComparisonResult.orderedAscending.rawValue)
		} else {
			setInt(for: key, ComparisonResult.orderedDescending.rawValue)
		}
	}
}

struct StateRestorationInfo {
	let hideReadFeeds: Bool
	let expandedContainers: Set<ContainerIdentifier>
	let selectedSidebarItem: SidebarItemIdentifier?
	let smartFeedsHidingReadArticles: Set<String>
	let feedsHidingReadArticles: [String: Set<String>]
	let foldersShowingReadArticles: [String: Set<String>]
	let selectedArticle: ArticleSpecifier?
	let articleWindowScrollY: Int

	init(hideReadFeeds: Bool,
	     expandedContainers: Set<ContainerIdentifier>,
	     selectedSidebarItem: SidebarItemIdentifier?,
	     smartFeedsHidingReadArticles: Set<String>,
	     feedsHidingReadArticles: [String: Set<String>],
	     foldersShowingReadArticles: [String: Set<String>],
	     selectedArticle: ArticleSpecifier?,
	     articleWindowScrollY: Int) {
		self.hideReadFeeds = hideReadFeeds
		self.expandedContainers = expandedContainers
		self.selectedSidebarItem = selectedSidebarItem
		self.smartFeedsHidingReadArticles = smartFeedsHidingReadArticles
		self.feedsHidingReadArticles = feedsHidingReadArticles
		self.foldersShowingReadArticles = foldersShowingReadArticles
		self.selectedArticle = selectedArticle
		self.articleWindowScrollY = articleWindowScrollY

		AppDefaults.logger.debug("AppDefaults: StateRestorationInfo:\nexpandedContainers: \(expandedContainers)\nselectedSidebarItem: \(selectedSidebarItem?.userInfo ?? [String: String]())\nsmartFeedsHidingReadArticles: \(smartFeedsHidingReadArticles)\nfeedsHidingReadArticles: \(feedsHidingReadArticles)\nfoldersShowingReadArticles: \(foldersShowingReadArticles)\nselectedArticle: \(selectedArticle?.dictionary ?? [String: String]())\narticleWindowScrollY: \(articleWindowScrollY)")
	}

	init() {
		self.init(hideReadFeeds: AppDefaults.shared.hideReadFeeds,
				  expandedContainers: AppDefaults.shared.expandedContainers,
				  selectedSidebarItem: AppDefaults.shared.selectedSidebarItem,
				  smartFeedsHidingReadArticles: AppDefaults.shared.smartFeedsHidingReadArticles,
				  feedsHidingReadArticles: AppDefaults.shared.feedsHidingReadArticles,
				  foldersShowingReadArticles: AppDefaults.shared.foldersShowingReadArticles,
				  selectedArticle: AppDefaults.shared.selectedArticle,
				  articleWindowScrollY: AppDefaults.shared.articleWindowScrollY)
	}

	// TODO: Delete for NetNewsWire 7.1.
	init(legacyState: NSUserActivity?) {
		if AppDefaults.shared.didMigrateLegacyStateRestorationInfo {
			self.init()
			return
		}

		AppDefaults.shared.didMigrateLegacyStateRestorationInfo = true

		// Extract legacy window state if available
		guard let windowState = legacyState?.userInfo?[UserInfoKey.windowState] as? [AnyHashable: Any] else {
			self.init()
			return
		}

		let hideReadFeeds: Bool
		if let legacyValue = windowState[UserInfoKey.readFeedsFilterState] as? Bool {
			hideReadFeeds = legacyValue
		} else {
			hideReadFeeds = AppDefaults.shared.hideReadFeeds
		}

		let expandedContainers: Set<ContainerIdentifier>
		if let legacyState = windowState[UserInfoKey.containerExpandedWindowState] as? [[AnyHashable: AnyHashable]] {
			let convertedState = legacyState.compactMap { dict -> [String: String]? in
				var stringDict = [String: String]()
				for (key, value) in dict {
					if let keyString = key as? String, let valueString = value as? String {
						stringDict[keyString] = valueString
					}
				}
				return stringDict.isEmpty ? nil : stringDict
			}
			let containerIdentifiers = convertedState.compactMap { ContainerIdentifier(userInfo: $0) }
			expandedContainers = Set(containerIdentifiers)
		} else {
			expandedContainers = AppDefaults.shared.expandedContainers
		}

		let sidebarItemsHidingReadArticles: Set<SidebarItemIdentifier>
		if let legacyState = windowState[UserInfoKey.readArticlesFilterState] as? [[AnyHashable: AnyHashable]: Bool] {
			let enabledFeeds = legacyState.filter { $0.value == true }
			let convertedState = enabledFeeds.keys.compactMap { key -> [String: String]? in
				var stringDict = [String: String]()
				for (k, v) in key {
					if let keyString = k as? String, let valueString = v as? String {
						stringDict[keyString] = valueString
					}
				}
				return stringDict.isEmpty ? nil : stringDict
			}
			let sidebarItemIdentifiers = convertedState.compactMap { SidebarItemIdentifier(userInfo: $0) }
			sidebarItemsHidingReadArticles = Set(sidebarItemIdentifiers)
		} else {
			sidebarItemsHidingReadArticles = Set<SidebarItemIdentifier>()
		}

		var smartFeedsHidingReadArticles = Set<String>()
		var feedsHidingReadArticles = [String: Set<String>]()
		for sidebarItem in sidebarItemsHidingReadArticles {
			switch sidebarItem {
			case .smartFeed(let id):
				smartFeedsHidingReadArticles.insert(id)
			case .feed(let accountID, let feedID):
				var feedIDs = feedsHidingReadArticles[accountID] ?? Set<String>()
				feedIDs.insert(feedID)
				feedsHidingReadArticles[accountID] = feedIDs
			default:
				continue
			}
		}

		let selectedSidebarItem: SidebarItemIdentifier?
		if let legacyState = windowState[UserInfoKey.feedIdentifier] as? [String: String],
		   let sidebarItemIdentifier = SidebarItemIdentifier(userInfo: legacyState) {
			selectedSidebarItem = sidebarItemIdentifier
		} else {
			selectedSidebarItem = AppDefaults.shared.selectedSidebarItem
		}

		self.init(hideReadFeeds: hideReadFeeds,
				  expandedContainers: expandedContainers,
				  selectedSidebarItem: selectedSidebarItem,
				  smartFeedsHidingReadArticles: smartFeedsHidingReadArticles,
				  feedsHidingReadArticles: feedsHidingReadArticles,
				  foldersShowingReadArticles: AppDefaults.shared.foldersShowingReadArticles,
				  selectedArticle: AppDefaults.shared.selectedArticle,
				  articleWindowScrollY: AppDefaults.shared.articleWindowScrollY)
	}
}
