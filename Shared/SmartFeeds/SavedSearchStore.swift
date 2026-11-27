//
//  SavedSearchStore.swift
//  NetNewsWire
//
//  Persists user-created LibrarySearchState presets ("Saved Searches") and
//  exposes them as SmartFeeds for the main menu shelf section.
//

import Foundation
import RSCore
import Account
import Articles
import ArticlesDatabase
import Images

extension Notification.Name {
	static let SavedSearchesDidChange = Notification.Name("SavedSearchesDidChange")
}

@MainActor final class SavedSearchStore {

	static let shared = SavedSearchStore()

	private let defaults: UserDefaults
	private let storageKey = "savedLibrarySearches"
	private(set) var savedSearches: [SavedSearch]

	init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
		if let data = defaults.data(forKey: storageKey),
		   let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data) {
			self.savedSearches = decoded
		} else {
			self.savedSearches = []
		}
	}

	func save(_ savedSearch: SavedSearch) {
		var updated = savedSearch
		updated.updatedAt = Date()
		if let index = savedSearches.firstIndex(where: { $0.id == updated.id }) {
			savedSearches[index] = updated
		} else {
			savedSearches.insert(updated, at: 0)
		}
		persistAndNotify()
	}

	func rename(id: UUID, to newName: String) {
		let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, let index = savedSearches.firstIndex(where: { $0.id == id }) else {
			return
		}
		savedSearches[index].name = trimmed
		savedSearches[index].updatedAt = Date()
		persistAndNotify()
	}

	func delete(id: UUID) {
		let previousCount = savedSearches.count
		savedSearches.removeAll { $0.id == id }
		if savedSearches.count != previousCount {
			persistAndNotify()
		}
	}

	func savedSearch(id: UUID) -> SavedSearch? {
		savedSearches.first { $0.id == id }
	}

	private func persistAndNotify() {
		if let data = try? JSONEncoder().encode(savedSearches) {
			defaults.set(data, forKey: storageKey)
		}
		NotificationCenter.default.post(name: .SavedSearchesDidChange, object: self)
	}
}

@MainActor final class SavedSearchesController: DisplayNameProvider, ContainerIdentifiable {
	static let sectionID = "__savedSearches__"
	nonisolated let containerID: ContainerIdentifier? = ContainerIdentifier.savedSearchesController

	static let shared = SavedSearchesController()
	let nameForDisplay = NSLocalizedString("Saved searches", comment: "Saved Searches shelf section title")

	var savedSearchFeeds: [SmartFeed] {
		SavedSearchStore.shared.savedSearches.map { SmartFeed(delegate: LibrarySearchFeedDelegate(savedSearch: $0)) }
	}

	func find(by identifier: SidebarItemIdentifier) -> PseudoFeed? {
		guard case .smartFeed(let stringIdentifier) = identifier,
			  stringIdentifier.hasPrefix(LibrarySearchFeedDelegate.savedSearchPrefix) else {
			return nil
		}
		let uuidString = String(stringIdentifier.dropFirst(LibrarySearchFeedDelegate.savedSearchPrefix.count))
		guard let uuid = UUID(uuidString: uuidString),
			  let savedSearch = SavedSearchStore.shared.savedSearch(id: uuid) else {
			return nil
		}
		return SmartFeed(delegate: LibrarySearchFeedDelegate(savedSearch: savedSearch))
	}
}

@MainActor struct LibrarySearchFeedDelegate: SmartFeedDelegate {

	static let savedSearchPrefix = "SavedSearch_"

	let savedSearchID: UUID?
	let state: LibrarySearchState
	let nameForDisplay: String
	let fetchType: FetchType
	var smallIcon: IconImage? = Assets.Images.searchFeed

	var sidebarItemID: SidebarItemIdentifier? {
		if let savedSearchID {
			return .smartFeed("\(Self.savedSearchPrefix)\(savedSearchID.uuidString)")
		}
		return .smartFeed(String(describing: LibrarySearchFeedDelegate.self))
	}

	init(savedSearch: SavedSearch) {
		self.savedSearchID = savedSearch.id
		self.state = savedSearch.state
		self.nameForDisplay = savedSearch.name
		self.fetchType = .search(savedSearch.state.query)
	}

	init(state: LibrarySearchState, title: String? = nil) {
		self.savedSearchID = nil
		self.state = state
		if let title, !title.isEmpty {
			self.nameForDisplay = title
		} else {
			self.nameForDisplay = Self.displayTitle(for: state)
		}
		self.fetchType = .search(state.query)
	}

	static func displayTitle(for state: LibrarySearchState) -> String {
		let trimmedQuery = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
		if !trimmedQuery.isEmpty {
			return NSLocalizedString("Search: ", comment: "Search smart feed title prefix") + trimmedQuery
		}

		let priorityCategories: [ArticleTagCategory] = [.fandom, .relationship, .character, .freeform, .author, .rating]
		for category in priorityCategories {
			if let primary = state.includedTags[category]?.sorted().first {
				let extraCount = max(0, state.activeFilterCount - 1)
				if extraCount == 0 {
					return primary
				}
				return "\(primary) (+\(extraCount))"
			}
		}

		return NSLocalizedString("Filtered Library", comment: "Filtered library search title")
	}

	func fetchArticleSearchMatchesOrderedAsync() async -> [ArticleSearchMatch]? {
		await AccountManager.shared.fetchArticleSearchMatchesAsync(for: state)
	}

	func fetchArticlesOrderedAsync() async -> [Article]? {
		await fetchArticleSearchMatchesOrderedAsync()?.map(\.article)
	}

	func fetchUnreadCount(account: Account) async -> Int {
		0
	}
}
