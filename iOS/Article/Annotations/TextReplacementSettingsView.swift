//
//  TextReplacementSettingsView.swift
//  NetNewsWire-iOS
//
//  Pushed from SettingsViewController's Articles section ("Text
//  Replacement" row), following the same UIHostingController-push
//  pattern as AnnotationsSettingsView/ArticleThemeListView elsewhere in
//  this app. See the feature's own implementation plan, "Settings
//  screen" for the five sections below and their ordering.
//
//  The Edit History section links into AnnotationsListView with
//  scope: .everything, same entry point AnnotationsSettingsView's own
//  "All Highlights" row already uses -- now the combined "This
//  book"/"All" tabbed viewer described in the plan's "Consolidated
//  viewer" section (AnnotationsListView itself grew the tab switcher;
//  no separate screen was needed). Opened from here with no book in
//  context, so it only ever offers the All tab -- see
//  AnnotationsListView.showsTabSwitcher.
//
//  The Reader-insert names section's "per-work override" entry point
//  is a NavigationLink to TextReplacementPerWorkOverrideView, shown
//  whenever currentWork is non-nil -- see that view's own header
//  comment for the contextual-surfacing decision (any resolvable
//  current work, not the plan's unspecified fandom/tag-matching
//  heuristic).
//

import SwiftUI
import Account
import Articles
import AnnotationsKit

@MainActor private final class TextReplacementSettingsModel: ObservableObject {
	@Published var readerInsertTable: TextReplacementRuleTable {
		didSet {
			AppDefaults.shared.textReplacementReaderInsertTable = readerInsertTable
		}
	}
	@Published var customTable: TextReplacementRuleTable {
		didSet {
			AppDefaults.shared.textReplacementCustomTable = customTable
		}
	}
	@Published var editHistoryCount: Int?

	init() {
		self.readerInsertTable = AppDefaults.shared.textReplacementReaderInsertTable
		self.customTable = AppDefaults.shared.textReplacementCustomTable
	}
}

struct TextReplacementSettingsView: View {

	var onNavigateToAnnotation: (_ annotation: Annotation, _ account: Account) -> Void
	var currentWork: (bookKey: String, title: String)?

	@AppStorage(AppDefaults.Key.textReplacementApplyAutomatically) private var applyAutomatically = true
	@AppStorage(AppDefaults.Key.textReplacementTypoFixesEnabled) private var typoFixesEnabled = true
	@AppStorage(AppDefaults.Key.textReplacementQuoteConversionEnabled) private var quoteConversionEnabled = false

	@StateObject private var model = TextReplacementSettingsModel()

	private var primaryAccount: Account? {
		AccountManager.shared.sortedAccounts.first
	}

	var body: some View {
		Form {
			Section {
				Toggle(isOn: $applyAutomatically) {
					Text("Apply Automatically on Open", comment: "Text replacement settings: master toggle label")
				}
			} footer: {
				Text("Original text is never changed -- every replacement below is reviewable and reversible in Edit History.", comment: "Text replacement settings: non-destructive guarantee footer")
			}

			Section {
				ruleRows($model.readerInsertTable)
				if let currentWork {
					NavigationLink {
						TextReplacementPerWorkOverrideView(bookKey: currentWork.bookKey, workTitle: currentWork.title)
					} label: {
						Text("Override for \(currentWork.title)", comment: "Text replacement settings: per-work override row label")
					}
				}
			} header: {
				Text("Reader-Insert Names", comment: "Text replacement settings: reader-insert section header")
			} footer: {
				Text("Replaces placeholder tokens like (Y/N) with a name you choose. Leave Replace With empty to leave a placeholder untouched.", comment: "Text replacement settings: reader-insert section footer")
			}

			Section {
				Toggle(isOn: $typoFixesEnabled) {
					Text("Common Typo Fixes", comment: "Text replacement settings: typo fixes toggle label")
				}
				Toggle(isOn: $quoteConversionEnabled) {
					Text("British-to-American Quotes", comment: "Text replacement settings: quote conversion toggle label")
				}
			} header: {
				Text("Style Corrections", comment: "Text replacement settings: style corrections section header")
			} footer: {
				Text("British-to-American Quotes converts dialogue marks, not every apostrophe -- contractions and possessives are left alone.", comment: "Text replacement settings: quote conversion clarifying footer")
			}

			Section {
				ruleRows($model.customTable)
				addRuleRow($model.customTable)
			} header: {
				Text("Custom Rules", comment: "Text replacement settings: custom rules section header")
			} footer: {
				Text("Your own find-and-replace pairs, for anything the typo table above doesn't cover.", comment: "Text replacement settings: custom rules section footer")
			}

			Section {
				if let primaryAccount {
					NavigationLink {
						AnnotationsListView(account: primaryAccount, scope: .everything) { annotation in
							onNavigateToAnnotation(annotation, primaryAccount)
						}
					} label: {
						LabeledContent {
							if let editHistoryCount = model.editHistoryCount {
								Text("\(editHistoryCount)", comment: "Text replacement settings: edit history count")
									.foregroundStyle(.secondary)
							}
						} label: {
							Text("Edit History", comment: "Text replacement settings: edit history row label")
						}
					}
				}
			} header: {
				Text("Edit History", comment: "Text replacement settings: edit history section header")
			}
		}
		.surfacePaletteListBackground()
		.navigationTitle(Text("Text Replacement", comment: "Text replacement settings navigation title"))
		.navigationBarTitleDisplayMode(.inline)
		.task {
			guard let primaryAccount else { return }
			let all = await primaryAccount.fetchAllAnnotations()
			model.editHistoryCount = all.filter { $0.originalText != nil }.count
		}
	}

	/// One row per rule: two text fields ("Find" / "Replace With"),
	/// deletable via swipe -- same swipeActions-to-delete shape
	/// DinosaursView already establishes for a person-editable list in
	/// this app.
	@ViewBuilder
	private func ruleRows(_ table: Binding<TextReplacementRuleTable>) -> some View {
		ForEach(table.rules) { $rule in
			VStack(alignment: .leading, spacing: 4) {
				TextField(NSLocalizedString("Find", comment: "Text replacement rule: input field placeholder"), text: $rule.input)
				TextField(NSLocalizedString("Replace With", comment: "Text replacement rule: output field placeholder"), text: $rule.output)
					.foregroundStyle(.secondary)
			}
			.swipeActions(edge: .trailing, allowsFullSwipe: false) {
				Button(role: .destructive) {
					table.wrappedValue.rules.removeAll { $0.id == rule.id }
				} label: {
					Image(systemName: "trash")
				}
			}
		}
	}

	private func addRuleRow(_ table: Binding<TextReplacementRuleTable>) -> some View {
		Button {
			table.wrappedValue.rules.append(TextReplacementRule(input: "", output: ""))
		} label: {
			Label {
				Text("Add Rule", comment: "Text replacement settings: add rule button label")
			} icon: {
				Image(systemName: "plus.circle")
			}
		}
	}
}
