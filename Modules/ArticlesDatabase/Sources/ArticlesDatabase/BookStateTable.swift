//
//  BookStateTable.swift
//  NetNewsWire
//
//  Consolidated book-level state, one row per bookKey, replacing the former
//  BookReadStateTable / BookStarredStateTable / BookLovedStateTable (each of
//  which stored a single TEXT-enum column keyed by bookKey) plus giving
//  scrollPosition and readingProgress the same bookKey-keyed treatment those
//  three already had. All five properties genuinely describe "this book, for
//  this reader" rather than "this (feed, guid) pair," so they belong in one
//  row together rather than four near-identical single-purpose tables that
//  can drift out of sync with each other.
//
//  This table is the *primary* store for read/starred/loved/scrollPosition
//  going forward; the parallel columns on `statuses` remain as a fallback for
//  the rare row with no resolvable bookKey (see ArticlesTable.bookKeysForArticleIDs'
//  `bookKey ?? uniqueID` convention -- in practice this fallback should be
//  nearly unreachable, but it costs nothing to keep). Fallback rows are
//  ordinary `statuses` rows and so are cleaned up automatically whenever a
//  feed's articles/statuses are deleted -- no special-casing needed for that.
//
//  Because the key is bookKey (not articleID), the same book appearing in
//  more than one Ambrosia collection feed at once shares one row here: a
//  read/loved/starred toggle or a scroll position update made through any one
//  copy is immediately the state for every copy. This is deliberate -- it's
//  the same book.

// CREATE TABLE if not EXISTS bookState (bookKey TEXT NOT NULL PRIMARY KEY, read BOOL NOT NULL DEFAULT 0, starred BOOL NOT NULL DEFAULT 0, loved BOOL NOT NULL DEFAULT 0, scrollPosition REAL NOT NULL DEFAULT 0, readingProgress REAL, lastOpenedAt DATE, updatedAt DATE NOT NULL, kudosAttemptedAt DATE, kudosAttemptedAuthenticated BOOL NOT NULL DEFAULT 0);

import Foundation
import RSDatabase
import RSDatabaseObjC

/// A book's full state as stored in bookState. Booleans/scrollPosition default to
/// false/0 for columns a partial upsert has never touched, matching the table's own
/// column defaults -- so a row that exists only because someone set a scroll
/// position, say, correctly reports read/starred/loved as false rather than nil.
struct BookState: Sendable {
	var read: Bool
	var starred: Bool
	var loved: Bool
	var scrollPosition: Double
	var readingProgress: Double?
	var lastOpenedAt: Date?

	// Kudos-on-like (Task 6). kudosAttemptedAt nil = never attempted;
	// kudosAttemptedAuthenticated is only meaningful when kudosAttemptedAt
	// is non-nil -- see the DatabaseKey.kudosAttemptedAt doc comment.
	var kudosAttemptedAt: Date?
	var kudosAttemptedAuthenticated: Bool
}

final class BookStateTable: DatabaseTable, Sendable {
	let name = DatabaseTableName.bookState
	private let queue: DatabaseQueue

	init(queue: DatabaseQueue) {
		self.queue = queue
	}

	/// Full state for a set of bookKeys, only returning entries that have a row --
	/// a book with no prior history is simply absent from the result.
	func state(for bookKeys: Set<String>, _ database: FMDatabase) -> [String: BookState] {
		guard !bookKeys.isEmpty else {
			return [:]
		}
		guard let resultSet = self.selectRowsWhere(key: DatabaseKey.bookKey, inValues: Array(bookKeys), in: database) else {
			return [:]
		}

		var d = [String: BookState]()
		while resultSet.next() {
			guard let bookKey = resultSet.swiftString(forColumn: DatabaseKey.bookKey) else {
				continue
			}
			d[bookKey] = BookState(
				read: resultSet.bool(forColumn: DatabaseKey.read),
				starred: resultSet.bool(forColumn: DatabaseKey.starred),
				loved: resultSet.bool(forColumn: DatabaseKey.loved),
				scrollPosition: resultSet.double(forColumn: DatabaseKey.scrollPosition),
				readingProgress: resultSet.columnIsNull(DatabaseKey.readingProgress) ? nil : resultSet.double(forColumn: DatabaseKey.readingProgress),
				lastOpenedAt: resultSet.columnIsNull(DatabaseKey.lastOpenedAt) ? nil : resultSet.date(forColumn: DatabaseKey.lastOpenedAt),
				kudosAttemptedAt: resultSet.columnIsNull(DatabaseKey.kudosAttemptedAt) ? nil : resultSet.date(forColumn: DatabaseKey.kudosAttemptedAt),
				kudosAttemptedAuthenticated: resultSet.bool(forColumn: DatabaseKey.kudosAttemptedAuthenticated)
			)
		}
		return d
	}

	// MARK: - Read/starred/loved
	//
	// Kept as three typed setters (rather than one generic "set this column"
	// entry point taking an ArticleStatus.Key) so this module doesn't have to
	// depend on the Articles module's status-key type just to know which
	// column to touch.

	func setRead(_ flag: Bool, bookKeys: Set<String>, _ database: FMDatabase) {
		upsert(bookKeys: bookKeys, column: DatabaseKey.read, value: flag, database)
	}

	func setStarred(_ flag: Bool, bookKeys: Set<String>, _ database: FMDatabase) {
		upsert(bookKeys: bookKeys, column: DatabaseKey.starred, value: flag, database)
	}

	func setLoved(_ flag: Bool, bookKeys: Set<String>, _ database: FMDatabase) {
		upsert(bookKeys: bookKeys, column: DatabaseKey.loved, value: flag, database)
	}

	// MARK: - Scroll position / reading progress

	func scrollPosition(for bookKey: String, _ database: FMDatabase) -> Double {
		state(for: [bookKey], database)[bookKey]?.scrollPosition ?? 0
	}

	func setScrollPosition(_ value: Double, bookKey: String, _ database: FMDatabase) {
		upsert(bookKeys: [bookKey], column: DatabaseKey.scrollPosition, value: value, database)
	}

	func readingProgress(for bookKey: String, _ database: FMDatabase) -> Double? {
		state(for: [bookKey], database)[bookKey]?.readingProgress
	}

	func setReadingProgress(_ value: Double, bookKey: String, _ database: FMDatabase) {
		upsert(bookKeys: [bookKey], column: DatabaseKey.readingProgress, value: value, database)
	}

	// MARK: - Last opened (Last Opened smart feed)

	func setLastOpenedAt(_ date: Date, bookKey: String, _ database: FMDatabase) {
		upsert(bookKeys: [bookKey], column: DatabaseKey.lastOpenedAt, value: date, database)
	}

	// MARK: - Kudos-on-like (Task 6)
	//
	// Two columns need to change together atomically (the timestamp and
	// whether the attempt was authenticated), unlike every other property
	// above, so this doesn't go through the single-column `upsert` helper
	// below -- see setKudosAttempted's own INSERT ... ON CONFLICT.

	/// nil if a kudos POST has never been attempted for this book.
	func kudosAttempt(for bookKey: String, _ database: FMDatabase) -> (attemptedAt: Date, authenticated: Bool)? {
		guard let state = state(for: [bookKey], database)[bookKey], let attemptedAt = state.kudosAttemptedAt else {
			return nil
		}
		return (attemptedAt, state.kudosAttemptedAuthenticated)
	}

	func setKudosAttempted(at date: Date, authenticated: Bool, bookKey: String, _ database: FMDatabase) {
		let now = Date()
		database.executeUpdate(
			"""
			INSERT INTO \(name) (\(DatabaseKey.bookKey), \(DatabaseKey.kudosAttemptedAt), \(DatabaseKey.kudosAttemptedAuthenticated), \(DatabaseKey.updatedAt))
			VALUES (?, ?, ?, ?)
			ON CONFLICT(\(DatabaseKey.bookKey)) DO UPDATE SET
				\(DatabaseKey.kudosAttemptedAt) = excluded.\(DatabaseKey.kudosAttemptedAt),
				\(DatabaseKey.kudosAttemptedAuthenticated) = excluded.\(DatabaseKey.kudosAttemptedAuthenticated),
				\(DatabaseKey.updatedAt) = excluded.\(DatabaseKey.updatedAt)
			""",
			withArgumentsIn: [bookKey, date, authenticated, now]
		)
	}

	// MARK: - Private

	/// Partial upsert of a single column, leaving every other column on an
	/// existing row untouched (see the class-level doc comment on why a raw
	/// INSERT ... ON CONFLICT is used instead of insertRows(insertType: .orReplace)).
	/// `value` must be a type FMDB's argument binding already accepts directly --
	/// Bool, Double, or Date, matching this table's only non-String columns.
	private func upsert(bookKeys: Set<String>, column: String, value: Sendable, _ database: FMDatabase) {
		guard !bookKeys.isEmpty else {
			return
		}
		let now = Date()
		for bookKey in bookKeys {
			database.executeUpdate(
				"INSERT INTO \(name) (\(DatabaseKey.bookKey), \(column), \(DatabaseKey.updatedAt)) VALUES (?, ?, ?) ON CONFLICT(\(DatabaseKey.bookKey)) DO UPDATE SET \(column) = excluded.\(column), \(DatabaseKey.updatedAt) = excluded.\(DatabaseKey.updatedAt)",
				withArgumentsIn: [bookKey, value, now]
			)
		}
	}
}
