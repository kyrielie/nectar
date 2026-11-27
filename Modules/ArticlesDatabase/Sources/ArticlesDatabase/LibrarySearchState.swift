//
//  LibrarySearchState.swift
//  ArticlesDatabase
//
//  Persistent, Codable search and AO3-style facet filter state for local
//  library queries over ArticlesDatabase.
//

import Foundation

public enum LibrarySearchCompletionFilter: String, Codable, Sendable, CaseIterable, Hashable {
	case any
	case completeOnly
	case wipOnly
}

public enum LibrarySearchCrossoverFilter: String, Codable, Sendable, CaseIterable, Hashable {
	case any
	case crossoverOnly
	case singleFandomOnly
}

public enum LibrarySearchSort: String, Codable, Sendable, CaseIterable, Hashable {
	case relevance
	case datePublished
	case dateModified
	case wordCount
	case kudosCount
	case bookmarkCount
	case hitCount
	case dateBookmarked
}

public struct LibrarySearchState: Codable, Sendable, Hashable {

	public var query: String
	public var includedTags: [ArticleTagCategory: Set<String>]
	public var excludedTags: [ArticleTagCategory: Set<String>]
	public var completion: LibrarySearchCompletionFilter
	public var crossover: LibrarySearchCrossoverFilter
	public var language: String?
	public var wordsFrom: Int?
	public var wordsTo: Int?
	public var sort: LibrarySearchSort

	public init(
		query: String = "",
		includedTags: [ArticleTagCategory: Set<String>] = [:],
		excludedTags: [ArticleTagCategory: Set<String>] = [:],
		completion: LibrarySearchCompletionFilter = .any,
		crossover: LibrarySearchCrossoverFilter = .any,
		language: String? = nil,
		wordsFrom: Int? = nil,
		wordsTo: Int? = nil,
		sort: LibrarySearchSort = .relevance
	) {
		self.query = query
		self.includedTags = includedTags
		self.excludedTags = excludedTags
		self.completion = completion
		self.crossover = crossover
		self.language = language
		self.wordsFrom = wordsFrom
		self.wordsTo = wordsTo
		self.sort = sort
	}

	public var hasActiveFilters: Bool {
		let hasIncluded = includedTags.values.contains { !$0.isEmpty }
		let hasExcluded = excludedTags.values.contains { !$0.isEmpty }
		let hasLanguage = !(language?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
		return hasIncluded
			|| hasExcluded
			|| completion != .any
			|| crossover != .any
			|| hasLanguage
			|| wordsFrom != nil
			|| wordsTo != nil
	}

	public var hasExecutableCriteria: Bool {
		query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 || hasActiveFilters
	}

	public var activeFilterCount: Int {
		var count = includedTags.values.reduce(0) { $0 + $1.count }
		count += excludedTags.values.reduce(0) { $0 + $1.count }
		if completion != .any { count += 1 }
		if crossover != .any { count += 1 }
		if !(language?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) { count += 1 }
		if wordsFrom != nil || wordsTo != nil { count += 1 }
		return count
	}

	public mutating func includeTag(_ name: String, category: ArticleTagCategory) {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		excludedTags[category]?.remove(trimmed)
		var set = includedTags[category] ?? []
		set.insert(trimmed)
		includedTags[category] = set
	}

	public mutating func excludeTag(_ name: String, category: ArticleTagCategory) {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		includedTags[category]?.remove(trimmed)
		var set = excludedTags[category] ?? []
		set.insert(trimmed)
		excludedTags[category] = set
	}

	public mutating func removeTag(_ name: String, category: ArticleTagCategory) {
		includedTags[category]?.remove(name)
		excludedTags[category]?.remove(name)
	}

	public mutating func resetFilters() {
		includedTags = [:]
		excludedTags = [:]
		completion = .any
		crossover = .any
		language = nil
		wordsFrom = nil
		wordsTo = nil
	}
}

public struct SavedSearch: Codable, Sendable, Hashable, Identifiable {
	public let id: UUID
	public var name: String
	public var state: LibrarySearchState
	public var createdAt: Date
	public var updatedAt: Date

	public init(
		id: UUID = UUID(),
		name: String,
		state: LibrarySearchState,
		createdAt: Date = Date(),
		updatedAt: Date = Date()
	) {
		self.id = id
		self.name = name
		self.state = state
		self.createdAt = createdAt
		self.updatedAt = updatedAt
	}
}
