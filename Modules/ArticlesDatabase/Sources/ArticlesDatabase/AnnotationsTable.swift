//
//  AnnotationsTable.swift
//  NetNewsWire
//
//  One row per highlight/note, keyed by client-generated annotationID
//  (UUID) -- articleID-scoped for anchor resolution (a highlight only
//  means something against the specific rendered text it was drawn
//  against), with bookKey carried alongside purely so a listing UI can
//  group annotations across every chapter/feed-copy of the same book
//  without a join through `articles` on every query. See
//  docs/annotations.md for the full anchor-resolution algorithm this
//  schema supports.
//

// CREATE TABLE if not EXISTS annotations (annotationID TEXT NOT NULL PRIMARY KEY, articleID TEXT NOT NULL, bookKey TEXT, quoteExact TEXT NOT NULL, quotePrefix TEXT NOT NULL DEFAULT '', quoteSuffix TEXT NOT NULL DEFAULT '', rootSelector TEXT NOT NULL DEFAULT '.articleBody', startOffset INTEGER NOT NULL, endOffset INTEGER NOT NULL, color TEXT NOT NULL DEFAULT 'yellow', note TEXT, createdAt DATE NOT NULL, updatedAt DATE NOT NULL, orphanedAt DATE, lastReanchoredAt DATE);

import Foundation
import RSDatabase
import RSDatabaseObjC
import Articles

final class AnnotationsTable: DatabaseTable, Sendable {
	let name = DatabaseTableName.annotations
	private let queue: DatabaseQueue

	init(queue: DatabaseQueue) {
		self.queue = queue
	}

	// MARK: - Fetching

	func fetchAnnotations(articleID: String, _ database: FMDatabase) -> [Annotation] {
		guard let resultSet = self.selectRowsWhere(key: DatabaseKey.articleID, equals: articleID, in: database) else {
			return []
		}
		return resultSet.compactMap(annotationWithRow)
	}

	func fetchAnnotations(bookKey: String, _ database: FMDatabase) -> [Annotation] {
		guard let resultSet = self.selectRowsWhere(key: DatabaseKey.bookKey, equals: bookKey, in: database) else {
			return []
		}
		return resultSet.compactMap(annotationWithRow)
	}

	func fetchAllAnnotations(_ database: FMDatabase) -> [Annotation] {
		guard let resultSet = database.executeQuery("select * from \(name);", withArgumentsIn: nil) else {
			return []
		}
		return resultSet.compactMap(annotationWithRow)
	}

	// MARK: - Saving

	/// Full-row insert-or-replace: annotationID is client-generated (a UUID),
	/// so a save is always either a brand-new row or a wholesale replace of
	/// one this same client created -- unlike BookStateTable's partial-column
	/// upsert, there's no "leave the other columns alone" case here, since a
	/// save always carries every column's current value.
	func save(_ annotation: Annotation, _ database: FMDatabase) {
		database.executeUpdate(
			"""
			INSERT INTO \(name) (
				\(DatabaseKey.annotationID), \(DatabaseKey.articleID), \(DatabaseKey.bookKey),
				\(DatabaseKey.quoteExact), \(DatabaseKey.quotePrefix), \(DatabaseKey.quoteSuffix),
				\(DatabaseKey.rootSelector), \(DatabaseKey.startOffset), \(DatabaseKey.endOffset),
				\(DatabaseKey.color), \(DatabaseKey.note), \(DatabaseKey.createdAt), \(DatabaseKey.updatedAt),
				\(DatabaseKey.orphanedAt), \(DatabaseKey.lastReanchoredAt)
			) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
			ON CONFLICT(\(DatabaseKey.annotationID)) DO UPDATE SET
				\(DatabaseKey.articleID) = excluded.\(DatabaseKey.articleID),
				\(DatabaseKey.bookKey) = excluded.\(DatabaseKey.bookKey),
				\(DatabaseKey.quoteExact) = excluded.\(DatabaseKey.quoteExact),
				\(DatabaseKey.quotePrefix) = excluded.\(DatabaseKey.quotePrefix),
				\(DatabaseKey.quoteSuffix) = excluded.\(DatabaseKey.quoteSuffix),
				\(DatabaseKey.rootSelector) = excluded.\(DatabaseKey.rootSelector),
				\(DatabaseKey.startOffset) = excluded.\(DatabaseKey.startOffset),
				\(DatabaseKey.endOffset) = excluded.\(DatabaseKey.endOffset),
				\(DatabaseKey.color) = excluded.\(DatabaseKey.color),
				\(DatabaseKey.note) = excluded.\(DatabaseKey.note),
				\(DatabaseKey.updatedAt) = excluded.\(DatabaseKey.updatedAt),
				\(DatabaseKey.orphanedAt) = excluded.\(DatabaseKey.orphanedAt),
				\(DatabaseKey.lastReanchoredAt) = excluded.\(DatabaseKey.lastReanchoredAt)
			""",
			withArgumentsIn: [
				annotation.annotationID, annotation.articleID, annotation.bookKey as Any,
				annotation.quoteExact, annotation.quotePrefix, annotation.quoteSuffix,
				annotation.rootSelector, annotation.startOffset, annotation.endOffset,
				annotation.color.rawValue, annotation.note as Any, annotation.createdAt, annotation.updatedAt,
				annotation.orphanedAt as Any, annotation.lastReanchoredAt as Any
			]
		)
	}

	// MARK: - Deleting

	func deleteAnnotation(annotationID: String, _ database: FMDatabase) {
		self.deleteRowsWhere(key: DatabaseKey.annotationID, equalsAnyValue: [annotationID], in: database)
	}

	// MARK: - Updating

	func updateNote(annotationID: String, note: String?, at date: Date, _ database: FMDatabase) {
		database.executeUpdate(
			"UPDATE \(name) SET \(DatabaseKey.note) = ?, \(DatabaseKey.updatedAt) = ? WHERE \(DatabaseKey.annotationID) = ?",
			withArgumentsIn: [note as Any, date, annotationID]
		)
	}

	func updateColor(annotationID: String, color: Annotation.Color, at date: Date, _ database: FMDatabase) {
		database.executeUpdate(
			"UPDATE \(name) SET \(DatabaseKey.color) = ?, \(DatabaseKey.updatedAt) = ? WHERE \(DatabaseKey.annotationID) = ?",
			withArgumentsIn: [color.rawValue, date, annotationID]
		)
	}

	/// Marks anchor resolution as having failed to relocate this
	/// annotation's quote (see docs/annotations.md) -- the annotation stays
	/// in the table, surfaced rather than dropped.
	func markOrphaned(annotationID: String, at date: Date, _ database: FMDatabase) {
		database.executeUpdate(
			"UPDATE \(name) SET \(DatabaseKey.orphanedAt) = ?, \(DatabaseKey.updatedAt) = ? WHERE \(DatabaseKey.annotationID) = ?",
			withArgumentsIn: [date, date, annotationID]
		)
	}

	/// Writes back corrected offsets/selector text after a successful
	/// re-anchor pass (see docs/annotations.md), and clears any prior
	/// orphaned mark -- a quote that re-resolves is no longer orphaned, even
	/// if it briefly was on an earlier render.
	func reanchor(
		annotationID: String,
		startOffset: Int,
		endOffset: Int,
		quoteExact: String,
		quotePrefix: String,
		quoteSuffix: String,
		at date: Date,
		_ database: FMDatabase
	) {
		database.executeUpdate(
			"""
			UPDATE \(name) SET
				\(DatabaseKey.startOffset) = ?,
				\(DatabaseKey.endOffset) = ?,
				\(DatabaseKey.quoteExact) = ?,
				\(DatabaseKey.quotePrefix) = ?,
				\(DatabaseKey.quoteSuffix) = ?,
				\(DatabaseKey.lastReanchoredAt) = ?,
				\(DatabaseKey.orphanedAt) = NULL,
				\(DatabaseKey.updatedAt) = ?
			WHERE \(DatabaseKey.annotationID) = ?
			""",
			withArgumentsIn: [startOffset, endOffset, quoteExact, quotePrefix, quoteSuffix, date, date, annotationID]
		)
	}

	// MARK: - Private

	private func annotationWithRow(_ resultSet: FMResultSet) -> Annotation? {
		guard
			let annotationID = resultSet.swiftString(forColumn: DatabaseKey.annotationID),
			let articleID = resultSet.swiftString(forColumn: DatabaseKey.articleID),
			let quoteExact = resultSet.swiftString(forColumn: DatabaseKey.quoteExact)
		else {
			return nil
		}
		let createdAt = resultSet.date(forColumn: DatabaseKey.createdAt)
		let updatedAt = resultSet.date(forColumn: DatabaseKey.updatedAt)

		let colorRawValue = resultSet.swiftString(forColumn: DatabaseKey.color) ?? Annotation.Color.yellow.rawValue
		let color = Annotation.Color(rawValue: colorRawValue) ?? .yellow

		return Annotation(
			annotationID: annotationID,
			articleID: articleID,
			bookKey: resultSet.swiftString(forColumn: DatabaseKey.bookKey),
			quoteExact: quoteExact,
			quotePrefix: resultSet.swiftString(forColumn: DatabaseKey.quotePrefix) ?? "",
			quoteSuffix: resultSet.swiftString(forColumn: DatabaseKey.quoteSuffix) ?? "",
			rootSelector: resultSet.swiftString(forColumn: DatabaseKey.rootSelector) ?? ".articleBody",
			startOffset: Int(resultSet.long(forColumn: DatabaseKey.startOffset)),
			endOffset: Int(resultSet.long(forColumn: DatabaseKey.endOffset)),
			color: color,
			note: resultSet.swiftString(forColumn: DatabaseKey.note),
			createdAt: createdAt,
			updatedAt: updatedAt,
			orphanedAt: resultSet.columnIsNull(DatabaseKey.orphanedAt) ? nil : resultSet.date(forColumn: DatabaseKey.orphanedAt),
			lastReanchoredAt: resultSet.columnIsNull(DatabaseKey.lastReanchoredAt) ? nil : resultSet.date(forColumn: DatabaseKey.lastReanchoredAt)
		)
	}
}
