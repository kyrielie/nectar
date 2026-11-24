//
//  AO3ImportMetadataQueue.swift
//  Account
//
//  Paced, serialized metadata fetcher for newly-imported AO3 work links.
//  Enforces a 1-slot concurrency cap with a 3.0-second delay between requests,
//  pauses on HTTP 429 cooldowns, and populates article placeholder stubs
//  without downloading or storing chapter bodies.
//

import Foundation
import os
import Articles
import ArticlesDatabase
import AO3Kit
import RSParser
import RSWeb

public actor AO3ImportMetadataQueue {

	public static let shared = AO3ImportMetadataQueue()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nectar", category: "AO3ImportMetadataQueue")

	public static let defaultDelayBetweenRequests: TimeInterval = 3.0

	// MARK: - Notifications

	public static let progressNotification = Notification.Name("AO3ImportMetadataQueueProgressDidChange")
	public static let progressCompletedKey = "completed"
	public static let progressTotalKey = "total"
	public static let progressIsDrainingKey = "isDraining"

	// MARK: - Work Item

	public struct WorkItem: Sendable, Hashable {
		public let workID: String
		public let accountID: String
		public let feedID: String

		public init(workID: String, accountID: String, feedID: String) {
			self.workID = workID
			self.accountID = accountID
			self.feedID = feedID
		}
	}

	// MARK: - State

	private var pending: [WorkItem] = []
	private var queuedWorkIDs: Set<String> = []
	public private(set) var completedCount: Int = 0
	public private(set) var totalCount: Int = 0
	public private(set) var isDraining: Bool = false

	public var delayBetweenRequests: TimeInterval

	public typealias FetchHandler = @Sendable (URL) async throws -> (Data?, HTTPURLResponse?)
	private var customFetchHandler: FetchHandler?

	public init(delayBetweenRequests: TimeInterval = defaultDelayBetweenRequests, fetchHandler: FetchHandler? = nil) {
		self.delayBetweenRequests = delayBetweenRequests
		self.customFetchHandler = fetchHandler
	}

	// MARK: - Enqueue

	/// Enqueues imported work IDs into the metadata queue.
	public func enqueue(workIDs: [String], accountID: String, feedID: String) {
		guard !workIDs.isEmpty else { return }

		var addedCount = 0
		for workID in workIDs {
			guard !queuedWorkIDs.contains(workID) else { continue }
			queuedWorkIDs.insert(workID)
			pending.append(WorkItem(workID: workID, accountID: accountID, feedID: feedID))
			addedCount += 1
		}

		guard addedCount > 0 else { return }
		totalCount += addedCount
		notifyProgress()

		if !isDraining {
			isDraining = true
			Task {
				await drain()
			}
		}
	}

	// MARK: - Drain Loop

	private func drain() async {
		defer {
			isDraining = false
			notifyProgress()
		}

		while !pending.isEmpty {
			if Task.isCancelled {
				break
			}

			// 1. Wait for any active 429 cooldown to clear before sending the request
			await waitForCooldownIfNeeded()

			if Task.isCancelled {
				break
			}

			let item = pending.removeFirst()
			await fetchAndProcess(item: item)

			completedCount += 1
			notifyProgress()

			// 2. Pace between requests: 3.0-second delay
			if !pending.isEmpty {
				do {
					try await Task.sleep(nanoseconds: UInt64(delayBetweenRequests * 1_000_000_000))
				} catch {
					break // Cancelled
				}
			}
		}
	}

	private func waitForCooldownIfNeeded() async {
		while true {
			let resumeDate = await MainActor.run {
				AO3RateLimit.activeResumeDate()
			}
			guard let resumeDate, resumeDate > Date() else {
				return
			}
			let waitTime = resumeDate.timeIntervalSince(Date())
			Self.logger.info("AO3ImportMetadataQueue paused for rate limit cooldown: waiting \(waitTime, format: .fixed(precision: 1))s until \(resumeDate)")
			do {
				try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
			} catch {
				return
			}
		}
	}

	private func fetchAndProcess(item: WorkItem) async {
		guard let url = AO3Link.workURL(id: item.workID, fullWork: false, adultView: true) else {
			Self.logger.warning("Invalid work ID: \(item.workID, privacy: .public)")
			return
		}

		do {
			let (data, response) = try await performFetch(url: url)

			if let response, response.statusCode == 429 {
				Self.logger.warning("AO3ImportMetadataQueue received 429 for work \(item.workID, privacy: .public)")
				let resumeDate = await MainActor.run {
					AO3RateLimit.record(url: url, response: response)
				}
				if let resumeDate, resumeDate > Date() {
					let wait = resumeDate.timeIntervalSince(Date())
					try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
				}
				return
			}

			guard let data, let html = String(data: data, encoding: .utf8) else {
				return
			}

			if AO3WorkPageClassifier.isInterstitial(html) {
				Self.logger.info("Skipping metadata update for work \(item.workID, privacy: .public): received interstitial page")
				return
			}

			guard let metadata = AO3ChapterHTMLExtractor.extractLightweightMetadata(fromWorkPageHTML: html) else {
				Self.logger.info("Could not extract metadata for work \(item.workID, privacy: .public)")
				return
			}

			await applyMetadata(metadata, for: item)
		} catch {
			Self.logger.error("Error fetching metadata for work \(item.workID, privacy: .public): \(error.localizedDescription, privacy: .public)")
		}
	}

	private func performFetch(url: URL) async throws -> (Data?, HTTPURLResponse?) {
		if let customFetchHandler {
			return try await customFetchHandler(url)
		}

		// Production transport: acquired via coordinator to respect global AO3 limit
		return try await AO3RequestCoordinator.shared.withSlot {
			let downloadResponse = try await Downloader.shared.download(url, shouldCache: { data, _ in
				guard let data, let html = String(data: data, encoding: .utf8) else { return true }
				return !AO3WorkPageClassifier.isInterstitial(html)
			})
			return (downloadResponse.data, downloadResponse.response as? HTTPURLResponse)
		}
	}

	@MainActor
	private func applyMetadata(_ metadata: AO3LightweightMetadata, for item: WorkItem) async {
		guard let account = AccountManager.shared.existingAccount(accountID: item.accountID) else {
			return
		}

		let articles = await account.fetchArticlesAsync(bookKeys: ["ao3-work:\(item.workID)"])
		guard let existingArticle = articles.first(where: { $0.feedID == item.feedID }) ?? articles.first else {
			return
		}

		let authors: Set<ParsedAuthor>?
		if !metadata.authors.isEmpty {
			authors = metadata.authors
		} else if let existingAuthors = existingArticle.authors {
			authors = Set(existingAuthors.map { ParsedAuthor(name: $0.name, url: $0.url, avatarURL: $0.avatarURL, emailAddress: $0.emailAddress) })
		} else {
			authors = nil
		}

		let additionalTags: Set<String>?
		if !metadata.additionalTags.isEmpty {
			additionalTags = Set(metadata.additionalTags)
		} else if let existingTags = existingArticle.additionalTags {
			additionalTags = Set(existingTags)
		} else {
			additionalTags = nil
		}

		let series: [ParsedSeriesEntry]?
		if !metadata.seriesEntries.isEmpty {
			series = metadata.seriesEntries.map(\.entry)
		} else if let existingSeries = existingArticle.series {
			series = existingSeries.map { ParsedSeriesEntry(name: $0.name, index: $0.index, ao3ID: $0.ao3ID, previousWorkURL: $0.previousWorkURL, nextWorkURL: $0.nextWorkURL) }
		} else {
			series = nil
		}

		let collections: [ParsedCollectionEntry]?
		if let parsedCollections = metadata.collections {
			collections = parsedCollections
		} else if let existingCollections = existingArticle.collections {
			collections = existingCollections.map { ParsedCollectionEntry(name: $0.name, slug: $0.slug) }
		} else {
			collections = nil
		}

		let updatedItem = ParsedItem(
			syncServiceID: existingArticle.articleID,
			uniqueID: existingArticle.uniqueID,
			feedURL: item.feedID,
			url: existingArticle.rawLink ?? "https://archiveofourown.org/works/\(item.workID)",
			externalURL: existingArticle.rawExternalLink,
			title: metadata.title ?? existingArticle.title,
			language: nil,
			contentHTML: nil, // Full chapter text is NEVER scraped or stored in batch import
			contentText: nil,
			markdown: nil,
			summary: metadata.summary ?? existingArticle.summary,
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: metadata.datePublished ?? existingArticle.datePublished,
			dateModified: metadata.dateModified ?? existingArticle.dateModified,
			authors: authors,
			tags: additionalTags,
			attachments: nil,
			isAmbrosiaItem: existingArticle.isAmbrosiaItem,
			wordCount: metadata.wordCount ?? existingArticle.wordCount,
			chapterCurrent: metadata.chapterCurrent ?? existingArticle.chapterCurrent,
			chapterTotal: metadata.chapterTotal ?? existingArticle.chapterTotal,
			isComplete: metadata.isComplete ?? existingArticle.isComplete,
			fandoms: metadata.fandoms.isEmpty ? existingArticle.fandoms : metadata.fandoms,
			relationships: metadata.relationships.isEmpty ? existingArticle.relationships : metadata.relationships,
			characters: metadata.characters.isEmpty ? existingArticle.characters : metadata.characters,
			ratings: metadata.ratings.isEmpty ? existingArticle.ratings : metadata.ratings,
			warnings: metadata.warnings.isEmpty ? existingArticle.warnings : metadata.warnings,
			categories: metadata.categories.isEmpty ? existingArticle.categories : metadata.categories,
			series: series,
			commentCount: metadata.commentCount ?? existingArticle.commentCount,
			kudosCount: metadata.kudosCount ?? existingArticle.kudosCount,
			bookmarkCount: metadata.bookmarkCount ?? existingArticle.bookmarkCount,
			hitCount: metadata.hitCount ?? existingArticle.hitCount,
			isRestricted: metadata.isRestricted ?? existingArticle.isRestricted,
			ao3Language: metadata.language ?? existingArticle.language,
			collections: collections,
			lastPrefaceFetchDate: Date(),
			ao3WorkID: item.workID
		)

		_ = await account.updateAsync(feedID: item.feedID, parsedItems: [updatedItem], deleteOlder: false)
	}

	private func notifyProgress() {
		let completed = completedCount
		let total = totalCount
		let draining = isDraining
		Task { @MainActor in
			NotificationCenter.default.post(
				name: Self.progressNotification,
				object: nil,
				userInfo: [
					Self.progressCompletedKey: completed,
					Self.progressTotalKey: total,
					Self.progressIsDrainingKey: draining
				]
			)
		}
	}
}

// MARK: - Test Hooks

extension AO3ImportMetadataQueue {

	public func pendingCountForTesting() -> Int {
		pending.count
	}

	public func setCustomFetchHandlerForTesting(_ handler: FetchHandler?) {
		self.customFetchHandler = handler
	}

	public func setDelayBetweenRequestsForTesting(_ delay: TimeInterval) {
		self.delayBetweenRequests = delay
	}

	public func resetForTesting() {
		pending.removeAll()
		queuedWorkIDs.removeAll()
		completedCount = 0
		totalCount = 0
		isDraining = false
		delayBetweenRequests = Self.defaultDelayBetweenRequests
		customFetchHandler = nil
	}
}
