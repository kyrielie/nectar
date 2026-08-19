//
//  BackupSQLiteImportTableTests.swift
//  ArticlesDatabaseTests
//
//  Backup/restore plan, "Suggested build order" step 4: direct coverage of
//  BackupSQLiteImportTable's per-table merge rules, mirroring
//  AmbrosiaSQLiteImportTableTests's shape (real ArticlesDatabase instances,
//  ATTACH-based bulk merge, asserted via the public fetch API plus a few
//  direct queue reads for columns with no public getter).
//
//  Two real ArticlesDatabase instances are used per test: `localDB` (the
//  live database being restored into) and `backupDB` (stands in for a
//  backup's DB.sqlite3 -- exportFullSnapshot(toPath:) is used to produce a
//  real, schema-correct snapshot file from it, so these tests exercise the
//  actual VACUUM INTO -> ATTACH -> merge path end to end rather than a
//  hand-rolled fixture file that could silently drift from the real schema).
//

import Testing
import Foundation
import RSParser
import Articles
import RSDatabaseObjC
@testable import ArticlesDatabase

@Suite("BackupSQLiteImportTable merge rules")
@MainActor
struct BackupSQLiteImportTableTests {

	private func tempPath() -> String {
		FileManager.default.temporaryDirectory
			.appendingPathComponent("backup-import-\(UUID().uuidString).sqlite")
			.path
	}

	/// Exports `backupDB` to a temp file and imports it into `localDB`,
	/// returning the temp file's path so callers needing to assert against
	/// the raw backup file too still can. Cleans up the temp file itself;
	/// callers manage nothing.
	private func mergeBackup(of backupDB: ArticlesDatabase, into localDB: ArticlesDatabase) throws {
		let backupPath = tempPath()
		defer { try? FileManager.default.removeItem(atPath: backupPath) }
		try backupDB.exportFullSnapshot(toPath: backupPath)
		try localDB.importBackupSnapshot(backupDatabasePath: backupPath)
	}

	// MARK: - articles

	@Test("an article present only in the backup is added locally; an article present only locally is untouched")
	func articlesAddOnlyMissingRows() async throws {
		let localDB = TestFixtures.makeDatabase()
		let backupDB = TestFixtures.makeDatabase()

		_ = await localDB.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "local-only", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)
		_ = await backupDB.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "backup-only", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)

		try mergeBackup(of: backupDB, into: localDB)

		let localOnlyID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "local-only")
		let backupOnlyID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "backup-only")
		let fetched = localDB.fetchArticles(articleIDs: [localOnlyID, backupOnlyID])

		#expect(fetched.count == 2)
		#expect(fetched.contains { $0.articleID == localOnlyID })
		#expect(fetched.contains { $0.articleID == backupOnlyID })
	}

	@Test("an article present in both, with a changed title in the backup, is NOT overwritten locally")
	func articlesConflictKeepsLocal() async throws {
		let localDB = TestFixtures.makeDatabase()
		let backupDB = TestFixtures.makeDatabase()

		_ = await localDB.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "shared", feedURL: "https://example.com/feed-a", title: "Local Title")], feedID: "feed-a", deleteOlder: false)
		_ = await backupDB.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "shared", feedURL: "https://example.com/feed-a", title: "Backup Title")], feedID: "feed-a", deleteOlder: false)

		try mergeBackup(of: backupDB, into: localDB)

		let articleID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "shared")
		let fetched = localDB.fetchArticles(articleIDs: [articleID])
		#expect(fetched.count == 1)
		#expect(fetched.first?.title == "Local Title")
	}

	// MARK: - statuses

	@Test("statuses: read/starred/loved are OR'd -- a true on either side stays true after merge")
	func statusesOrOfBooleans() async throws {
		let localDB = TestFixtures.makeDatabase()
		let backupDB = TestFixtures.makeDatabase()

		_ = await localDB.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "shared", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)
		_ = await backupDB.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "shared", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)

		let articleID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "shared")

		// Local: starred only. Backup: read + loved only. Neither side has
		// all three -- the merge should end up with all three true, which
		// is only possible if the merge is a real OR and not "last write
		// wins" in either direction.
		_ = await localDB.markAsync(articleIDs: [articleID], statusKey: .starred, flag: true)
		_ = await backupDB.markAsync(articleIDs: [articleID], statusKey: .read, flag: true)
		_ = await backupDB.markAsync(articleIDs: [articleID], statusKey: .loved, flag: true)

		try mergeBackup(of: backupDB, into: localDB)

		let fetched = localDB.fetchArticles(articleIDs: [articleID])
		let status = try #require(fetched.first?.status)
		#expect(status.boolStatus(forKey: .read) == true)
		#expect(status.boolStatus(forKey: .starred) == true)
		#expect(status.boolStatus(forKey: .loved) == true)
	}

	@Test("statuses: scrollPosition/readingProgress are taken from whichever side has the later lastOpenedAt")
	func statusesLaterLastOpenedAtWins() async throws {
		let localDB = TestFixtures.makeDatabase()
		let backupDB = TestFixtures.makeDatabase()

		_ = await localDB.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "shared", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)
		_ = await backupDB.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "shared", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)

		let articleID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "shared")

		// No public setter for lastOpenedAt -- set scrollPosition/
		// readingProgress via the public API (which also has no lastOpenedAt
		// side effect), then stamp lastOpenedAt directly via the queue,
		// same "@testable direct queue access" idiom
		// ArticlesDatabaseFullSnapshotExportTests already uses.
		await localDB.saveScrollPositionAsync(0.25, articleID: articleID)
		_ = await localDB.saveReadingProgressAsync(0.25, articleID: articleID)
		await backupDB.saveScrollPositionAsync(0.90, articleID: articleID)
		_ = await backupDB.saveReadingProgressAsync(0.90, articleID: articleID)

		let earlier = Date(timeIntervalSince1970: 1_700_000_000)
		let later = Date(timeIntervalSince1970: 1_700_100_000)
		localDB.queue.runInDatabaseSync { database in
			_ = database.executeUpdate("UPDATE statuses SET lastOpenedAt = ? WHERE articleID = ?;", withArgumentsIn: [earlier, articleID])
		}
		backupDB.queue.runInDatabaseSync { database in
			_ = database.executeUpdate("UPDATE statuses SET lastOpenedAt = ? WHERE articleID = ?;", withArgumentsIn: [later, articleID])
		}

		try mergeBackup(of: backupDB, into: localDB)

		// DatabaseBlock is declared `@Sendable`, so the compiler treats this
		// closure as potentially concurrent even though runInDatabaseSync
		// is a synchronous, single-threaded call -- this var is never
		// touched from more than one thread at a time in practice. Same
		// pattern as AmbrosiaSQLiteImportTable.importTransfer and
		// ArticlesDatabaseFullSnapshotExportTests.waitForIndexing.
		nonisolated(unsafe) var mergedScrollPosition: Double?
		localDB.queue.runInDatabaseSync { database in
			guard let resultSet = database.executeQuery("SELECT scrollPosition, readingProgress FROM statuses WHERE articleID = ?;", withArgumentsIn: [articleID]) else { return }
			defer { resultSet.close() }
			if resultSet.next() {
				mergedScrollPosition = resultSet.double(forColumn: "scrollPosition")
			}
		}
		#expect(mergedScrollPosition == 0.90)
	}

	// MARK: - annotations

	@Test("a new-only annotation from the backup is inserted locally")
	func annotationsNewOnlyInserted() async throws {
		let localDB = TestFixtures.makeDatabase()
		let backupDB = TestFixtures.makeDatabase()

		_ = await backupDB.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)
		let articleID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "u1")

		let now = Date(timeIntervalSince1970: 1_700_000_000)
		await backupDB.saveAnnotation(Annotation(
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

		try mergeBackup(of: backupDB, into: localDB)

		let fetched = await localDB.fetchAnnotations(articleID: articleID)
		#expect(fetched.count == 1)
		#expect(fetched.first?.annotationID == "annotation-a")
	}

	@Test("a conflicting annotationID keeps whichever side has the later updatedAt, in full, not a partial merge")
	func annotationsLaterUpdatedAtWinsInFull() async throws {
		let localDB = TestFixtures.makeDatabase()
		let backupDB = TestFixtures.makeDatabase()

		_ = await localDB.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)
		_ = await backupDB.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)
		let articleID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "u1")

		let earlier = Date(timeIntervalSince1970: 1_700_000_000)
		let later = Date(timeIntervalSince1970: 1_700_100_000)

		// Same annotationID on both sides, diverged: local has an older
		// edit (created and never touched again); backup has a later
		// edit (e.g. a note added on the other device after the anchor
		// was created). The later updatedAt should win, and win in full --
		// the merged row's note should be the backup's, not a column-by-
		// column splice.
		await localDB.saveAnnotation(Annotation(
			annotationID: "shared-annotation", articleID: articleID, bookKey: nil,
			quoteExact: "original quote", quotePrefix: "", quoteSuffix: "",
			startOffset: 0, endOffset: 8, color: .yellow, note: nil,
			createdAt: earlier, updatedAt: earlier
		))
		await backupDB.saveAnnotation(Annotation(
			annotationID: "shared-annotation", articleID: articleID, bookKey: nil,
			quoteExact: "original quote", quotePrefix: "", quoteSuffix: "",
			startOffset: 0, endOffset: 8, color: .blue, note: "added on the other device",
			createdAt: earlier, updatedAt: later
		))

		try mergeBackup(of: backupDB, into: localDB)

		let fetched = await localDB.fetchAnnotations(articleID: articleID)
		#expect(fetched.count == 1)
		#expect(fetched.first?.note == "added on the other device")
		#expect(fetched.first?.color == .blue)
	}

	@Test("a conflicting annotationID where the LOCAL side is later is left untouched by the merge")
	func annotationsLaterLocalIsKept() async throws {
		let localDB = TestFixtures.makeDatabase()
		let backupDB = TestFixtures.makeDatabase()

		_ = await localDB.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)
		_ = await backupDB.updateAsync(parsedItems: [TestFixtures.makeParsedItem(uniqueID: "u1", feedURL: "https://example.com/feed-a")], feedID: "feed-a", deleteOlder: false)
		let articleID = Article.calculatedArticleID(feedID: "feed-a", uniqueID: "u1")

		let earlier = Date(timeIntervalSince1970: 1_700_000_000)
		let later = Date(timeIntervalSince1970: 1_700_100_000)

		await localDB.saveAnnotation(Annotation(
			annotationID: "shared-annotation", articleID: articleID, bookKey: nil,
			quoteExact: "original quote", quotePrefix: "", quoteSuffix: "",
			startOffset: 0, endOffset: 8, color: .green, note: "edited locally, more recently",
			createdAt: earlier, updatedAt: later
		))
		await backupDB.saveAnnotation(Annotation(
			annotationID: "shared-annotation", articleID: articleID, bookKey: nil,
			quoteExact: "original quote", quotePrefix: "", quoteSuffix: "",
			startOffset: 0, endOffset: 8, color: .yellow, note: nil,
			createdAt: earlier, updatedAt: earlier
		))

		try mergeBackup(of: backupDB, into: localDB)

		let fetched = await localDB.fetchAnnotations(articleID: articleID)
		#expect(fetched.count == 1)
		#expect(fetched.first?.note == "edited locally, more recently")
		#expect(fetched.first?.color == .green)
	}
}
