//
//  ContentHTMLCompression.swift
//  ArticlesDatabase
//
//  Compress contentHTML at rest (Wire Contract's compression reference).
//
//  Reuses the same NSData.compressed(using: .lzfse)/decompressed(using: .lzfse)
//  Foundation API.
//
//  articles.contentHTML and pendingUpdateContentHTML are stored as native
//  SQLite BLOBs containing raw LZFSE-compressed bytes, avoiding the ~33%
//  space inflation and string churn of Base64 encoding.
//
//  Backward compatibility:
//  `decompressAny` seamlessly handles:
//  1. `Data` (modern LZFSE binary BLOB).
//  2. `String` (legacy Base64-encoded LZFSE string).
//  3. Uncompressed fallback (if data/string was stored plain before compression).
//
import Foundation

public enum ContentHTMLCompression {

	/// Compresses `html` for storage as raw LZFSE binary `Data`.
	/// Returns nil if input is nil or empty, and falls back to storing
	/// the UTF-8 bytes of the original string if LZFSE compression fails
	/// for some reason, rather than losing the content.
	public static func compress(_ html: String?) -> Data? {
		guard let html, !html.isEmpty else {
			return nil
		}
		let data = Data(html.utf8)
		guard let compressed = try? (data as NSData).compressed(using: .lzfse) else {
			return data
		}
		return compressed as Data
	}

	/// Legacy string-returning compressor preserved for callers that specifically
	/// require a Base64-encoded string representation.
	public static func compressBase64(_ html: String?) -> String? {
		guard let data = compress(html) else {
			return html
		}
		return data.base64EncodedString()
	}

	/// Decompresses any supported storage format:
	/// 1. `Data` (modern raw LZFSE binary bytes, or uncompressed UTF-8 fallback).
	/// 2. `String` (legacy Base64-encoded LZFSE string, or legacy plain text).
	public static func decompressAny(_ stored: Any?) -> String? {
		guard let stored, !(stored is NSNull) else {
			return nil
		}
		if let data = stored as? Data {
			return decompress(data)
		}
		if let string = stored as? String {
			return decompress(string)
		}
		return nil
	}

	/// Decompresses raw LZFSE bytes, falling back to UTF-8 decoding if uncompressed.
	public static func decompress(_ data: Data?) -> String? {
		guard let data, !data.isEmpty else {
			return nil
		}
		if let decompressed = try? (data as NSData).decompressed(using: .lzfse) {
			return String(data: decompressed as Data, encoding: .utf8)
		}
		return String(data: data, encoding: .utf8)
	}

	/// Reverses legacy string storage. See the type-level doc comment for why a
	/// decode/decompress failure falls back to the stored value as-is instead
	/// of throwing.
	public static func decompress(_ stored: String?) -> String? {
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
