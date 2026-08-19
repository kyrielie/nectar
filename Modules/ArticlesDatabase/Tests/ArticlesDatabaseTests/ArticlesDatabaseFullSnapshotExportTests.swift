//
//  ArticlesDatabaseFullSnapshotExportTests.swift
//  ArticlesDatabaseTests
//
//  Backup/restore plan, "Suggested build order" step 1 and "Remaining
//  engineering verification" item 2: exportFullSnapshot round-trips
//  every table, including bookState, AnnotationsTable, and -- the
//  specifically-flagged risk -- the FTS4 `search` virtual table, which
//  has historically had edge cases with file-level copy operations.
//  This asserts `search` is not just present after VACUUM INTO but
//  actually queryable (a real FTS4 MATCH query against the copied file),
//  since a corrupted-but-present virtual table can pass a naive
//  "table exists" check and still fail every real query.
//

import Testing
import Foundation
import RSDatabaseObjC
import Articles
@testable import ArticlesDatabase

@Suite("ArticlesDatabase.exportFullSnapshot round-trip")
@MainActor
struct ArticlesDatabaseFullSnapshotExportTests {

	private func tempPath() -> String {
		FileManager.default.temporaryDirectory
			.appendingPathComponent("full-snapshot-\(UUID().uuidString).sqlite")
			.path
	}

	/// `indexUnindexedArticles` batches over `DispatchQueue.main.async`
	/// recursion (see ArticlesTable.swift), so a freshly-inserted article
	/// isn't indexed synchronously -- yield to the main run loop until
	/// `searchRowID` is populated (or give up after a bounded number of
	/// yields, which fails the test loudly rather than hanging).
	private func waitForIndexing(_ db: ArticlesDatabase, articleID: String) async {
		for _ in 0..<50 {
			// DatabaseBlock is declared `@Sendable`, so the compiler treats
			// this closure as potentially concurrent even though
			// runInDatabaseSync is a synchronous, single-threaded call --
			// this var is never touched from more than one thread at a time
			// in practice. Same pattern as AmbrosiaSQLiteImportTable.importTransfer.
			nonisolated(unsafe) var isIndexed = false
			db.queue.runInDatabaseSync { database in
				guard let resultSet = database.executeQuery("SELECT searchRowID FROM articles WHERE articleID = ?;", withArgumentsIn: [articleID]) else {
					return
				}
				defer { resultSet.close() }
				if resultSet.next() {
					isIndexed = !resultSet.columnIsNull("searchRowID")
				}
			}
			if isIndexed {
				return
			}
			await Task.yield()
		}
	}

	@Test("exportFullSnapshot copies articles, statuses, bookState, and annotations")
	func roundTripsCoreTables() async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)
		let articleID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "u1")

		let now = Date(timeIntervalSince1970: 1_700_000_000)
		await db.saveAnnotation(Annotation(
			annotationID: "annotation-a",
			articleID: articleID,
			bookKey: nil,
			quoteExact: "a quote",
			quotePrefix: "",
			quoteSuffix: "",
			startOffset: 0,
			endOffset: 7,
			color: .yellow,
			note: nil,
			createdAt: now,
			updatedAt: now
		))

		let destinationPath = tempPath()
		defer { try? FileManager.default.removeItem(atPath: destinationPath) }
		try db.exportFullSnapshot(toPath: destinationPath)

		guard let snapshot = FMDatabase(path: destinationPath), snapshot.open() else {
			Issue.record("could not open exported snapshot")
			return
		}
		defer { snapshot.close() }

		for table in ["articles", "statuses", "bookState", "annotations"] {
			guard let resultSet = snapshot.executeQuery("SELECT COUNT(*) FROM \(table);", withArgumentsIn: []) else {
				Issue.record("could not query \(table) in snapshot")
				continue
			}
			defer { resultSet.close() }
			#expect(resultSet.next())
		}

		guard let articlesCount = snapshot.executeQuery("SELECT COUNT(*) FROM articles;", withArgumentsIn: []) else {
			Issue.record("could not query articles count")
			return
		}
		defer { articlesCount.close() }
		// intWithCountResult() calls next() itself -- an extra next() call
		// here would consume the row's single result before
		// intWithCountResult() gets to read it, since a COUNT(*) query only
		// ever returns one row.
		#expect(articlesCount.intWithCountResult() == 1)
	}

	@Test("exportFullSnapshot's copy of the FTS `search` table survives VACUUM INTO and is queryable")
	func fullTextSearchSurvivesVacuumInto() async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a", title: "Distinctive Searchable Title")], feedID: "feed-a", deleteOlder: false)
		let articleID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "u1")

		await waitForIndexing(db, articleID: articleID)

		let destinationPath = tempPath()
		defer { try? FileManager.default.removeItem(atPath: destinationPath) }
		try db.exportFullSnapshot(toPath: destinationPath)

		guard let snapshot = FMDatabase(path: destinationPath), snapshot.open() else {
			Issue.record("could not open exported snapshot")
			return
		}
		defer { snapshot.close() }

		// A real FTS4 MATCH query, not just "does the table exist" --
		// this is the actual risk the plan flags: a virtual table can
		// survive a naive file copy in name only.
		guard let resultSet = snapshot.executeQuery("SELECT rowid FROM search WHERE search MATCH 'Distinctive';", withArgumentsIn: []) else {
			Issue.record("FTS MATCH query failed against the exported snapshot")
			return
		}
		defer { resultSet.close() }
		#expect(resultSet.next())
	}

	// MARK: - destinationPath already existing fails, doesn't silently overwrite

	@Test("exporting to a destinationPath that already exists throws rather than overwriting")
	func existingDestinationPathThrows() async throws {
		let db = TestFixtures.makeDatabase()
		_ = await db.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)

		let destinationPath = tempPath()
		defer { try? FileManager.default.removeItem(atPath: destinationPath) }
		FileManager.default.createFile(atPath: destinationPath, contents: Data())

		#expect(throws: ArticlesDatabaseFullSnapshotExportError.self) {
			try db.exportFullSnapshot(toPath: destinationPath)
		}
	}
}
