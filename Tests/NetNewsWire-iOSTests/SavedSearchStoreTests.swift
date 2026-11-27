//
//  SavedSearchStoreTests.swift
//  NetNewsWire-iOSTests
//

import XCTest
import ArticlesDatabase
@testable import Nectar

@MainActor
final class SavedSearchStoreTests: XCTestCase {

	func testSaveRenameAndDeleteRoundTrip() throws {
		let suiteName = "SavedSearchStoreTests-\(UUID().uuidString)"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let store = SavedSearchStore(defaults: defaults)
		XCTAssertTrue(store.savedSearches.isEmpty)

		var state = LibrarySearchState(query: "chronometer")
		state.includeTag("Fandom Alpha", category: .fandom)
		let saved = SavedSearch(name: "Fandom Chronometer", state: state)
		store.save(saved)

		XCTAssertEqual(store.savedSearches.count, 1)
		XCTAssertEqual(store.savedSearch(id: saved.id)?.name, "Fandom Chronometer")

		store.rename(id: saved.id, to: "Updated Name")
		XCTAssertEqual(store.savedSearch(id: saved.id)?.name, "Updated Name")

		let reloadedStore = SavedSearchStore(defaults: defaults)
		XCTAssertEqual(reloadedStore.savedSearches.count, 1)
		XCTAssertEqual(reloadedStore.savedSearches.first?.state, state)

		reloadedStore.delete(id: saved.id)
		XCTAssertTrue(reloadedStore.savedSearches.isEmpty)
	}

	func testDisplayTitleForFandomAndMultiFilterStates() {
		var singleFandom = LibrarySearchState()
		singleFandom.includeTag("Arcane", category: .fandom)
		XCTAssertEqual(LibrarySearchFeedDelegate.displayTitle(for: singleFandom), "Arcane")

		var multiFilter = singleFandom
		multiFilter.completion = .completeOnly
		XCTAssertEqual(LibrarySearchFeedDelegate.displayTitle(for: multiFilter), "Arcane (+1)")

		var scalarOnly = LibrarySearchState()
		scalarOnly.completion = .completeOnly
		XCTAssertEqual(
			LibrarySearchFeedDelegate.displayTitle(for: scalarOnly),
			NSLocalizedString("Filtered Library", comment: "Filtered library search title")
		)
	}
}
