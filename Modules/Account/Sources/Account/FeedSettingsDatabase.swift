//
//  FeedSettingsDatabase.swift
//  Account
//
//  Created by Brent Simmons on 3/6/26.
//

import Foundation
import os
import RSDatabase
import RSDatabaseObjC
import RSWeb
import Articles

enum FeedSettingsRestoreError: Error, CustomStringConvertible {
	case attachFailed(String)
	case mergeFailed(String)

	var description: String {
		switch self {
		case .attachFailed(let detail):
			return "FeedSettings restore: ATTACH DATABASE failed (\(detail))"
		case .mergeFailed(let detail):
			return "FeedSettings restore: merge failed (\(detail))"
		}
	}
}

final class FeedSettingsDatabase: Sendable {
	enum Column: String {
		case feedID
		case homePageURL
		case iconURL
		case faviconURL
		case editedName
		case contentHash
		case newArticleNotificationsEnabled
		case authors
		case conditionalGetInfoLastModified
		case conditionalGetInfoEtag
		case conditionalGetInfoDate
		case cacheControlInfoDateCreated
		case cacheControlInfoMaxAge
		case externalID
		case folderRelationship
		case lastCheckDate
		case lastResponseCode
		case ao3SearchLastFetchedPage
		case ao3SearchFetchedPages
		case ao3SearchTotalPages
	}

	struct Row {
		let feedID: String
		let homePageURL: String?
		let iconURL: String?
		let faviconURL: String?
		let editedName: String?
		let contentHash: String?
		let newArticleNotificationsEnabled: Bool
		let authors: Set<Author>?
		let conditionalGetInfo: HTTPConditionalGetInfo?
		let conditionalGetInfoDate: Date?
		let cacheControlInfo: CacheControlInfo?
		let externalID: String?
		let folderRelationship: [String: String]?
		let lastCheckDate: Date?
		let lastResponseCode: Int?
		let ao3SearchLastFetchedPage: Int?
		let ao3SearchFetchedPages: Set<Int>?
		let ao3SearchTotalPages: Int?
	}

	let databasePath: String

	nonisolated(unsafe) private let database: FMDatabase // Used on serial dispatch queue only
	private let serialDispatchQueue: DispatchQueue
	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedSettingsDatabase")

	init(databasePath: String) {
		self.databasePath = databasePath
		self.serialDispatchQueue = DispatchQueue(label: "FeedSettingsDatabase")
		self.database = FMDatabase.openAndSetUpDatabase(path: databasePath)
		serialDispatchQueue.sync { [database] in
			database.runCreateStatements(Self.tableCreationStatements)
			if !database.columnExists("lastResponseCode", inTableWithName: "feedSettings") {
				database.executeStatements("ALTER TABLE feedSettings ADD COLUMN lastResponseCode INTEGER;")
			}
			if !database.columnExists("ao3SearchLastFetchedPage", inTableWithName: "feedSettings") {
				database.executeStatements("ALTER TABLE feedSettings ADD COLUMN ao3SearchLastFetchedPage INTEGER;")
			}
			if !database.columnExists("ao3SearchFetchedPages", inTableWithName: "feedSettings") {
				database.executeStatements("ALTER TABLE feedSettings ADD COLUMN ao3SearchFetchedPages TEXT;")
				Self.backfillFetchedPagesFromLegacyColumn(database)
			}
			if !database.columnExists("ao3SearchTotalPages", inTableWithName: "feedSettings") {
				database.executeStatements("ALTER TABLE feedSettings ADD COLUMN ao3SearchTotalPages INTEGER;")
			}
		}
		vacuumIfNeeded()
	}

	func vacuum() async {
		await withCheckedContinuation { continuation in
			serialDispatchQueue.async {
				self.database.vacuum()
				continuation.resume()
			}
		}
	}

	func vacuumIfNeeded() {
		serialDispatchQueue.async {
			self.database.vacuumIfNeeded()
		}
	}

	var isEmpty: Bool {
		serialDispatchQueue.sync {
			guard let resultSet = self.database.executeQuery("SELECT 1 FROM feedSettings LIMIT 1;", withArgumentsIn: []) else {
				return true
			}
			defer {
				resultSet.close()
			}
			return !resultSet.next()
		}
	}

	// MARK: - Feed Existence

	func ensureFeedExists(_ feedURL: String, feedID: String) {
		serialDispatchQueue.async {
			self.database.executeUpdate("INSERT OR IGNORE INTO feedSettings (feedURL, feedID) VALUES (?, ?);", withArgumentsIn: [feedURL, feedID])
		}
	}

	/// Renames a row's primary key (`feedURL`) in place, preserving every other
	/// column (editedName, cacheControlInfo, lastCheckDate, notification
	/// preference, etc.) -- used by `Account.repointFeed(_:to:)` so a feed whose
	/// address changes doesn't silently lose its settings, the way an unguarded
	/// `deleteSettingsForFeedsNotIn` cleanup would.
	func repointFeedURL(from oldFeedURL: String, to newFeedURL: String) {
		serialDispatchQueue.async {
			self.database.executeUpdate("UPDATE feedSettings SET feedURL = ? WHERE feedURL = ?;", withArgumentsIn: [newFeedURL, oldFeedURL])
		}
	}

	// MARK: - Insert Row

	func insertRow(_ feedURL: String, _ columnValues: [Column: Any]) {
		var dictionary = DatabaseDictionary()
		dictionary["feedURL"] = feedURL
		for (column, value) in columnValues {
			dictionary[column.rawValue] = value
		}
		nonisolated(unsafe) let capturedDictionary = dictionary
		serialDispatchQueue.async {
			self.database.insertRow(capturedDictionary, insertType: .orReplace, tableName: "feedSettings")
		}
	}

	// MARK: - Fetch Rows

	func allRows() -> [String: Row] {
		serialDispatchQueue.sync {
			guard let resultSet = self.database.executeQuery("SELECT * FROM feedSettings;", withArgumentsIn: []) else {
				return [:]
			}
			defer {
				resultSet.close()
			}

			var rows = [String: Row]()
			while resultSet.next() {
				if let feedURL = resultSet.swiftString(forColumn: "feedURL") {
					rows[feedURL] = self.row(from: resultSet)
				}
			}
			return rows
		}
	}

	// MARK: - String

	func setString(_ value: String?, for feedURL: String, column: Column) {
		let name = column.rawValue
		serialDispatchQueue.async {
			if let value {
				self.database.executeUpdate("UPDATE feedSettings SET \(name) = ? WHERE feedURL = ?;", withArgumentsIn: [value, feedURL])
			} else {
				self.database.executeUpdate("UPDATE feedSettings SET \(name) = NULL WHERE feedURL = ?;", withArgumentsIn: [feedURL])
			}
		}
	}

	// MARK: - Bool

	func setBool(_ value: Bool, for feedURL: String, column: Column) {
		let name = column.rawValue
		serialDispatchQueue.async {
			self.database.executeUpdate("UPDATE feedSettings SET \(name) = ? WHERE feedURL = ?;", withArgumentsIn: [value, feedURL])
		}
	}

	// MARK: - Int

	func setInt(_ value: Int?, for feedURL: String, column: Column) {
		let name = column.rawValue
		serialDispatchQueue.async {
			if let value {
				self.database.executeUpdate("UPDATE feedSettings SET \(name) = ? WHERE feedURL = ?;", withArgumentsIn: [value, feedURL])
			} else {
				self.database.executeUpdate("UPDATE feedSettings SET \(name) = NULL WHERE feedURL = ?;", withArgumentsIn: [feedURL])
			}
		}
	}

	// MARK: - Set<Int>

	/// `Set<Int>` is trivially `Codable`, so this is a plain
	/// `JSONEncoder`/`JSONDecoder` round-trip -- unlike `authors`, which
	/// needs `Author`'s own custom `.json()`/`.authorsWithJSON(_:)`
	/// machinery because `Author` itself requires custom encoding.
	func setSetOfInt(_ value: Set<Int>?, for feedURL: String, column: Column) {
		let name = column.rawValue
		serialDispatchQueue.async {
			if let value {
				guard let data = try? JSONEncoder().encode(value), let jsonString = String(data: data, encoding: .utf8) else {
					return
				}
				self.database.executeUpdate("UPDATE feedSettings SET \(name) = ? WHERE feedURL = ?;", withArgumentsIn: [jsonString, feedURL])
			} else {
				self.database.executeUpdate("UPDATE feedSettings SET \(name) = NULL WHERE feedURL = ?;", withArgumentsIn: [feedURL])
			}
		}
	}

	// MARK: - Date

	func setDate(_ value: Date?, for feedURL: String, column: Column) {
		let name = column.rawValue
		serialDispatchQueue.async {
			if let value {
				self.database.executeUpdate("UPDATE feedSettings SET \(name) = ? WHERE feedURL = ?;", withArgumentsIn: [value.timeIntervalSinceReferenceDate, feedURL])
			} else {
				self.database.executeUpdate("UPDATE feedSettings SET \(name) = NULL WHERE feedURL = ?;", withArgumentsIn: [feedURL])
			}
		}
	}

	// MARK: - Compound Types

	func setConditionalGetInfo(_ info: HTTPConditionalGetInfo?, for feedURL: String) {
		serialDispatchQueue.async {
			if let info {
				self.database.executeUpdate("UPDATE feedSettings SET conditionalGetInfoLastModified = ?, conditionalGetInfoEtag = ? WHERE feedURL = ?;", withArgumentsIn: [info.lastModified as Any, info.etag as Any, feedURL])
			} else {
				self.database.executeUpdate("UPDATE feedSettings SET conditionalGetInfoLastModified = NULL, conditionalGetInfoEtag = NULL WHERE feedURL = ?;", withArgumentsIn: [feedURL])
			}
		}
	}

	func setCacheControlInfo(_ info: CacheControlInfo?, for feedURL: String) {
		serialDispatchQueue.async {
			if let info {
				self.database.executeUpdate("UPDATE feedSettings SET cacheControlInfoDateCreated = ?, cacheControlInfoMaxAge = ? WHERE feedURL = ?;", withArgumentsIn: [info.dateCreated.timeIntervalSinceReferenceDate, info.maxAge, feedURL])
			} else {
				self.database.executeUpdate("UPDATE feedSettings SET cacheControlInfoDateCreated = NULL, cacheControlInfoMaxAge = NULL WHERE feedURL = ?;", withArgumentsIn: [feedURL])
			}
		}
	}

	func setAuthors(_ authors: Set<Author>?, for feedURL: String) {
		serialDispatchQueue.async {
			if let authors {
				let jsonString = authors.json()
				self.database.executeUpdate("UPDATE feedSettings SET authors = ? WHERE feedURL = ?;", withArgumentsIn: [jsonString as Any, feedURL])
			} else {
				self.database.executeUpdate("UPDATE feedSettings SET authors = NULL WHERE feedURL = ?;", withArgumentsIn: [feedURL])
			}
		}
	}

	func setFolderRelationship(_ relationship: [String: String]?, for feedURL: String) {
		serialDispatchQueue.async {
			if let relationship {
				if let data = try? JSONSerialization.data(withJSONObject: relationship), let jsonString = String(data: data, encoding: .utf8) {
					self.database.executeUpdate("UPDATE feedSettings SET folderRelationship = ? WHERE feedURL = ?;", withArgumentsIn: [jsonString, feedURL])
				}
			} else {
				self.database.executeUpdate("UPDATE feedSettings SET folderRelationship = NULL WHERE feedURL = ?;", withArgumentsIn: [feedURL])
			}
		}
	}

	// MARK: - Deletion

	func deleteSettings(for feedURL: String) {
		serialDispatchQueue.async {
			self.database.executeUpdate("DELETE FROM feedSettings WHERE feedURL = ?;", withArgumentsIn: [feedURL])
		}
	}

	// MARK: - Backup/restore merge

	/// Backup/restore plan, Correction 6: `INSERT OR IGNORE` keyed on
	/// `feedURL` -- an existing local row always wins, the backup's row only
	/// ever fills in a feed that has no local row at all. Not every column
	/// here is disposable cache (`editedName`/`newArticleNotificationsEnabled`
	/// are real user customization -- see Correction 6's own reasoning), but
	/// with no per-row timestamp on this table to arbitrate a genuine
	/// conflict, "keep local" is the only mechanically sound default for v1,
	/// same conclusion the plan reaches for `statuses`' pre-timestamp era.
	/// Mirrors `BackupSQLiteImportTable`'s ATTACH/BEGIN/DETACH ordering
	/// exactly (see that file's extended comment on why DETACH must run only
	/// after an explicit commit/rollback, not inside a deferred-COMMIT
	/// block) -- this table doesn't have a `DatabaseQueue` wrapper the way
	/// `ArticlesDatabase` does, so transaction control and DETACH are done
	/// directly against `self.database` on `serialDispatchQueue`, the same
	/// queue every other method on this type already confines its database
	/// access to.
	func mergeFromBackup(atPath backupPath: String) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			serialDispatchQueue.async {
				let attachedSchemaName = "feedSettings_restore"

				guard self.database.executeUpdate("ATTACH DATABASE ? AS \(attachedSchemaName);", withArgumentsIn: [backupPath]) else {
					continuation.resume(throwing: FeedSettingsRestoreError.attachFailed(self.database.lastErrorMessage() ?? "unknown error"))
					return
				}

				var mergeError: Error?
				self.database.beginTransaction()
				let sql = """
				INSERT OR IGNORE INTO feedSettings (
				  feedURL, feedID, homePageURL, iconURL, faviconURL, editedName, contentHash,
				  newArticleNotificationsEnabled, authors, conditionalGetInfoLastModified,
				  conditionalGetInfoEtag, conditionalGetInfoDate, cacheControlInfoDateCreated,
				  cacheControlInfoMaxAge, externalID, folderRelationship, lastCheckDate,
				  lastResponseCode, ao3SearchLastFetchedPage, ao3SearchFetchedPages, ao3SearchTotalPages
				)
				SELECT
				  b.feedURL, b.feedID, b.homePageURL, b.iconURL, b.faviconURL, b.editedName, b.contentHash,
				  b.newArticleNotificationsEnabled, b.authors, b.conditionalGetInfoLastModified,
				  b.conditionalGetInfoEtag, b.conditionalGetInfoDate, b.cacheControlInfoDateCreated,
				  b.cacheControlInfoMaxAge, b.externalID, b.folderRelationship, b.lastCheckDate,
				  b.lastResponseCode, b.ao3SearchLastFetchedPage, b.ao3SearchFetchedPages, b.ao3SearchTotalPages
				FROM \(attachedSchemaName).feedSettings AS b;
				"""
				if self.database.executeUpdate(sql, withArgumentsIn: []) {
					self.database.commit()
				} else {
					mergeError = FeedSettingsRestoreError.mergeFailed(self.database.lastErrorMessage() ?? "unknown error")
					self.database.rollback()
				}

				self.database.clearCachedStatements()
				if !self.database.executeUpdate("DETACH DATABASE \(attachedSchemaName);", withArgumentsIn: []) {
					Self.logger.error("FeedSettingsDatabase: DETACH DATABASE \(attachedSchemaName, privacy: .public) failed -- \(self.database.lastErrorMessage() ?? "unknown error", privacy: .public)")
				}

				if let mergeError {
					continuation.resume(throwing: mergeError)
				} else {
					continuation.resume()
				}
			}
		}
	}

	// MARK: - Cleanup on launch

	func deleteSettingsForFeedsNotIn(_ feedURLs: Set<String>) {
		guard !feedURLs.isEmpty else {
			return
		}

		let feedURLsArray = Array(feedURLs)
		serialDispatchQueue.async {
			let placeholders = NSString.rs_SQLValueList(withPlaceholders: UInt(feedURLsArray.count))!
			let sql = "DELETE FROM feedSettings WHERE feedURL NOT IN \(placeholders);"
			self.database.executeUpdate(sql, withArgumentsIn: feedURLsArray)

			#if DEBUG
			let numberOfRowChanges: Int32 = self.database.changes()
			if numberOfRowChanges > 0 {
				Self.logger.info("FeedSettingsDatabase: deleteSettingsForFeedsNotIn: deleted \(numberOfRowChanges) orphaned feed settings")
			}
			#endif
		}
	}
}

// MARK: - Private

private extension FeedSettingsDatabase {

	static let tableCreationStatements = """
	CREATE TABLE IF NOT EXISTS feedSettings (feedURL TEXT PRIMARY KEY, feedID TEXT NOT NULL DEFAULT '', homePageURL TEXT, iconURL TEXT, faviconURL TEXT, editedName TEXT, contentHash TEXT, newArticleNotificationsEnabled INTEGER NOT NULL DEFAULT 0, authors TEXT, conditionalGetInfoLastModified TEXT, conditionalGetInfoEtag TEXT, conditionalGetInfoDate REAL, cacheControlInfoDateCreated REAL, cacheControlInfoMaxAge REAL, externalID TEXT, folderRelationship TEXT, lastCheckDate REAL, lastResponseCode INTEGER, ao3SearchLastFetchedPage INTEGER, ao3SearchFetchedPages TEXT, ao3SearchTotalPages INTEGER);
	"""

	/// Every page fetched before `ao3SearchFetchedPages` existed was
	/// fetched sequentially with no gaps (the old "load more" was always
	/// `highest + 1`), so this backfill is exact, not a guess: for each row
	/// where the legacy `ao3SearchLastFetchedPage` is non-null and
	/// `ao3SearchFetchedPages` is still null, write
	/// `ao3SearchFetchedPages = Set(1...oldValue)`. Runs once, immediately
	/// after the column is added, on `serialDispatchQueue` (called only
	/// from inside the `init` block already confined to that queue).
	static func backfillFetchedPagesFromLegacyColumn(_ database: FMDatabase) {
		guard let resultSet = database.executeQuery("SELECT feedURL, ao3SearchLastFetchedPage FROM feedSettings WHERE ao3SearchLastFetchedPage IS NOT NULL;", withArgumentsIn: []) else {
			return
		}
		var updates = [(feedURL: String, jsonString: String)]()
		while resultSet.next() {
			guard let feedURL = resultSet.swiftString(forColumn: "feedURL") else {
				continue
			}
			let oldValue = Int(resultSet.int(forColumn: "ao3SearchLastFetchedPage"))
			guard oldValue >= 1 else {
				continue
			}
			let fetchedPages = Set(1...oldValue)
			guard let data = try? JSONEncoder().encode(fetchedPages), let jsonString = String(data: data, encoding: .utf8) else {
				continue
			}
			updates.append((feedURL, jsonString))
		}
		resultSet.close()

		for update in updates {
			database.executeUpdate("UPDATE feedSettings SET ao3SearchFetchedPages = ? WHERE feedURL = ?;", withArgumentsIn: [update.jsonString, update.feedURL])
		}
	}

	func row(from resultSet: FMResultSet) -> Row {
		let lastModified = resultSet.swiftString(forColumn: Column.conditionalGetInfoLastModified.rawValue)
		let etag = resultSet.swiftString(forColumn: Column.conditionalGetInfoEtag.rawValue)

		var conditionalGetInfoDate: Date?
		if !resultSet.columnIsNull(Column.conditionalGetInfoDate.rawValue) {
			conditionalGetInfoDate = Date(timeIntervalSinceReferenceDate: resultSet.double(forColumn: Column.conditionalGetInfoDate.rawValue))
		}

		var cacheControlInfo: CacheControlInfo?
		if !resultSet.columnIsNull(Column.cacheControlInfoDateCreated.rawValue) && !resultSet.columnIsNull(Column.cacheControlInfoMaxAge.rawValue) {
			let dateCreated = Date(timeIntervalSinceReferenceDate: resultSet.double(forColumn: Column.cacheControlInfoDateCreated.rawValue))
			let maxAge = resultSet.double(forColumn: Column.cacheControlInfoMaxAge.rawValue)
			cacheControlInfo = CacheControlInfo(dateCreated: dateCreated, maxAge: maxAge)
		}

		var authors: Set<Author>?
		if let authorsData = resultSet.data(forColumn: Column.authors.rawValue) {
			authors = Author.authorsWithJSON(authorsData)
		}

		var folderRelationship: [String: String]?
		if let folderData = resultSet.data(forColumn: Column.folderRelationship.rawValue) {
			folderRelationship = try? JSONSerialization.jsonObject(with: folderData) as? [String: String]
		}

		var lastCheckDate: Date?
		if !resultSet.columnIsNull(Column.lastCheckDate.rawValue) {
			lastCheckDate = Date(timeIntervalSinceReferenceDate: resultSet.double(forColumn: Column.lastCheckDate.rawValue))
		}

		var lastResponseCode: Int?
		if !resultSet.columnIsNull(Column.lastResponseCode.rawValue) {
			lastResponseCode = Int(resultSet.int(forColumn: Column.lastResponseCode.rawValue))
		}

		var ao3SearchLastFetchedPage: Int?
		if !resultSet.columnIsNull(Column.ao3SearchLastFetchedPage.rawValue) {
			ao3SearchLastFetchedPage = Int(resultSet.int(forColumn: Column.ao3SearchLastFetchedPage.rawValue))
		}

		var ao3SearchFetchedPages: Set<Int>?
		if let jsonString = resultSet.swiftString(forColumn: Column.ao3SearchFetchedPages.rawValue), let data = jsonString.data(using: .utf8) {
			ao3SearchFetchedPages = try? JSONDecoder().decode(Set<Int>.self, from: data)
		}

		var ao3SearchTotalPages: Int?
		if !resultSet.columnIsNull(Column.ao3SearchTotalPages.rawValue) {
			ao3SearchTotalPages = Int(resultSet.int(forColumn: Column.ao3SearchTotalPages.rawValue))
		}

		return Row(
			feedID: resultSet.swiftString(forColumn: Column.feedID.rawValue) ?? "",
			homePageURL: resultSet.swiftString(forColumn: Column.homePageURL.rawValue),
			iconURL: resultSet.swiftString(forColumn: Column.iconURL.rawValue),
			faviconURL: resultSet.swiftString(forColumn: Column.faviconURL.rawValue),
			editedName: resultSet.swiftString(forColumn: Column.editedName.rawValue),
			contentHash: resultSet.swiftString(forColumn: Column.contentHash.rawValue),
			newArticleNotificationsEnabled: resultSet.bool(forColumn: Column.newArticleNotificationsEnabled.rawValue),
			authors: authors,
			conditionalGetInfo: HTTPConditionalGetInfo(lastModified: lastModified, etag: etag),
			conditionalGetInfoDate: conditionalGetInfoDate,
			cacheControlInfo: cacheControlInfo,
			externalID: resultSet.swiftString(forColumn: Column.externalID.rawValue),
			folderRelationship: folderRelationship,
			lastCheckDate: lastCheckDate,
			lastResponseCode: lastResponseCode,
			ao3SearchLastFetchedPage: ao3SearchLastFetchedPage,
			ao3SearchFetchedPages: ao3SearchFetchedPages,
			ao3SearchTotalPages: ao3SearchTotalPages
		)
	}
}
