//
//  AO3ChapterFetcher.swift
//  Account
//
//  Nectar AO3 direct-reading support, Workstream 2 ("On-demand chapter
//  fetch and storage") -- see docs/ao3-merged-plan-nectar.md.
//
//  Fetches an AO3 work's live page (`?view_full_work=true`) on demand and
//  persists the extracted, workskin-preserving contentHTML for any article
//  whose bookKey identifies it as an AO3 work ("ao3-work:<id>"). Modeled
//  directly on HTMLMetadataDownloader: same hoursBetweenAttempts gate, same
//  ActivityLog start/complete/fail calls, same "leave existing content alone
//  on failure, don't retry aggressively" shape. Fetches are anonymous --
//  Downloader already forces httpShouldSetCookies = false / .never cookie
//  policy app-wide, so no change is needed to get that behavior here.
//
//  ParsedItem reconstruction: Account.updateAsync(feedID:parsedItems:...) is
//  the only write path for contentHTML (no single-field "update just this"
//  API exists), and Article+Database.changesFrom diffs the incoming
//  ParsedItem against the existing Article field by field. That means every
//  field the existing Article already has must be copied into the rebuilt
//  ParsedItem unchanged -- only contentHTML and chapterCurrent actually
//  change here -- or an otherwise-ordinary "just update the content" fetch
//  would blank title/summary/fandoms/etc. on that article.
//
//  ao3WorkID for the refetch URL is recovered directly from the existing
//  article's own bookKey (stripping the "ao3-work:" prefix) rather than
//  needing isAnthology/ao3SeriesID/seriesName carried through the rebuild:
//  bookKey only resolves to "ao3-work:<id>" when isAnthology wasn't true to
//  begin with (anthology series id/name takes precedence -- see
//  ParsedItem.bookKey), so reconstructing with isAnthology left nil
//  reproduces the identical bookKey.
//

import Foundation
import os
import RSCore
import RSParser
import RSWeb
import Articles
import ActivityLog

nonisolated public final class AO3ChapterFetcher: Sendable {

	public static let shared = AO3ChapterFetcher()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AO3ChapterFetcher")

	private static let hoursBetweenAttempts = 3
	private static let ao3WorkIDBookKeyPrefix = "ao3-work:"

	private let attemptDates = OSAllocatedUnfairLock(initialState: [String: Date]())

	init() {}

	/// Kicks off a fetch if `article` is an AO3-sourced article (per its
	/// bookKey) whose stored content looks stale or missing, and enough time
	/// has passed since the last attempt for this article. No-op for any
	/// other article -- including one with no resolvable ao3WorkID at all.
	/// Fire-and-forget; callers observe `.ao3ChapterFetchDidComplete` to know
	/// when to reload.
	public func fetchIfNeeded(for article: Article) {
		guard let workID = Self.ao3WorkID(fromBookKey: article.bookKey), isStale(article: article) else {
			return
		}
		downloadIfNeeded(workID: workID, articleID: article.articleID, accountID: article.accountID, feedID: article.feedID)
	}

	/// True when the article has no stored content yet, or when the stored
	/// content's own chapter count -- re-derived by walking the same
	/// `#workskin` wrapper AO3ChapterHTMLExtractor produced, since the stored
	/// contentHTML *is* that wrapper -- is behind `chapterCurrent` (the
	/// feed-reported total, Workstream 1's territory). Exposed internally for
	/// direct testing against fixtures.
	func isStale(article: Article) -> Bool {
		guard let contentHTML = article.contentHTML, !contentHTML.isEmpty else {
			return true
		}
		guard let chapterCurrent = article.chapterCurrent else {
			// No chapter-count metadata at all -- shouldn't happen for an
			// article whose bookKey resolved to ao3-work: (Workstream 1
			// always sets chapterCurrent for AO3 items), but with nothing to
			// compare against, don't treat that as stale on every call.
			return false
		}
		let storedChapterCount = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: contentHTML)?.chapters.count ?? 0
		return storedChapterCount < chapterCurrent
	}
}

// MARK: - Internal, directly testable

extension AO3ChapterFetcher {

	static func ao3WorkID(fromBookKey bookKey: String) -> String? {
		guard bookKey.hasPrefix(ao3WorkIDBookKeyPrefix) else {
			return nil
		}
		let workID = String(bookKey.dropFirst(ao3WorkIDBookKeyPrefix.count))
		return workID.isEmpty ? nil : workID
	}
}

// MARK: - Private

nonisolated private extension AO3ChapterFetcher {

	func downloadIfNeeded(workID: String, articleID: String, accountID: String, feedID: String) {
		let shouldDownload = attemptDates.withLock { dates in
			let currentDate = Date()
			if let attemptDate = dates[articleID], attemptDate > currentDate.bySubtracting(hours: Self.hoursBetweenAttempts) {
				return false
			}
			dates[articleID] = currentDate
			return true
		}

		if shouldDownload {
			download(workID: workID, articleID: articleID, accountID: accountID, feedID: feedID)
		}
	}

	func download(workID: String, articleID: String, accountID: String, feedID: String) {
		guard let url = URL(string: "https://archiveofourown.org/works/\(workID)?view_full_work=true") else {
			return
		}

		Task { @MainActor in
			let activityLog = ActivityLog.shared
			let kind = ActivityKind.fetchAO3Chapter(workID: workID)

			activityLog.createActivity(owner: .ao3ChapterFetcher, kind: kind, detail: nil)
			activityLog.didStart(.ao3ChapterFetcher, kind: kind)

			do {
				let downloadResponse = try await Downloader.shared.download(url)

				guard let data = downloadResponse.data, !data.isEmpty, let response = downloadResponse.response, response.statusIsOK else {
					// Bad response -- leave existing content alone. The
					// hoursBetweenAttempts gate above already prevents
					// hammering a gated/deleted/moved work; no further
					// backoff bookkeeping needed here.
					let statusCode = downloadResponse.response?.forcedStatusCode ?? -1
					let userInfo = [NSLocalizedDescriptionKey: "HTTP \(statusCode)"]
					activityLog.didFail(.ao3ChapterFetcher, kind: kind, error: NSError(domain: "Nectar", code: statusCode, userInfo: userInfo))
					return
				}

				guard let html = String(data: data, encoding: .utf8),
				      let extraction = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html) else {
					// No .chapter div found -- gated (logged out) or
					// deleted/moved look identical by this signal (see
					// AO3ChapterHTMLExtractor's doc comment); treat as
					// unfetchable rather than an error worth retrying
					// aggressively. Existing contentHTML (nil, on first
					// fetch) is left alone; ArticleRenderer's
					// contentHTML ?? contentText ?? summary chain already
					// falls back to Workstream 1's blurb.
					let userInfo = [NSLocalizedDescriptionKey: "No chapter content found (gated or removed work)"]
					activityLog.didFail(.ao3ChapterFetcher, kind: kind, error: NSError(domain: "Nectar", code: -1, userInfo: userInfo))
					return
				}

				guard let account = AccountManager.shared.existingAccount(accountID: accountID) else {
					let userInfo = [NSLocalizedDescriptionKey: "Account no longer exists"]
					activityLog.didFail(.ao3ChapterFetcher, kind: kind, error: NSError(domain: "Nectar", code: -1, userInfo: userInfo))
					return
				}
				let existingArticles = await account.fetchArticlesAsync(.articleIDs([articleID]))
				guard let existingArticle = existingArticles.first else {
					let userInfo = [NSLocalizedDescriptionKey: "Article no longer exists"]
					activityLog.didFail(.ao3ChapterFetcher, kind: kind, error: NSError(domain: "Nectar", code: -1, userInfo: userInfo))
					return
				}

				let parsedItem = Self.rebuildParsedItem(from: existingArticle, workID: workID, extraction: extraction)
				_ = await account.updateAsync(feedID: feedID, parsedItems: [parsedItem], deleteOlder: false)

				activityLog.didComplete(.ao3ChapterFetcher, kind: kind, message: ActivityLog.dataSizeMessage(data), returnedFromCache: downloadResponse.returnedFromCache)
				postNotification(articleID: articleID)

			} catch {
				// Pre-response failure (DNS, TLS, network) -- same
				// leave-it-alone handling.
				activityLog.didFail(.ao3ChapterFetcher, kind: kind, error: error)
			}
		}
	}

	/// Copies every field from `existingArticle` unchanged except
	/// `contentHTML` (the freshly fetched, workskin-preserving HTML) and
	/// `chapterCurrent` (bumped to the chapter count actually found in this
	/// fetch). `chapterTotal`/`isComplete` are left as whatever the article
	/// already has -- those are Workstream 1's (feed-derived) territory, and
	/// a partial chapter fetch shouldn't be used to infer completion.
	///
	/// `tags` and `language` have no persisted home on `Article` at all (see
	/// ParsedItem/Article field lists), so both are passed through as nil --
	/// this doesn't blank anything that was ever actually stored.
	static func rebuildParsedItem(from existingArticle: Article, workID: String, extraction: AO3ChapterExtractionResult) -> ParsedItem {
		let authors: Set<ParsedAuthor>? = existingArticle.authors.map { authorSet in
			Set(authorSet.map { ParsedAuthor(name: $0.name, url: $0.url, avatarURL: $0.avatarURL, emailAddress: $0.emailAddress) })
		}
		let series: [ParsedSeriesEntry]? = existingArticle.series?.map { ParsedSeriesEntry(name: $0.name, index: $0.index, ao3ID: $0.ao3ID) }

		return ParsedItem(
			syncServiceID: nil,
			uniqueID: existingArticle.uniqueID,
			feedURL: existingArticle.feedID,
			url: existingArticle.rawLink,
			externalURL: existingArticle.rawExternalLink,
			title: existingArticle.title,
			language: nil,
			contentHTML: extraction.contentHTML,
			contentText: existingArticle.contentText,
			// existingArticle.markdown is expected nil for every AO3-sourced
			// article (markdown is an Ambrosia/JSON-Feed-only concept, never
			// populated from an AO3 Atom feed) -- passing it through as-is is
			// still correct field-copying, but flag the interaction: if this
			// were ever non-nil, ParsedItem's init would re-render markdown
			// to HTML and discard the contentHTML fetched above entirely.
			markdown: existingArticle.markdown,
			summary: existingArticle.summary,
			imageURL: existingArticle.rawImageLink,
			bannerImageURL: nil,
			datePublished: existingArticle.datePublished,
			dateModified: existingArticle.dateModified,
			authors: authors,
			tags: nil,
			attachments: nil,
			isAmbrosiaItem: false,
			wordCount: existingArticle.wordCount,
			chapterCurrent: extraction.chapters.count,
			chapterTotal: existingArticle.chapterTotal,
			isComplete: existingArticle.isComplete,
			fandoms: existingArticle.fandoms,
			relationships: existingArticle.relationships,
			characters: existingArticle.characters,
			ratings: existingArticle.ratings,
			warnings: existingArticle.warnings,
			categories: existingArticle.categories,
			series: series,
			ao3WorkID: workID
		)
	}

	func postNotification(articleID: String) {
		let userInfo: [String: Any] = [AO3ChapterFetchUserInfoKey.articleID: articleID]
		NotificationCenter.default.postOnMainThread(
			name: .ao3ChapterFetchDidComplete, object: self, userInfo: userInfo
		)
	}
}
