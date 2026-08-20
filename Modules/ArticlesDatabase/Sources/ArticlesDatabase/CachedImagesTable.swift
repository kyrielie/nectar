//
//  CachedImagesTable.swift
//  ArticlesDatabase
//
//  Persistent, backup/export-visible cache for images fetched via the
//  in-app image viewer (both <img> taps and the AO3-off-site-art <a
//  href="....jpg"> case). Rows live in the account's own DB.sqlite3,
//  not a Caches-directory file, so a cached copy survives even after
//  the source link goes stale/deleted -- see
//  nectar-toolbar-image-link-viewer.md's "Persistent, backup/export-
//  visible image cache" section for the full rationale (this deliberately
//  diverges from the Images/ImageDownloader favicon precedent).
//
//  Write-once per (articleID, imageURL): unlike annotations, a cached
//  image never changes once fetched, so upsert(_:) uses a plain INSERT
//  OR REPLACE rather than an ON CONFLICT DO UPDATE column list, and
//  BackupSQLiteImportTable's merge rule for this table is a plain
//  INSERT OR IGNORE (see that file's header comment for why annotations
//  needed a later-updatedAt-wins rule instead and this table doesn't).
//

// CREATE TABLE if not EXISTS cachedImages (articleID TEXT NOT NULL, imageURL TEXT NOT NULL, imageData TEXT NOT NULL, dateCached DATE NOT NULL, PRIMARY KEY (articleID, imageURL));
// CREATE INDEX if not EXISTS cachedImages_articleID_index on cachedImages (articleID);

import Foundation
import RSDatabase
import RSDatabaseObjC

final class CachedImagesTable: DatabaseTable, Sendable {
	let name = DatabaseTableName.cachedImages
	private let queue: DatabaseQueue

	init(queue: DatabaseQueue) {
		self.queue = queue
	}

	// MARK: - Fetching

	/// Cache-first lookup for a single image, keyed on the composite
	/// primary key. Returns the LZFSE-compressed, base64-encoded imageData
	/// as stored -- decompression is the caller's job (matching
	/// ContentHTMLCompression's split of concerns), so this table stays
	/// agnostic of the compression scheme the same way ArticlesTable's row
	/// accessors do for contentHTML.
	func fetchCachedImage(articleID: String, imageURL: String, _ database: FMDatabase) -> CachedImage? {
		guard let resultSet = database.executeQuery(
			"select * from \(name) where \(DatabaseKey.articleID) = ? and \(DatabaseKey.url) = ?;",
			withArgumentsIn: [articleID, imageURL]
		) else {
			return nil
		}
		defer {
			resultSet.close()
		}
		guard resultSet.next() else {
			return nil
		}
		return cachedImageWithRow(resultSet)
	}

	func fetchCachedImageAsync(articleID: String, imageURL: String, _ completion: @escaping @Sendable (CachedImage?) -> Void) {
		queue.runInDatabase { database in
			let image = self.fetchCachedImage(articleID: articleID, imageURL: imageURL, database)
			DispatchQueue.main.async {
				completion(image)
			}
		}
	}

	// MARK: - Saving

	/// Write-once upsert: a cached image for a given (articleID, imageURL)
	/// never changes once fetched (see file header), so this is a plain
	/// INSERT OR REPLACE rather than a column-by-column upsert -- there's
	/// no "leave the other columns alone" case the way BookStateTable's
	/// partial upsert has, and no divergent-value case the way
	/// AnnotationsTable.save's ON CONFLICT DO UPDATE has.
	func save(articleID: String, imageURL: String, imageData: String, dateCached: Date, _ database: FMDatabase) {
		database.executeUpdate(
			"""
			INSERT OR REPLACE INTO \(name) (
				\(DatabaseKey.articleID), \(DatabaseKey.url), \(DatabaseKey.imageData), \(DatabaseKey.dateCached)
			) VALUES (?, ?, ?, ?)
			""",
			withArgumentsIn: [articleID, imageURL, imageData, dateCached]
		)
	}

	func saveAsync(articleID: String, imageURL: String, imageData: String, dateCached: Date, _ completion: (@Sendable () -> Void)? = nil) {
		queue.runInDatabase { database in
			self.save(articleID: articleID, imageURL: imageURL, imageData: imageData, dateCached: dateCached, database)
			DispatchQueue.main.async {
				completion?()
			}
		}
	}

	// MARK: - Deleting

	/// Deletes every cached image for the given articleIDs. Called from
	/// ArticlesTable.clearContentHTML inside that method's own transaction
	/// -- see the call site's comment for why this must not open its own
	/// transaction here.
	func deleteAll(articleIDs: Set<String>, _ database: FMDatabase) {
		guard !articleIDs.isEmpty else { return }
		self.deleteRowsWhere(key: DatabaseKey.articleID, equalsAnyValue: Array(articleIDs), in: database)
	}

	// MARK: - Private

	private func cachedImageWithRow(_ resultSet: FMResultSet) -> CachedImage? {
		guard
			let articleID = resultSet.swiftString(forColumn: DatabaseKey.articleID),
			let imageURL = resultSet.swiftString(forColumn: DatabaseKey.url),
			let imageData = resultSet.swiftString(forColumn: DatabaseKey.imageData),
			let dateCached = resultSet.date(forColumn: DatabaseKey.dateCached)
		else {
			return nil
		}
		return CachedImage(articleID: articleID, imageURL: imageURL, imageData: imageData, dateCached: dateCached)
	}
}

/// imageData is the LZFSE-compressed, base64-encoded string as stored --
/// same TEXT-column-not-BLOB reasoning as ContentHTMLCompression (see that
/// file's header comment). Decompression happens at the call site, via
/// ContentHTMLCompression.decompress(_:), which is format-agnostic despite
/// its name (see that type's doc comment).
public struct CachedImage: Sendable {
	public let articleID: String
	public let imageURL: String
	public let imageData: String
	public let dateCached: Date
}
