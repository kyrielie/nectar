//
//  BookStarredStateTable.swift
//  NetNewsWire
//
//  Book-level starred state, parallel to BookReadStateTable (see that file
//  for the rationale behind keying on Article.bookKey instead of (feed,
//  guid)). Kept as its own table, rather than folding into
//  BookReadStateTable, so the read/starred/loved write-throughs in
//  ArticlesTable.mark(_:_:_:_:) stay simple one-flag-per-table upserts.

// CREATE TABLE if not EXISTS bookStarredState (bookKey TEXT NOT NULL PRIMARY KEY, state TEXT NOT NULL, updatedAt DATE NOT NULL);

import Foundation
import RSDatabase
import RSDatabaseObjC

private enum BookStarredStateValue: String {
	case starred
	case unstarred
}

final class BookStarredStateTable: DatabaseTable, Sendable {
	let name = DatabaseTableName.bookStarredState
	private let queue: DatabaseQueue

	init(queue: DatabaseQueue) {
		self.queue = queue
	}

	/// Starred state for a set of bookKeys, only returning entries that have a
	/// row -- a book with no prior starred/unstarred history is simply absent
	/// from the result.
	func state(for bookKeys: Set<String>, _ database: FMDatabase) -> [String: Bool] {
		guard !bookKeys.isEmpty else {
			return [:]
		}
		guard let resultSet = self.selectRowsWhere(key: DatabaseKey.bookKey, inValues: Array(bookKeys), in: database) else {
			return [:]
		}

		var d = [String: Bool]()
		while resultSet.next() {
			guard let bookKey = resultSet.swiftString(forColumn: DatabaseKey.bookKey),
				  let stateString = resultSet.swiftString(forColumn: DatabaseKey.state),
				  let value = BookStarredStateValue(rawValue: stateString) else {
				continue
			}
			d[bookKey] = (value == .starred)
		}
		return d
	}

	/// Upsert starred state for every bookKey in the set.
	func setState(_ flag: Bool, bookKeys: Set<String>, _ database: FMDatabase) {
		guard !bookKeys.isEmpty else {
			return
		}
		let value: BookStarredStateValue = flag ? .starred : .unstarred
		let now = Date()
		let rows: [DatabaseDictionary] = bookKeys.map { bookKey in
			[
				DatabaseKey.bookKey: bookKey,
				DatabaseKey.state: value.rawValue,
				DatabaseKey.updatedAt: now
			]
		}
		self.insertRows(rows, insertType: .orReplace, in: database)
	}
}
