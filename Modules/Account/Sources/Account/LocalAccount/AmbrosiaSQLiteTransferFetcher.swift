//
//  AmbrosiaSQLiteTransferFetcher.swift
//  NetNewsWire
//
//  Nectar Implementation Plan, Phase 2, sections 2d ("Client timeout fix")
//  and 2e ("Import path").
//
//  Fetches a `.sqlite` transfer file from one of Ambrosia's three new routes,
//  decompresses it (LZFSE, raw bytes, no Content-Encoding header per the Wire
//  Contract), writes it to a temp file, and hands it to ArticlesDatabase's
//  importer. Deliberately bypasses DownloadSession: a single-file transfer
//  can take minutes and DownloadSession's default 15s timeoutIntervalForRequest
//  would kill it outright, so this uses the same bare-URLSession bypass
//  pattern LocalAccountRefresher.mergedParsedFeed already uses for next_url
//  pagination page-fetches (URLSession.shared.data(from:)), just with its own
//  session/configuration instead of the shared one, so the generous timeout
//  doesn't leak into unrelated requests.
//
//  Partial-success handling: none, by design (plan 2g) -- a dropped
//  connection means redo the whole fetch. Nothing to build here beyond
//  surfacing the failure to the caller.
//

import Foundation
import os
import ArticlesDatabase

enum AmbrosiaSQLiteTransferError: Error, CustomStringConvertible {
	case decompressFailed
	case tempFileWriteFailed(String)

	var description: String {
		switch self {
		case .decompressFailed:
			return "Ambrosia SQLite transfer: LZFSE decompress failed"
		case .tempFileWriteFailed(let detail):
			return "Ambrosia SQLite transfer: could not write decompressed file to disk (\(detail))"
		}
	}
}

enum AmbrosiaSQLiteTransferFetcher {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AmbrosiaSQLiteTransferFetcher")

	/// Generous timeout for a whole-database transfer, as opposed to
	/// DownloadSession's 15s default meant for ordinary feed-sized requests.
	/// Not a magic number chosen here in isolation -- section 2d calls out
	/// that a multi-minute transfer must not be killed "unconditionally,
	/// regardless of anything else in this plan," so this errs long.
	private static let timeoutIntervalForRequest: TimeInterval = 300

	private static var session: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
		configuration.timeoutIntervalForResource = timeoutIntervalForRequest
		return URLSession(configuration: configuration)
	}()

	/// Fetches `url`, decompresses the response body, writes it to a temp file,
	/// runs the version check, and imports it into `articlesDatabase` under
	/// `feedID`. Throws (no partial writes) on any failure: network,
	/// decompression, or the version-mismatch/import errors from
	/// AmbrosiaSQLiteImportTable via ArticlesDatabase.importAmbrosiaSQLiteTransfer.
	static func fetchAndImport(url: URL, into articlesDatabase: ArticlesDatabase, feedID: String) async throws {
		Self.logger.debug("AmbrosiaSQLiteTransferFetcher: fetching \(url.absoluteString, privacy: .public)")

		let (compressedData, _) = try await session.data(from: url)

		// Hard error on decompress failure -- unlike the CloudKitArticlesZone
		// reference pattern's `try?` (which silently drops a failed
		// compress/decompress and continues), this route treats it as a hard
		// failure, matching the versioning hard-fail policy: a decompress
		// failure here almost certainly means the same kind of skew/corruption
		// problem a version mismatch would, not something to quietly skip.
		guard let decompressedData = try? (compressedData as NSData).decompressed(using: .lzfse) else {
			throw AmbrosiaSQLiteTransferError.decompressFailed
		}

		let temporaryFilePath = NSTemporaryDirectory() + "ambrosia-transfer-\(UUID().uuidString).sqlite"
		do {
			try (decompressedData as Data).write(to: URL(fileURLWithPath: temporaryFilePath))
		} catch {
			throw AmbrosiaSQLiteTransferError.tempFileWriteFailed(error.localizedDescription)
		}
		defer {
			try? FileManager.default.removeItem(atPath: temporaryFilePath)
		}

		try articlesDatabase.importAmbrosiaSQLiteTransfer(temporaryFilePath: temporaryFilePath, feedID: feedID, wireFormatVersion: AmbrosiaSQLiteWireFormat.version)
	}
}
