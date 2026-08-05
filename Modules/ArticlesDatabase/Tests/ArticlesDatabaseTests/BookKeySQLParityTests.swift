//
//  BookKeySQLParityTests.swift
//  ArticlesDatabaseTests
//
//  Phase 1.2 of the database cleanup plan: `ParsedItem.bookKey` (Swift) and
//  `AmbrosiaSQLiteImportTable.bookKeySQLExpression` (SQL) are meant to
//  compute the identical value for the same inputs, per both files' own
//  doc comments. Nothing before this test actually checked that. This is
//  the deliverable of Phase 1 -- it turns "don't reorder this without
//  checking" from a comment into something the test suite enforces.
//

import Testing
import Foundation
import RSParser
import RSDatabaseObjC
@testable import ArticlesDatabase

@Suite("ParsedItem.bookKey / AmbrosiaSQLiteImportTable SQL parity")
struct BookKeySQLParityTests {

	private struct Row: Sendable {
		let label: String
		let isAnthology: Bool
		let ao3SeriesID: String?
		let seriesName: String?
		let ao3WorkID: String?
		let id: String
	}

	// Covers every branch documented on both ParsedItem.bookKey and
	// bookKeySQLExpression: ao3SeriesID routes independently of
	// isAnthology (a series-group item sets it without isAnthology);
	// seriesName only applies when isAnthology; ao3WorkID's empty-string
	// case must fall through, not be treated as present; and the bare id
	// fallback.
	private static let matrix: [Row] = [
		Row(label: "anthology with series id", isAnthology: true, ao3SeriesID: "series-1", seriesName: nil, ao3WorkID: nil, id: "row-1"),
		Row(label: "series-group item with series id, not an anthology", isAnthology: false, ao3SeriesID: "series-2", seriesName: nil, ao3WorkID: nil, id: "row-2"),
		Row(label: "anthology with series name only", isAnthology: true, ao3SeriesID: nil, seriesName: "Collected Works", ao3WorkID: nil, id: "row-3"),
		Row(label: "anthology with neither series id nor name", isAnthology: true, ao3SeriesID: nil, seriesName: nil, ao3WorkID: "work-4", id: "row-4"),
		Row(label: "non-anthology with work id", isAnthology: false, ao3SeriesID: nil, seriesName: nil, ao3WorkID: "work-5", id: "row-5"),
		Row(label: "non-anthology with empty-string work id falls through to id", isAnthology: false, ao3SeriesID: nil, seriesName: nil, ao3WorkID: "", id: "row-6"),
		Row(label: "bare fallback", isAnthology: false, ao3SeriesID: nil, seriesName: nil, ao3WorkID: nil, id: "row-7"),
	]

	@Test("Swift and SQL bookKey computation agree for every case in the matrix", arguments: matrix)
	private func bookKeyParity(row: Row) throws {
		guard let database = FMDatabase(path: ":memory:"), database.open() else {
			Issue.record("could not open in-memory scratch database")
			return
		}
		defer { database.close() }

		database.executeStatements("""
		CREATE TABLE t (
		  id TEXT, is_anthology INTEGER, ao3_series_id TEXT, series_name TEXT, ao3_work_id TEXT
		);
		""")
		let inserted = database.executeUpdate(
			"INSERT INTO t (id, is_anthology, ao3_series_id, series_name, ao3_work_id) VALUES (?, ?, ?, ?, ?);",
			withArgumentsIn: [row.id, row.isAnthology, row.ao3SeriesID as Any, row.seriesName as Any, row.ao3WorkID as Any]
		)
		#expect(inserted)

		guard let resultSet = database.executeQuery("SELECT \(AmbrosiaSQLiteImportTable.bookKeySQLExpression) AS book_key FROM t;", withArgumentsIn: []) else {
			Issue.record("SQL query failed: \(database.lastErrorMessage() ?? "unknown error")")
			return
		}
		defer { resultSet.close() }
		#expect(resultSet.next())
		let sqlBookKey = resultSet.swiftString(forColumn: "book_key")

		let parsedItem = ParsedItem(
			syncServiceID: nil,
			uniqueID: row.id,
			feedURL: "https://example.com/feed",
			url: nil,
			externalURL: nil,
			title: nil,
			language: nil,
			contentHTML: nil,
			contentText: nil,
			markdown: nil,
			summary: nil,
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			tags: nil,
			attachments: nil,
			ao3WorkID: row.ao3WorkID,
			isAnthology: row.isAnthology,
			ao3SeriesID: row.ao3SeriesID,
			seriesName: row.seriesName
		)

		#expect(sqlBookKey == parsedItem.bookKey, "mismatch for case: \(row.label)")
	}
}
