import AO3Kit
//
//  AO3KudosManager.swift
//  Account
//
//  Nectar AO3 direct-reading support, Task 6 ("kudos-on-like").
//
//  Two entry points, one shared attempt path:
//
//  - attemptKudosIfNeeded(article:workID:csrfToken:) -- the piggyback path,
//    called from AO3ChapterFetcher.download's success handler with the CSRF
//    token that fetch's own page load already scraped. No dedicated
//    request needed: opening/refreshing an already-loved article's chapter
//    is common enough (every stale-check refetch) that reusing that
//    fetch's token avoids a second round trip to AO3 for the common case.
//
//  - attemptImmediateKudosIfNeeded(for:) -- the list-view path, called from
//    SceneCoordinator when an article is marked loved from a list action
//    (swipe/context menu) rather than by opening it. There's no
//    accompanying page fetch to piggyback a token off of here, so this
//    dispatches its own dedicated, token-only fetch of the work's page --
//    unlike the piggyback path, it can't wait for the next natural
//    chapter-content refetch, since that could be arbitrarily far in the
//    future (or never, once AO3FetchPolicy.isStale goes permanently
//    false) and the person just loved this from the list expecting the
//    kudos-on-like behavior (once enabled) to fire close to when they
//    tapped, not on some later, unrelated refresh.
//
//  Both funnel into the same eligibility gate and re-attempt policy:
//  feature toggle on, book loved, a CSRF token available, and -- per
//  Account.kudosAttempt(bookKey:)/setKudosAttempted(bookKey:authenticated:)
//  -- no already-authenticated attempt on record. A prior guest attempt is
//  retried once signed in (an authenticated kudos and a guest kudos are
//  AO3-side distinct identities -- see AO3KudosOutcome.alreadyKudosed's doc
//  comment); an authenticated attempt, successful or not, is never retried
//  automatically.
//
//  Entirely fire-and-forget and silently no-op for anything ineligible --
//  neither entry point returns a value or throws. Failures are visible only
//  via the Activity Log (ActivityOwner.ao3KudosManager), the same place
//  AO3ChapterFetcher's own failures show up.
//

import Foundation
import RSParser
import RSWeb
import Articles
import ActivityLog
import os

public enum AO3KudosManager {

	// attemptWithFreshFetch below fires its own dedicated URLSession request
	// rather than going through Downloader.shared, so it produced no console
	// output at all until this was added -- see this file's header comment
	// for why it needs its own fetch, and the Task 8 audit note on why that
	// made this exact request invisible when diagnosing the Ambrosia-toggle
	// leak. "Requesting AO3:" prefix matches AO3KudosFetcher's so both are
	// greppable as one group, distinct from Downloader's own "Downloader:"
	// lines.
	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nectar", category: "AO3KudosManager")

	/// Piggyback path -- see this file's header comment. `csrfToken` comes
	/// straight from `AO3ChapterHTMLExtractor`'s scrape of the same page
	/// fetch; `nil` (the meta tag was missing) is a no-op, same as every
	/// other ineligibility case here.
	public static func attemptKudosIfNeeded(article: Article, workID: String, csrfToken: String?) {
		guard AO3KudosOnLikePreference.isEnabled else { return }
		guard article.status.loved else { return }
		guard let csrfToken else { return }

		Task {
			await attempt(article: article, workID: workID, csrfToken: csrfToken)
		}
	}

	/// List-view path -- see this file's header comment. Takes the whole
	/// batch `markArticlesWithUndo` just loved, rather than one article at
	/// a time, so callers (SceneCoordinator) don't need to filter down to
	/// the AO3-sourced, newly loved subset themselves; this does that
	/// filtering internally via the same eligibility checks
	/// `attemptKudosIfNeeded` uses.
	public static func attemptImmediateKudosIfNeeded(for articles: [Article]) {
		guard AO3KudosOnLikePreference.isEnabled else { return }

		var eligible = [(article: Article, workID: String)]()
		for article in articles {
			guard article.status.loved else { continue }
			guard let workID = AO3FetchPolicy.workID(fromBookKey: article.bookKey) else { continue }
			// Bug fix (Task 8 audit): this path fires its own dedicated request to
			// AO3 (see attemptWithFreshFetch below) rather than piggybacking on an
			// existing fetch, so it must independently respect the same
			// Ambrosia-local-only-reader gate AO3ChapterFetcher.fetchIfNeeded/
			// checkForUpdates already apply -- this was missing entirely, letting
			// a swipe/context-menu love on an Ambrosia-sourced work reach AO3
			// regardless of AmbrosiaAO3NetworkPreference.updatesEnabled being off.
			guard AO3FetchPolicy.isNetworkRequestAllowed(for: article) else { continue }
			eligible.append((article, workID))
		}
		guard !eligible.isEmpty else { return }

		// One task, one article at a time, with the same pause AO3's paged
		// requests use between them. A multi-select love used to start one
		// concurrent request per article.
		Task {
			for (index, item) in eligible.enumerated() {
				if index > 0 {
					try? await Task.sleep(nanoseconds: UInt64(AO3ChapterFetcher.secondsBetweenAO3PagedRequests * 1_000_000_000))
				}
				await attemptWithFreshFetch(article: item.article, workID: item.workID)
			}
		}
	}
}

// MARK: - Private

private extension AO3KudosManager {

	/// List-view path's dedicated fetch -- gets a page load purely for its
	/// CSRF token (see this file's header comment for why the piggyback
	/// path's token isn't available here). Goes through `Downloader.shared`
	/// with caching vetoed. Deliberately anonymous, same as
	/// AO3ChapterFetcher's primary fetch: the CSRF token itself doesn't
	/// depend on being signed in (see AO3ChapterHTMLExtractor.csrfToken's
	/// doc comment), and whether the actual kudos POST goes out
	/// authenticated is decided separately, in `attempt(...)`, from
	/// AO3SessionStore.isSignedIn at attempt time -- not from how this
	/// token happened to be fetched.
	static func attemptWithFreshFetch(article: Article, workID: String) async {
		guard let url = AO3Link.workURL(id: workID) else { return }

		logger.debug("Requesting AO3: GET \(url.absoluteString, privacy: .public) (list-view kudos CSRF fetch, articleID=\(article.articleID, privacy: .public))")

		// Routed through Downloader so this request shares its per-host
		// cooldown, User-Agent, redirect handling and one-connection-per-host
		// cap with every other AO3 fetch. Never cached: a CSRF token is tied
		// to a session and goes stale.
		guard let downloadResponse = try? await Downloader.shared.download(url, shouldCache: { _, _ in false }),
			  let data = downloadResponse.data,
			  let response = downloadResponse.response, response.statusIsOK,
			  let html = String(data: data, encoding: .utf8) else {
			return
		}

		guard case .success(let result) = AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html),
			  let csrfToken = result.csrfToken else {
			return
		}

		await attempt(article: article, workID: workID, csrfToken: csrfToken)
	}

	/// The shared eligibility/re-attempt-policy/networking path both entry
	/// points funnel into. `csrfToken` is assumed already scraped from a
	/// real page fetch by the caller -- this never invents one.
	@MainActor
	static func attempt(article: Article, workID: String, csrfToken: String) async {
		let bookKey = article.bookKey
		guard let account = AccountManager.shared.existingAccount(accountID: article.accountID) else { return }

		if let existingAttempt = await account.kudosAttempt(bookKey: bookKey) {
			// Re-attempt policy -- see this file's header comment.
			guard !existingAttempt.authenticated, AO3SessionStore.isSignedIn else { return }
		}

		let cookieHeaderValue = AO3SessionStore.isSignedIn ? AO3SessionStore.cookieHeaderValue : nil
		let authenticated = cookieHeaderValue != nil

		let activityLog = ActivityLog.shared
		let kind = ActivityKind.leaveAO3Kudos(workID: workID)
		activityLog.createActivity(owner: .ao3KudosManager, kind: kind, detail: nil)
		activityLog.didStart(.ao3KudosManager, kind: kind)

		do {
			let outcome = try await AO3KudosFetcher.leaveKudos(workID: workID, csrfToken: csrfToken, cookieHeaderValue: cookieHeaderValue)
			switch outcome {
			case .success, .alreadyKudosed:
				await account.setKudosAttempted(bookKey: bookKey, authenticated: authenticated)
				activityLog.didComplete(.ao3KudosManager, kind: kind, message: outcome == .alreadyKudosed ? "Already kudosed" : nil)
				NotificationCenter.default.post(name: .ao3KudosDidSucceed, object: nil, userInfo: [
					AO3KudosUserInfoKey.articleID: article.articleID,
					AO3KudosUserInfoKey.workID: workID
				])
			case .authError, .invalidWork, .rateLimited, .otherFailure:
				// Not recorded as attempted -- a fresh token from a later
				// fetch (or, for .rateLimited, simply trying again later)
				// gets another chance rather than being permanently
				// blocked by this one failure.
				fail(kind: kind, activityLog: activityLog, message: message(for: outcome))
				NotificationCenter.default.post(name: .ao3KudosDidFail, object: nil, userInfo: [
					AO3KudosUserInfoKey.articleID: article.articleID,
					AO3KudosUserInfoKey.workID: workID
				])
			}
		} catch {
			fail(kind: kind, activityLog: activityLog, message: error.localizedDescription, error: error)
		}
	}

	static func message(for outcome: AO3KudosOutcome) -> String {
		switch outcome {
		case .success, .alreadyKudosed:
			return ""
		case .authError:
			return "AO3 rejected the kudos request (auth error)"
		case .invalidWork:
			return "AO3 didn't recognize this work"
		case .rateLimited:
			return "AO3 rate limit hit while leaving kudos"
		case .otherFailure(let message):
			return message
		}
	}

	@MainActor
	static func fail(kind: ActivityKind, activityLog: ActivityLog, message: String, error: Error? = nil) {
		let loggedError = error ?? NSError(domain: "Nectar", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
		activityLog.didFail(.ao3KudosManager, kind: kind, error: loggedError)
	}
}
