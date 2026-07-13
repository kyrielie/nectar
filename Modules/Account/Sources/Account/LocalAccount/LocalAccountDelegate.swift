//
//  LocalAccountDelegate.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/16/17.
//  Copyright © 2017 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import RSCore
import RSParser
import Articles
import ArticlesDatabase
import FeedFinder
import RSWeb
import Secrets

@MainActor final class LocalAccountDelegate: AccountDelegate {
	weak var account: Account?

	let behaviors: AccountBehaviors = []
	let isOPMLImportInProgress = false

	var progressInfo = ProgressInfo() {
		didSet {
			if progressInfo != oldValue {
				postProgressInfoDidChangeNotification()
			}
		}
	}

	let server: String? = nil
	var credentials: Credentials?
	var accountSettings: AccountSettings?

	private lazy var refresher: LocalAccountRefresher = {
		let refresher = LocalAccountRefresher()
		refresher.delegate = self
		NotificationCenter.default.addObserver(self, selector: #selector(progressInfoDidChange(_:)), name: .progressInfoDidChange, object: refresher)
		return refresher
	}()

	func receiveRemoteNotification(userInfo: [AnyHashable: Any]) async {
	}

	@MainActor func refreshAll() async throws {
		guard let account else {
			return
		}
		guard progressInfo.isComplete, !Platform.isRunningUnitTests else {
			return
		}

		let feeds = account.flattenedFeeds()
		refresher.accountID = account.accountID
		await refresher.refreshFeeds(feeds)
		account.lastRefreshCompletedDate = Date()
	}

	@MainActor func syncArticleStatus() async throws -> Bool {
		false
	}

	@MainActor func sendArticleStatus() async throws {
	}

	@MainActor func refreshArticleStatus() async throws {
	}

	@MainActor func importOPML(opmlFile: URL) async throws {
		guard let account else {
			return
		}
		try await account.logActivity(kind: .importOPML, detail: opmlFile.lastPathComponent) {
			let opmlData = try Data(contentsOf: opmlFile)
			let parserData = ParserData(url: opmlFile.absoluteString, data: opmlData)
			let opmlDocument = try OPMLParser.parseOPML(with: parserData)

			// TODO: throw appropriate error for empty OPML
			guard let children = opmlDocument.children else {
				return
			}

			Self.rewriteAmbrosiaJSONFeedURLs(in: children)

			// Snapshot existing feeds by Ambrosia collection identity *before* import,
			// so we can tell a re-pair (same collection, new host) apart from a
			// genuinely new subscription once the import has created its Feed objects.
			let preexistingFeedsByCollectionKey = Self.collectionKeyIndex(for: account.flattenedFeeds())

			BatchUpdate.shared.perform {
				account.loadOPMLItems(children)
			}

			await reconcileRepairedFeeds(incomingItems: children, preexistingFeedsByCollectionKey: preexistingFeedsByCollectionKey)
		}
	}

	/// Maps Ambrosia collection key -> Feed for every feed in `feeds` that is a
	/// recognized Ambrosia route. Feeds that aren't Ambrosia routes are omitted.
	private static func collectionKeyIndex(for feeds: Set<Feed>) -> [String: Feed] {
		var index = [String: Feed]()
		for feed in feeds {
			guard let key = AmbrosiaFeedIdentity.collectionKey(for: feed.url) else {
				continue
			}
			index[key] = feed
		}
		return index
	}

	/// Recursively collects every `feedURL` referenced by `items`, matching the
	/// traversal `addOPMLItems` uses so we can find the Feed objects this import
	/// just created.
	private static func flattenedFeedURLs(in items: [OPMLItem]) -> Set<String> {
		var urls = Set<String>()
		for item in items {
			if let feedSpecifier = item.feedSpecifier {
				urls.insert(feedSpecifier.feedURL)
			}
			if let children = item.children {
				urls.formUnion(flattenedFeedURLs(in: children))
			}
		}
		return urls
	}

	/// After an OPML import, finds any newly created feed that shares an Ambrosia
	/// collection identity with a feed that already existed under a different URL
	/// (the LAN-IP-changed re-pair case) and repoints the existing feed to the new
	/// address instead of leaving the just-created duplicate in the sidebar.
	///
	/// This supersedes the earlier merge-by-bookKey approach: since `repointFeed`
	/// leaves `feedID` unchanged, `staleFeed`'s articles, statuses (starred/loved/
	/// readingProgress/scrollPosition), and bookReadState rows are already correctly
	/// associated with no copying needed -- `articleID` is derived from `feedID`,
	/// not `url`.
	private func reconcileRepairedFeeds(incomingItems: [OPMLItem], preexistingFeedsByCollectionKey: [String: Feed]) async {
		guard let account, !preexistingFeedsByCollectionKey.isEmpty else {
			return
		}

		let incomingURLs = Self.flattenedFeedURLs(in: incomingItems)
		guard !incomingURLs.isEmpty else {
			return
		}

		let duplicateFeeds = account.flattenedFeeds().filter { incomingURLs.contains($0.url) }

		for duplicateFeed in duplicateFeeds {
			guard let collectionKey = AmbrosiaFeedIdentity.collectionKey(for: duplicateFeed.url) else {
				continue
			}
			guard let staleFeed = preexistingFeedsByCollectionKey[collectionKey], staleFeed.feedID != duplicateFeed.feedID else {
				continue
			}
			await repointAndRefresh(staleFeed: staleFeed, replacing: duplicateFeed, account: account)
		}
	}

	/// Repoints `staleFeed` to `duplicateFeed`'s (new) URL, removes `duplicateFeed`
	/// from the sidebar (it was only ever a byproduct of `loadOPMLItems` creating a
	/// fresh `Feed` for every OPML entry, with no identity check), and refreshes
	/// `staleFeed` so it starts fetching from the new address.
	private func repointAndRefresh(staleFeed: Feed, replacing duplicateFeed: Feed, account: Account) async {
		account.repointFeed(staleFeed, to: duplicateFeed.url)
		removeFromSidebar(duplicateFeed, account: account)

		refresher.accountID = account.accountID
		await refresher.refreshFeeds([staleFeed])
	}

	/// Removes `feed` from every container it's in. Deliberately leaves its
	/// articles and feedSettings row alone -- Phase 1 already stopped the
	/// unconditional cleanup that used to hard-delete these, and a discarded
	/// duplicate's leftovers are exactly the harmless orphan case that guard
	/// was meant to tolerate.
	private func removeFromSidebar(_ feed: Feed, account: Account) {
		for container in account.existingContainers(withFeed: feed) {
			container.removeFeedFromTreeAtTopLevel(feed)
		}
	}

	/// Ambrosia's exported OPML points `xmlUrl` at the hand-rolled RSS 2.0
	/// route (`/feed/collection/<id>.xml`, `/feed/search.xml`,
	/// `/feed/random-daily.xml`), which carries none of the `_ambrosia`
	/// metadata (word count, fandoms, series, etc.) — that only comes through
	/// the sibling JSON Feed route (same path, `.json` instead of `.xml`).
	/// Importing the OPML as-is would silently subscribe to feeds with no
	/// book-card data. Rewrite matching URLs in place before subscribing.
	private static func rewriteAmbrosiaJSONFeedURLs(in items: [OPMLItem]) {
		for item in items {
			if var attributes = item.attributes,
			   let xmlURLKey = attributes.keys.first(where: { $0.caseInsensitiveCompare("xmlUrl") == .orderedSame }),
			   let xmlURLString = attributes[xmlURLKey],
			   let rewritten = ambrosiaJSONFeedURLString(for: xmlURLString) {
				attributes[xmlURLKey] = rewritten
				item.attributes = attributes
			}
			if let children = item.children {
				rewriteAmbrosiaJSONFeedURLs(in: children)
			}
		}
	}

	/// Returns the JSON Feed equivalent of an Ambrosia RSS route URL, or nil
	/// if `xmlURLString` doesn't match one of Ambrosia's known `.xml` routes.
	private static func ambrosiaJSONFeedURLString(for xmlURLString: String) -> String? {
		guard let url = URL(string: xmlURLString), url.pathExtension.lowercased() == "xml" else {
			return nil
		}

		let path = url.path
		let isAmbrosiaRoute = path.hasSuffix("/feed/search.xml")
			|| path.hasSuffix("/feed/random-daily.xml")
			|| (path.contains("/feed/collection/") && path.hasSuffix(".xml"))
		guard isAmbrosiaRoute else {
			return nil
		}

		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			return nil
		}
		components.path = String(path.dropLast(4)) + ".json"
		return components.url?.absoluteString
	}

	@MainActor func createFeed(url urlString: String, name: String?, container: Container, validateFeed: Bool) async throws -> Feed {
		guard let account else {
			throw AccountError.invalidParameter
		}
		guard let url = URL(string: urlString) else {
			throw AccountError.invalidParameter
		}

		return try await account.logActivity(kind: .subscribeFeed, detail: urlString) {
			try await createFeed(account: account, url: url, editedName: name, container: container)
		}
	}

	@MainActor func renameFeed(with feed: Feed, to name: String) async throws {
		feed.editedName = name
	}

	@MainActor func removeFeed(feed: Feed, container: Container) async throws {
		container.removeFeedFromTreeAtTopLevel(feed)
	}

	@MainActor func moveFeed(feed: Feed, sourceContainer: Container, destinationContainer: Container) async throws {
		sourceContainer.removeFeedFromTreeAtTopLevel(feed)
		destinationContainer.addFeedToTreeAtTopLevel(feed)
	}

	@MainActor func addFeed(feed: Feed, container: Container) async throws {
		container.addFeedToTreeAtTopLevel(feed)
	}

	@MainActor func restoreFeed(feed: Feed, container: Container) async throws {
		container.addFeedToTreeAtTopLevel(feed)
	}

	@MainActor func createFolder(name: String) async throws -> Folder {
		guard let account else {
			throw AccountError.invalidParameter
		}
		guard let folder = account.ensureFolder(with: name) else {
			throw AccountError.invalidParameter
		}
		return folder
	}

	@MainActor func renameFolder(with folder: Folder, to name: String) async throws {
		folder.name = name
	}

	@MainActor func removeFolder(with folder: Folder) async throws {
		account?.removeFolderFromTree(folder)
	}

	@MainActor func restoreFolder(folder: Folder) async throws {
		account?.addFolderToTree(folder)
	}

	@MainActor func markArticles(articleIDs: Set<String>, statusKey: ArticleStatus.Key, flag: Bool) async throws {
		_ = await account?.updateStatusesAsync(articleIDs: articleIDs, statusKey: statusKey, flag: flag)
	}

	func accountDidInitialize() {
	}

	func accountWillBeDeleted() {
	}

	static func validateCredentials(credentials: Credentials, endpoint: URL?) async throws -> Credentials? {
		nil
	}

	func vacuumDatabases() async {
	}

	// MARK: Suspend and Resume (for iOS)

	@MainActor func suspendNetwork() {
		refresher.suspend()
	}

	@MainActor func resume() {
		refresher.resume()
	}

	// MARK: - Notifications

	@objc func progressInfoDidChange(_ notification: Notification) {
		progressInfo = refresher.progressInfo
	}
}

extension LocalAccountDelegate: LocalAccountRefresherDelegate {

	func localAccountRefresher(_ refresher: LocalAccountRefresher, articleChanges: ArticleChanges) {
	}
}

private extension LocalAccountDelegate {

	@MainActor func createFeed(account: Account, url: URL, editedName: String?, container: Container) async throws -> Feed {
		// We need to use a batch update here because we need to assign add the feed to the
		// container before the name has been downloaded.  This will put it in the sidebar
		// with an Untitled name if we don't delay it being added to the sidebar.
		BatchUpdate.shared.start()
		defer {
			BatchUpdate.shared.end()
		}

		let feedSpecifiers = try await FeedFinder.find(url: url)

		guard let bestFeedSpecifier = FeedSpecifier.bestFeed(in: feedSpecifiers),
			  let url = URL(string: bestFeedSpecifier.urlString) else {
			throw AccountError.createErrorNotFound
		}

		guard !account.hasFeed(withURL: bestFeedSpecifier.urlString) else {
			throw AccountError.createErrorAlreadySubscribed
		}

		if let repairedFeed = repointIfAmbrosiaRepair(urlString: bestFeedSpecifier.urlString, account: account, container: container) {
			refresher.accountID = account.accountID
			await refresher.refreshFeeds([repairedFeed])
			return repairedFeed
		}

		let (parsedFeed, response) = try await InitialFeedDownloader.download(url)
		guard let parsedFeed else {
			throw AccountError.createErrorNotFound
		}

		let feed = account.createFeed(with: nil, url: url.absoluteString, feedID: url.absoluteString, homePageURL: nil)
		feed.lastCheckDate = Date()

		// Save conditional GET info so that first refresh uses conditional GET.
		if let httpResponse = response as? HTTPURLResponse,
		   let conditionalGetInfo = HTTPConditionalGetInfo(urlResponse: httpResponse) {
			feed.conditionalGetInfo = conditionalGetInfo
		}

		feed.editedName = editedName
		container.addFeedToTreeAtTopLevel(feed)

		Task {
			await account.updateAsync(feed: feed, parsedFeed: parsedFeed)
		}

		return feed
	}

	/// If `urlString` is an Ambrosia route whose collection matches an existing
	/// feed under a different URL (the LAN-IP-changed re-pair case), repoints that
	/// existing feed to `urlString` and adds it to `container`, returning it.
	/// Returns nil when this isn't a repair -- either `urlString` isn't a
	/// recognized Ambrosia route, or no existing feed matches its collection --
	/// in which case the caller should proceed with a normal create.
	@MainActor func repointIfAmbrosiaRepair(urlString: String, account: Account, container: Container) -> Feed? {
		guard let collectionKey = AmbrosiaFeedIdentity.collectionKey(for: urlString) else {
			return nil
		}
		guard let staleFeed = LocalAccountDelegate.collectionKeyIndex(for: account.flattenedFeeds())[collectionKey], staleFeed.url != urlString else {
			return nil
		}

		account.repointFeed(staleFeed, to: urlString)
		container.addFeedToTreeAtTopLevel(staleFeed)
		return staleFeed
	}
}
