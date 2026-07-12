//
//  BookReadStateTable.swift
//  NetNewsWire
//
//  Phase 6 (fork addition): book-level read state, independent of NetNewsWire's
//  per-(feed, guid) `read` flag on `statuses`. Keyed by Article.bookKey (see
//  ParsedItem.bookKey), which identifies "the same book" across collection
//  feeds and across re-subscriptions -- something (feed, guid) cannot do,
//  since the same book can appear in more than one Ambrosia collection feed
//  simultaneously, and re-subscribing/re-importing a feed is otherwise
//  indistinguishable from discovering brand-new articles.
//
//  Explicit unread is a real row, not an absence: if someone deliberately
//  marks a book unread, that persists as state="unread" here so a later
//  re-import doesn't fall back to "no row -> default unread" for the wrong
//  reason and silently break once an explicit "reset to unread" affordance
//  is added later.

// CREATE TABLE if not EXISTS bookReadState (bookKey TEXT NOT NULL PRIMARY KEY, state TEXT NOT NULL, updatedAt DATE NOT NULL);

import Foundation
import RSDatabase
import RSDatabaseObjC

private enum BookReadStateValue: String {
	case read
	case unread
}

final class BookReadStateTable: DatabaseTable, Sendable {
	let name = DatabaseTableName.bookReadState
	private let queue: DatabaseQueue

	init(queue: DatabaseQueue) {
		self.queue = queue
	}

	/// Read state for a set of bookKeys, only returning entries that have a row
	/// (i.e. a book with no prior read/unread history is simply absent from the
	/// result -- callers should not assume "unread" for missing keys, since the
	/// caller's own default logic, not this table, owns that decision).
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
				  let value = BookReadStateValue(rawValue: stateString) else {
				continue
			}
			d[bookKey] = (value == .read)
		}
		return d
	}

	/// Upsert read state for every bookKey in the set. Called both from the
	/// user-driven read/unread toggle (write-through) and, in principle, from
	/// any future explicit "reset to unread" affordance.
	func setState(_ flag: Bool, bookKeys: Set<String>, _ database: FMDatabase) {
		guard !bookKeys.isEmpty else {
			return
		}
		let value: BookReadStateValue = flag ? .read : .unread
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
