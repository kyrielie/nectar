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
import os

/// Posted after a refresh pass completes with one or more feeds left
/// interrupted (cancelled by `suspend()` or cut off by the background
/// pagination deadline). `userInfo["feedURLs"]` is the `Set<String>` of
/// affected feed URLs. The platform layer (`iOS/AppDelegate`) observes this
/// to retry promptly on next foreground rather than waiting out the normal
/// refresh interval, since an interrupted feed is exactly as stale as it
/// was before the attempt.
public extension Notification.Name {
	static let refreshDidCompleteWithInterruptedFeeds = Notification.Name("LocalAccountDelegate.refreshDidCompleteWithInterruptedFeeds")
}

@MainActor final class LocalAccountDelegate: AccountDelegate {
	weak var account: Account?

	let behaviors: AccountBehaviors = []
	let isOPMLImportInProgress = false

	private static let logger = Logger(subsystem: "com.kyrielie.Nectar", category: "LocalAccountDelegate")

	var progressInfo = ProgressInfo() {
		didSet {
			if progressInfo != oldValue {
				postProgressInfoDidChangeNotification()
			}
		}
	}

	let server: String? = nil
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

		if !refresher.interruptedFeedURLs.isEmpty {
			Self.logger.notice("LocalAccountDelegate: refresh completed with \(self.refresher.interruptedFeedURLs.count) feed(s) interrupted -- will need retrying")
			NotificationCenter.default.post(name: .refreshDidCompleteWithInterruptedFeeds, object: account, userInfo: ["feedURLs": refresher.interruptedFeedURLs])
		}
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

	@MainActor func moveFeed(feed: Feed, sourceContainer: Container, destinationContainer: Container, targetIndex: Int?) async throws {
		if sourceContainer === destinationContainer {
			sourceContainer.removeFeedFromTreeAtTopLevel(feed)
			sourceContainer.addFeedToTreeAtTopLevel(feed, at: targetIndex)
			return
		}
		sourceContainer.removeFeedFromTreeAtTopLevel(feed)
		destinationContainer.addFeedToTreeAtTopLevel(feed, at: targetIndex)
	}

	@MainActor func moveFolder(folder: Folder, sourceContainer: Container, destinationContainer: Container, targetIndex: Int?) async throws {
		// Depth cap: reject a move that would push the folder's deepest
		// descendant past 3 levels. destinationContainer's own depth
		// (0 for an account, pathNames.count for a folder) plus 1 (the
		// folder being dropped in) plus however many levels the dragged
		// folder's own subfolders extend must not exceed 3.
		let destinationDepth = (destinationContainer as? Folder)?.pathNames.count ?? 0
		let resultingDepth = destinationDepth + 1 + folder.maxDescendantDepth
		guard resultingDepth <= 3 else {
			throw AccountError.invalidParameter
		}

		if sourceContainer === destinationContainer {
			sourceContainer.removeFolderFromTree(folder)
			sourceContainer.addFolderToTree(folder, at: targetIndex)
			return
		}
		sourceContainer.removeFolderFromTree(folder)
		destinationContainer.addFolderToTree(folder, at: targetIndex)
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
		// Use the folder's actual parent (another Folder if nested, the
		// Account if top-level) rather than always the account directly
		// -- with nesting, a folder's parent isn't necessarily the
		// account, and removing from the wrong container would silently
		// disconnect it from its real position in the tree.
		(folder.parent ?? account)?.removeFolderFromTree(folder)
	}

	@MainActor func restoreFolder(folder: Folder) async throws {
		// Mirrors removeFolder(with:) above: restore to the folder's own
		// recorded parent so undo puts a nested folder back where it
		// actually was, not at the account's top level.
		(folder.parent ?? account)?.addFolderToTree(folder)
	}

	@MainActor func markArticles(articleIDs: Set<String>, statusKey: ArticleStatus.Key, flag: Bool) async throws {
		_ = await account?.updateStatusesAsync(articleIDs: articleIDs, statusKey: statusKey, flag: flag)
	}

	func accountDidInitialize() {
	}

	func accountWillBeDeleted() {
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

		// Any AO3 listing page (search/tag results, author works,
		// bookmarks, marked-for-later, subscriptions, a collection, or a
		// series -- see isAO3ListingFeed's own doc comment) always serves
		// a feed.atom `<link rel="alternate">` in their HTML head, same
		// as any other AO3 page. Running these through FeedFinder would
		// discover that unrelated feed.atom instead of the listing URL
		// the person actually pasted, silently resolving every such paste
		// to whatever feed.atom the account is already subscribed to and
		// getting rejected below as a duplicate. Skip autodiscovery
		// entirely for these and use the pasted URL verbatim -- see
		// LocalAccountRefresher.isAO3ListingFeed(_:), which this reuses
		// so create-time detection and refresh-time routing stay in sync.
		let isAO3ListingURL = LocalAccountRefresher.isAO3ListingFeed(url)

		let feedURLString: String
		if isAO3ListingURL {
			feedURLString = url.absoluteString
		} else {
			let feedSpecifiers = try await FeedFinder.find(url: url)
			guard let bestFeedSpecifier = FeedSpecifier.bestFeed(in: feedSpecifiers) else {
				throw AccountError.createErrorNotFound
			}
			feedURLString = bestFeedSpecifier.urlString
		}

		guard let url = URL(string: feedURLString) else {
			throw AccountError.createErrorNotFound
		}

		guard !account.hasFeed(withURL: feedURLString) else {
			throw AccountError.createErrorAlreadySubscribed
		}

		if isAO3ListingURL {
			// The URL itself is an HTML listing page, not a feed
			// document -- InitialFeedDownloader's FeedParser can't parse it,
			// so don't try. Create the feed immediately and fetch page 1
			// directly (not via refresher.refreshFeeds) so a Cloudflare
			// challenge on this very first fetch can be surfaced back to
			// the add-feed UI as a thrown error, rather than only reaching
			// ActivityLog the way a routine refresh's challenge does --
			// required so the add-feed screen can offer the WKWebView
			// fallback immediately instead of leaving a newly-added feed
			// silently empty until the person separately notices and
			// retries. This does not consolidate onto
			// AO3SearchResultsPaginator.refreshFirstPage(for:account:) --
			// that stays a separate cleanup, since this call site needs to
			// propagate .cloudflareChallenge as a thrown error rather than
			// a PageOutcome the caller has to unwrap.
			let feed = account.createFeed(with: nil, url: feedURLString, feedID: feedURLString, homePageURL: nil)
			feed.editedName = editedName
			container.addFeedToTreeAtTopLevel(feed)
			feed.lastCheckDate = Date()

			// A no-op for a genuinely new feedID; collapses stale duplicate
			// rows left behind if this URL was previously subscribed and
			// deleted -- see ArticlesDatabase.deduplicateArticlesAsync(feedID:).
			// Deliberately not gated on the fetch below succeeding: the
			// duplicates predate this fetch entirely and a Cloudflare
			// challenge/rate-limit on page 1 shouldn't leave them in place.
			await account.database.deduplicateArticlesAsync(feedID: feed.feedID)

			// Subscriptions and marked-for-later are always-yours,
			// always-private (see isAlwaysAuthenticatedAO3ListingFeed's
			// own doc comment) -- route through the authenticated-then-
			// anonymous fetch so a signed-in person actually gets their
			// feed, and a signed-out person gets a clearly-surfaced "sign
			// in" state instead of a silently-empty feed. Widened beyond
			// isAlwaysAuthenticatedAO3ListingFeed alone: any general
			// search/tag page also routes through fetchRequiringSignIn
			// once a session exists, so a signed-in person's add-time
			// fetch for a general listing gets the authenticated-first
			// attempt too. A subscriptions/marked-for-later page still
			// always routes through it (session or not) to get the
			// correct .notSignedIn surfaced when signed out. Every other
			// listing type, when signed out, keeps using the plain
			// anonymous fetch, unchanged.
			let isAlwaysAuthenticatedListing = LocalAccountRefresher.isAlwaysAuthenticatedAO3ListingFeed(url)
			let requiresSignIn = isAlwaysAuthenticatedListing || AO3SessionStore.isSignedIn

			do {
				let outcome: AO3SearchResultsFetchOutcome
				if requiresSignIn {
					outcome = try await AO3SearchResultsFetcher.fetchRequiringSignIn(url: url, feedURL: feed.url, isAlwaysAuthenticatedListing: isAlwaysAuthenticatedListing)
				} else {
					outcome = try await AO3SearchResultsFetcher.fetch(url: url, feedURL: feed.url)
				}

				switch outcome {
				case .success(let parsedItems, _, let pageTitle, let totalPages):
					let articleChanges = await account.updateAsync(feedID: feed.feedID, parsedItems: Set(parsedItems), deleteOlder: false)
					account.sendNotificationAbout(articleChanges)
					feed.ao3SearchFetchedPages = [1]
					feed.ao3SearchTotalPages = totalPages
					// feed.name (not editedName, set above from the user's
					// typed Name field) -- nameForDisplay's own
					// editedName -> name -> "Untitled" precedence means a
					// typed name still wins; this only fills in the
					// otherwise-permanent "Untitled" fallback for a feed
					// added with no typed name. AO3 renders a real
					// <title> on every search/tag-listing page (see
					// AO3SearchResultsExtractor.extractPageTitle), so
					// pageTitle is nil only if that page's own markup was
					// missing or empty, not from any condition this
					// branch already handles differently.
					if let pageTitle {
						feed.name = pageTitle
					}
				case .noResults(let pageTitle, let totalPages):
					// Not thrown -- the feed is still validly added, same
					// as today's behavior via refresher.refreshFeeds;
					// zero results is visible via a subsequent manual
					// "load more" / paginator call, not blocking here.
					// AO3 still serves a real, titled page for a
					// zero-result search, so this still isn't left
					// "Untitled" if a title's available.
					if let pageTitle {
						feed.name = pageTitle
					}
					if let totalPages {
						feed.ao3SearchTotalPages = totalPages
					}
				case .registrationRequired, .rateLimited:
					// Not thrown -- the feed is still validly added, same
					// as today's behavior via refresher.refreshFeeds;
					// these outcomes are visible via a subsequent manual
					// "load more" / paginator call, not blocking here.
					// Neither carries a pageTitle: a registration wall
					// never reaches AO3SearchResultsExtractor.extract at
					// all (caught earlier by isRegistrationRequired), and
					// a 429 has no body to parse a title from.
					// .registrationRequired is reachable here for a
					// non-always-authenticated listing type regardless of
					// sign-in state: requiresSignIn == false takes the
					// plain anonymous path; requiresSignIn == true (a
					// signed-in general listing, or an always-
					// authenticated listing type) only turns a rejected/
					// missing session into .notSignedIn for the
					// always-authenticated types specifically -- see
					// fetchRequiringSignIn's own doc comment on
					// isAlwaysAuthenticatedListing.
					break
				case .cloudflareChallenge(let challengedURL):
					AO3ChallengeSessionStore.lastChallengedURL = challengedURL
					throw AccountError.ao3CloudflareChallenge(challengedURL: challengedURL, feed: feed)
				case .notSignedIn:
					throw AccountError.ao3ListingRequiresSignIn(feed: feed)
				}
			} catch let error as AccountError {
				throw error
			} catch {
				// Fetch-level failure (exhausted retries, etc.) -- feed
				// stays added, same as above; surfaced through the usual
				// refresh/ActivityLog path on the next manual retry.
			}

			return feed
		}

		if let repairedFeed = repointIfAmbrosiaRepair(urlString: feedURLString, account: account, container: container) {
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

		// See the matching call/comment in the AO3-listing branch above --
		// same no-op-for-a-new-feedID reasoning applies here.
		await account.database.deduplicateArticlesAsync(feedID: feed.feedID)

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
