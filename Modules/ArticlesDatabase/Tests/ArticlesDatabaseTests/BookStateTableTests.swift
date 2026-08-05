//
//  BookStateTableTests.swift
//  ArticlesDatabaseTests
//
//  Nectar cleanup plan v2, Phase 3b: direct coverage of BookStateTable,
//  previously only exercised indirectly through ArticlesTable.mark/
//  saveReadingProgress. Three cases, matching the plan's numbering:
//  (1) a partial-column upsert leaves other columns alone, (2) kudosAttempt/
//  setKudosAttempted's atomic two-column write survives an unrelated upsert,
//  (3) state(for:) on empty/unknown bookKeys.
//

import Testing
import Foundation
import RSDatabaseObjC
@testable import ArticlesDatabase

@Suite("BookStateTable partial upsert / kudos / lookup")
@MainActor
struct BookStateTableTests {

	private func makeTable() -> (ArticlesDatabase, BookStateTable) {
		let db = TestFixtures.makeDatabase()
		return (db, BookStateTable(queue: db.queue))
	}

	// MARK: - 1. Partial-column upsert leaves other columns alone

	@Test("setting scrollPosition after setRead(true) doesn't reset read back to false")
	func partialUpsertLeavesOtherColumnsAlone() {
		let (db, table) = makeTable()
		let bookKey = "ao3-work:12345"

		db.queue.runInDatabaseSync { database in
			table.setRead(true, bookKeys: [bookKey], database)
			table.setScrollPosition(0.5, bookKey: bookKey, database)

			let state = table.state(for: [bookKey], database)[bookKey]
			#expect(state?.read == true)
			#expect(state?.scrollPosition == 0.5)
		}
	}

	@Test("setting read after setScrollPosition doesn't reset scrollPosition back to 0")
	func partialUpsertLeavesOtherColumnsAloneReversedOrder() {
		let (db, table) = makeTable()
		let bookKey = "ao3-work:12345"

		db.queue.runInDatabaseSync { database in
			table.setScrollPosition(0.75, bookKey: bookKey, database)
			table.setStarred(true, bookKeys: [bookKey], database)

			let state = table.state(for: [bookKey], database)[bookKey]
			#expect(state?.scrollPosition == 0.75)
			#expect(state?.starred == true)
		}
	}

	// MARK: - 2. kudosAttempt/setKudosAttempted's atomic two-column write

	@Test("kudosAttempt round-trips through setKudosAttempted, both for the never-attempted and attempted cases, and an unrelated upsert doesn't disturb it")
	func kudosAttemptRoundTripsAndSurvivesUnrelatedUpsert() {
		let (db, table) = makeTable()
		let bookKey = "ao3-work:12345"

		db.queue.runInDatabaseSync { database in
			// Never attempted.
			#expect(table.kudosAttempt(for: bookKey, database) == nil)

			// Authenticated attempt.
			let attemptDate = Date(timeIntervalSince1970: 1_700_000_000)
			table.setKudosAttempted(at: attemptDate, authenticated: true, bookKey: bookKey, database)
			let attempted = table.kudosAttempt(for: bookKey, database)
			#expect(attempted?.attemptedAt.timeIntervalSince1970 == attemptDate.timeIntervalSince1970)
			#expect(attempted?.authenticated == true)

			// An unrelated upsert (setRead) on the same bookKey shouldn't
			// disturb the kudos columns -- same partial-upsert concern as
			// case 1, cross-checked against the one path that doesn't use
			// the generic `upsert` helper.
			table.setRead(true, bookKeys: [bookKey], database)
			let afterUnrelatedUpsert = table.kudosAttempt(for: bookKey, database)
			#expect(afterUnrelatedUpsert?.attemptedAt.timeIntervalSince1970 == attemptDate.timeIntervalSince1970)
			#expect(afterUnrelatedUpsert?.authenticated == true)
		}
	}

	@Test("kudosAttempt reports the guest (unauthenticated) case correctly")
	func kudosAttemptGuestCase() {
		let (db, table) = makeTable()
		let bookKey = "ao3-work:99999"

		db.queue.runInDatabaseSync { database in
			let attemptDate = Date(timeIntervalSince1970: 1_700_000_000)
			table.setKudosAttempted(at: attemptDate, authenticated: false, bookKey: bookKey, database)
			let attempted = table.kudosAttempt(for: bookKey, database)
			#expect(attempted?.authenticated == false)
		}
	}

	// MARK: - 3. state(for:) on an empty/unknown bookKey set

	@Test("state(for:) on an empty set of bookKeys returns an empty dictionary")
	func stateForEmptyBookKeySetReturnsEmptyDictionary() {
		let (db, table) = makeTable()
		db.queue.runInDatabaseSync { database in
			#expect(table.state(for: [], database).isEmpty)
		}
	}

	@Test("state(for:) omits a never-seen bookKey entirely, rather than returning a default-valued entry")
	func stateForUnknownBookKeyOmitsIt() {
		let (db, table) = makeTable()
		db.queue.runInDatabaseSync { database in
			let result = table.state(for: ["never-seen"], database)
			#expect(result.isEmpty)
			#expect(result["never-seen"] == nil)
		}
	}

	@Test("state(for:) returns only the bookKeys that have a row, omitting unknown ones from a mixed set")
	func stateForMixedKnownAndUnknownBookKeys() {
		let (db, table) = makeTable()
		let knownKey = "ao3-work:12345"

		db.queue.runInDatabaseSync { database in
			table.setRead(true, bookKeys: [knownKey], database)

			let result = table.state(for: [knownKey, "never-seen"], database)
			#expect(result.count == 1)
			#expect(result[knownKey] != nil)
			#expect(result["never-seen"] == nil)
		}
	}
}
