//
//  Account.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/1/17.
//  Copyright © 2017 Ranchero Software, LLC. All rights reserved.
//

#if os(iOS)
import UIKit
#endif

import Foundation
import RSCore
import Articles
import RSParser
import RSDatabase
import ArticlesDatabase
import RSWeb
import ErrorLog
import ActivityLog
import os

// Main thread only.

public extension Notification.Name {
	static let UserDidAddAccount = Notification.Name("UserDidAddAccount")
	static let UserDidDeleteAccount = Notification.Name("UserDidDeleteAccount")
	static let AccountRefreshDidBegin = Notification.Name(rawValue: "AccountRefreshDidBegin")
	static let AccountRefreshDidFinish = Notification.Name(rawValue: "AccountRefreshDidFinish")
	static let AccountDidDownloadArticles = Notification.Name(rawValue: "AccountDidDownloadArticles")
	static let AccountStateDidChange = Notification.Name(rawValue: "AccountStateDidChange")
	static let StatusesDidChange = Notification.Name(rawValue: "StatusesDidChange")
	/// Posted when an article's reading-progress percentage is saved. Deliberately
	/// separate from `StatusesDidChange` -- readingProgress isn't a syncable
	/// ArticleStatus.Key, and it's saved on every scroll tick, so folding it into
	/// StatusesDidChange would also trigger unrelated observers (e.g. unread-count
	/// recalculation in SceneCoordinator) far more often than necessary.
	static let ReadingProgressDidChange = Notification.Name(rawValue: "ReadingProgressDidChange")
	/// Posted when a delegate enqueues one or more status changes for upstream send.
	/// Distinct from `StatusesDidChange`, which also fires for remote-sourced changes.
	static let AccountDidQueueArticleStatuses = Notification.Name(rawValue: "AccountDidQueueArticleStatuses")
	/// Posted when `Account.isLibraryReachable` changes — i.e. a paired local server
	/// (non-nil `endpointURL`) went from reachable to unreachable, or vice versa.
	static let AccountLibraryReachabilityDidChange = Notification.Name(rawValue: "AccountLibraryReachabilityDidChange")
}

nonisolated public enum AccountType: Int, Codable, Sendable {
	// Raw values should not change since they’re stored on disk.
	case onMyMac = 1

	public var displayName: String {
		switch self {
		case .onMyMac:
			return NSLocalizedString("account.name.on-my-device", tableName: "DefaultAccountNames", comment: "Local account name, e.g. Collections")
		}
	}
}

public enum FetchType {
    case starred(_: Int? = nil)
	case loved(_: Int? = nil)
	case unread(_: Int? = nil)
	case read(_: Int? = nil)
	case today(_: Int? = nil)
	case lastOpened(_: Int? = nil)
	case folder(Folder, Bool)
	case feed(Feed)
	case articleIDs(Set<String>)
	case search(String)
	case searchWithArticleIDs(String, Set<String>)
}

@MainActor public final class Account: ProgressInfoReporter, DisplayNameProvider, UnreadCountProvider, Container, Hashable {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Account")

    public struct UserInfoKey {
		public static let account = "account" // UserDidAddAccount, UserDidDeleteAccount
		public static let newArticles = "newArticles" // AccountDidDownloadArticles
		public static let updatedArticles = "updatedArticles" // AccountDidDownloadArticles
		public static let statuses = "statuses" // StatusesDidChange
		public static let articles = "articles" // StatusesDidChange
		public static let articleIDs = "articleIDs" // StatusesDidChange, ReadingProgressDidChange
		public static let statusKey = "statusKey" // StatusesDidChange
		public static let statusFlag = "statusFlag" // StatusesDidChange
		public static let feeds = "feeds" // AccountDidDownloadArticles, StatusesDidChange
		public static let syncErrors = "syncErrors" // AccountsDidFailToSyncWithErrors
	}

	public var isDeleted = false

	public var containerID: ContainerIdentifier? {
		ContainerIdentifier.account(accountID)
	}

	public var account: Account? {
		self
	}
	nonisolated public let accountID: String
	public let type: AccountType
	public var nameForDisplay: String {
		guard let name = name, !name.isEmpty else {
			return defaultName
		}
		return name
	}

	public var activityOwner: ActivityOwner {
		.account(accountID: accountID, displayName: nameForDisplay)
	}

	public var name: String? {
		get {
			settings.name
		}
		set {
			let currentNameForDisplay = nameForDisplay
			if newValue != settings.name {
				settings.name = newValue
				if currentNameForDisplay != nameForDisplay {
					postDisplayNameDidChangeNotification()
				}
			}
		}
	}
	public let defaultName: String

	public var isActive: Bool {
		get {
			settings.isActive
		}
		set {
			if newValue != settings.isActive {
				settings.isActive = newValue
				var userInfo = [AnyHashable: Any]()
				userInfo[UserInfoKey.account] = self
				NotificationCenter.default.post(name: .AccountStateDidChange, object: self, userInfo: userInfo)
			}
		}
	}

	public var topLevelFeeds = OrderedSet<Feed>()
	public var folders: OrderedSet<Folder>? = OrderedSet<Folder>()

	public var externalID: String? {
		get {
			settings.externalID
		}
		set {
			settings.externalID = newValue
		}
	}

	public var sortedFolders: [Folder]? {
		if let folders = folders {
			return Array(folders).sorted(by: { $0.nameForDisplay.caseInsensitiveCompare($1.nameForDisplay) == .orderedAscending })
		}
		return nil
	}

	private var feedDictionariesNeedUpdate = true
	private var _idToFeedDictionary = [String: Feed]()
	var idToFeedDictionary: [String: Feed] {
		if feedDictionariesNeedUpdate {
			rebuildFeedDictionaries()
		}
		return _idToFeedDictionary
	}
	private var _externalIDToFeedDictionary = [String: Feed]()
	var externalIDToFeedDictionary: [String: Feed] {
		if feedDictionariesNeedUpdate {
			rebuildFeedDictionaries()
		}
		return _externalIDToFeedDictionary
	}

	var username: String? {
		get {
			settings.username
		}
		set {
			if newValue != settings.username {
				settings.username = newValue
			}
		}
	}

	public var lastArticleFetchStartTime: Date? {
		get {
			settings.lastArticleFetchStartTime
		}
		set {
			settings.lastArticleFetchStartTime = newValue
		}
	}

	public var lastRefreshCompletedDate: Date? {
		get {
			settings.lastRefreshCompletedDate
		}
		set {
			settings.lastRefreshCompletedDate = newValue
		}
	}

	public var endpointURL: URL? {
		get {
			settings.endpointURL
		}
		set {
			if newValue != settings.endpointURL {
				settings.endpointURL = newValue
			}
		}
	}

	/// Whether this account's paired local server (`endpointURL`) was reachable as of
	/// the most recent refresh attempt. Only meaningful when `endpointURL` is non-nil —
	/// a plain local ".onMyMac" account with no server has nothing to be unreachable
	/// from, so this is always `true` in that case. Distinct from a feed-level HTTP
	/// error: this specifically tracks connection-level failures (host asleep, closed,
	/// or otherwise unreachable on the network) versus the server responding at all.
	public var isLibraryReachable: Bool {
		get {
			guard endpointURL != nil else {
				return true
			}
			return settings.isLibraryReachable
		}
		set {
			guard endpointURL != nil else {
				return
			}
			if newValue != settings.isLibraryReachable {
				settings.isLibraryReachable = newValue
				NotificationCenter.default.post(name: .AccountLibraryReachabilityDidChange, object: self)
			}
		}
	}

	private var fetchingAllUnreadCounts = false
	var areUnreadCountsInitialized = false

	public let dataFolder: String
	let database: ArticlesDatabase
	var delegate: AccountDelegate

	private var unreadCounts = [String: Int]() // [feedID: Int]

	private var _flattenedFeeds = Set<Feed>()
	private var flattenedFeedsNeedUpdate = true
	private var flattenedFeedsIDs: Set<String> {
		flattenedFeeds().feedIDs()
	}

	private lazy var opmlFile = OPMLFile(filename: (dataFolder as NSString).appendingPathComponent("Subscriptions.opml"), account: self)
	private let settings: AccountSettings
	private let feedSettingsDatabase: FeedSettingsDatabase
	private typealias FeedSettingsDictionary = [String: FeedSettings]
	private var feedSettingsCache = FeedSettingsDictionary()

    public var unreadCount = 0 {
        didSet {
            if unreadCount != oldValue {
                postUnreadCountDidChangeNotification()
            }
        }
    }

	public var behaviors: AccountBehaviors {
		delegate.behaviors
	}

	public var refreshInProgress = false {
		didSet {
			if refreshInProgress != oldValue {
				if refreshInProgress {
					NotificationCenter.default.post(name: .AccountRefreshDidBegin, object: self)
				} else {
					NotificationCenter.default.post(name: .AccountRefreshDidFinish, object: self)
					opmlFile.markAsDirty()
				}
			}
		}
	}

	public var progressInfo = ProgressInfo() {
		didSet {
			if progressInfo != oldValue {
				postProgressInfoDidChangeNotification()
			}
			refreshInProgress = !progressInfo.isComplete
		}
	}

	init(dataFolder: String, type: AccountType, accountID: String) {
		switch type {
		case .onMyMac:
			self.delegate = LocalAccountDelegate()
		}

		self.accountID = accountID
		self.type = type
		self.dataFolder = dataFolder

		let databaseFilePath = (dataFolder as NSString).appendingPathComponent("DB.sqlite3")
		let retentionStyle: ArticlesDatabase.RetentionStyle = .feedBased
		self.database = ArticlesDatabase(databaseFilePath: databaseFilePath, accountID: accountID, retentionStyle: retentionStyle)

		defaultName = type.displayName

		let feedSettingsDatabasePath = (dataFolder as NSString).appendingPathComponent("FeedSettings.db")
		self.feedSettingsDatabase = FeedSettingsDatabase(databasePath: feedSettingsDatabasePath)

		self.settings = AccountSettings(accountID: accountID, dataFolder: dataFolder)

		NotificationCenter.default.addObserver(self, selector: #selector(progressInfoDidChange(_:)), name: .progressInfoDidChange, object: delegate)
		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(batchUpdateDidPerform(_:)), name: .BatchUpdateDidPerform, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(displayNameDidChange(_:)), name: .DisplayNameDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(childrenDidChange(_:)), name: .ChildrenDidChange, object: nil)

		delegate.accountSettings = settings

		FeedSettingsImporter.importIfNeeded(dataFolder: dataFolder, database: feedSettingsDatabase)
		populateFeedSettingsCache()

		opmlFile.load()
		// Not calling feedSettingsDatabase.deleteSettingsForFeedsNotIn(flattenedFeedURLs)
		// here: feedSettings is keyed by feedURL, and for a paired local-server
		// account (Ambrosia) the URL changes whenever the server's LAN address
		// changes. Purging settings for "currently unsubscribed" URLs on every
		// launch silently discards editedName, cacheControlInfo, lastCheckDate,
		// etc. for feeds that are really just mid-re-pair, not abandoned. The
		// cost of not garbage-collecting stale rows here is a handful of small,
		// harmless leftover settings rows -- not worth the risk of discarding
		// live settings. See feed-repointing.md.

		DispatchQueue.main.async {
			self.database.cleanupDatabaseAtStartup(subscribedToFeedIDs: self.flattenedFeedsIDs)
			self._fetchAllUnreadCounts()
		}

		delegate.account = self
		delegate.accountDidInitialize()
	}

	public func receiveRemoteNotification(userInfo: [AnyHashable: Any]) async {
		await delegate.receiveRemoteNotification(userInfo: userInfo)
	}

	// MARK: - Refreshing

	/// Start a refresh session without waiting or catching errors.
	public func triggerRefreshAll() {
		Task {
			try? await refreshAll()
		}
	}

	public func refreshAll() async throws {
		try await delegate.refreshAll()
	}

	// MARK: - Activity Log

	@discardableResult
	public func logActivity<T>(
		kind: ActivityKind,
		detail: String? = nil,
		successMessage: ((T) -> String?)? = nil,
		durationIsSignificant: ((T) -> Bool)? = nil,
		_ work: () async throws -> T
	) async rethrows -> T {
		try await ActivityLog.shared.logActivity(owner: activityOwner, kind: kind, detail: detail, successMessage: successMessage, durationIsSignificant: durationIsSignificant, work)
	}

	/// Synchronous overload of `logActivity` for non-async work.
	@discardableResult
	public func logActivity<T>(
		kind: ActivityKind,
		detail: String? = nil,
		successMessage: ((T) -> String?)? = nil,
		durationIsSignificant: ((T) -> Bool)? = nil,
		_ work: () throws -> T
	) rethrows -> T {
		try ActivityLog.shared.logActivity(owner: activityOwner, kind: kind, detail: detail, successMessage: successMessage, durationIsSignificant: durationIsSignificant, work)
	}

	// MARK: - Syncing Article Status

	public func sendArticleStatus() async throws {
		try await delegate.sendArticleStatus()
	}

	@discardableResult
	public func syncArticleStatus() async throws -> Bool {
		try await delegate.syncArticleStatus()
	}

	// MARK: - OPML

	public func importOPML(_ opmlFile: URL, completion: @escaping (Result<Void, Error>) -> Void) {
		guard !delegate.isOPMLImportInProgress else {
			completion(.failure(AccountError.opmlImportInProgress))
			return
		}

		Task { @MainActor in
			do {
				try await delegate.importOPML(opmlFile: opmlFile)
				// Reset the last fetch date to get the article history for the added feeds.
				lastArticleFetchStartTime = nil
				try? await delegate.refreshAll()
				completion(.success(()))
			} catch {
				completion(.failure(error))
			}
		}
	}

	// MARK: - Suspend/Resume

	public func suspendNetwork() {
		delegate.suspendNetwork()
	}

	/// Resume network activity for the delegate after a previous `suspendNetwork()`.
	public func resumeDelegate() {
		delegate.resume()
	}

	/// Reload OPML, etc.
	public func resume() {
		_fetchAllUnreadCounts()
	}

	// MARK: - Data

	public func save() {
		MainActor.assumeIsolated {
			opmlFile.save()
		}
	}

	public func prepareForDeletion() {
		delegate.accountWillBeDeleted()
	}

	func deleteSettings() {
		settings.deleteSettings()
	}

	func addOPMLItems(_ items: [OPMLItem]) {
		addOPMLItems(items, into: self, depth: 1)
	}

	/// Recurses into arbitrarily-nested OPML folders, up to `maxDepth`
	/// levels. At the depth cap, a would-be-too-deep folder's contents
	/// are flattened into its would-be-parent instead of being dropped
	/// or creating an illegal depth-4+ folder -- see `flattenIntoContainer`.
	private func addOPMLItems(_ items: [OPMLItem], into container: Container, depth: Int) {
		let maxDepth = 3
		for item in items {
			if let feedSpecifier = item.feedSpecifier {
				container.addFeedToTreeAtTopLevel(newFeed(with: feedSpecifier))
				continue
			}
			guard let title = item.titleFromAttributes else {
				continue
			}
			guard let folder = container.ensureChildFolder(named: title) else {
				continue
			}
			folder.externalID = item.attributes?["nnw_externalID"]
			guard let itemChildren = item.children else {
				continue
			}
			if depth >= maxDepth {
				flattenIntoContainer(itemChildren, container: folder)
			} else {
				addOPMLItems(itemChildren, into: folder, depth: depth + 1)
			}
		}
	}

	/// Used once the depth cap (`maxDepth` in `addOPMLItems(_:into:depth:)`)
	/// is reached: recurses through any further folder-shaped items
	/// without creating them, so their feeds still land in `container`
	/// instead of being silently lost.
	private func flattenIntoContainer(_ items: [OPMLItem], container: Container) {
		for item in items {
			if let feedSpecifier = item.feedSpecifier {
				container.addFeedToTreeAtTopLevel(newFeed(with: feedSpecifier))
			} else if let itemChildren = item.children {
				flattenIntoContainer(itemChildren, container: container)
			}
		}
	}

	func loadOPMLItems(_ items: [OPMLItem]) {
		addOPMLItems(OPMLNormalizer.normalize(items))
	}

	public func markArticles(articleIDs: Set<String>, statusKey: ArticleStatus.Key, flag: Bool) async throws {
		try await delegate.markArticles(articleIDs: articleIDs, statusKey: statusKey, flag: flag)
	}

	func existingContainer(withExternalID externalID: String) -> Container? {
		guard self.externalID != externalID else {
			return self
		}
		return existingFolder(withExternalID: externalID)
	}

	/// Every container (this account, plus any folder or subfolder at
	/// any depth) that directly holds `feed` at its own top level.
	public func existingContainers(withFeed feed: Feed) -> [Container] {
		var containers = [Container]()
		if topLevelFeeds.contains(feed) {
			containers.append(self)
		}
		if let folders {
			for folder in folders {
				containers.append(contentsOf: folder.existingContainers(withFeed: feed))
			}
		}
		return containers
	}

	@discardableResult
	func ensureFolder(with name: String) -> Folder? {
		return ensureChildFolder(named: name)
	}

	/// Walks/creates a chain of folders nested up to `folderNames.count`
	/// levels deep, starting at this account's top level. Nesting depth
	/// is capped at 3: a path longer than 3 names is truncated to its
	/// first 3 segments, and the returned depth-3 folder is where a
	/// caller (e.g. OPML import) should attach anything that would
	/// otherwise have gone deeper -- this truncation is what makes
	/// "flatten into the depth-3 folder" the natural behavior for an
	/// over-deep path, with no separate flattening logic needed here.
	public func ensureFolder(withFolderNames folderNames: [String]) -> Folder? {
		guard !folderNames.isEmpty else {
			return nil
		}

		let maxDepth = 3
		let effectiveNames = folderNames.count > maxDepth ? Array(folderNames.prefix(maxDepth)) : folderNames

		var container: Container = self
		for name in effectiveNames {
			guard let next = container.ensureChildFolder(named: name) else {
				return nil
			}
			container = next
		}
		return container as? Folder
	}

	public func existingFolder(withDisplayName displayName: String) -> Folder? {
		return folders?.first(where: { $0.nameForDisplay == displayName })
	}

	public func existingFolder(withExternalID externalID: String) -> Folder? {
		return folders?.first(where: { $0.externalID == externalID })
	}

	func newFeed(with opmlFeedSpecifier: OPMLFeedSpecifier) -> Feed {
		let feedURL = opmlFeedSpecifier.feedURL
		let settings = feedSettings(feedURL: feedURL, feedID: feedURL)
		let feed = Feed(account: self, url: opmlFeedSpecifier.feedURL, settings: settings)
		if let feedTitle = opmlFeedSpecifier.title {
			if feed.name == nil {
				feed.name = feedTitle
			}
		}
		return feed
	}

	func addFeed(_ feed: Feed, container: Container) async throws {
		try await delegate.addFeed(feed: feed, container: container)
	}

	public func addFeed(_ feed: Feed, to container: Container, completion: @escaping (Result<Void, Error>) -> Void) {
		Task { @MainActor in
			do {
				try await delegate.addFeed(feed: feed, container: container)
				completion(.success(()))
			} catch {
				completion(.failure(error))
			}
		}
	}

	public func createFeed(url: String, name: String?, container: Container, validateFeed: Bool, completion: @escaping (Result<Feed, Error>) -> Void) {
		Task { @MainActor in
			do {
				let feed = try await delegate.createFeed(url: url, name: name, container: container, validateFeed: validateFeed)
				completion(.success(feed))
			} catch {
				completion(.failure(error))
			}
		}
	}

	func createFeed(with name: String?, url: String, feedID: String, homePageURL: String?) -> Feed {
		let settings = feedSettings(feedURL: url, feedID: feedID)
		let feed = Feed(account: self, url: url, settings: settings)
		feed.name = name
		feed.homePageURL = homePageURL
		return feed
	}

	/// The `nectar-import:` scheme used for the one-time pasted-AO3-link-list
	/// import feed's synthetic URL -- see `importPastedAO3Links(_:)` below and
	/// `LocalAccountRefresher.feedShouldBeSkippedForDisallowedHostReasons`,
	/// which permanently excludes this scheme from every refresh pass. Unlike
	/// every other feed in this codebase, this feed has no real server to
	/// fetch from -- its articles are written directly via `updateAsync`,
	/// never through `LocalAccountRefresher`/`DownloadSession`.
	static let importedLinksFeedURL = "nectar-import://pasted-ao3-links"

	/// Scans `pastedText` for AO3 work links (known-host allowlist, work id
	/// via the existing `AO3SummaryExtractor.ao3WorkID(fromPermalink:)`,
	/// deduped within the paste) and adds each as a bare-link article under a
	/// single reused "Imported Links" feed -- created on first use, top-level.
	/// No live AO3 fetch: articles are titled from their work id only, until
	/// the person opens one and the existing AO3ChapterFetcher path takes
	/// over. Returns the number of new links added (0 if none were
	/// recognized or all were already imported previously -- `updateAsync`'s
	/// `deleteOlder: false` plus this feed's stable feedID means a repeat
	/// paste of the same link is a no-op at the database level, not just
	/// within a single paste).
	@discardableResult
	public func importPastedAO3Links(_ pastedText: String) async -> Int {
		let links = AO3LinkListImporter.importedLinks(fromPastedText: pastedText)
		guard !links.isEmpty else {
			return 0
		}

		let feed: Feed
		if let existing = existingFeed(withURL: Self.importedLinksFeedURL) {
			feed = existing
		} else {
			feed = createFeed(with: NSLocalizedString("Imported Links", comment: "Pasted AO3 link-list import feed name"), url: Self.importedLinksFeedURL, feedID: Self.importedLinksFeedURL, homePageURL: nil)
			addFeedToTreeAtTopLevel(feed)
		}

		let parsedItems = Set(links.map { link in
			ParsedItem(syncServiceID: nil,
			           uniqueID: link.ao3WorkID,
			           feedURL: Self.importedLinksFeedURL,
			           url: link.permalink,
			           externalURL: nil,
			           title: String(format: NSLocalizedString("AO3 Work %@", comment: "Imported-link placeholder title, before the work is opened and its real title fetched"), link.ao3WorkID),
			           language: nil,
			           contentHTML: nil,
			           contentText: nil,
			           markdown: nil,
			           summary: nil,
			           imageURL: nil,
			           bannerImageURL: nil,
			           datePublished: nil,
			           dateModified: nil,
			           authors: nil,
			           tags: nil,
			           attachments: nil,
			           ao3WorkID: link.ao3WorkID)
		})

		let articleChanges = await updateAsync(feedID: feed.feedID, parsedItems: parsedItems, deleteOlder: false)
		return articleChanges.new?.count ?? 0
	}

	func clearFeedSettings(_ feed: Feed) {
		// Call before permanently removing a feed so the next feed created at this URL
		// doesn’t inherit a stale feedID/externalID from the cache or database.
		feedSettingsCache[feed.url] = nil
		feedSettingsDatabase.deleteSettings(for: feed.url)
	}

	/// Repoints `feed`'s fetch address to `newURLString`, keeping its `feedID`
	/// (and therefore its articles, statuses, and bookReadState rows) unchanged.
	/// Used to fix the LAN-IP-changed Ambrosia re-pair case in place instead of
	/// creating a duplicate feed and merging into it.
	func repointFeed(_ feed: Feed, to newURLString: String) {
		let oldURLString = feed.url
		guard oldURLString != newURLString else {
			return
		}

		feedSettingsDatabase.repointFeedURL(from: oldURLString, to: newURLString)
		feedSettingsCache[oldURLString] = nil

		feed.repoint(to: newURLString)
		feed.settings = feedSettings(feedURL: newURLString, feedID: feed.feedID)
	}

	public func removeFeed(_ feed: Feed, from container: Container, completion: @escaping (Result<Void, Error>) -> Void) {
		Task { @MainActor in
			do {
				try await delegate.removeFeed(feed: feed, container: container)
				completion(.success(()))
			} catch {
				completion(.failure(error))
			}
		}
	}

	public func moveFeed(_ feed: Feed, from: Container, to: Container, targetIndex: Int?, completion: @escaping (Result<Void, Error>) -> Void) {
		Task { @MainActor in
			do {
				try await delegate.moveFeed(feed: feed, sourceContainer: from, destinationContainer: to, targetIndex: targetIndex)
				completion(.success(()))
			} catch {
				completion(.failure(error))
			}
		}
	}

	public func moveFolder(_ folder: Folder, from: Container, to: Container, targetIndex: Int?, completion: @escaping (Result<Void, Error>) -> Void) {
		Task { @MainActor in
			do {
				try await delegate.moveFolder(folder: folder, sourceContainer: from, destinationContainer: to, targetIndex: targetIndex)
				completion(.success(()))
			} catch {
				completion(.failure(error))
			}
		}
	}

	public func renameFeed(_ feed: Feed, name: String) async throws {
		try await delegate.renameFeed(with: feed, to: name)
	}

	public func restoreFeed(_ feed: Feed, container: Container, completion: @escaping (Result<Void, Error>) -> Void) {
		Task { @MainActor in
			do {
				try await delegate.restoreFeed(feed: feed, container: container)
				completion(.success(()))
			} catch {
				completion(.failure(error))
			}
		}
	}

	@discardableResult
	public func addFolder(_ name: String) async throws -> Folder {
		try await delegate.createFolder(name: name)
	}

	public func removeFolder(_ folder: Folder, completion: @escaping (Result<Void, Error>) -> Void) {
		Task { @MainActor in
			do {
				try await delegate.removeFolder(with: folder)
				completion(.success(()))
			} catch {
				completion(.failure(error))
			}
		}
	}

	public func renameFolder(_ folder: Folder, to name: String) async throws {
		try await delegate.renameFolder(with: folder, to: name)
	}

	public func restoreFolder(_ folder: Folder, completion: @escaping (Result<Void, Error>) -> Void) {
		Task { @MainActor in
			do {
				try await delegate.restoreFolder(folder: folder)
				completion(.success(()))
			} catch {
				completion(.failure(error))
			}
		}
	}

	public func addFolderToTree(_ folder: Folder, at index: Int?) {
		if let index {
			folders!.insert(folder, at: index)
		} else {
			folders!.insert(folder)
		}
		folder.parent = self
		postChildrenDidChangeNotification()
		structureDidChange()
	}

	/// Reorder a folder that already lives directly under this account
	/// to a new index within this account's own folder order. Not for
	/// moving a folder between different containers -- see
	/// `moveFolder(_:from:to:targetIndex:completion:)` for that.
	func reorderFolder(_ folder: Folder, toIndex index: Int) {
		folders!.remove(folder)
		addFolderToTree(folder, at: index)
	}

	public func updateUnreadCounts(feeds: Set<Feed>) {
		_fetchUnreadCounts(feeds: feeds)
	}

	// MARK: - Fetching Articles

	/// Task 4 (SQLite export): pass-through to ArticlesDatabase.exportArticlesSQLite.
	/// `feedIDs` nil/empty exports every article in this account; a non-empty
	/// set scopes the export to those feeds only. `destinationPath` must not
	/// already exist.
	public func exportArticlesSQLite(feedIDs: Set<String>? = nil, toPath destinationPath: String) throws {
		try database.exportArticlesSQLite(feedIDs: feedIDs, toPath: destinationPath)
	}

	/// Backup/restore: pass-through to ArticlesDatabase.exportFullSnapshot,
	/// needed because `database` itself is internal to this module.
	/// Unlike `exportArticlesSQLite` above, this is the *entire* database
	/// -- articles, statuses, bookState, annotations, and the FTS `search`
	/// table -- suitable for a full restore rather than the per-feed
	/// "Export..." feature. `destinationPath` must not already exist.
	public func exportFullSnapshot(toPath destinationPath: String) throws {
		try database.exportFullSnapshot(toPath: destinationPath)
	}

	/// Backup/restore: pass-through to
	/// ArticlesDatabase.importBackupSnapshot(backupDatabasePath:) -- the
	/// non-destructive articles/statuses/bookState/annotations merge, same
	/// reasoning as exportFullSnapshot above (`database` is internal to this
	/// module, so BackupManager can't call it directly).
	public func importBackupSnapshot(backupDatabasePath: String) throws {
		try database.importBackupSnapshot(backupDatabasePath: backupDatabasePath)
	}

	/// Backup/restore: pass-through to
	/// FeedSettingsDatabase.mergeFromBackup(atPath:) -- `INSERT OR IGNORE`
	/// keyed on feedURL, keep-local-backfill-missing (Correction 6). Same
	/// "internal type, needs a public entry point" reasoning as the two
	/// methods above.
	public func mergeFeedSettings(fromBackupAtPath backupPath: String) async throws {
		try await feedSettingsDatabase.mergeFromBackup(atPath: backupPath)
	}

	public func fetchArticles(_ fetchType: FetchType) -> Set<Article> {
		switch fetchType {
		case .starred(let limit):
			return _fetchStarredArticles(limit: limit)
		case .loved(let limit):
			return _fetchLovedArticles(limit: limit)
		case .unread(let limit):
			return _fetchUnreadArticles(limit: limit)
		case .read(let limit):
			return _fetchReadArticles(limit: limit)
		case .today(let limit):
			return _fetchTodayArticles(limit: limit)
		case .lastOpened(let limit):
			return _fetchLastOpenedArticles(limit: limit)
		case .folder(let folder, let readFilter):
			if readFilter {
				return _fetchUnreadArticles(container: folder)
			} else {
				return _fetchArticles(container: folder)
			}
		case .feed(let feed):
			return _fetchArticles(feed: feed)
		case .articleIDs(let articleIDs):
			return _fetchArticles(articleIDs: articleIDs)
		case .search(let searchString):
			return _fetchArticlesMatching(searchString: searchString)
		case .searchWithArticleIDs(let searchString, let articleIDs):
			return _fetchArticlesMatchingWithArticleIDs(searchString: searchString, articleIDs: articleIDs)
		}
	}

	public func fetchArticlesAsync(_ fetchType: FetchType) async -> Set<Article> {
		switch fetchType {
		case .starred(let limit):
			return await _fetchStarredArticlesAsync(limit: limit)
		case .loved(let limit):
			return await _fetchLovedArticlesAsync(limit: limit)
		case .unread(let limit):
			return await _fetchUnreadArticlesAsync(limit: limit)
		case .read(let limit):
			return await _fetchReadArticlesAsync(limit: limit)
		case .today(let limit):
			return await _fetchTodayArticlesAsync(limit: limit)
		case .lastOpened(let limit):
			return await _fetchLastOpenedArticlesAsync(limit: limit)
		case .folder(let folder, let readFilter):
			if readFilter {
				return await _fetchUnreadArticlesAsync(container: folder)
			} else {
				return await _fetchArticlesAsync(container: folder)
			}
		case .feed(let feed):
			return await _fetchArticlesAsync(feed: feed)
		case .articleIDs(let articleIDs):
			return await _fetchArticlesAsync(articleIDs: articleIDs)
		case .search(let searchString):
			return await _fetchArticlesMatchingAsync(searchString: searchString)
		case .searchWithArticleIDs(let searchString, let articleIDs):
			return await _fetchArticlesMatchingWithArticleIDsAsync(searchString: searchString, articleIDs: articleIDs)
		}
	}

	/// Account-wide, no feed/folder scoping -- deliberately not a
	/// `FetchType` case: every existing case is a feed/folder/status
	/// view a person can actually navigate to, while this is a narrower,
	/// AO3-specific identity lookup ("does this work exist anywhere in
	/// the account") with a single caller
	/// (`AO3SeriesNavigator`'s cross-feed stub reuse). Pass-through to
	/// `ArticlesDatabase.fetchArticlesAsync(bookKeys:)` -- see that
	/// method's own doc comment for why the plain `bookKey in (...)`
	/// match (no pre-migration uniqueID fallback) is safe for this
	/// caller specifically.
	public func fetchArticlesAsync(bookKeys: Set<String>) async -> Set<Article> {
		await database.fetchArticlesAsync(bookKeys: bookKeys)
	}

	public func fetchUnreadCountForStarredArticlesAsync() async -> Int {
		await database.fetchUnreadCountForStarredArticlesAsync(feedIDs: flattenedFeedsIDs)
	}

	public func fetchUnreadCountForLovedArticlesAsync() async -> Int {
		await database.fetchUnreadCountForLovedArticlesAsync(feedIDs: flattenedFeedsIDs)
	}

	public func fetchCountForStarredArticles() -> Int {
		database.fetchStarredArticlesCount(feedIDs: flattenedFeedsIDs)
	}

	public func fetchCountForLovedArticles() -> Int {
		database.fetchLovedArticlesCount(feedIDs: flattenedFeedsIDs)
	}

	public func fetchCountForReadArticles() -> Int {
		database.fetchReadArticlesCount(feedIDs: flattenedFeedsIDs)
	}

	public func fetchArticleCountsAsync() async -> ArticleCounts {
		await database.fetchArticleCountsAsync(feedIDs: flattenedFeedsIDs)
	}

	/// Largest-N articles by stored `contentHTML` size, for the Manage
	/// Storage screen.
	public func fetchArticleStorageInfo(limit: Int) async -> [ArticleStorageInfo] {
		await database.fetchArticleStorageInfo(limit: limit)
	}

	/// Total stored `contentHTML` size across all of this account's
	/// articles, for the Manage Storage screen's total-size figure.
	public func fetchTotalContentHTMLSize() async -> Int {
		await database.fetchTotalContentHTMLSize()
	}

	// MARK: - Kudos-on-like (Task 6)

	/// Whether/how a kudos POST has already been attempted for this book.
	/// See ArticlesDatabase.kudosAttempt(bookKey:) for the re-attempt policy.
	public func kudosAttempt(bookKey: String) async -> (attemptedAt: Date, authenticated: Bool)? {
		await database.kudosAttempt(bookKey: bookKey)
	}

	/// Records that a kudos POST was attempted for this book.
	public func setKudosAttempted(bookKey: String, authenticated: Bool) async {
		await database.setKudosAttempted(bookKey: bookKey, authenticated: authenticated)
	}

	/// Returns a dictionary of feedID → latest article date for all feeds with articles.
	public func fetchLastUpdateDates() async -> [String: Date] {
		await database.fetchLastUpdateDates()
	}

	public func fetchUnreadCountForTodayAsync() async -> Int {
		await database.fetchUnreadCountForTodayAsync(feedIDs: flattenedFeedsIDs)
	}

	public func fetchCountForTodayArticlesAsync() async -> Int {
		await database.fetchTodayArticlesCountAsync(feedIDs: flattenedFeedsIDs)
	}

	public func fetchCountForStarredArticlesAsync() async -> Int {
		await database.fetchStarredArticlesCountAsync(feedIDs: flattenedFeedsIDs)
	}

	public func fetchCountForLovedArticlesAsync() async -> Int {
		await database.fetchLovedArticlesCountAsync(feedIDs: flattenedFeedsIDs)
	}

	public func fetchCountForReadArticlesAsync() async -> Int {
		await database.fetchReadArticlesCountAsync(feedIDs: flattenedFeedsIDs)
	}

	public func fetchUnreadArticleIDsAsync() async -> Set<String> {
		await database.fetchUnreadArticleIDsAsync()
	}

	public func fetchStarredArticleIDsAsync() async -> Set<String> {
		await database.fetchStarredArticleIDsAsync()
	}

	public func fetchLovedArticleIDsAsync() async -> Set<String> {
		await database.fetchLovedArticleIDsAsync()
	}

	/// Fetch articleIDs for articles that we should have, but don’t. These articles are either (starred) or (newer than the article cutoff date).
	public func fetchArticleIDsForStatusesWithoutArticlesNewerThanCutoffDateAsync() async -> Set<String> {
		await database.fetchArticleIDsForStatusesWithoutArticlesNewerThanCutoffDateAsync()
	}

	// MARK: - Unread Counts
	public func unreadCount(for feed: Feed) -> Int {
		unreadCounts[feed.feedID] ?? 0
	}

	public func setUnreadCount(_ unreadCount: Int, for feed: Feed) {
		unreadCounts[feed.feedID] = unreadCount
	}

	public func structureDidChange() {
		// Feeds were added or deleted. Or folders added or deleted.
		// Or feeds inside folders were added or deleted.
		opmlFile.markAsDirty()
		flattenedFeedsNeedUpdate = true
		feedDictionariesNeedUpdate = true
	}

	// MARK: - Updating Feeds

	/// - Parameter isPartial: true if `parsedFeed` is known to be an incomplete
	///   fetch (for example, one page of a paginated JSON Feed failed to load).
	///   When true, `deleteOlder` pruning is skipped for this refresh -- an
	///   item missing only because its page failed to fetch must not be
	///   mistaken for an item the server actually removed from the feed.
	@discardableResult
	func updateAsync(feed: Feed, parsedFeed: ParsedFeed, isPartial: Bool = false) async -> ArticleChanges {
		precondition(Thread.isMainThread)

		feed.takeSettings(from: parsedFeed)
		let parsedItems = parsedFeed.items
		guard !parsedItems.isEmpty else {
			return ArticleChanges()
		}

		return await updateAsync(feedID: feed.feedID, parsedItems: parsedItems, deleteOlder: !isPartial)
	}

	func updateAsync(feedID: String, parsedItems: Set<ParsedItem>, deleteOlder: Bool = true) async -> ArticleChanges {
		precondition(Thread.isMainThread)

		// AmbrosiaAO3NetworkPreference.updatesEnabled ("fetch AO3
		// updates") gates whether Nectar makes a *live request to AO3's
		// servers* -- it's not a display filter over metadata already in
		// hand. A feed refresh here is never an AO3 request itself (the
		// feed came from Ambrosia's own LocalFeedServer, or from an
		// AO3-native RSS/Atom/search-results source that this preference
		// doesn't gate at all -- see AmbrosiaAO3NetworkPreference's own
		// doc comment and AO3ChapterFetcher.isAO3NetworkRequestAllowed),
		// so there is no request here to withhold, and stripping
		// comment/kudos/bookmark/hit counts the feed already sent us
		// doesn't stop any traffic -- it only hides data Nectar already
		// downloaded. Previously this stripped those four fields from
		// Ambrosia-sourced items whenever the toggle was off (Task 8
		// audit, finding #3); reverted, since that contradicted the
		// toggle's actual purpose and, on top of that, only ever applied
		// to isAmbrosiaItem items -- AO3-search-results-sourced items
		// (isAmbrosiaItem: false) were never covered by it either way,
		// so the old behavior was inconsistent across sources on top of
		// being the wrong behavior for the ones it did cover.
		let articleChanges = await database.updateAsync(parsedItems: parsedItems, feedID: feedID, deleteOlder: deleteOlder)
		sendNotificationAbout(articleChanges)
		return articleChanges
	}

	/// Mark statuses for articleIDs. Returns the articleIDs whose status actually changed.
	@discardableResult
	func updateStatusesAsync(articleIDs: Set<String>, statusKey: ArticleStatus.Key, flag: Bool) async -> Set<String> {
		guard !articleIDs.isEmpty else {
			return Set<String>()
		}

		let changedArticleIDs = await database.markAsync(articleIDs: articleIDs, statusKey: statusKey, flag: flag)
		guard !changedArticleIDs.isEmpty else {
			return Set<String>()
		}
		noteStatusesForArticleIDsDidChange(articleIDs: changedArticleIDs, statusKey: statusKey, flag: flag)

		return changedArticleIDs
	}

	// MARK: - Article Statuses

	/// Make sure statuses exist. Any existing statuses won’t be touched.
	/// All created statuses will be marked as read and not starred.
	/// Sends a .StatusesDidChange notification.
	func createStatusesIfNeededAsync(articleIDs: Set<String>) async {
		guard !articleIDs.isEmpty else {
			return
		}
		await database.createStatusesIfNeededAsync(articleIDs: articleIDs)
		noteStatusesForArticleIDsDidChange(articleIDs)
	}

	/// Mark articleIDs statuses based on statusKey and flag.
	///
	/// Will create statuses in the database and in memory as needed. Sends a .StatusesDidChange notification.
	/// Returns a set of new article statuses.
	func markAndFetchNewAsync(articleIDs: Set<String>, statusKey: ArticleStatus.Key, flag: Bool) async -> Set<String> {
		guard !articleIDs.isEmpty else {
			return Set<String>()
		}

		let newArticleStatusIDs = await database.markAndFetchNewAsync(articleIDs: articleIDs, statusKey: statusKey, flag: flag)
		noteStatusesForArticleIDsDidChange(articleIDs: articleIDs, statusKey: statusKey, flag: flag)
		return newArticleStatusIDs
	}

	/// Mark articleIDs as read.
	///
	/// - Returns: Set of new article statuses.
	/// Will create statuses in the database and in memory as needed. Sends a .StatusesDidChange notification.
	@discardableResult
	func markAsReadAsync(articleIDs: Set<String>) async -> Set<String> {
		await markAndFetchNewAsync(articleIDs: articleIDs, statusKey: .read, flag: true)
	}

	// MARK: - Scroll Position (Phase 2)

	/// Per-article scroll position (raw window.scrollY pixel value, same convention as
	/// windowScrollY). Local UI state only -- unlike read/starred, it isn't part of the
	/// syncable ArticleStatus.Key set and doesn't send a .StatusesDidChange notification.
	public func saveScrollPosition(_ scrollPosition: Double, forArticleID articleID: String) async {
		await database.saveScrollPositionAsync(scrollPosition, articleID: articleID)
	}

	public func fetchScrollPosition(forArticleID articleID: String) async -> Double {
		await database.fetchScrollPositionAsync(articleID: articleID)
	}

	// MARK: - Annotations (highlights + notes)

	public func saveAnnotation(_ annotation: Annotation) async {
		await database.saveAnnotation(annotation)
	}

	public func deleteAnnotation(annotationID: String) async {
		await database.deleteAnnotation(annotationID: annotationID)
	}

	public func updateAnnotationNote(annotationID: String, note: String?) async {
		await database.updateAnnotationNote(annotationID: annotationID, note: note)
	}

	public func updateAnnotationColor(annotationID: String, color: Annotation.Color) async {
		await database.updateAnnotationColor(annotationID: annotationID, color: color)
	}

	public func markAnnotationOrphaned(annotationID: String, at date: Date) async {
		await database.markAnnotationOrphaned(annotationID: annotationID, at: date)
	}

	public func reanchorAnnotation(annotationID: String, startOffset: Int, endOffset: Int, quoteExact: String, quotePrefix: String, quoteSuffix: String, chapterTitle: String?) async {
		await database.reanchorAnnotation(annotationID: annotationID, startOffset: startOffset, endOffset: endOffset, quoteExact: quoteExact, quotePrefix: quotePrefix, quoteSuffix: quoteSuffix, chapterTitle: chapterTitle)
	}

	public func fetchAnnotations(forArticleID articleID: String) async -> [Annotation] {
		await database.fetchAnnotations(articleID: articleID)
	}

	/// Cross-chapter listing: every annotation for every article sharing this bookKey.
	public func fetchAnnotations(forBookKey bookKey: String) async -> [Annotation] {
		await database.fetchAnnotations(bookKey: bookKey)
	}

	/// Every annotation in this account, unscoped.
	public func fetchAllAnnotations() async -> [Annotation] {
		await database.fetchAllAnnotations()
	}

	// MARK: - Pending content update (Task 8: content archival & destructive-update protection)

	/// Stashes a freshly fetched contentHTML as a pending update instead of
	/// writing it straight to contentHTML -- called by
	/// AO3ChapterFetcher.download when its regression guard flags the fetch
	/// as a likely destructive edit. See ArticlesTable.setPendingContentUpdate.
	public func setPendingContentUpdateAsync(_ contentHTML: String, forArticleID articleID: String) async {
		await database.setPendingContentUpdateAsync(contentHTML, detectedAt: Date(), articleID: articleID)
	}

	/// Resolves an article's pending content update: `accept == true`
	/// promotes the pending copy to contentHTML, `accept == false` discards
	/// it. Either way clears the pending slot, unblocking
	/// AO3ChapterFetcher.isStale's auto-fetch gate for this article again.
	public func resolvePendingContentUpdateAsync(forArticleID articleID: String, accept: Bool) async {
		await database.resolvePendingContentUpdateAsync(articleID: articleID, accept: accept)
	}

	// MARK: - AO3 confirmed-missing

	/// Marks an article's AO3 work as confirmed gone -- called by
	/// AO3ChapterFetcher.download once both anonymous and authenticated
	/// retry have exhausted with a `.notFound` response. See
	/// ArticlesTable.setAO3ConfirmedMissing.
	public func setAO3ConfirmedMissingAsync(forArticleID articleID: String) async {
		await database.setAO3ConfirmedMissingAsync(articleID: articleID)
	}

	/// Clears a previously-set confirmed-missing flag -- called on a
	/// successful fetch (author restored the work, or an earlier gate was a
	/// false positive), unblocking AO3ChapterFetcher.isStale's auto-fetch
	/// gate for this article again.
	public func clearAO3ConfirmedMissingAsync(forArticleID articleID: String) async {
		await database.clearAO3ConfirmedMissingAsync(articleID: articleID)
	}

	// MARK: - Last Opened (Last Opened smart feed)

	/// Records that this book was just opened into the reader. bookKey-keyed and
	/// shared across every duplicate copy, same as read/starred/loved/
	/// scrollPosition -- opening any copy bumps the whole book. Does not send
	/// .StatusesDidChange (see StatusesTable.setLastOpenedAt); SceneCoordinator
	/// is responsible for deciding *whether* to call this at all (see
	/// currentArticle's didSet) so that opening a book from the Last Opened feed
	/// itself doesn't reorder that feed.
	public func recordBookOpened(articleID: String) async {
		await database.recordBookOpenedAsync(articleID: articleID)
	}

	// MARK: - Reading Progress (Phase A1)

	/// Fraction (0...1) of the article read. Local UI state, same treatment as scroll
	/// position -- not part of the syncable ArticleStatus.Key set, so it does not send
	/// a .StatusesDidChange notification (that would also fire unrelated observers, like
	/// SceneCoordinator's unread-count recompute, on every scroll tick). It's mirrored
	/// onto the cached ArticleStatus for the article (see StatusesTable.saveReadingProgress),
	/// so the timeline can read it synchronously via `article.status.readingProgress` --
	/// but reading it synchronously into the model isn't enough on its own, since the
	/// timeline's collection view only redraws a cell when told to. Post a dedicated,
	/// lighter-weight .ReadingProgressDidChange notification so the timeline knows to
	/// refresh the affected row(s) -- as of the bookKey write-through below, that can be
	/// more than one articleID when the same book appears via more than one feed.
	public func saveReadingProgress(_ readingProgress: Double, forArticleID articleID: String) async {
		let changedArticleIDs = await database.saveReadingProgressAsync(readingProgress, articleID: articleID)
		NotificationCenter.default.post(name: .ReadingProgressDidChange, object: self, userInfo: [UserInfoKey.articleIDs: changedArticleIDs])
	}

	/// Mark articleIDs as unread.
	/// - Returns: Set of new article statuses.
	/// Will create statuses in the database and in memory as needed. Sends a .StatusesDidChange notification.
	@discardableResult
	func markAsUnreadAsync(articleIDs: Set<String>) async -> Set<String> {
		await markAndFetchNewAsync(articleIDs: articleIDs, statusKey: .read, flag: false)
	}

	/// Mark articleIDs as starred.
	/// - Returns: Set of new article statuses.
	/// Will create statuses in the database and in memory as needed. Sends a .StatusesDidChange notification.
	@discardableResult
	func markAsStarredAsync(articleIDs: Set<String>) async -> Set<String> {
		await markAndFetchNewAsync(articleIDs: articleIDs, statusKey: .starred, flag: true)
	}

	/// Mark articleIDs as unstarred.
	/// - Returns: Set of new article statuses.
	/// Will create statuses in the database and in memory as needed. Sends a .StatusesDidChange notification.
	@discardableResult
	func markAsUnstarredAsync(articleIDs: Set<String>) async -> Set<String> {
		await markAndFetchNewAsync(articleIDs: articleIDs, statusKey: .starred, flag: false)
	}

	// Delete the articles associated with the given set of articleIDs.
	// Public: the Manage Storage screen (iOS/Settings) is, as of that
	// screen's addition, the first app-UI caller of this -- previously only
	// called from within the Account module itself.
	public func delete(articleIDs: Set<String>) async {
		guard !articleIDs.isEmpty else {
			return
		}
		await database.deleteAsync(articleIDs: articleIDs)
	}

	/// Clear the given articles' content -- title, tags, status, bookKey,
	/// and every other Ambrosia metadata field stay intact, only content and
	/// content-dependent staged state are cleared. This is the Manage
	/// Storage screen's "Clear Content" action, which used to call
	/// `delete(articleIDs:)` above and silently lose the article's metadata
	/// along with its content -- see ArticlesTable.clearContentHTML's doc
	/// comment.
	public func clearContent(articleIDs: Set<String>) async {
		guard !articleIDs.isEmpty else {
			return
		}
		await database.clearContentHTMLAsync(articleIDs: articleIDs)
	}

	/// Empty caches that can reasonably be emptied. Call when the app goes in the background, for instance.
	func emptyCaches() {
		database.emptyCaches()
	}

	// MARK: - Container

	public func flattenedFeeds() -> Set<Feed> {
		assert(Thread.isMainThread)
		if flattenedFeedsNeedUpdate {
			updateFlattenedFeeds()
		}
		return _flattenedFeeds
	}

	public func removeFeedFromTreeAtTopLevel(_ feed: Feed) {
		topLevelFeeds.remove(feed)
		structureDidChange()
		postChildrenDidChangeNotification()
	}

	public func removeAllInstancesOfFeedFromTreeAtAllLevels(_ feed: Feed) {
		topLevelFeeds.remove(feed)

		if let folders {
			for folder in folders {
				folder.removeFeedFromTreeAtTopLevel(feed)
			}
		}

		structureDidChange()
		postChildrenDidChangeNotification()
	}

	public func removeFeedsFromTreeAtTopLevel(_ feeds: Set<Feed>) {
		guard !feeds.isEmpty else {
			return
		}
		topLevelFeeds.subtract(feeds)
		structureDidChange()
		postChildrenDidChangeNotification()
	}

	public func addFeedToTreeAtTopLevel(_ feed: Feed, at index: Int?) {
		if let index {
			topLevelFeeds.insert(feed, at: index)
		} else {
			topLevelFeeds.insert(feed)
		}
		structureDidChange()
		postChildrenDidChangeNotification()
	}

	func addFeedIfNotInAnyFolder(_ feed: Feed) {
		if !flattenedFeeds().contains(feed) {
			addFeedToTreeAtTopLevel(feed)
		}
	}

	/// Remove the folder from this account. Does not call delegate.
	public func removeFolderFromTree(_ folder: Folder) {
		folders?.remove(folder)
		structureDidChange()
		postChildrenDidChangeNotification()
	}

	// MARK: - Vacuum

	public func vacuumDatabases() async {
		await logActivity(kind: .vacuumDatabase, detail: AppConfig.relativeDataPath(database.databasePath)) {
			await database.vacuum()
		}
		await logActivity(kind: .vacuumDatabase, detail: AppConfig.relativeDataPath(feedSettingsDatabase.databasePath)) {
			await feedSettingsDatabase.vacuum()
		}
		await delegate.vacuumDatabases()
	}

	public func debugDropConditionalGetInfo() {
#if DEBUG
		for feed in flattenedFeeds() {
			feed.dropConditionalGetInfo()
		}
#endif
	}

	public func debugRunSearch() {
		#if DEBUG
		let t1 = Date()
		let articles = _fetchArticlesMatching(searchString: "Brent NetNewsWire")
		let t2 = Date()
		print(t2.timeIntervalSince(t1))
		print(articles.count)
		#endif
	}

	// MARK: - Notifications

	@objc func progressInfoDidChange(_ note: Notification) {
		progressInfo = delegate.progressInfo
	}

	@objc func unreadCountDidChange(_ note: Notification) {
		if let feed = note.object as? Feed, feed.account === self {
			updateUnreadCount()
		}
	}

    @objc func batchUpdateDidPerform(_ note: Notification) {
		flattenedFeedsNeedUpdate = true
		rebuildFeedDictionaries()
        updateUnreadCount()
    }

	@objc func childrenDidChange(_ note: Notification) {
		guard let object = note.object else {
			return
		}
		if let account = object as? Account, account === self {
			structureDidChange()
			updateUnreadCount()
		}
		if let folder = object as? Folder, folder.account === self {
			structureDidChange()
		}
	}

	@objc func displayNameDidChange(_ note: Notification) {
		if let folder = note.object as? Folder, folder.account === self {
			structureDidChange()
		}
	}

	// MARK: - Hashable

	public func hash(into hasher: inout Hasher) {
		hasher.combine(accountID)
	}

	// MARK: - Equatable

	public static func ==(lhs: Account, rhs: Account) -> Bool {
		return lhs === rhs
	}
}

// MARK: - Fetching Articles (Private)

private extension Account {

	// MARK: - Starred Articles

	func _fetchStarredArticles(limit: Int? = nil) -> Set<Article> {
		database.fetchStarredArticles(feedIDs: flattenedFeedsIDs, limit: limit)
	}

	func _fetchStarredArticlesAsync(limit: Int? = nil) async -> Set<Article> {
		await database.fetchedStarredArticlesAsync(feedIDs: flattenedFeedsIDs, limit: limit)
	}

	// MARK: - Loved Articles

	func _fetchLovedArticles(limit: Int? = nil) -> Set<Article> {
		database.fetchLovedArticles(feedIDs: flattenedFeedsIDs, limit: limit)
	}

	func _fetchLovedArticlesAsync(limit: Int? = nil) async -> Set<Article> {
		await database.fetchedLovedArticlesAsync(feedIDs: flattenedFeedsIDs, limit: limit)
	}

	// MARK: - Last Opened Articles

	func _fetchLastOpenedArticles(limit: Int? = nil) -> Set<Article> {
		database.fetchLastOpenedArticles(feedIDs: flattenedFeedsIDs, limit: limit)
	}

	func _fetchLastOpenedArticlesAsync(limit: Int? = nil) async -> Set<Article> {
		await database.fetchedLastOpenedArticlesAsync(feedIDs: flattenedFeedsIDs, limit: limit)
	}

	// MARK: - Read Articles

	func _fetchReadArticles(limit: Int? = nil) -> Set<Article> {
		database.fetchReadArticles(feedIDs: flattenedFeedsIDs, limit: limit)
	}

	func _fetchReadArticlesAsync(limit: Int? = nil) async -> Set<Article> {
		await database.fetchedReadArticlesAsync(feedIDs: flattenedFeedsIDs, limit: limit)
	}

	// MARK: - Account Unread Articles

	func _fetchUnreadArticles(limit: Int? = nil) -> Set<Article> {
		_fetchUnreadArticles(container: self, limit: limit)
	}

	func _fetchUnreadArticlesAsync(limit: Int? = nil) async -> Set<Article> {
		await _fetchUnreadArticlesAsync(container: self, limit: limit)
	}

	// MARK: - Today Articles

	func _fetchTodayArticles(limit: Int? = nil) -> Set<Article> {
		database.fetchTodayArticles(feedIDs: flattenedFeedsIDs, limit: limit)
	}

	func _fetchTodayArticlesAsync(limit: Int? = nil) async -> Set<Article> {
		await database.fetchTodayArticlesAsync(feedIDs: flattenedFeedsIDs, limit: limit)
	}

	// MARK: - Container Articles

	func _fetchArticles(container: Container) -> Set<Article> {
		let feeds = container.flattenedFeeds()
		let articles = database.fetchArticles(feedIDs: feeds.feedIDs())
		validateUnreadCountsAfterFetchingUnreadArticles(feeds: feeds, articles: articles)
		return articles
	}

	func _fetchArticlesAsync(container: Container) async -> Set<Article> {
		let feeds = container.flattenedFeeds()
		let articles = await database.fetchArticlesAsync(feedIDs: feeds.feedIDs())
		validateUnreadCountsAfterFetchingUnreadArticles(feeds: feeds, articles: articles)
		return articles
	}

	func _fetchUnreadArticles(container: Container, limit: Int? = nil) -> Set<Article> {
		let feeds = container.flattenedFeeds()
		let articles = database.fetchUnreadArticles(feedIDs: feeds.feedIDs(), limit: limit)

		// We don't validate limit queries because they, by definition, won't correctly match the
		// complete unread state for the given container.
		if limit == nil {
			validateUnreadCountsAfterFetchingUnreadArticles(feeds: feeds, articles: articles)
		}

		return articles
	}

	func _fetchUnreadArticlesAsync(container: Container, limit: Int? = nil) async -> Set<Article> {
		let feeds = container.flattenedFeeds()
		let articles = await database.fetchUnreadArticlesAsync(feedIDs: feeds.feedIDs(), limit: limit)

		// We don't validate limit queries because they, by definition, won't correctly match the
		// complete unread state for the given container.
		if limit == nil {
			validateUnreadCountsAfterFetchingUnreadArticles(feeds: feeds, articles: articles)
		}

		return articles
	}

	// MARK: - Feed Articles

	func _fetchArticles(feed: Feed) -> Set<Article> {
		let articles = database.fetchArticles(feedID: feed.feedID)
		validateUnreadCount(feed: feed, articles: articles)
		return articles
	}

	func _fetchArticlesAsync(feed: Feed) async -> Set<Article> {
		let articles = await database.fetchArticlesAsync(feedID: feed.feedID)
		validateUnreadCount(feed: feed, articles: articles)
		return articles
	}

	func _fetchUnreadArticles(feed: Feed) -> Set<Article> {
		let articles = database.fetchUnreadArticles(feedIDs: Set([feed.feedID]))
		validateUnreadCount(feed: feed, articles: articles)
		return articles
	}

	// MARK: - ArticleIDs Articles

	func _fetchArticles(articleIDs: Set<String>) -> Set<Article> {
		database.fetchArticles(articleIDs: articleIDs)
	}

	func _fetchArticlesAsync(articleIDs: Set<String>) async -> Set<Article> {
		await database.fetchArticlesAsync(articleIDs: articleIDs)
	}

	// MARK: - Search Articles

	func _fetchArticlesMatching(searchString: String) -> Set<Article> {
		database.fetchArticlesMatching(searchString: searchString, feedIDs: flattenedFeedsIDs)
	}

	func _fetchArticlesMatchingAsync(searchString: String) async -> Set<Article> {
		await database.fetchArticlesMatchingAsync(searchString: searchString, feedIDs: flattenedFeedsIDs)
	}

	func _fetchArticlesMatchingWithArticleIDs(searchString: String, articleIDs: Set<String>) -> Set<Article> {
		database.fetchArticlesMatchingWithArticleIDs(searchString: searchString, articleIDs: articleIDs)
	}

	func _fetchArticlesMatchingWithArticleIDsAsync(searchString: String, articleIDs: Set<String>) async -> Set<Article> {
		await database.fetchArticlesMatchingWithArticleIDsAsync(searchString: searchString, articleIDs: articleIDs)
	}

	// MARK: - Unread Counts

	private func validateUnreadCountsAfterFetchingUnreadArticles(feeds: Set<Feed>, articles: Set<Article>) {
		// Validate unread counts. This was the site of a performance slowdown:
		// it was calling going through the entire list of articles once per feed:
		// feeds.forEach { validateUnreadCount($0, articles) }
		// Now we loop through articles exactly once. This makes a huge difference.

		var unreadCountStorage = [String: Int]() // [FeedID: Int]
		for article in articles where !article.status.read {
			unreadCountStorage[article.feedID, default: 0] += 1
		}
		for feed in feeds {
			let unreadCount = unreadCountStorage[feed.feedID, default: 0]
			feed.unreadCount = unreadCount
		}
	}

	private func validateUnreadCount(feed: Feed, articles: Set<Article>) {
		// articles must contain all the unread articles for the feed.
		// The unread number should match the feed’s unread count.
		var feedUnreadCount = 0
		for article in articles {
			if article.feed == feed && !article.status.read {
				feedUnreadCount += 1
			}
		}
		feed.unreadCount = feedUnreadCount
	}
}

// MARK: - Fetching Unread Counts (Private)

private extension Account {

	/// Fetch unread counts for zero or more feeds.
	///
	/// Uses the most efficient method based on how many feeds were passed in.
	func _fetchUnreadCounts(for feeds: Set<Feed>) {
		if feeds.isEmpty {
			return
		}

		if feeds.count == 1, let feed = feeds.first {
			_fetchUnreadCount(feed: feed)
		} else if feeds.count < 10 {
			_fetchUnreadCounts(feeds: feeds)
		} else {
			_fetchAllUnreadCounts()
		}
	}

	func _fetchUnreadCount(feed: Feed) {
		Task { @MainActor in
			let unreadCount = await database.fetchUnreadCountAsync(feedID: feed.feedID)
			feed.unreadCount = unreadCount
		}
	}

	func _fetchUnreadCounts(feeds: Set<Feed>) {
		Task { @MainActor in
			let unreadCountDictionary = await database.fetchUnreadCountsAsync(feedIDs: feeds.feedIDs())
			processUnreadCounts(unreadCountDictionary: unreadCountDictionary, feeds: feeds)
		}
	}

	func _fetchAllUnreadCounts() {
		fetchingAllUnreadCounts = true

		Task { @MainActor in
			guard let unreadCountDictionary = await database.fetchAllUnreadCountsAsync() else {
				fetchingAllUnreadCounts = false
				return
			}

			processUnreadCounts(unreadCountDictionary: unreadCountDictionary, feeds: flattenedFeeds())
			fetchingAllUnreadCounts = false
			updateUnreadCount()

			if !self.areUnreadCountsInitialized {
				self.areUnreadCountsInitialized = true
				self.postUnreadCountDidInitializeNotification()
			}
		}
	}

	private func processUnreadCounts(unreadCountDictionary: UnreadCountDictionary, feeds: Set<Feed>) {
		for feed in feeds {
			// When the unread count is zero, it won’t appear in unreadCountDictionary.
			let unreadCount = unreadCountDictionary[feed.feedID] ?? 0
			feed.unreadCount = unreadCount
		}
	}
}

// MARK: - Private

private extension Account {

	func populateFeedSettingsCache() {
		let rows = feedSettingsDatabase.allRows()
		for (feedURL, row) in rows {
			feedSettingsCache[feedURL] = FeedSettings(feedURL: feedURL, row: row, database: feedSettingsDatabase)
		}
	}

	func feedSettings(feedURL: String, feedID: String) -> FeedSettings {
		if let d = feedSettingsCache[feedURL] {
			return d
		}
		let d = FeedSettings(feedURL: feedURL, feedID: feedID, database: feedSettingsDatabase)
		feedSettingsCache[feedURL] = d
		return d
	}

	func updateFlattenedFeeds() {
		var feeds = Set<Feed>()
		feeds.formUnion(topLevelFeeds)
		if let folders {
			for folder in folders {
				feeds.formUnion(folder.flattenedFeeds())
			}
		}

		_flattenedFeeds = feeds
		flattenedFeedsNeedUpdate = false
	}

	func rebuildFeedDictionaries() {
		var idDictionary = [String: Feed]()
		var externalIDDictionary = [String: Feed]()

		for feed in flattenedFeeds() {
			idDictionary[feed.feedID] = feed
			if let externalID = feed.externalID {
				externalIDDictionary[externalID] = feed
			}
		}

		_idToFeedDictionary = idDictionary
		_externalIDToFeedDictionary = externalIDDictionary
		feedDictionariesNeedUpdate = false
	}

    func updateUnreadCount() {
		if fetchingAllUnreadCounts {
			return
		}
		var updatedUnreadCount = 0
		for feed in flattenedFeeds() {
			updatedUnreadCount += feed.unreadCount
		}
		unreadCount = updatedUnreadCount
    }

	func noteStatusesForArticleIDsDidChange(articleIDs: Set<String>, statusKey: ArticleStatus.Key, flag: Bool) {
		_fetchAllUnreadCounts()
		NotificationCenter.default.post(name: .StatusesDidChange, object: self, userInfo: [UserInfoKey.articleIDs: articleIDs, UserInfoKey.statusKey: statusKey, UserInfoKey.statusFlag: flag])
	}

	func noteStatusesForArticleIDsDidChange(_ articleIDs: Set<String>) {
		_fetchAllUnreadCounts()
		NotificationCenter.default.post(name: .StatusesDidChange, object: self, userInfo: [UserInfoKey.articleIDs: articleIDs])
	}

}

// MARK: - Container Overrides

extension Account {

	func sendNotificationAbout(_ articleChanges: ArticleChanges) {
		var feeds = Set<Feed>()

		if let newArticles = articleChanges.new {
			feeds.formUnion(Set(newArticles.compactMap { $0.feed }))
		}
		if let updatedArticles = articleChanges.updated {
			feeds.formUnion(Set(updatedArticles.compactMap { $0.feed }))
		}

		var shouldSendNotification = false
		var shouldUpdateUnreadCounts = false
		var userInfo = [String: Any]()

		if let newArticles = articleChanges.new, !newArticles.isEmpty {
			shouldSendNotification = true
			shouldUpdateUnreadCounts = true
			userInfo[UserInfoKey.newArticles] = newArticles
		}

		if let updatedArticles = articleChanges.updated, !updatedArticles.isEmpty {
			shouldSendNotification = true
			userInfo[UserInfoKey.updatedArticles] = updatedArticles
		}

		if let deletedArticles = articleChanges.deleted, !deletedArticles.isEmpty {
			shouldUpdateUnreadCounts = true
		}

		if shouldUpdateUnreadCounts {
			updateUnreadCounts(feeds: feeds)
		}

		if shouldSendNotification {
			userInfo[UserInfoKey.feeds] = feeds
			NotificationCenter.default.postOnMainThread(name: .AccountDidDownloadArticles, object: self, userInfo: userInfo)
		}
	}

	public func existingFeed(withFeedID feedID: String) -> Feed? {
		return idToFeedDictionary[feedID]
	}

	public func existingFeed(withExternalID externalID: String) -> Feed? {
		return externalIDToFeedDictionary[externalID]
	}
}

// MARK: - OPMLRepresentable

extension Account: OPMLRepresentable {

	public func OPMLString(indentLevel: Int, allowCustomAttributes: Bool) -> String {
		var s = ""
		for feed in topLevelFeeds {
			s += feed.OPMLString(indentLevel: indentLevel + 1, allowCustomAttributes: allowCustomAttributes)
		}
		for folder in folders! {
			s += folder.OPMLString(indentLevel: indentLevel + 1, allowCustomAttributes: allowCustomAttributes)
		}
		return s
	}
}
