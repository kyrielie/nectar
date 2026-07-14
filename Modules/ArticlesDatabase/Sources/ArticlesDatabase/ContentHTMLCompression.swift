//
//  ContentHTMLCompression.swift
//  ArticlesDatabase
//
//  Nectar Implementation Plan, Phase 3 ("compress contentHTML at rest").
//
//  Reuses the same NSData.compressed(using: .lzfse)/decompressed(using: .lzfse)
//  Foundation API this codebase already uses for CloudKit sync (see
//  Modules/Account/Sources/Account/CloudKit/CloudKitArticlesZone.swift's
//  compressArticleRecords and CloudKitArticlesZoneDelegate.swift), per the
//  Wire Contract's compression reference in the implementation plan.
//
//  articles.contentHTML is a TEXT column (see ArticlesDatabase.swift's
//  `CREATE TABLE ... articles` statement) and FMDB's row accessors this
//  codebase uses elsewhere are all String-based (row.swiftString(forColumn:)),
//  so compressed bytes are base64-encoded into a String rather than switching
//  the column to BLOB or adding a raw-bytes FMDB call path.
//
//  No migration path: per the plan, this is still in development, so there's
//  no concern about pre-existing uncompressed rows in a dev database. decompress
//  still falls back to returning the stored string as-is if it isn't valid
//  base64/LZFSE, purely so a row written before this landed doesn't crash the
//  reader mid-development -- not a supported compatibility guarantee.
//
import Foundation

enum ContentHTMLCompression {

	/// Compresses `html` for storage. Returns nil/empty input unchanged
	/// (nothing to compress), and falls back to storing the original string
	/// if LZFSE compression fails for some reason, rather than losing the
	/// content -- matching the CloudKitArticlesZone reference pattern's
	/// tolerance for compress failures (as opposed to the wire-transfer
	/// route's decompress step, which is a hard failure by design).
	static func compress(_ html: String?) -> String? {
		guard let html, !html.isEmpty else {
			return html
		}
		let data = Data(html.utf8) as NSData
		guard let compressed = try? data.compressed(using: .lzfse) else {
			return html
		}
		return (compressed as Data).base64EncodedString()
	}

	/// Reverses `compress(_:)`. See the type-level doc comment for why a
	/// decode/decompress failure falls back to the stored value as-is instead
	/// of throwing.
	static func decompress(_ stored: String?) -> String? {
		guard let stored, !stored.isEmpty else {
			return stored
		}
		guard let data = Data(base64Encoded: stored) else {
			return stored
		}
		guard let decompressed = try? (data as NSData).decompressed(using: .lzfse) else {
			return stored
		}
		return String(data: decompressed as Data, encoding: .utf8) ?? stored
	}
}
