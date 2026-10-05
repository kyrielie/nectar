//
//  AO3IgnoreListView.swift
//  NetNewsWire-iOS
//
//  Manager for AO3IgnoreList: the works and authors the person chose to hide,
//  with swipe to remove. Pushed from AO3AccountSettingsView.
//
//  Rules apply to new feed items only. AO3IgnoreList filters while a feed is
//  parsed, so a rule never touches works already in the library, and removing
//  a rule does not bring back items skipped while it was active; they return
//  only if they appear in a later fetch. The footer says so.
//
//  A rule made before labels existed shows its work id or author URL.
//

import SwiftUI
import AO3Kit

struct AO3IgnoreListView: View {

	private struct WorkRule: Identifiable {
		let id: String
		let name: String
	}

	private struct AuthorRule: Identifiable {
		let id: String
		let name: String
	}

	@State private var works = [WorkRule]()
	@State private var authors = [AuthorRule]()

	var body: some View {
		List {
			if works.isEmpty && authors.isEmpty {
				Section {
					Text(NSLocalizedString("No ignored works or authors.", comment: "AO3 ignore list: empty state"))
						.foregroundStyle(.secondary)
				}
			}

			if !works.isEmpty {
				Section {
					ForEach(works) { rule in
						Text(rule.name)
							.swipeActions(edge: .trailing, allowsFullSwipe: true) {
								Button(role: .destructive) {
									AO3IgnoreList.unignoreWork(id: rule.id)
									reload()
								} label: {
									Text(NSLocalizedString("Remove", comment: "Remove button"))
								}
							}
					}
				} header: {
					Text(NSLocalizedString("Works", comment: "AO3 ignore list: works section header"))
				}
			}

			if !authors.isEmpty {
				Section {
					ForEach(authors) { rule in
						Text(rule.name)
							.swipeActions(edge: .trailing, allowsFullSwipe: true) {
								Button(role: .destructive) {
									AO3IgnoreList.unignoreAuthor(url: rule.id)
									reload()
								} label: {
									Text(NSLocalizedString("Remove", comment: "Remove button"))
								}
							}
					}
				} header: {
					Text(NSLocalizedString("Authors", comment: "AO3 ignore list: authors section header"))
				}
			}

			Section {
			} footer: {
				Text(NSLocalizedString("Rules apply to new feed items only. Works already in your library stay, and removing a rule does not bring back items that were skipped while it was active.", comment: "AO3 ignore list: footer explaining rules are not retroactive"))
			}
		}
		.navigationTitle(Text(NSLocalizedString("Ignored Works and Authors", comment: "AO3 settings: ignore list row title")))
		.navigationBarTitleDisplayMode(.inline)
		.onAppear {
			reload()
		}
	}

	private func reload() {
		works = AO3IgnoreList.ignoredWorkIDs
			.map { WorkRule(id: $0, name: AO3IgnoreList.workDisplayName(id: $0)) }
			.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		authors = AO3IgnoreList.ignoredAuthorURLs
			.map { AuthorRule(id: $0, name: AO3IgnoreList.authorDisplayName(url: $0)) }
			.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
	}
}

#Preview {
	NavigationStack {
		AO3IgnoreListView()
	}
}
