//
//  AmbrosiaSQLiteTransferFetcher.swift
//  NetNewsWire
//
//  Nectar Implementation Plan, Phase 2, sections 2d ("Client timeout fix"),
//  2e ("Import path"), and 3b/3c/3d (paginated walk loop + gap detection).
//
//  Fetches every page of a paginated `.sqlite` transfer walk from one of
//  Ambrosia's three routes, decompressing (LZFSE, raw bytes, no
//  Content-Encoding header per the Wire Contract) and importing each page in
//  turn. Deliberately bypasses DownloadSession: a single page can still take
//  a while and DownloadSession's default 15s timeoutIntervalForRequest would
//  kill it outright, so this uses the same bare-URLSession bypass pattern
//  LocalAccountRefresher.mergedParsedFeed already uses for next_url
//  pagination page-fetches (URLSession.shared.data(from:)), just with its
//  own session/configuration instead of the shared one, so the generous
//  timeout doesn't leak into unrelated requests.
//
//  Gap detection (plan 3c): every page's `transfer_manifest` is read and
//  validated (via ArticlesDatabase.readAmbrosiaSQLiteTransferManifest)
//  before a single row is imported. A page that fails this check is retried
//  a bounded number of times; a walk_id mismatch on a resumed walk discards
//  progress and restarts fresh at page 1; a final-page row-count mismatch
//  marks the whole walk `.incomplete` even though every individual page
//  passed its own check. None of this is folded into ordinary network-error
//  handling -- see AmbrosiaSQLiteWalkResult.
//

import Foundation
import os
import RSWeb
import ArticlesDatabase

enum AmbrosiaSQLiteTransferError: Error, CustomStringConvertible {
	case badResponse(Int?)
	case decompressFailed
	case tempFileWriteFailed(String)

	var description: String {
		switch self {
		case .badResponse(let statusCode):
			return "Ambrosia SQLite transfer: bad HTTP response (\(statusCode.map(String.init) ?? "no status"))"
		case .decompressFailed:
			return "Ambrosia SQLite transfer: LZFSE decompress failed"
		case .tempFileWriteFailed(let detail):
			return "Ambrosia SQLite transfer: could not write decompressed file to disk (\(detail))"
		}
	}
}

/// Internal-only signaling for `fetchPageWithRetries`'s two non-retryable
/// (or already-exhausted-retries) outcomes. Never surfaced to callers of
/// `fetchAndImportWalk` as a thrown error -- both are handled inside the
/// walk loop itself (plan 3c/3d).
private enum AmbrosiaSQLiteTransferWalkControl: Error {
	case walkIDMismatch
	case exhaustedRetries
}

/// Outcome of a full paginated `.sqlite` transfer walk (plan 3b/3d).
/// `.incomplete` is a first-class result, not an error: a walk that
/// exhausted its per-page retry budget, or failed final-total validation,
/// is reported this way so the caller can surface a distinct "sync
/// incomplete" status instead of routing it through the generic
/// feed-refresh-error path. It is retried automatically on the next
/// scheduled refresh (resuming from the persisted state this call leaves
/// behind), but stays visible until a walk actually reaches `.complete`.
enum AmbrosiaSQLiteWalkResult {
	case complete(pagesImported: Int, rowsImported: Int)
	case incomplete(pagesImported: Int, rowsImported: Int, expectedTotal: Int, lastPageAttempted: Int)
}

enum AmbrosiaSQLiteTransferFetcher {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AmbrosiaSQLiteTransferFetcher")

	/// Generous timeout for a whole-database transfer, as opposed to
	/// DownloadSession's 15s default meant for ordinary feed-sized requests.
	/// Not a magic number chosen here in isolation -- section 2d calls out
	/// that a multi-minute transfer must not be killed "unconditionally,
	/// regardless of anything else in this plan," so this errs long.
	private static let timeoutIntervalForRequest: TimeInterval = 300

	private static let session: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
		configuration.timeoutIntervalForResource = timeoutIntervalForRequest
		return URLSession(configuration: configuration)
	}()

	/// Bounded retry budget for a single page (plan 3c/5.2) -- a
	/// transfer_manifest that's missing or internally inconsistent, or an
	/// ordinary transient network failure, gets this many attempts (with a
	/// short exponential backoff) before the whole walk is given up on for
	/// this refresh cycle and reported `.incomplete`. Proposed starting
	/// value per the plan; open to adjusting based on how flaky observed
	/// drops turn out to be in practice.
	private static let maxAttemptsPerPage = 3
	private static let retryBackoffBaseSeconds: TimeInterval = 1

	/// Runs a full paginated walk for one Ambrosia `.sqlite` feed, resuming
	/// from persisted `AmbrosiaSQLiteTransferWalkState` when one exists and
	/// is still `.inProgress` (plan 3b.1). `baseURL` is the feed's page-less
	/// `.sqlite` URL (e.g. `.../feed/collection/<id>.sqlite`); this method
	/// appends/replaces `page=` itself for every page.
	static func fetchAndImportWalk(baseURL: URL, feedID: String, into articlesDatabase: ArticlesDatabase) async throws -> AmbrosiaSQLiteWalkResult {

		var page: Int
		var walkID: String?
		var importedRowCountSoFar: Int

		if let existing = AmbrosiaSQLiteTransferWalkStateStore.load(feedID: feedID), existing.status == .inProgress {
			// Resume: request the next page on the same URL, and verify
			// (inside fetchPageWithRetries) that the response's walk_id
			// still matches before importing.
			page = existing.lastImportedPage + 1
			walkID = existing.walkID
			importedRowCountSoFar = existing.importedRowCountSoFar
			Self.logger.notice("AmbrosiaSQLiteTransferFetcher: resuming walk for feedID \(feedID, privacy: .public) at page \(page) (walkID \(existing.walkID, privacy: .public))")
		} else {
			// No state, or a previous walk finished (.complete or
			// .incomplete) and this is a fresh refresh cycle: always start
			// a new walk at page 1 -- "page=1 always means start over" is
			// the rule the server side relies on too.
			page = 1
			walkID = nil
			importedRowCountSoFar = 0
			AmbrosiaSQLiteTransferWalkStateStore.clear(feedID: feedID)
		}

		var pagesImportedThisCall = 0

		while true {
			let pageURL = Self.url(for: baseURL, page: page)

			let fetchResult: (temporaryFilePath: String, manifest: AmbrosiaSQLiteTransferManifest)
			do {
				fetchResult = try await Self.fetchPageWithRetries(url: pageURL, feedID: feedID, expectedWalkID: walkID, articlesDatabase: articlesDatabase)
			} catch AmbrosiaSQLiteTransferWalkControl.walkIDMismatch {
				// The server restarted, or its cache entry was pruned/evicted
				// and a page=1 request from something else regenerated it,
				// between our last successful page and now (plan 3c). Do not
				// attempt to append this page's rows onto the old walk's
				// progress -- discard the stored state entirely and start a
				// brand-new walk at page 1 with the new walk_id. Deliberate
				// full restart, not a silent merge of two walks' data.
				Self.logger.notice("AmbrosiaSQLiteTransferFetcher: walk_id mismatch resuming feedID \(feedID, privacy: .public) -- discarding state and restarting at page 1")
				AmbrosiaSQLiteTransferWalkStateStore.clear(feedID: feedID)
				page = 1
				walkID = nil
				importedRowCountSoFar = 0
				continue
			} catch AmbrosiaSQLiteTransferWalkControl.exhaustedRetries {
				// Every attempt for this page failed (bad manifest or
				// transient network error). Give up on this walk for this
				// refresh cycle: already-imported pages' article data stays
				// (harmless/idempotent to have partially imported), and the
				// persisted state records exactly how far we got so the next
				// scheduled refresh resumes right here instead of starting
				// over.
				let state = AmbrosiaSQLiteTransferWalkState(
					feedID: feedID,
					walkID: walkID ?? UUID().uuidString,
					lastImportedPage: page - 1,
					expectedTotalRowCount: 0,
					importedRowCountSoFar: importedRowCountSoFar,
					status: .incomplete
				)
				AmbrosiaSQLiteTransferWalkStateStore.save(state)
				return .incomplete(pagesImported: pagesImportedThisCall, rowsImported: importedRowCountSoFar, expectedTotal: 0, lastPageAttempted: page)
			}

			let (temporaryFilePath, manifest) = fetchResult
			walkID = manifest.walkID

			do {
				try await articlesDatabase.importAmbrosiaSQLiteTransfer(temporaryFilePath: temporaryFilePath, feedID: feedID, wireFormatVersion: AmbrosiaSQLiteWireFormat.version)
			} catch {
				try? FileManager.default.removeItem(atPath: temporaryFilePath)
				throw error
			}
			try? FileManager.default.removeItem(atPath: temporaryFilePath)

			importedRowCountSoFar += manifest.pageRowCount
			pagesImportedThisCall += 1

			if manifest.hasMore {
				let state = AmbrosiaSQLiteTransferWalkState(
					feedID: feedID,
					walkID: manifest.walkID,
					lastImportedPage: page,
					expectedTotalRowCount: manifest.expectedTotalRowCount,
					importedRowCountSoFar: importedRowCountSoFar,
					status: .inProgress
				)
				AmbrosiaSQLiteTransferWalkStateStore.save(state)
				page += 1
				continue
			}

			// Final page: compare importedRowCountSoFar (accumulated across
			// every page actually imported in this walk) against
			// expected_total_row_count from this final page's manifest. If
			// they don't match, treat the *entire walk* as failed even
			// though every individual page passed its own per-page check
			// above -- the server's underlying candidate set can shift
			// between page 1 and the last page of a long walk (plan 3c).
			if importedRowCountSoFar == manifest.expectedTotalRowCount {
				AmbrosiaSQLiteTransferWalkStateStore.clear(feedID: feedID)
				return .complete(pagesImported: pagesImportedThisCall, rowsImported: importedRowCountSoFar)
			} else {
				Self.logger.error("AmbrosiaSQLiteTransferFetcher: final-total mismatch for feedID \(feedID, privacy: .public) -- imported \(importedRowCountSoFar), expected \(manifest.expectedTotalRowCount)")
				let state = AmbrosiaSQLiteTransferWalkState(
					feedID: feedID,
					walkID: manifest.walkID,
					lastImportedPage: page,
					expectedTotalRowCount: manifest.expectedTotalRowCount,
					importedRowCountSoFar: importedRowCountSoFar,
					status: .incomplete
				)
				AmbrosiaSQLiteTransferWalkStateStore.save(state)
				return .incomplete(pagesImported: pagesImportedThisCall, rowsImported: importedRowCountSoFar, expectedTotal: manifest.expectedTotalRowCount, lastPageAttempted: page)
			}
		}
	}

	/// Appends/replaces the `page` query parameter on `baseURL`. `page == 1`
	/// is sent with no `page` parameter at all (matching the server's
	/// `?? 1` default), consistent with every existing Ambrosia route.
	private static func url(for baseURL: URL, page: Int) -> URL {
		guard page > 1, var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
			return baseURL
		}
		var items = (components.queryItems ?? []).filter { $0.name != "page" }
		items.append(URLQueryItem(name: "page", value: String(page)))
		components.queryItems = items
		return components.url ?? baseURL
	}

	/// Fetches, decompresses, writes to a temp file, and validates one page,
	/// with up to `maxAttemptsPerPage` attempts. A wire-format-version
	/// mismatch is a hard, non-retryable failure (propagated immediately, a
	/// build/version skew bug, not something a retry fixes). A walk_id
	/// mismatch against `expectedWalkID` (when resuming) is also not
	/// retried -- see `AmbrosiaSQLiteTransferWalkControl.walkIDMismatch`.
	/// Every other failure (network error, decompress failure, missing/
	/// inconsistent manifest) counts against the retry budget; once
	/// exhausted, throws `.exhaustedRetries`.
	private static func fetchPageWithRetries(url: URL, feedID: String, expectedWalkID: String?, articlesDatabase: ArticlesDatabase) async throws -> (temporaryFilePath: String, manifest: AmbrosiaSQLiteTransferManifest) {
		for attempt in 1...maxAttemptsPerPage {
			do {
				return try await Self.fetchPageOnce(url: url, expectedWalkID: expectedWalkID, articlesDatabase: articlesDatabase)
			} catch AmbrosiaSQLiteTransferWalkControl.walkIDMismatch {
				throw AmbrosiaSQLiteTransferWalkControl.walkIDMismatch
			} catch let error as AmbrosiaSQLiteImportError {
				if case .wireFormatVersionMismatch = error {
					throw error
				}
				Self.logger.error("AmbrosiaSQLiteTransferFetcher: page fetch/validate attempt \(attempt) failed for feedID \(feedID, privacy: .public): \(error.description, privacy: .public)")
			} catch {
				Self.logger.error("AmbrosiaSQLiteTransferFetcher: page fetch/validate attempt \(attempt) failed for feedID \(feedID, privacy: .public): \(error.localizedDescription, privacy: .public)")
			}

			if attempt < maxAttemptsPerPage {
				let backoffSeconds = retryBackoffBaseSeconds * pow(2, Double(attempt - 1))
				try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
			}
		}
		throw AmbrosiaSQLiteTransferWalkControl.exhaustedRetries
	}

	/// One attempt: fetch, decompress, write temp file, validate manifest
	/// (version + row-count consistency), and check `expectedWalkID` when
	/// resuming. Cleans up the temp file itself on every failure path.
	private static func fetchPageOnce(url: URL, expectedWalkID: String?, articlesDatabase: ArticlesDatabase) async throws -> (temporaryFilePath: String, manifest: AmbrosiaSQLiteTransferManifest) {
		Self.logger.debug("AmbrosiaSQLiteTransferFetcher: fetching \(url.absoluteString, privacy: .public)")

		let (compressedData, response) = try await session.data(from: url)
		guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusIsOK else {
			throw AmbrosiaSQLiteTransferError.badResponse((response as? HTTPURLResponse)?.statusCode)
		}

		// Hard error on decompress failure -- unlike the CloudKitArticlesZone
		// reference pattern's `try?` (which silently drops a failed
		// compress/decompress and continues), this route treats it as a hard
		// failure, matching the versioning hard-fail policy.
		guard let decompressedData = try? (compressedData as NSData).decompressed(using: .lzfse) else {
			throw AmbrosiaSQLiteTransferError.decompressFailed
		}

		let temporaryFilePath = NSTemporaryDirectory() + "ambrosia-transfer-\(UUID().uuidString).sqlite"
		do {
			try (decompressedData as Data).write(to: URL(fileURLWithPath: temporaryFilePath))
		} catch {
			throw AmbrosiaSQLiteTransferError.tempFileWriteFailed(error.localizedDescription)
		}

		do {
			// Reads and validates transfer_manifest + PRAGMA user_version
			// before anything is imported (plan 3c) -- a manifest that's
			// missing or internally inconsistent, or a version mismatch,
			// means this page's file must not be trusted at all.
			let manifest = try articlesDatabase.readAmbrosiaSQLiteTransferManifest(temporaryFilePath: temporaryFilePath, wireFormatVersion: AmbrosiaSQLiteWireFormat.version)

			if let expectedWalkID, manifest.walkID != expectedWalkID {
				try? FileManager.default.removeItem(atPath: temporaryFilePath)
				throw AmbrosiaSQLiteTransferWalkControl.walkIDMismatch
			}

			return (temporaryFilePath, manifest)
		} catch {
			if case AmbrosiaSQLiteTransferWalkControl.walkIDMismatch = error {
				throw error
			}
			try? FileManager.default.removeItem(atPath: temporaryFilePath)
			throw error
		}
	}

}