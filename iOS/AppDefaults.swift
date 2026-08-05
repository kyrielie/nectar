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

/// Whether `.badges` mode's rating/warning/category pills render with their
/// own tint or stay neutral. `.neutral` is the default (today's rendering);
/// fandom pills stay neutral in both modes -- see MainTimelineCellData's
/// BadgeCategory doc comment for why.
enum BadgeColorMode: Int, CaseIterable, Sendable {
	case neutral = 1
	case colored = 2

	var description: String {
		switch self {
		case .neutral:
			return NSLocalizedString("Neutral", comment: "Neutral badge color mode")
		case .colored:
			return NSLocalizedString("Colored", comment: "Colored badge color mode")
		}
	}
}

enum PageCounterDisplayMode: String, CaseIterable, Sendable {
	case off
	case percentage
	case pageCount
}

extension Notification.Name {
	public static let userInterfaceColorPaletteDidUpdate = Notification.Name("UserInterfaceColorPaletteDidUpdateNotification")
	public static let timelineIconSizeDidChange = Notification.Name("TimelineIconSizeDidChangeNotification")
	public static let timelineNumberOfLinesDidChange = Notification.Name("TimelineNumberOfLinesDidChangeNotification")
	public static let timelineTagDisplayModeDidChange = Notification.Name("TimelineTagDisplayModeDidChangeNotification")
	public static let badgeColorModeDidChange = Notification.Name("BadgeColorModeDidChangeNotification")
	public static let articleThemeOverridesDidChange = Notification.Name("ArticleThemeOverridesDidChangeNotification")
}

final class AppDefaults: Sendable {
	static let shared = AppDefaults()
	static let defaultThemeName = "Default"
	fileprivate static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDefaults")

	private init() {}

	nonisolated(unsafe) static let store: UserDefaults = .standard

	struct Key {
		static let userInterfaceColorPalette = "userInterfaceColorPalette"
		static let lastImageCacheFlushDate = "lastImageCacheFlushDate"
		static let firstRunDate = "firstRunDate"
		static let hasShownAO3Onboarding = "hasShownAO3Onboarding"
		static let timelineGroupByFeed = "timelineGroupByFeed"
		static let refreshClearsReadArticles = "refreshClearsReadArticles"
		static let timelineNumberOfLines = "timelineNumberOfLines"
		static let timelineIconDimension = "timelineIconSize"
		static let timelineTagDisplayMode = "timelineTagDisplayMode"
		static let badgeColorMode = "badgeColorMode"
		static let timelineSortDirection = "timelineSortDirection"
		static let timelineSortField = "timelineSortField"
		static let articleFullscreenAvailable = "articleFullscreenAvailable"
		static let articleFullscreenEnabled = "articleFullscreenEnabled"
		static let articleBackSwipeEnabled = "articleBackSwipeEnabled"
		static let articlePagingSwipeEnabled = "articlePagingSwipeEnabled"
		static let showFeedNameInReaderView = "showFeedNameInReaderView"
		static let showPrevNextArticleButtons = "showPrevNextArticleButtons"
		static let showTableOfContentsAndFind = "showTableOfContentsAndFind"
		static let hideNotchInFullScreen = "hideNotchInFullScreen"
		static let pageCounterDisplayMode = "pageCounterDisplayMode"
		static let disableArticleLinks = "disableArticleLinks"
		static let showLastUpdatedLabel = "showLastUpdatedLabel"
		static let articleThemeOverrides = "articleThemeOverrides"
		static let lastRefresh = "lastRefresh"
		static let addFeedAccountID = "addFeedAccountID"
		static let addFeedFolderName = "addFeedFolderName"
		static let addFolderAccountID = "addFolderAccountID"
		static let useSystemBrowser = "useSystemBrowser"
		static let currentThemeName = "currentThemeName"
		static let hideReadFeeds = "hideReadFeeds"
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

	/// Controls the article view's edge-swipe-back-to-timeline gesture (the
	/// standard interactive pop gesture). Independent of fullscreen state.
	/// Default: true.
	var articleBackSwipeEnabled: Bool {
		get {
			return AppDefaults.bool(for: Key.articleBackSwipeEnabled)
		}
		set {
			AppDefaults.setBool(for: Key.articleBackSwipeEnabled, newValue)
		}
	}

	/// Controls the article view's swipe-to-next/previous-article gesture
	/// (paging on ArticleViewController's UIPageViewController). Independent
	/// of fullscreen state. Default: true.
	var articlePagingSwipeEnabled: Bool {
		get {
			return AppDefaults.bool(for: Key.articlePagingSwipeEnabled)
		}
		set {
			AppDefaults.setBool(for: Key.articlePagingSwipeEnabled, newValue)
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

	/// Whether the reader view toolbar shows the previous/next article buttons.
	/// Replaced by the Table of Contents/Find buttons when showTableOfContentsAndFind
	/// is on — see ArticleViewController.rightBarButtonItems().
	var showPrevNextArticleButtons: Bool {
		get {
			return AppDefaults.bool(for: Key.showPrevNextArticleButtons)
		}
		set {
			AppDefaults.setBool(for: Key.showPrevNextArticleButtons, newValue)
		}
	}

	/// Whether the reader view toolbar shows Table of Contents/Find buttons
	/// instead of the previous/next article buttons. Opt-in (default false)
	/// since it replaces, rather than adds to, the existing toolbar slot.
	var showTableOfContentsAndFind: Bool {
		get {
			return AppDefaults.bool(for: Key.showTableOfContentsAndFind)
		}
		set {
			AppDefaults.setBool(for: Key.showTableOfContentsAndFind, newValue)
		}
	}

	/// Whether the notch/Dynamic Island area is masked (solid black) while in
	/// fullscreen reading mode, instead of showing through as normal. Exposed
	/// as its own toggle -- independent of the page counter below -- for
	/// people who want the notch hidden but don't care about the counter.
	/// The page counter turning on also hides the notch (see
	/// WebViewController.updateNotchAndPageCounterVisibility()) without
	/// requiring this setting to also be switched on: showing a page counter
	/// in a space that still displays the notch would look broken.
	var hideNotchInFullScreen: Bool {
		get {
			return AppDefaults.bool(for: Key.hideNotchInFullScreen)
		}
		set {
			AppDefaults.setBool(for: Key.hideNotchInFullScreen, newValue)
		}
	}

	/// Page counter shown in the notch's leading side space while in
	/// fullscreen reading mode. Off by default; when on, implies hiding the
	/// notch regardless of hideNotchInFullScreen's own value (see above).
	var pageCounterDisplayMode: PageCounterDisplayMode {
		get {
			guard let rawValue = AppDefaults.string(for: Key.pageCounterDisplayMode),
				  let mode = PageCounterDisplayMode(rawValue: rawValue) else {
				return .off
			}
			return mode
		}
		set {
			AppDefaults.setString(for: Key.pageCounterDisplayMode, newValue.rawValue)
		}
	}

	/// When on, tapping any link in the article body (including target=_blank
	/// links) is suppressed entirely rather than navigating anywhere. Off by
	/// default, since it changes existing behavior.
	var disableArticleLinks: Bool {
		get {
			return AppDefaults.bool(for: Key.disableArticleLinks)
		}
		set {
			AppDefaults.setBool(for: Key.disableArticleLinks, newValue)
		}
	}

	/// The "Updated X ago" / "Updated Just Now" label shown under the feed
	/// list while idle. On by default, preserving current behavior.
	var showLastUpdatedLabel: Bool {
		get {
			return AppDefaults.bool(for: Key.showLastUpdatedLabel)
		}
		set {
			AppDefaults.setBool(for: Key.showLastUpdatedLabel, newValue)
		}
	}

	/// Whether the AO3 first-run onboarding screen (shown once, only when
	/// the local account has zero subscribed feeds) has already been shown.
	/// Off by default; set once the screen is dismissed (by either action)
	/// so it never shows again regardless of the account's feed count
	/// afterward. See MainFeedCollectionViewController.presentAO3OnboardingIfNeeded().
	var hasShownAO3Onboarding: Bool {
		get {
			return AppDefaults.bool(for: Key.hasShownAO3Onboarding)
		}
		set {
			AppDefaults.setBool(for: Key.hasShownAO3Onboarding, newValue)
		}
	}


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

	var badgeColorMode: BadgeColorMode {
		get {
			let rawValue = AppDefaults.store.integer(forKey: Key.badgeColorMode)
			return BadgeColorMode(rawValue: rawValue) ?? .neutral
		}
		set {
			AppDefaults.store.set(newValue.rawValue, forKey: Key.badgeColorMode)
			NotificationCenter.default.post(name: .badgeColorModeDidChange, object: nil)
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
									Key.badgeColorMode: BadgeColorMode.neutral.rawValue,
										Key.timelineSortDirection: ComparisonResult.orderedDescending.rawValue,
								Key.timelineSortField: ArticleSorter.SortField.date.rawValue,
										Key.articleFullscreenAvailable: false,
										Key.articleFullscreenEnabled: false,
										Key.articleBackSwipeEnabled: true,
									Key.articlePagingSwipeEnabled: true,
										Key.showFeedNameInReaderView: false,
									Key.showPrevNextArticleButtons: true,
									Key.showLastUpdatedLabel: true,
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

	init(hideReadFeeds: Bool,
	     expandedContainers: Set<ContainerIdentifier>,
	     selectedSidebarItem: SidebarItemIdentifier?,
	     smartFeedsHidingReadArticles: Set<String>,
	     feedsHidingReadArticles: [String: Set<String>],
	     foldersShowingReadArticles: [String: Set<String>],
	     selectedArticle: ArticleSpecifier?) {
		self.hideReadFeeds = hideReadFeeds
		self.expandedContainers = expandedContainers
		self.selectedSidebarItem = selectedSidebarItem
		self.smartFeedsHidingReadArticles = smartFeedsHidingReadArticles
		self.feedsHidingReadArticles = feedsHidingReadArticles
		self.foldersShowingReadArticles = foldersShowingReadArticles
		self.selectedArticle = selectedArticle

		AppDefaults.logger.debug("AppDefaults: StateRestorationInfo:\nexpandedContainers: \(expandedContainers)\nselectedSidebarItem: \(selectedSidebarItem?.userInfo ?? [String: String]())\nsmartFeedsHidingReadArticles: \(smartFeedsHidingReadArticles)\nfeedsHidingReadArticles: \(feedsHidingReadArticles)\nfoldersShowingReadArticles: \(foldersShowingReadArticles)\nselectedArticle: \(selectedArticle?.dictionary ?? [String: String]())")
	}

	init() {
		self.init(hideReadFeeds: AppDefaults.shared.hideReadFeeds,
				  expandedContainers: AppDefaults.shared.expandedContainers,
				  selectedSidebarItem: AppDefaults.shared.selectedSidebarItem,
				  smartFeedsHidingReadArticles: AppDefaults.shared.smartFeedsHidingReadArticles,
				  feedsHidingReadArticles: AppDefaults.shared.feedsHidingReadArticles,
				  foldersShowingReadArticles: AppDefaults.shared.foldersShowingReadArticles,
				  selectedArticle: AppDefaults.shared.selectedArticle)
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
				  selectedArticle: AppDefaults.shared.selectedArticle)
	}
}
