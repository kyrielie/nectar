//
//  LibrarySearchSheetView.swift
//  NetNewsWire
//
//  SwiftUI AO3-style local library search and filter builder presented from
//  the main menu's top-left Search button, timeline Filter button, or Saved
//  Searches context menu. Mirrors Kudos's AO3FilterPanel + TagSelectField UX.
//

import SwiftUI
import Account
import ArticlesDatabase

private enum LibraryTagSelectionState {
	case clear
	case included
	case excluded

	var next: LibraryTagSelectionState {
		switch self {
		case .clear: return .included
		case .included: return .excluded
		case .excluded: return .clear
		}
	}
}

struct LibrarySearchSheetView: View {

	@State private var state: LibrarySearchState
	@State private var wordsFromText: String
	@State private var wordsToText: String
	@State private var availableLanguages = [String]()
	@State private var availableRatings = [TagSuggestion]()
	@State private var availableWarnings = [TagSuggestion]()
	@State private var availableCategories = [TagSuggestion]()
	@State private var showingSavePrompt = false
	@State private var saveName: String

	private let editingSavedSearch: SavedSearch?
	private let onSearch: (LibrarySearchState) -> Void
	private let onSave: (SavedSearch) -> Void
	private let onCancel: () -> Void

	init(
		initialState: LibrarySearchState = LibrarySearchState(),
		editingSavedSearch: SavedSearch? = nil,
		onSearch: @escaping (LibrarySearchState) -> Void,
		onSave: @escaping (SavedSearch) -> Void,
		onCancel: @escaping () -> Void
	) {
		let resolvedState = editingSavedSearch?.state ?? initialState
		_state = State(initialValue: resolvedState)
		_wordsFromText = State(initialValue: resolvedState.wordsFrom.map(String.init) ?? "")
		_wordsToText = State(initialValue: resolvedState.wordsTo.map(String.init) ?? "")
		_saveName = State(initialValue: editingSavedSearch?.name ?? resolvedState.query)
		self.editingSavedSearch = editingSavedSearch
		self.onSearch = onSearch
		self.onSave = onSave
		self.onCancel = onCancel
	}

	private var scopedFandoms: Set<String> {
		state.includedTags[.fandom] ?? []
	}

	var body: some View {
		NavigationStack {
			Form {
				Section("Search Text") {
					TextField("Title, text, or keywords (3+ chars)", text: $state.query)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
						.submitLabel(.search)
						.onSubmit {
							runSearchIfReady()
						}
				}

				Section {
					tagNavigationRow(title: "Fandoms", category: .fandom)
					tagNavigationRow(title: "Relationships", category: .relationship)
					tagNavigationRow(title: "Characters", category: .character)
					tagNavigationRow(title: "Additional Tags", category: .freeform)
					tagNavigationRow(title: "Authors", category: .author)
				} header: {
					Text("Tags & Authors")
				} footer: {
					Text("Tap a tag chip to cycle include, exclude, and clear.")
				}

				facetSection(title: "Ratings", category: .rating, suggestions: availableRatings)
				facetSection(title: "Warnings", category: .warning, suggestions: availableWarnings)
				facetSection(title: "Categories", category: .category, suggestions: availableCategories)

				Section("Work Details") {
					Picker("Completion", selection: $state.completion) {
						Text("Any").tag(LibrarySearchCompletionFilter.any)
						Text("Complete Only").tag(LibrarySearchCompletionFilter.completeOnly)
						Text("WIP Only").tag(LibrarySearchCompletionFilter.wipOnly)
					}

					Picker("Crossovers", selection: $state.crossover) {
						Text("Any").tag(LibrarySearchCrossoverFilter.any)
						Text("Crossovers Only").tag(LibrarySearchCrossoverFilter.crossoverOnly)
						Text("Single Fandom").tag(LibrarySearchCrossoverFilter.singleFandomOnly)
					}

					if !availableLanguages.isEmpty {
						Picker("Language", selection: Binding(
							get: { state.language ?? "" },
							set: { state.language = $0.isEmpty ? nil : $0 }
						)) {
							Text("Any").tag("")
							ForEach(availableLanguages, id: \.self) { language in
								Text(language).tag(language)
							}
						}
					}

					HStack {
						Text("Word Count")
						Spacer()
						TextField("From", text: $wordsFromText)
							.keyboardType(.numberPad)
							.multilineTextAlignment(.trailing)
							.frame(width: 80)
							.onChange(of: wordsFromText) { newValue in
								state.wordsFrom = Int(newValue.trimmingCharacters(in: .whitespaces))
							}
						Text("–")
							.foregroundStyle(.secondary)
						TextField("To", text: $wordsToText)
							.keyboardType(.numberPad)
							.multilineTextAlignment(.trailing)
							.frame(width: 80)
							.onChange(of: wordsToText) { newValue in
								state.wordsTo = Int(newValue.trimmingCharacters(in: .whitespaces))
							}
					}
				}

				Section {
					Picker("Sort By", selection: $state.sort) {
						Text("Best Match").tag(LibrarySearchSort.relevance)
						Text("Date Updated").tag(LibrarySearchSort.dateModified)
						Text("Date Published").tag(LibrarySearchSort.datePublished)
						Text("Word Count").tag(LibrarySearchSort.wordCount)
						Text("Kudos").tag(LibrarySearchSort.kudosCount)
						Text("Bookmarks").tag(LibrarySearchSort.bookmarkCount)
						Text("Hits").tag(LibrarySearchSort.hitCount)
						Text("Date Bookmarked").tag(LibrarySearchSort.dateBookmarked)
					}
				}

				Section {
					Button {
						runSearchIfReady()
					} label: {
						HStack {
							Spacer()
							Label("Apply Filters", systemImage: "magnifyingglass")
								.fontWeight(.semibold)
							Spacer()
						}
					}
					.disabled(!state.hasExecutableCriteria)

					Button {
						if saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
							saveName = defaultSavedSearchName()
						}
						showingSavePrompt = true
					} label: {
						HStack {
							Spacer()
							Label(editingSavedSearch == nil ? "Save Search…" : "Update Saved Search…", systemImage: "bookmark")
							Spacer()
						}
					}
					.disabled(!state.hasExecutableCriteria)

					if state.hasActiveFilters {
						Button("Reset Filters", role: .destructive) {
							state.resetFilters()
							wordsFromText = ""
							wordsToText = ""
						}
					}
				}
			}
			.navigationTitle(editingSavedSearch == nil ? "Search Library" : "Edit Saved Search")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel", action: onCancel)
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Search") {
						runSearchIfReady()
					}
					.disabled(!state.hasExecutableCriteria)
				}
			}
			.alert(editingSavedSearch == nil ? "Save Search" : "Update Saved Search", isPresented: $showingSavePrompt) {
				TextField("Name", text: $saveName)
				Button("Save") {
					let trimmed = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
					let finalName = trimmed.isEmpty ? defaultSavedSearchName() : trimmed
					let saved = SavedSearch(
						id: editingSavedSearch?.id ?? UUID(),
						name: finalName,
						state: state,
						createdAt: editingSavedSearch?.createdAt ?? Date(),
						updatedAt: Date()
					)
					onSave(saved)
				}
				Button("Cancel", role: .cancel) {}
			} message: {
				Text("Saved searches appear in the Saved Searches shelf on the main menu.")
			}
			.task {
				async let languages = AccountManager.shared.fetchAvailableLanguagesAsync()
				async let ratings = AccountManager.shared.fetchTagSuggestionsAsync(category: .rating, prefix: "", limit: 20)
				async let warnings = AccountManager.shared.fetchTagSuggestionsAsync(category: .warning, prefix: "", limit: 20)
				async let categories = AccountManager.shared.fetchTagSuggestionsAsync(category: .category, prefix: "", limit: 20)
				availableLanguages = await languages
				availableRatings = await ratings
				availableWarnings = await warnings
				availableCategories = await categories
			}
		}
	}

	private func tagNavigationRow(title: String, category: ArticleTagCategory) -> some View {
		let included = (state.includedTags[category] ?? []).sorted()
		let excluded = (state.excludedTags[category] ?? []).sorted()
		let pickerFandomScope = category == .fandom ? Set<String>() : scopedFandoms

		return VStack(alignment: .leading, spacing: 8) {
			NavigationLink {
				LibraryTagPickerView(
					title: title,
					category: category,
					scopedFandoms: pickerFandomScope,
					state: $state
				)
			} label: {
				LabeledContent(title) {
					if included.isEmpty && excluded.isEmpty {
						Text("Any")
							.foregroundStyle(.secondary)
					} else {
						Text(summaryText(includeCount: included.count, excludeCount: excluded.count))
							.foregroundStyle(.secondary)
					}
				}
			}

			if !included.isEmpty || !excluded.isEmpty {
				TagChipFlowLayout(spacing: 6, rowSpacing: 6) {
					ForEach(included, id: \.self) { name in
						LibraryFilterTagChip(name: name, selectionState: .included) {
							cycleTag(name, category: category)
						}
					}
					ForEach(excluded, id: \.self) { name in
						LibraryFilterTagChip(name: name, selectionState: .excluded) {
							cycleTag(name, category: category)
						}
					}
				}
				.padding(.top, 2)
			}
		}
	}

	@ViewBuilder
	private func facetSection(title: String, category: ArticleTagCategory, suggestions: [TagSuggestion]) -> some View {
		if !suggestions.isEmpty {
			Section(title) {
				ForEach(suggestions) { suggestion in
					let currentState = tagState(for: suggestion.name, category: category)
					Button {
						cycleTag(suggestion.name, category: category)
					} label: {
						HStack {
							Text(suggestion.name)
								.foregroundStyle(.primary)
							Spacer()
							selectionBadge(for: currentState)
						}
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
				}
			}
		}
	}

	@ViewBuilder
	private func selectionBadge(for selectionState: LibraryTagSelectionState) -> some View {
		switch selectionState {
		case .clear:
			EmptyView()
		case .included:
			Label("Include", systemImage: "plus.circle.fill")
				.font(.caption.weight(.semibold))
				.foregroundStyle(Color.accentColor)
		case .excluded:
			Label("Exclude", systemImage: "minus.circle.fill")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.red)
		}
	}

	private func tagState(for name: String, category: ArticleTagCategory) -> LibraryTagSelectionState {
		if state.includedTags[category]?.contains(name) == true { return .included }
		if state.excludedTags[category]?.contains(name) == true { return .excluded }
		return .clear
	}

	private func cycleTag(_ name: String, category: ArticleTagCategory) {
		switch tagState(for: name, category: category).next {
		case .included:
			state.includeTag(name, category: category)
		case .excluded:
			state.excludeTag(name, category: category)
		case .clear:
			state.removeTag(name, category: category)
		}
	}

	private func summaryText(includeCount: Int, excludeCount: Int) -> String {
		var parts = [String]()
		if includeCount > 0 { parts.append("\(includeCount) included") }
		if excludeCount > 0 { parts.append("\(excludeCount) excluded") }
		return parts.joined(separator: " · ")
	}

	private func runSearchIfReady() {
		guard state.hasExecutableCriteria else { return }
		onSearch(state)
	}

	private func defaultSavedSearchName() -> String {
		let trimmedQuery = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
		if !trimmedQuery.isEmpty {
			return trimmedQuery
		}
		if let firstFandom = state.includedTags[.fandom]?.sorted().first {
			return firstFandom
		}
		if let firstShip = state.includedTags[.relationship]?.sorted().first {
			return firstShip
		}
		return "Saved Search"
	}
}

private struct LibraryTagPickerView: View {

	let title: String
	let category: ArticleTagCategory
	let scopedFandoms: Set<String>
	@Binding var state: LibrarySearchState

	@State private var filterText = ""
	@State private var suggestions = [TagSuggestion]()

	private var suggestionsHeaderTitle: String {
		let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.isEmpty, category != .fandom, let primaryFandom = scopedFandoms.sorted().first {
			return "Popular in \(primaryFandom)"
		}
		return "Suggestions"
	}

	var body: some View {
		List {
			let included = (state.includedTags[category] ?? []).sorted()
			let excluded = (state.excludedTags[category] ?? []).sorted()

			if !included.isEmpty || !excluded.isEmpty {
				Section("Selected") {
					TagChipFlowLayout(spacing: 6, rowSpacing: 6) {
						ForEach(included, id: \.self) { name in
							LibraryFilterTagChip(name: name, selectionState: .included) {
								cycle(name)
							}
						}
						ForEach(excluded, id: \.self) { name in
							LibraryFilterTagChip(name: name, selectionState: .excluded) {
								cycle(name)
							}
						}
					}
					.padding(.vertical, 2)
				}
			}

			Section {
				if suggestions.isEmpty {
					Text("No matching \(title.lowercased())")
						.foregroundStyle(.secondary)
				} else {
					ForEach(suggestions) { suggestion in
						let currentState = tagState(for: suggestion.name)
						Button {
							cycle(suggestion.name)
						} label: {
							HStack {
								Text(suggestion.name)
									.foregroundStyle(.primary)
								Spacer()
								if currentState == .included {
									Label("Include", systemImage: "plus.circle.fill")
										.font(.caption.weight(.semibold))
										.foregroundStyle(Color.accentColor)
								} else if currentState == .excluded {
									Label("Exclude", systemImage: "minus.circle.fill")
										.font(.caption.weight(.semibold))
										.foregroundStyle(.red)
								}
								Text("\(suggestion.articleCount)")
									.foregroundStyle(.secondary)
									.font(.footnote)
							}
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
					}
				}
			} header: {
				Text(suggestionsHeaderTitle)
			} footer: {
				Text("Tap a tag once to include it, twice to exclude it, and a third time to clear it.")
			}
		}
		.navigationTitle(title)
		.navigationBarTitleDisplayMode(.inline)
		.searchable(text: $filterText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter \(title.lowercased())")
		.task(id: "\(filterText)|\(scopedFandoms.sorted().joined(separator: "\u{0000}"))") {
			suggestions = await AccountManager.shared.fetchTagSuggestionsAsync(
				category: category,
				prefix: filterText,
				limit: 40,
				scopedFandoms: scopedFandoms
			)
		}
	}

	private func tagState(for name: String) -> LibraryTagSelectionState {
		if state.includedTags[category]?.contains(name) == true { return .included }
		if state.excludedTags[category]?.contains(name) == true { return .excluded }
		return .clear
	}

	private func cycle(_ name: String) {
		switch tagState(for: name).next {
		case .included:
			state.includeTag(name, category: category)
		case .excluded:
			state.excludeTag(name, category: category)
		case .clear:
			state.removeTag(name, category: category)
		}
	}
}

private struct LibraryFilterTagChip: View {
	let name: String
	let selectionState: LibraryTagSelectionState
	let onTap: () -> Void

	var body: some View {
		Button(action: onTap) {
			HStack(spacing: 4) {
				Image(systemName: selectionState == .included ? "plus.circle.fill" : "minus.circle.fill")
					.font(.caption2.weight(.semibold))
				Text(name)
					.font(.caption.weight(.medium))
					.lineLimit(1)
			}
			.padding(.horizontal, 8)
			.padding(.vertical, 4)
			.foregroundStyle(selectionState == .included ? Color.accentColor : Color.red)
			.background(
				Capsule()
					.fill((selectionState == .included ? Color.accentColor : Color.red).opacity(0.14))
			)
		}
		.buttonStyle(.plain)
	}
}

private struct TagChipFlowLayout: Layout {
	var spacing: CGFloat = 6
	var rowSpacing: CGFloat = 6

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let maxWidth = proposal.width ?? .greatestFiniteMagnitude
		let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
		let totalHeight = rows.reduce(CGFloat(0)) { $0 + $1.height }
			+ CGFloat(max(0, rows.count - 1)) * rowSpacing
		let maxRowWidth = rows.map(\.width).max() ?? 0
		return CGSize(width: proposal.width ?? maxRowWidth, height: totalHeight)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
		var y = bounds.minY
		for row in rows {
			var x = bounds.minX
			for item in row.items {
				let size = item.size
				item.subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
				x += size.width + spacing
			}
			y += row.height + rowSpacing
		}
	}

	private struct RowItem {
		let subview: LayoutSubview
		let size: CGSize
	}

	private struct Row {
		var items = [RowItem]()
		var width: CGFloat = 0
		var height: CGFloat = 0
	}

	private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
		var rows = [Row]()
		var currentRow = Row()
		for subview in subviews {
			let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
			let neededWidth = currentRow.items.isEmpty ? size.width : currentRow.width + spacing + size.width
			if !currentRow.items.isEmpty && neededWidth > maxWidth {
				rows.append(currentRow)
				currentRow = Row()
			}
			currentRow.items.append(RowItem(subview: subview, size: size))
			currentRow.width = currentRow.items.count == 1 ? size.width : currentRow.width + spacing + size.width
			currentRow.height = max(currentRow.height, size.height)
		}
		if !currentRow.items.isEmpty {
			rows.append(currentRow)
		}
		return rows
	}
}
