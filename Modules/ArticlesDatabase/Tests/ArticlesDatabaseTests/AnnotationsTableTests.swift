//
//  AnnotationsTableTests.swift
//  ArticlesDatabaseTests
//
//  Direct coverage of AnnotationsTable: (1) save/fetch round-trip including
//  every column, (2) fetch scoping by articleID vs bookKey vs unscoped,
//  (3) note/color partial updates, (4) delete, (5) the orphan/reanchor
//  lifecycle (markOrphaned sets orphanedAt; a later successful reanchor
//  clears it again).
//

import Testing
import Foundation
import Articles
@testable import ArticlesDatabase

@Suite("AnnotationsTable save / fetch / update / orphan-reanchor lifecycle")
@MainActor
struct AnnotationsTableTests {

	private func makeTable() -> (ArticlesDatabase, AnnotationsTable) {
		let db = TestFixtures.makeDatabase()
		return (db, AnnotationsTable(queue: db.queue))
	}

	private func makeAnnotation(
		annotationID: String = "annotation-1",
		articleID: String = "article-1",
		bookKey: String? = "ao3-work:12345",
		quoteExact: String = "a highlighted phrase",
		color: Annotation.Color = .yellow,
		note: String? = nil,
		startOffset: Int = 10,
		endOffset: Int = 31
	) -> Annotation {
		let now = Date(timeIntervalSince1970: 1_700_000_000)
		return Annotation(
			annotationID: annotationID,
			articleID: articleID,
			bookKey: bookKey,
			quoteExact: quoteExact,
			quotePrefix: "before the ",
			quoteSuffix: " after it",
			startOffset: startOffset,
			endOffset: endOffset,
			color: color,
			note: note,
			createdAt: now,
			updatedAt: now
		)
	}

	// MARK: - 1. Save/fetch round-trip

	@Test("saving an annotation and fetching it by articleID round-trips every column")
	func saveAndFetchRoundTripsAllColumns() {
		let (db, table) = makeTable()
		let annotation = makeAnnotation(note: "an attached note")

		db.queue.runInDatabaseSync { database in
			table.save(annotation, database)
			let fetched = table.fetchAnnotations(articleID: "article-1", database)

			#expect(fetched.count == 1)
			let result = fetched[0]
			#expect(result.annotationID == annotation.annotationID)
			#expect(result.articleID == annotation.articleID)
			#expect(result.bookKey == annotation.bookKey)
			#expect(result.quoteExact == annotation.quoteExact)
			#expect(result.quotePrefix == annotation.quotePrefix)
			#expect(result.quoteSuffix == annotation.quoteSuffix)
			#expect(result.rootSelector == annotation.rootSelector)
			#expect(result.startOffset == annotation.startOffset)
			#expect(result.endOffset == annotation.endOffset)
			#expect(result.color == annotation.color)
			#expect(result.note == annotation.note)
			#expect(result.orphanedAt == nil)
			#expect(result.lastReanchoredAt == nil)
		}
	}

	@Test("saving with the same annotationID replaces the existing row rather than creating a second one")
	func saveWithSameAnnotationIDReplaces() {
		let (db, table) = makeTable()
		let original = makeAnnotation(quoteExact: "original phrase")
		let replacement = makeAnnotation(quoteExact: "edited phrase", color: .green)

		db.queue.runInDatabaseSync { database in
			table.save(original, database)
			table.save(replacement, database)

			let fetched = table.fetchAnnotations(articleID: "article-1", database)
			#expect(fetched.count == 1)
			#expect(fetched[0].quoteExact == "edited phrase")
			#expect(fetched[0].color == .green)
		}
	}

	@Test("a nil note round-trips as nil (highlight with no note)")
	func nilNoteRoundTrips() {
		let (db, table) = makeTable()
		let annotation = makeAnnotation(note: nil)

		db.queue.runInDatabaseSync { database in
			table.save(annotation, database)
			let fetched = table.fetchAnnotations(articleID: "article-1", database)
			#expect(fetched.first?.note == nil)
		}
	}

	// MARK: - 2. Fetch scoping

	@Test("fetchAnnotations(bookKey:) returns annotations from every article sharing that bookKey")
	func fetchByBookKeySpansMultipleArticles() {
		let (db, table) = makeTable()
		let sharedBookKey = "ao3-work:12345"
		let first = makeAnnotation(annotationID: "a1", articleID: "chapter-1", bookKey: sharedBookKey)
		let second = makeAnnotation(annotationID: "a2", articleID: "chapter-2", bookKey: sharedBookKey)
		let unrelated = makeAnnotation(annotationID: "a3", articleID: "chapter-3", bookKey: "ao3-work:99999")

		db.queue.runInDatabaseSync { database in
			table.save(first, database)
			table.save(second, database)
			table.save(unrelated, database)

			let fetched = table.fetchAnnotations(bookKey: sharedBookKey, database)
			#expect(fetched.count == 2)
			#expect(Set(fetched.map(\.annotationID)) == ["a1", "a2"])
		}
	}

	@Test("fetchAllAnnotations returns every annotation regardless of articleID/bookKey")
	func fetchAllReturnsEverything() {
		let (db, table) = makeTable()
		let first = makeAnnotation(annotationID: "a1", articleID: "article-1", bookKey: "book-1")
		let second = makeAnnotation(annotationID: "a2", articleID: "article-2", bookKey: "book-2")

		db.queue.runInDatabaseSync { database in
			table.save(first, database)
			table.save(second, database)

			#expect(table.fetchAllAnnotations(database).count == 2)
		}
	}

	@Test("a nil bookKey is stored and round-trips as nil, and is excluded from fetchAnnotations(bookKey:)")
	func nilBookKeyRoundTripsAndIsExcludedFromBookKeyFetch() {
		let (db, table) = makeTable()
		let annotation = makeAnnotation(bookKey: nil)

		db.queue.runInDatabaseSync { database in
			table.save(annotation, database)
			let byArticle = table.fetchAnnotations(articleID: "article-1", database)
			#expect(byArticle.first?.bookKey == nil)

			let byBookKey = table.fetchAnnotations(bookKey: "ao3-work:12345", database)
			#expect(byBookKey.isEmpty)
		}
	}

	// MARK: - 3. Note/color updates

	@Test("updateNote changes only the note column, leaving color and the anchor selector untouched")
	func updateNoteLeavesOtherColumnsAlone() {
		let (db, table) = makeTable()
		let annotation = makeAnnotation(color: .purple, note: "first draft")

		db.queue.runInDatabaseSync { database in
			table.save(annotation, database)
			table.updateNote(annotationID: annotation.annotationID, note: "revised note", at: Date(), database)

			let fetched = table.fetchAnnotations(articleID: "article-1", database).first
			#expect(fetched?.note == "revised note")
			#expect(fetched?.color == .purple)
			#expect(fetched?.quoteExact == annotation.quoteExact)
		}
	}

	@Test("updateColor changes only the color column")
	func updateColorLeavesOtherColumnsAlone() {
		let (db, table) = makeTable()
		let annotation = makeAnnotation(color: .yellow, note: "keep me")

		db.queue.runInDatabaseSync { database in
			table.save(annotation, database)
			table.updateColor(annotationID: annotation.annotationID, color: .blue, at: Date(), database)

			let fetched = table.fetchAnnotations(articleID: "article-1", database).first
			#expect(fetched?.color == .blue)
			#expect(fetched?.note == "keep me")
		}
	}

	// MARK: - 4. Delete

	@Test("deleteAnnotation removes the row")
	func deleteRemovesRow() {
		let (db, table) = makeTable()
		let annotation = makeAnnotation()

		db.queue.runInDatabaseSync { database in
			table.save(annotation, database)
			table.deleteAnnotation(annotationID: annotation.annotationID, database)

			#expect(table.fetchAnnotations(articleID: "article-1", database).isEmpty)
		}
	}

	// MARK: - 5. Orphan / reanchor lifecycle

	@Test("markOrphaned sets orphanedAt without touching the stored anchor selector")
	func markOrphanedSetsOrphanedAt() {
		let (db, table) = makeTable()
		let annotation = makeAnnotation()
		let orphanedDate = Date(timeIntervalSince1970: 1_700_100_000)

		db.queue.runInDatabaseSync { database in
			table.save(annotation, database)
			table.markOrphaned(annotationID: annotation.annotationID, at: orphanedDate, database)

			let fetched = table.fetchAnnotations(articleID: "article-1", database).first
			#expect(fetched?.orphanedAt?.timeIntervalSince1970 == orphanedDate.timeIntervalSince1970)
			#expect(fetched?.quoteExact == annotation.quoteExact)
			#expect(fetched?.startOffset == annotation.startOffset)
		}
	}

	@Test("reanchor writes corrected offsets/quote and clears a prior orphaned mark")
	func reanchorClearsOrphanedMarkAndUpdatesOffsets() {
		let (db, table) = makeTable()
		let annotation = makeAnnotation(startOffset: 10, endOffset: 31)

		db.queue.runInDatabaseSync { database in
			table.save(annotation, database)
			table.markOrphaned(annotationID: annotation.annotationID, at: Date(), database)
			#expect(table.fetchAnnotations(articleID: "article-1", database).first?.orphanedAt != nil)

			table.reanchor(
				annotationID: annotation.annotationID,
				startOffset: 40,
				endOffset: 61,
				quoteExact: "a highlighted phrase",
				quotePrefix: "new prefix ",
				quoteSuffix: " new suffix",
				at: Date(),
				database
			)

			let fetched = table.fetchAnnotations(articleID: "article-1", database).first
			#expect(fetched?.orphanedAt == nil)
			#expect(fetched?.startOffset == 40)
			#expect(fetched?.endOffset == 61)
			#expect(fetched?.quotePrefix == "new prefix ")
			#expect(fetched?.quoteSuffix == " new suffix")
			#expect(fetched?.lastReanchoredAt != nil)
		}
	}
}
