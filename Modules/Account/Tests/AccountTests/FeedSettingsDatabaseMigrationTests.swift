//
//  FeedSettingsDatabaseMigrationTests.swift
//  AccountTests
//
//  Coverage for the ao3-arbitrary-page-fetch plan (Part 8): seeds a
//  feedSettings row with only the legacy ao3SearchLastFetchedPage column
//  set (pre-migration schema), then opens it through FeedSettingsDatabase
//  (which runs the migration on init) and confirms ao3SearchFetchedPages
//  backfills to the exact expected set -- Set(1...oldValue), since every
//  page fetched before this feature existed was fetched sequentially with
//  no gaps.
//

import XCTest
import RSDatabaseObjC
@testable import Account

@MainActor final class FeedSettingsDatabaseMigrationTests: XCTestCase {

	private var databasePath: String!

	override func setUp() {
		let tempDirectory = FileManager.default.temporaryDirectory
		databasePath = tempDirectory.appendingPathComponent("FeedSettingsDatabaseMigrationTests-\(UUID().uuidString).sqlite3").path
	}

	override func tearDown() {
		try? FileManager.default.removeItem(atPath: databasePath)
		databasePath = nil
	}

	/// Builds the pre-migration schema directly (no ao3SearchFetchedPages
	/// or ao3SearchTotalPages column at all -- the shape any row created
	/// before this feature existed would have), then seeds one row with
	/// only the legacy ao3SearchLastFetchedPage column populated.
	private func seedLegacyRow(feedURL: String, legacyLastFetchedPage: Int) {
		let database = FMDatabase(path: databasePath)
		database.open()
		database.executeStatements("""
		CREATE TABLE IF NOT EXISTS feedSettings (feedURL TEXT PRIMARY KEY, feedID TEXT NOT NULL DEFAULT '', homePageURL TEXT, iconURL TEXT, faviconURL TEXT, editedName TEXT, contentHash TEXT, newArticleNotificationsEnabled INTEGER NOT NULL DEFAULT 0, authors TEXT, conditionalGetInfoLastModified TEXT, conditionalGetInfoEtag TEXT, conditionalGetInfoDate REAL, cacheControlInfoDateCreated REAL, cacheControlInfoMaxAge REAL, externalID TEXT, folderRelationship TEXT, lastCheckDate REAL, lastResponseCode INTEGER, ao3SearchLastFetchedPage INTEGER);
		""")
		database.executeUpdate("INSERT INTO feedSettings (feedURL, feedID, ao3SearchLastFetchedPage) VALUES (?, ?, ?);", withArgumentsIn: [feedURL, feedURL, legacyLastFetchedPage])
		database.close()
	}

	func testBackfillFromLegacyColumnProducesExactExpectedSet() {
		let feedURL = "https://archiveofourown.org/works?work_search%5Bquery%5D=migration-test"
		seedLegacyRow(feedURL: feedURL, legacyLastFetchedPage: 4)

		// Opening FeedSettingsDatabase runs the migration synchronously
		// inside init (serialDispatchQueue.sync).
		let migratedDatabase = FeedSettingsDatabase(databasePath: databasePath)

		let rows = migratedDatabase.allRows()
		let row = rows[feedURL]
		XCTAssertEqual(row?.ao3SearchFetchedPages, Set(1...4))
	}

	func testBackfillLeavesRowsWithNoLegacyValueUntouched() {
		let feedURL = "https://example.com/ordinary-feed"
		let database = FMDatabase(path: databasePath)
		database.open()
		database.executeStatements("""
		CREATE TABLE IF NOT EXISTS feedSettings (feedURL TEXT PRIMARY KEY, feedID TEXT NOT NULL DEFAULT '', homePageURL TEXT, iconURL TEXT, faviconURL TEXT, editedName TEXT, contentHash TEXT, newArticleNotificationsEnabled INTEGER NOT NULL DEFAULT 0, authors TEXT, conditionalGetInfoLastModified TEXT, conditionalGetInfoEtag TEXT, conditionalGetInfoDate REAL, cacheControlInfoDateCreated REAL, cacheControlInfoMaxAge REAL, externalID TEXT, folderRelationship TEXT, lastCheckDate REAL, lastResponseCode INTEGER, ao3SearchLastFetchedPage INTEGER);
		""")
		database.executeUpdate("INSERT INTO feedSettings (feedURL, feedID) VALUES (?, ?);", withArgumentsIn: [feedURL, feedURL])
		database.close()

		let migratedDatabase = FeedSettingsDatabase(databasePath: databasePath)

		let rows = migratedDatabase.allRows()
		let row = rows[feedURL]
		XCTAssertNil(row?.ao3SearchFetchedPages)
		XCTAssertNil(row?.ao3SearchTotalPages)
	}

	func testAo3SearchTotalPagesHasNoLegacyBackfillAndStartsNil() {
		let feedURL = "https://archiveofourown.org/works?work_search%5Bquery%5D=migration-test-2"
		seedLegacyRow(feedURL: feedURL, legacyLastFetchedPage: 2)

		let migratedDatabase = FeedSettingsDatabase(databasePath: databasePath)

		let row = migratedDatabase.allRows()[feedURL]
		XCTAssertEqual(row?.ao3SearchFetchedPages, Set(1...2))
		XCTAssertNil(row?.ao3SearchTotalPages)
	}
}
