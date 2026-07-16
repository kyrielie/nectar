//
//  BookLovedStateTable.swift
//  NetNewsWire
//
//  Book-level loved state, parallel to BookReadStateTable and
//  BookStarredStateTable (see BookReadStateTable for the rationale behind
//  keying on Article.bookKey instead of (feed, guid)).

// CREATE TABLE if not EXISTS bookLovedState (bookKey TEXT NOT NULL PRIMARY KEY, state TEXT NOT NULL, updatedAt DATE NOT NULL);

import Foundation
import RSDatabase
import RSDatabaseObjC

private enum BookLovedStateValue: String {
	case loved
	case unloved
}

final class BookLovedStateTable: DatabaseTable, Sendable {
	let name = DatabaseTableName.bookLovedState
	private let queue: DatabaseQueue

	init(queue: DatabaseQueue) {
		self.queue = queue
	}

	/// Loved state for a set of bookKeys, only returning entries that have a
	/// row -- a book with no prior loved/unloved history is simply absent
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
				  let value = BookLovedStateValue(rawValue: stateString) else {
				continue
			}
			d[bookKey] = (value == .loved)
		}
		return d
	}

	/// Upsert loved state for every bookKey in the set.
	func setState(_ flag: Bool, bookKeys: Set<String>, _ database: FMDatabase) {
		guard !bookKeys.isEmpty else {
			return
		}
		let value: BookLovedStateValue = flag ? .loved : .unloved
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
